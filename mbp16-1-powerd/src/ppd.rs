use std::time::{Duration, Instant};

const DEST: &str = "org.freedesktop.UPower.PowerProfiles";
const PATH: &str = "/org/freedesktop/UPower/PowerProfiles";
const IFACE: &str = "org.freedesktop.UPower.PowerProfiles";

/// Persistent system-bus connection. No busctl child process.
pub struct Ppd {
    conn: Option<zbus::blocking::Connection>,
    cached: String,
    next_refresh: Instant,
}

impl Ppd {
    pub fn connect() -> Self {
        let mut ppd = Self {
            conn: None,
            cached: "balanced".into(),
            next_refresh: Instant::now(),
        };
        match zbus::blocking::Connection::system() {
            Ok(conn) => {
                ppd.conn = Some(conn);
                ppd.pull();
            }
            Err(err) => eprintln!("D-Bus unavailable ({err}); PPD stays 'balanced'"),
        }
        ppd
    }

    fn proxy(&self) -> Option<zbus::blocking::Proxy<'_>> {
        let conn = self.conn.as_ref()?;
        zbus::blocking::Proxy::new(conn, DEST, PATH, IFACE).ok()
    }

    fn pull(&mut self) {
        let result = self.proxy().and_then(|proxy| proxy.get_property::<String>("ActiveProfile").ok());
        if let Some(profile) = result {
            if !profile.is_empty() {
                self.cached = profile;
            }
        }
        self.next_refresh = Instant::now() + Duration::from_secs(15);
    }

    pub fn profile(&mut self) -> &str {
        if Instant::now() >= self.next_refresh {
            self.pull();
        }
        &self.cached
    }

    pub fn restore(&self, profile: &str) {
        if let Some(proxy) = self.proxy() {
            if let Err(err) = proxy.set_property("ActiveProfile", profile) {
                eprintln!("PPD restore failed: {err}");
            }
        }
    }
}
