# mbp16-1-powerd

Rust occupancy + skin RAPL/EPP policy for this MacBookPro16,1. Super menu (`power-saver` / `balanced` / `performance`) is the only UI. The daemon never wraps jobs and never calls `powerprofilesctl set` / `HoldProfile` / `omarchy-powerprofiles-set` except restore-on-stop.

Apple firmware PL1 is **100 W**, PL2 **125 W**. This process writes PL1 + EPP **inside** the Super envelope from core occupancy, CPU PSI, package watts, and applesmc `Ts0S`/`Ts1S`. PL2 is fixed per profile (`pl2_w`, `0` = firmware) and re-asserted if anything else moves it.

**Never writes:** AMD DPM, `no_turbo`, `fan*_output`, `brcmfmac`, `t2bce`.

## Envelopes (`/etc/mbp16-1-powerd.conf`)

| Super | Idle desk | Many busy cores | PL2 | Skin hard stop |
| --- | --- | --- | --- | --- |
| power-saver | 22 W, EPP `power` | 32 W, `balance_power` | 70 W | 40 °C |
| **balanced** (AC here) | **40 W**, `balance_power` | 48 W, `balance_performance` | 70 W | 43 °C |
| performance | 45 W, `balance_performance` | 80 W, `performance` | firmware 125 W | 43 °C |

Balanced was 58 W busy with firmware PL2 125 W until 2026-11-09. A three-way test under sustained 12-thread load picked 48/70: die 93 → 84 °C, time at TjMax 34 % → 0 %, palm rest and trackpad no warmer, sustained throughput −1.7 %, single-thread unchanged. Long all-core builds lose about 2 %; switch to `performance` for those.

Occupancy: util ≥ 0.50 = busy; first busy core ignored; `occ = clamp((n_busy−1)/5)`; four cores ≥ 0.80 → `occ = max(occ, 0.75)`. Skin fades from 40 °C to `skin_hard`. EMA τ_up 2.5 s, τ_down 15 s. Idle poll 3 s.

## Install

Needs root for RAPL/EPP sysfs. Rust via **Omarchy** `omarchy install dev-env rust` (rustup), not a random curl. The toolbox does that for you:

```bash
mbp16-1 deps rust     # omarchy-install-dev-env rust if cargo/rustc are missing
mbp16-1 apply power
```

Or by hand after rustup (`~/.cargo/env` on PATH):

```bash
cargo build --release
sudo install -m 0755 target/release/mbp16-1-powerd /usr/local/sbin/mbp16-1-powerd
sudo install -m 0644 mbp16-1-powerd.conf /etc/mbp16-1-powerd.conf
sudo install -m 0644 mbp16-1-powerd.service /etc/systemd/system/mbp16-1-powerd.service
sudo systemctl daemon-reload
sudo systemctl enable --now mbp16-1-powerd.service
```

The unit must not `After=power-profiles-daemon.service`: PPD is `After=multi-user.target`, which cycles with `WantedBy=multi-user.target` and systemd drops the start job. Powerd polls PPD on its own.

AC envelope: `omarchy-powerprofiles-set ac balanced`.

Status: `cat /run/mbp16-1-powerd/status`. Stop (restores firmware PL1 100 W and PL2 125 W): `sudo systemctl disable --now mbp16-1-powerd`.

Do not install TLP / auto-cpufreq / watt.
