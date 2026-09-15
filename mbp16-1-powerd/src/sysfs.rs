use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

const SMC_DIR: &str = "/sys/bus/acpi/devices/APP0001:00";
const WANT_SMC: &[&str] = &["Ts0S", "Ts1S", "Ts0P", "TC0P"];
const RAPL_PL1: &str = "/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw";
const RAPL_ENERGY: &str = "/sys/class/powercap/intel-rapl:0/energy_uj";
const MAX_PERF: &str = "/sys/devices/system/cpu/intel_pstate/max_perf_pct";
const CPUFREQ: &str = "/sys/devices/system/cpu/cpufreq";
const DRM: &str = "/sys/class/drm";

pub struct SysfsFile {
    file: File,
}

impl SysfsFile {
    pub fn open_ro(path: impl AsRef<Path>) -> io::Result<Self> {
        Ok(Self {
            file: File::open(path)?,
        })
    }

    pub fn open_rw(path: impl AsRef<Path>) -> io::Result<Self> {
        Ok(Self {
            file: OpenOptions::new().read(true).write(true).open(path)?,
        })
    }

    pub fn read_string(&mut self) -> io::Result<String> {
        self.file.seek(SeekFrom::Start(0))?;
        let mut buf = String::new();
        self.file.read_to_string(&mut buf)?;
        Ok(buf.trim().to_string())
    }

    pub fn read_i64(&mut self) -> Option<i64> {
        self.read_string().ok()?.parse().ok()
    }

    pub fn write_str(&mut self, value: &str) -> bool {
        self.file.seek(SeekFrom::Start(0)).is_ok() && self.file.write_all(value.as_bytes()).is_ok()
    }
}

pub struct Hardware {
    pub stat: SysfsFile,
    pub psi: SysfsFile,
    pub pl1: SysfsFile,
    pub energy: SysfsFile,
    pub max_perf: SysfsFile,
    pub smc: HashMap<String, SysfsFile>,
    pub epp: Vec<SysfsFile>,
    pub amd_dpm_path: Option<PathBuf>,
}

impl Hardware {
    pub fn open() -> io::Result<Self> {
        Ok(Self {
            stat: SysfsFile::open_ro("/proc/stat")?,
            psi: SysfsFile::open_ro("/proc/pressure/cpu")?,
            pl1: SysfsFile::open_rw(RAPL_PL1)?,
            energy: SysfsFile::open_ro(RAPL_ENERGY)?,
            max_perf: SysfsFile::open_rw(MAX_PERF)?,
            smc: discover_smc(),
            epp: discover_epp(),
            amd_dpm_path: discover_amd_dpm(),
        })
    }

    pub fn read_pl1_w(&mut self) -> Option<f64> {
        self.pl1.read_i64().map(|u| u as f64 / 1_000_000.0)
    }

    pub fn write_pl1_w(&mut self, watts: i32) -> bool {
        self.pl1.write_str(&format!("{}", watts as i64 * 1_000_000))
    }

    pub fn write_epp(&mut self, name: &str) -> bool {
        let mut ok = true;
        for node in &mut self.epp {
            if !node.write_str(name) {
                ok = false;
            }
        }
        ok
    }

    pub fn read_epp(&mut self) -> Option<String> {
        self.epp.first_mut()?.read_string().ok()
    }

    pub fn smc_temps(&mut self) -> HashMap<String, f64> {
        let mut out = HashMap::new();
        for (name, node) in &mut self.smc {
            if let Some(mill) = node.read_i64() {
                out.insert(name.clone(), mill as f64 / 1000.0);
            }
        }
        out
    }

    pub fn read_proc_stat(&mut self) -> Vec<(u64, u64)> {
        let Ok(text) = self.stat.read_string() else {
            return Vec::new();
        };
        let mut rows = Vec::new();
        for line in text.lines() {
            if !line.starts_with("cpu") || line.as_bytes().get(3).is_none_or(|c| !c.is_ascii_digit())
            {
                continue;
            }
            let nums: Vec<u64> = line
                .split_whitespace()
                .skip(1)
                .filter_map(|s| s.parse().ok())
                .collect();
            if nums.len() < 4 {
                continue;
            }
            let idle = nums[3] + nums.get(4).copied().unwrap_or(0);
            let total: u64 = nums.iter().sum();
            rows.push((idle, total));
        }
        rows
    }

    pub fn psi_some_avg10(&mut self) -> f64 {
        let Ok(text) = self.psi.read_string() else {
            return 0.0;
        };
        let Some(first) = text.lines().next() else {
            return 0.0;
        };
        for tok in first.split_whitespace() {
            if let Some(v) = tok.strip_prefix("avg10=") {
                return v.parse().unwrap_or(0.0);
            }
        }
        0.0
    }

    pub fn read_amd_dpm(&self) -> Option<String> {
        let path = self.amd_dpm_path.as_ref()?;
        fs::read_to_string(path)
            .ok()
            .map(|s| s.trim().to_string())
    }
}

fn discover_smc() -> HashMap<String, SysfsFile> {
    let mut found = HashMap::new();
    let dir = Path::new(SMC_DIR);
    let Ok(rd) = fs::read_dir(dir) else {
        return found;
    };
    for ent in rd.flatten() {
        let fname = ent.file_name();
        let fname = fname.to_string_lossy();
        let Some(mid) = fname.strip_prefix("temp").and_then(|s| s.strip_suffix("_label")) else {
            continue;
        };
        let Ok(label) = fs::read_to_string(ent.path()) else {
            continue;
        };
        let label = label.trim();
        if !WANT_SMC.contains(&label) {
            continue;
        }
        let input = dir.join(format!("temp{mid}_input"));
        if let Ok(f) = SysfsFile::open_ro(&input) {
            found.insert(label.to_string(), f);
        }
    }
    found
}

fn discover_epp() -> Vec<SysfsFile> {
    let mut paths: Vec<PathBuf> = fs::read_dir(CPUFREQ)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path().join("energy_performance_preference"))
        .filter(|p| p.is_file())
        .collect();
    paths.sort();
    paths
        .into_iter()
        .filter_map(|p| SysfsFile::open_rw(p).ok())
        .collect()
}

fn discover_amd_dpm() -> Option<PathBuf> {
    let rd = fs::read_dir(DRM).ok()?;
    for ent in rd.flatten() {
        let vendor = ent.path().join("device/vendor");
        let Ok(id) = fs::read_to_string(&vendor) else {
            continue;
        };
        if id.trim() == "0x1002" {
            return Some(ent.path().join("device/power_dpm_force_performance_level"));
        }
    }
    None
}
