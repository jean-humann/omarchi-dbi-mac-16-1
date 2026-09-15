pub const EPP_ORDER: [&str; 4] = ["power", "balance_power", "balance_performance", "performance"];

pub fn clamp(x: f64, lo: f64, hi: f64) -> f64 {
    x.max(lo).min(hi)
}

pub fn ema(prev: f64, raw: f64, dt: f64, tau_up: f64, tau_down: f64) -> f64 {
    let tau = if raw > prev { tau_up } else { tau_down };
    let alpha = 1.0 - (-dt / tau.max(0.05)).exp();
    prev + alpha * (raw - prev)
}

pub fn pick_epp(idle: &str, busy: &str, demand: f64) -> &'static str {
    let idle_i = index_of(idle).unwrap_or(1);
    let busy_i = index_of(busy).unwrap_or(idle_i);
    let span = busy_i as f64 - idle_i as f64;
    let mut idx = (idle_i as f64 + demand * span).round() as i32;
    let lo = idle_i.min(busy_i);
    let hi = idle_i.max(busy_i);
    idx = idx.clamp(lo, hi);
    EPP_ORDER[idx as usize]
}

fn index_of(name: &str) -> Option<i32> {
    EPP_ORDER.iter().position(|n| *n == name).map(|i| i as i32)
}

pub fn occupancy(utils: &[f64], busy_u: f64, hot_u: f64) -> (f64, u32, u32) {
    let n_busy = utils.iter().filter(|u| **u >= busy_u).count() as u32;
    let n_hot = utils.iter().filter(|u| **u >= hot_u).count() as u32;
    let mut occ = clamp((n_busy as f64 - 1.0) / 5.0, 0.0, 1.0);
    if n_hot >= 4 {
        occ = occ.max(0.75);
    }
    (occ, n_busy, n_hot)
}

pub fn core_utils(prev: &[(u64, u64)], cur: &[(u64, u64)]) -> Vec<f64> {
    prev.iter()
        .zip(cur)
        .map(|((pi, pt), (ci, ct))| {
            let dt = ct.saturating_sub(*pt);
            if dt == 0 {
                0.0
            } else {
                clamp(1.0 - ((ci.saturating_sub(*pi)) as f64 / dt as f64), 0.0, 1.0)
            }
        })
        .collect()
}

pub fn round_to(x: f64, digits: u32) -> f64 {
    let p = 10f64.powi(digits as i32);
    (x * p).round() / p
}
