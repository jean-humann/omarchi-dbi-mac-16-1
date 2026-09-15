//! MacBookPro16,1 occupancy + skin power policy.
//!
//! HWP picks clocks. This daemon never wraps jobs and never calls
//! `powerprofilesctl set` / HoldProfile / `omarchy-powerprofiles-set`.
//! Super menu is the only UI (envelopes). Inside that envelope we cap RAPL
//! PL1 from core occupancy, PSI, package watts, and applesmc Ts0S/Ts1S.
//!
//! Never writes: AMD DPM, no_turbo, fan*_output, brcmfmac, t2bce.

mod config;
mod policy;
mod ppd;
mod sysfs;

use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use config::Config;
use policy::{clamp, core_utils, ema, occupancy, pick_epp, round_to};
use ppd::Ppd;
use sysfs::Hardware;

const STATUS_PATH: &str = "/run/mbp16-1-powerd/status";
const DEFAULT_CONF: &str = "/etc/mbp16-1-powerd.conf";

struct Daemon {
    cfg: Config,
    dry_run: bool,
    hw: Hardware,
    ppd: Ppd,
    started_profile: String,
    demand: f64,
    last_pl1: Option<i32>,
    last_epp: Option<String>,
    rapl_ok: bool,
    pkg_w: Option<f64>,
    last_status_log: Instant,
    last_max_perf: Option<i32>,
    last_status_blob: String,
    amd_dpm: Option<String>,
    amd_next: Instant,
    prev_stat: Vec<(u64, u64)>,
    prev_energy: Option<i64>,
    prev_t: Instant,
}

struct Tick {
    profile: String,
    demand: f64,
    n_busy: u32,
    emergency: bool,
    pl1_now: Option<i32>,
    epp: Option<String>,
    skin: Option<f64>,
}

impl Daemon {
    fn new(cfg: Config, dry_run: bool) -> std::io::Result<Self> {
        let mut hw = Hardware::open()?;
        let mut ppd = Ppd::connect();
        let started_profile = ppd.profile().to_string();
        let prev_stat = hw.read_proc_stat();
        let prev_energy = hw.energy.read_i64();
        let mut d = Self {
            cfg,
            dry_run,
            hw,
            ppd,
            started_profile,
            demand: 0.0,
            last_pl1: None,
            last_epp: None,
            rapl_ok: true,
            pkg_w: None,
            last_status_log: Instant::now() - Duration::from_secs(15),
            last_max_perf: None,
            last_status_blob: String::new(),
            amd_dpm: None,
            amd_next: Instant::now(),
            prev_stat,
            prev_energy,
            prev_t: Instant::now(),
        };
        d.refresh_amd(true);
        if let Some(parent) = Path::new(STATUS_PATH).parent() {
            let _ = fs::create_dir_all(parent);
        }
        Ok(d)
    }

    fn refresh_amd(&mut self, force: bool) {
        if !force && Instant::now() < self.amd_next {
            return;
        }
        self.amd_next = Instant::now() + Duration::from_secs(30);
        self.amd_dpm = self.hw.read_amd_dpm();
    }

