//! Notices when the network under the app changes: Wi-Fi to cable or
//! mobile data, a VPN coming up or going down. A connection opened on the
//! old route can hang until its read timeout (two minutes) while the new
//! route works, so on a change the connection pools are dropped and reads
//! still waiting on the old route give up at once; the relay then goes on
//! from the byte it had reached.
//!
//! The route is read the way the system picks it: a UDP socket "connected"
//! to a public address sends nothing, yet takes the source address of the
//! default route. No permission, no platform API, the same on every system.

use std::collections::VecDeque;
use std::net::{SocketAddr, UdpSocket};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex, Once};
use std::time::Duration;

/// How often the route is read.
const EVERY: Duration = Duration::from_secs(2);

static GENERATION: AtomicU64 = AtomicU64::new(0);
static LOG: LazyLock<Mutex<VecDeque<String>>> = LazyLock::new(|| Mutex::new(VecDeque::new()));
static START: Once = Once::new();

/// Bumped on every change of route; equal readings mean the same network.
pub fn generation() -> u64 {
    START.call_once(start);
    GENERATION.load(Ordering::Acquire)
}

/// The log lines since the last call.
pub fn take_log() -> Vec<String> {
    LOG.lock()
        .unwrap_or_else(|e| e.into_inner())
        .drain(..)
        .collect()
}

/// The source addresses of the default IPv4 and IPv6 routes, or none
/// where that family has no route.
pub(crate) fn route() -> (Option<SocketAddr>, Option<SocketAddr>) {
    fn source(bind: &str, to: &str) -> Option<SocketAddr> {
        let socket = UdpSocket::bind(bind).ok()?;
        socket.connect(to).ok()?;
        socket.local_addr().ok().map(|mut a| {
            // The port is new for every socket; only the address names the route.
            a.set_port(0);
            a
        })
    }
    (
        source("0.0.0.0:0", "8.8.8.8:53"),
        source("[::]:0", "[2001:4860:4860::8888]:53"),
    )
}

fn describe(route: &(Option<SocketAddr>, Option<SocketAddr>)) -> String {
    match route {
        (None, None) => "no route".into(),
        (Some(_), None) => "IPv4".into(),
        (None, Some(_)) => "IPv6".into(),
        (Some(_), Some(_)) => "IPv4 and IPv6".into(),
    }
}

/// Whether two readings name different networks.
pub(crate) fn changed(
    before: &(Option<SocketAddr>, Option<SocketAddr>),
    now: &(Option<SocketAddr>, Option<SocketAddr>),
) -> bool {
    before != now
}

fn start() {
    let spawned = std::thread::Builder::new()
        .name("lumtub-netwatch".into())
        .spawn(|| {
            let mut last = route();
            loop {
                std::thread::sleep(EVERY);
                let now = route();
                if !changed(&last, &now) {
                    continue;
                }
                // Losing the route for a moment is common while switching;
                // the change is counted once the new route is there.
                if now == (None, None) {
                    last = now;
                    continue;
                }
                GENERATION.fetch_add(1, Ordering::AcqRel);
                crate::http::network_changed();
                let mut log = LOG.lock().unwrap_or_else(|e| e.into_inner());
                if log.len() >= 20 {
                    log.pop_front();
                }
                // Addresses are not written: they can identify the user.
                log.push_back(format!(
                    "The network changed (now {}); open connections are dropped and reads go on over the new route",
                    describe(&now)
                ));
                last = now;
            }
        });
    if spawned.is_err() {
        eprintln!("lumtub: could not watch the network for changes");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reading_the_route_sends_nothing_and_does_not_fail() {
        let (v4, v6) = route();
        for addr in [v4, v6].into_iter().flatten() {
            assert_eq!(addr.port(), 0);
        }
        assert_eq!(route(), route());
    }

    #[test]
    fn a_new_source_address_is_a_change() {
        let a: SocketAddr = "192.168.1.5:0".parse().unwrap();
        let b: SocketAddr = "10.8.0.2:0".parse().unwrap();
        assert!(!changed(&(Some(a), None), &(Some(a), None)));
        assert!(changed(&(Some(a), None), &(Some(b), None)));
        assert!(changed(
            &(Some(a), None),
            &(Some(a), Some("[fe80::1]:0".parse().unwrap()))
        ));
    }
}
