//! Loopback listeners that come back after the system takes their socket
//! away. iOS reclaims the listening sockets of an app it suspends: back in
//! the foreground, `accept` only fails and connections to the port are
//! refused. The listener then listens again, on the same port when it is
//! free, so the addresses already handed out keep working.

use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicU16, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::Duration;

/// Failed accepts in a row taken as a lost socket rather than a passing
/// shortage (too many open files, a connection aborted before it was
/// taken).
const FAILURES: u32 = 5;

/// How long a check waits for the listener to answer.
const PROBE: Duration = Duration::from_millis(500);

type Serve = Box<dyn Fn(TcpStream) + Send + Sync>;
type Log = Box<dyn Fn(String) + Send + Sync>;

pub struct Loopback {
    name: &'static str,
    port: AtomicU16,
    /// Counts the listeners; a thread whose listener was replaced ends.
    generation: AtomicU64,
    rebinding: Mutex<()>,
    stopped: AtomicBool,
    /// The thread of the newest listener.
    thread: Mutex<Option<JoinHandle<()>>>,
    serve: Serve,
    log: Log,
}

impl Loopback {
    /// Listens on a random loopback port and hands each connection to
    /// [serve] on the accepting thread, named [name].
    pub fn start(name: &'static str, serve: Serve, log: Log) -> std::io::Result<Arc<Loopback>> {
        let listener = TcpListener::bind("127.0.0.1:0")?;
        let loopback = Arc::new(Loopback {
            name,
            port: AtomicU16::new(listener.local_addr()?.port()),
            generation: AtomicU64::new(0),
            rebinding: Mutex::new(()),
            stopped: AtomicBool::new(false),
            thread: Mutex::new(None),
            serve,
            log,
        });
        loopback.clone().spawn(listener, 0)?;
        Ok(loopback)
    }

    pub fn port(&self) -> u16 {
        self.port.load(Ordering::SeqCst)
    }

    /// Makes sure the port still takes connections and listens again when
    /// it does not; the port to use.
    pub fn ensure(self: &Arc<Self>) -> u16 {
        let seen = self.generation.load(Ordering::SeqCst);
        let port = self.port();
        if self.stopped.load(Ordering::SeqCst) || answers(port) {
            return port;
        }
        self.rebind(seen, "it no longer took connections");
        self.port()
    }

    /// Stops listening: the port is closed when this returns.
    pub fn stop(&self) {
        self.stopped.store(true, Ordering::SeqCst);
        // Wakes the accepting thread, which then sees [stopped].
        let _ = TcpStream::connect_timeout(&address(self.port()), PROBE);
        let thread = self.thread.lock().unwrap_or_else(|e| e.into_inner()).take();
        if let Some(thread) = thread
            && thread.thread().id() != std::thread::current().id()
        {
            let _ = thread.join();
        }
    }

    fn spawn(self: Arc<Self>, listener: TcpListener, generation: u64) -> std::io::Result<()> {
        let me = self.clone();
        let thread = std::thread::Builder::new()
            .name(self.name.into())
            .spawn(move || me.accept(listener, generation))?;
        *self.thread.lock().unwrap_or_else(|e| e.into_inner()) = Some(thread);
        Ok(())
    }

    fn current(&self, generation: u64) -> bool {
        self.generation.load(Ordering::SeqCst) == generation
    }