    fn loop_once(&mut self) -> Tick {
        let now = Instant::now();
        let dt = now.duration_since(self.prev_t).as_secs_f64().max(0.05);
        self.prev_t = now;

        let cur_stat = self.hw.read_proc_stat();
        let utils = core_utils(&self.prev_stat, &cur_stat);
        self.prev_stat = cur_stat;

        let energy = self.hw.energy.read_i64();
        if let (Some(energy), Some(prev), true) = (energy, self.prev_energy, dt > 0.0) {
            let mut du = energy - prev;
            if du < 0 {
                du += 1 << 32;
            }
            self.pkg_w = Some(du as f64 / dt / 1_000_000.0);
        }
        self.prev_energy = energy;

        let (occ, n_busy, n_hot) =
            occupancy(&utils, self.cfg.busy_core_util, self.cfg.hot_core_util);
        let psi = self.hw.psi_some_avg10();
        let psi_d = clamp(psi / self.cfg.psi_busy_pct, 0.0, 1.0);
        let p_d = match self.pkg_w {
            None => 0.0,
            Some(w) => clamp(
                (w - self.cfg.idle_watts) / (self.cfg.busy_watts - self.cfg.idle_watts).max(1.0),
                0.0,
                1.0,
            ),
        };
        let mut raw = occ.max(psi_d).max(p_d * 0.85);

        let temps = self.hw.smc_temps();
        let skin = ["Ts0S", "Ts1S"]
            .iter()
            .filter_map(|k| temps.get(*k).copied())
            .fold(None, |acc: Option<f64>, v| Some(acc.map_or(v, |a| a.max(v))));
        let tc0p = temps.get("TC0P").copied();

        let profile = self.ppd.profile().to_string();
        let env = self.cfg.envelope(&profile).clone();
        let mut emergency = false;
        if let Some(skin) = skin {
            if skin >= env.skin_hard {
                raw = 0.0;
                emergency = true;
            } else if skin > self.cfg.skin_fade_c {
                raw *= clamp(
                    (env.skin_hard - skin) / (env.skin_hard - self.cfg.skin_fade_c).max(0.5),
                    0.0,
                    1.0,
                );
            }
        }

        self.demand = ema(
            self.demand,
            raw,
            dt,
            self.cfg.tau_up_s,
            self.cfg.tau_down_s,
        );
        if emergency {
            self.demand = 0.0;
        }

        let mut pl1 = (env.pl1_idle as f64
            + self.demand * (env.pl1_busy - env.pl1_idle) as f64)
            .round() as i32;
        if emergency {
            pl1 = pl1.min(env.pl1_idle);
        }
        let epp = pick_epp(&env.epp_idle, &env.epp_busy, self.demand);

        if !self.dry_run {
            if self.last_pl1.is_none_or(|prev| (pl1 - prev).abs() >= 2) {
                if self.hw.write_pl1_w(pl1) {
                    match self.hw.read_pl1_w() {
                        Some(back) if (back - pl1 as f64).abs() > 3.0 => {
                            self.rapl_ok = false;
                            eprintln!(
                                "RAPL PL1 write {pl1} W read back {back:.0} W — firmware may ignore"
                            );
                        }
                        _ => {
                            self.rapl_ok = true;
                            self.last_pl1 = Some(pl1);
                        }
                    }
                } else {
                    self.rapl_ok = false;
                    eprintln!("RAPL PL1 not writable");
                }
            }
            if self.last_epp.as_deref() != Some(epp) {
                if self.hw.write_epp(epp) {
                    self.last_epp = Some(epp.to_string());
                } else {
                    eprintln!("EPP write {epp} failed");
                }
            }
            if !self.rapl_ok {
                let pct = if emergency {
                    50
                } else {
                    55 + (self.demand * 45.0).round() as i32
                };
                if self.last_max_perf != Some(pct) {
                    self.hw.max_perf.write_str(&pct.to_string());
                    self.last_max_perf = Some(pct);
                }
            } else if !matches!(self.last_max_perf, None | Some(100)) {
                self.hw.max_perf.write_str("100");
                self.last_max_perf = Some(100);
            }
        }

        self.refresh_amd(false);
        let pl1_now = self.last_pl1.or_else(|| self.hw.read_pl1_w().map(|w| w.round() as i32));
        let tick = Tick {
            profile: profile.clone(),
            demand: self.demand,
            n_busy,
            emergency,
            pl1_now,
            epp: self.last_epp.clone(),
            skin,
        };
        self.write_status(&tick, raw, n_hot, psi, tc0p, pl1);
        tick
    }

    fn write_status(
        &mut self,
        tick: &Tick,
        raw: f64,
        n_hot: u32,
        psi: f64,
        tc0p: Option<f64>,
        pl1_target: i32,
    ) {
        let blob = serde_json::json!({
            "profile": tick.profile,
            "demand": round_to(self.demand, 3),
            "raw": round_to(raw, 3),
            "n_busy": tick.n_busy,
            "n_hot": n_hot,
            "psi_avg10": psi,
            "pkg_w": self.pkg_w.map(|w| round_to(w, 1)),
            "skin_c": tick.skin.map(|s| round_to(s, 1)),
            "tc0p_c": tc0p.map(|s| round_to(s, 1)),
            "pl1_target_w": pl1_target,
            "pl1_now_w": tick.pl1_now,
            "epp": tick.epp,
            "emergency": tick.emergency,
            "rapl_ok": self.rapl_ok,
            "dry_run": self.dry_run,
            "amd_dpm": self.amd_dpm,
        })
        .to_string()
            + "\n";
        if blob == self.last_status_blob {
            return;
        }
        self.last_status_blob = blob.clone();
        let tmp = format!("{STATUS_PATH}.tmp");
        if let Ok(mut f) = fs::File::create(&tmp) {
            if f.write_all(blob.as_bytes()).is_ok() {
                let _ = fs::rename(tmp, STATUS_PATH);
            }
        }
    }

