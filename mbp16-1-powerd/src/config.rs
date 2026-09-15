use std::collections::HashMap;
use std::fs;
use std::path::Path;

#[derive(Clone, Debug)]
pub struct Envelope {
    pub pl1_idle: i32,
    pub pl1_busy: i32,
    pub epp_idle: String,
    pub epp_busy: String,
    pub skin_hard: f64,
}

#[derive(Clone, Debug)]
pub struct Config {
    pub interval_s: f64,
    pub interval_idle_s: f64,
    pub tau_up_s: f64,
    pub tau_down_s: f64,
    pub skin_fade_c: f64,
    pub busy_core_util: f64,
    pub hot_core_util: f64,
    pub firmware_pl1_w: i32,
    pub psi_busy_pct: f64,
    pub idle_watts: f64,
    pub busy_watts: f64,
    pub envelopes: HashMap<String, Envelope>,
}

impl Config {
    pub fn load(path: &Path) -> Self {
        let mut ini = defaults_ini();
        if let Ok(text) = fs::read_to_string(path) {
            merge_ini(&mut ini, &parse_ini(&text));
        }
        Self::from_ini(&ini)
    }

    pub fn envelope(&self, profile: &str) -> &Envelope {
        self.envelopes
            .get(profile)
            .unwrap_or_else(|| &self.envelopes["balanced"])
    }

    fn from_ini(ini: &HashMap<String, HashMap<String, String>>) -> Self {
        let g = |k: &str| f64_of(ini, "general", k);
        let mut envelopes = HashMap::new();
        for name in ["power-saver", "balanced", "performance"] {
            envelopes.insert(
                name.to_string(),
                Envelope {
                    pl1_idle: i32_of(ini, name, "pl1_idle_w"),
                    pl1_busy: i32_of(ini, name, "pl1_busy_w"),
                    epp_idle: str_of(ini, name, "epp_idle"),
                    epp_busy: str_of(ini, name, "epp_busy"),
                    skin_hard: f64_of(ini, name, "skin_hard_c"),
                },
            );
        }
        Self {
            interval_s: g("interval_s"),
            interval_idle_s: g("interval_idle_s"),
            tau_up_s: g("tau_up_s"),
            tau_down_s: g("tau_down_s"),
            skin_fade_c: g("skin_fade_c"),
            busy_core_util: g("busy_core_util"),
            hot_core_util: g("hot_core_util"),
            firmware_pl1_w: i32_of(ini, "general", "firmware_pl1_w"),
            psi_busy_pct: g("psi_busy_pct"),
            idle_watts: g("idle_watts"),
            busy_watts: g("busy_watts"),
            envelopes,
        }
    }
}

fn defaults_ini() -> HashMap<String, HashMap<String, String>> {
    parse_ini(
        r#"
[general]
interval_s = 1.0
interval_idle_s = 3.0
tau_up_s = 2.5
tau_down_s = 15
skin_fade_c = 40
busy_core_util = 0.50
hot_core_util = 0.80
firmware_pl1_w = 100
psi_busy_pct = 20
idle_watts = 18
busy_watts = 50

[power-saver]
pl1_idle_w = 22
pl1_busy_w = 32
epp_idle = power
epp_busy = balance_power
skin_hard_c = 40

[balanced]
pl1_idle_w = 40
pl1_busy_w = 58
epp_idle = balance_power
epp_busy = balance_performance
skin_hard_c = 43

[performance]
pl1_idle_w = 45
pl1_busy_w = 80
epp_idle = balance_performance
epp_busy = performance
skin_hard_c = 43
"#,
    )
}

fn parse_ini(text: &str) -> HashMap<String, HashMap<String, String>> {
    let mut out: HashMap<String, HashMap<String, String>> = HashMap::new();
    let mut section = String::from("general");
    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if let Some(name) = line.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
            section = name.trim().to_string();
            out.entry(section.clone()).or_default();
            continue;
        }
        let Some((k, v)) = line.split_once('=') else {
            continue;
        };
        out.entry(section.clone())
            .or_default()
            .insert(k.trim().to_string(), v.trim().to_string());
    }
    out
}

fn merge_ini(
    base: &mut HashMap<String, HashMap<String, String>>,
    extra: &HashMap<String, HashMap<String, String>>,
) {
    for (section, keys) in extra {
        let dest = base.entry(section.clone()).or_default();
        for (k, v) in keys {
            dest.insert(k.clone(), v.clone());
        }
    }
}

fn str_of(ini: &HashMap<String, HashMap<String, String>>, section: &str, key: &str) -> String {
    ini.get(section)
        .and_then(|s| s.get(key))
        .cloned()
        .unwrap_or_default()
}

fn f64_of(ini: &HashMap<String, HashMap<String, String>>, section: &str, key: &str) -> f64 {
    str_of(ini, section, key).parse().unwrap_or(0.0)
}

fn i32_of(ini: &HashMap<String, HashMap<String, String>>, section: &str, key: &str) -> i32 {
    f64_of(ini, section, key) as i32
}