    fn accept(self: Arc<Self>, listener: TcpListener, generation: u64) {
        let mut failures = 0;
        loop {
            match listener.accept() {
                Ok((client, _)) => {
                    failures = 0;
                    if self.stopped.load(Ordering::SeqCst) {
                        return;
                    }
                    // Taken by a listener that was replaced meanwhile: it is
                    // still served, then this thread ends.
                    let replaced = !self.current(generation);
                    (self.serve)(client);
                    if replaced {
                        return;
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(e) => {
                    if !self.current(generation) {
                        return;
                    }
                    failures += 1;
                    if failures < FAILURES {
                        std::thread::sleep(Duration::from_millis(20 << failures));
                        continue;
                    }
                    // Closed first, so its port can be taken again.
                    drop(listener);
                    self.rebind(generation, &format!("accepting failed: {e}"));
                    return;
                }
            }
        }
    }

    /// Listens again, unless another listener already replaced the one of
    /// [seen].
    fn rebind(self: &Arc<Self>, seen: u64, why: &str) {
        let _one = self.rebinding.lock().unwrap_or_else(|e| e.into_inner());
        if !self.current(seen) || self.stopped.load(Ordering::SeqCst) {
            return;
        }
        let old = self.port();
        let listener =
            TcpListener::bind(address(old)).or_else(|_| TcpListener::bind("127.0.0.1:0"));
        let listener = match listener.and_then(|l| l.local_addr().map(|a| (l, a.port()))) {
            Ok(found) => found,
            Err(e) => {
                (self.log)(format!(
                    "The {} on port {old} stopped ({why}) and could not listen again: {e}",
                    self.name
                ));
                return;
            }
        };
        let (listener, port) = listener;
        let generation = seen + 1;
        self.port.store(port, Ordering::SeqCst);
        self.generation.store(generation, Ordering::SeqCst);
        match self.clone().spawn(listener, generation) {
            Ok(()) if port == old => (self.log)(format!(
                "The {} on port {old} stopped ({why}); listening again",
                self.name
            )),
            Ok(()) => (self.log)(format!(
                "The {} on port {old} stopped ({why}); listening on port {port}",
                self.name
            )),
            Err(e) => (self.log)(format!(
                "The {} could not start a thread to listen again: {e}",
                self.name
            )),
        }
    }
}

fn address(port: u16) -> SocketAddr {
    SocketAddr::from(([127, 0, 0, 1], port))
}

/// Whether something takes connections on [port].
fn answers(port: u16) -> bool {
    TcpStream::connect_timeout(&address(port), PROBE).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};

    fn echo() -> Arc<Loopback> {
        Loopback::start(
            "test listener",
            Box::new(|mut client| {
                std::thread::spawn(move || {
                    let mut byte = [0u8; 1];
                    if client.read_exact(&mut byte).is_ok() {
                        let _ = client.write_all(&byte);
                    }
                });
            }),
            Box::new(|_| {}),
        )
        .unwrap()
    }

    fn round_trip(port: u16) -> bool {
        let Ok(mut stream) = TcpStream::connect_timeout(&address(port), PROBE) else {
            return false;
        };
        let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
        let mut byte = [0u8; 1];
        stream.write_all(b"x").is_ok() && stream.read_exact(&mut byte).is_ok() && &byte == b"x"
    }

    #[test]
    fn a_live_listener_keeps_its_port() {
        let loopback = echo();
        let port = loopback.port();
        assert_eq!(loopback.ensure(), port);
        assert!(round_trip(port));
        loopback.stop();
    }

    /// What iOS does to a suspended app: the socket goes, the thread
    /// keeps waiting on it. A check listens again, on the same port.
    #[test]
    fn listens_again_after_losing_its_socket() {
        let loopback = echo();
        let port = loopback.port();
        // The listener's socket is gone: its generation no longer counts and
        // nothing answers on the port.
        loopback.generation.fetch_add(1, Ordering::SeqCst);
        let _ = TcpStream::connect(address(port));
        std::thread::sleep(Duration::from_millis(100));
        assert!(!answers(port));
        loopback.generation.fetch_sub(1, Ordering::SeqCst);
        let again = loopback.ensure();
        assert_eq!(again, port);
        assert!(round_trip(again));
        assert_eq!(loopback.ensure(), port);
        loopback.stop();
    }

    #[test]
    fn takes_another_port_when_its_own_is_taken() {
        let loopback = echo();
        let port = loopback.port();
        loopback.generation.fetch_add(1, Ordering::SeqCst);
        let _ = TcpStream::connect(address(port));
        std::thread::sleep(Duration::from_millis(100));
        // Something else listens there now but never accepts: still taken.
        let squatter = TcpListener::bind(address(port)).unwrap();
        loopback.generation.fetch_sub(1, Ordering::SeqCst);
        // It answers (the backlog accepts), so ensure keeps it; the accept
        // thread is the one that notices. Simulate that path directly.
        loopback.rebind(0, "test");
        let moved = loopback.port();
        assert_ne!(moved, port);
        assert!(round_trip(moved));
        drop(squatter);
        loopback.stop();
    }
}