    fn restore(&mut self) {
        if self.dry_run {
            return;
        }
        self.hw.write_pl1_w(self.cfg.firmware_pl1_w);
        self.hw.max_perf.write_str("100");
        self.ppd.restore(&self.started_profile);
        eprintln!(
            "restored PL1={} W max_perf_pct=100 PPD {}",
            self.cfg.firmware_pl1_w, self.started_profile
        );
    }

    fn run(&mut self, stop: &AtomicBool) {
        if self.amd_dpm.as_deref().is_some_and(|d| d != "low") {
            eprintln!(
                "WARNING: AMD DPM is {:?}, expected low — not writing it",
                self.amd_dpm
            );
        }
        eprintln!(
            "start profile={} dry_run={} PL1={:?} EPP={:?} DPM={:?}",
            self.started_profile,
            self.dry_run,
            self.hw.read_pl1_w(),
            self.hw.read_epp(),
            self.amd_dpm
        );
        thread::sleep(Duration::from_millis(250));
        while !stop.load(Ordering::Relaxed) {
            let tick = self.loop_once();
            if self.last_status_log.elapsed() >= Duration::from_secs(15) {
                self.last_status_log = Instant::now();
                eprintln!(
                    "profile={} demand={:.2} busy={} skin={:?} PL1={:?} EPP={:?}",
                    tick.profile, tick.demand, tick.n_busy, tick.skin, tick.pl1_now, tick.epp
                );
            }
            let idle = tick.demand < 0.05 && tick.n_busy <= 1 && !tick.emergency;
            let wait = if idle {
                self.cfg.interval_idle_s
            } else {
                self.cfg.interval_s
            };
            thread::sleep(Duration::from_secs_f64(wait.max(0.2)));
        }
        self.restore();
    }
}

fn usage() {
    eprintln!(
        "mbp16-1-powerd [--config PATH] [--dry-run]\n  occupancy + skin RAPL/EPP policy for MacBookPro16,1"
    );
}

fn parse_args() -> Option<(PathBuf, bool)> {
    let mut config = PathBuf::from(DEFAULT_CONF);
    let mut dry_run = false;
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                usage();
                return None;
            }
            "--dry-run" => dry_run = true,
            "--config" => {
                config = args.next().map(PathBuf::from).unwrap_or(config);
            }
            other if other.starts_with("--config=") => {
                config = PathBuf::from(other.trim_start_matches("--config="));
            }
            other => {
                eprintln!("unknown argument: {other}");
                usage();
                return None;
            }
        }
    }
    Some((config, dry_run))
}

fn euid() -> u32 {
    unsafe { libc::geteuid() }
}

fn main() -> ExitCode {
    if euid() != 0 {
        eprintln!("mbp16-1-powerd must run as root");
        return ExitCode::FAILURE;
    }
    let Some((config_path, dry_run)) = parse_args() else {
        return ExitCode::FAILURE;
    };
    let cfg = Config::load(&config_path);
    let stop = Arc::new(AtomicBool::new(false));
    if let Err(err) = signal_hook::flag::register(signal_hook::consts::SIGTERM, Arc::clone(&stop))
    {
        eprintln!("signal SIGTERM: {err}");
        return ExitCode::FAILURE;
    }
    if let Err(err) = signal_hook::flag::register(signal_hook::consts::SIGINT, Arc::clone(&stop)) {
        eprintln!("signal SIGINT: {err}");
        return ExitCode::FAILURE;
    }
    match Daemon::new(cfg, dry_run) {
        Ok(mut daemon) => {
            daemon.run(&stop);
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("failed to start: {err}");
            ExitCode::FAILURE
        }
    }
}
