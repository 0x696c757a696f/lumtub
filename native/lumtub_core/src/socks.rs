//! A local HTTP proxy that forwards through a SOCKS proxy. libmpv and
//! dart:io can only use HTTP proxies, so a SOCKS setting reaches them as
//! `http://127.0.0.1:port`. It accepts `CONNECT host:port` (https) and
//! plain absolute-URI requests (http), listens on loopback only, and when
//! the SOCKS proxy fails the request fails: nothing connects directly.
//!
//! Every connection is copied on native threads, never through Dart.

use crate::loopback::Loopback;
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{IpAddr, Shutdown, SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

const TIMEOUT: Duration = Duration::from_secs(15);
/// Connections served at once; the next waits until one ends. mpv and yt-dlp open a handful each.
const MAX_CLIENTS: usize = 128;
/// The bridge's threads only copy bytes through a heap buffer.
const STACK: usize = 128 << 10;

/// Where the SOCKS proxy is and how to talk to it.
#[derive(Clone, Debug, PartialEq)]
pub struct Proxy {
    pub host: String,
    pub port: u16,
    pub user: String,
    pub pass: String,
    /// SOCKS4 rather than SOCKS5.
    pub v4: bool,
    /// The proxy resolves names (socks5h, socks4a).
    pub remote_dns: bool,
}

impl Proxy {
    /// `socks5://[user:pass@]host:port`, also `socks5h`, `socks4`, `socks4a`.
    pub fn parse(url: &str) -> Option<Proxy> {
        let (scheme, rest) = url.split_once("://")?;
        let (v4, remote_dns) = match scheme.to_ascii_lowercase().as_str() {
            "socks5" => (false, false),
            "socks5h" => (false, true),
            "socks4" => (true, false),
            "socks4a" => (true, true),
            _ => return None,
        };
        let rest = rest.trim_end_matches('/');
        let (login, address) = rest.rsplit_once('@').unwrap_or(("", rest));
        let (user, pass) = login.split_once(':').unwrap_or((login, ""));
        let (host, port) = split_host_port(address)?;
        let decode = |s: &str| crate::relay::decode(&s.replace('+', "%2B"));
        Some(Proxy {
            host,
            port,
            user: decode(user),
            pass: decode(pass),
            v4,
            remote_dns,
        })
    }
}

/// `host:port` or `[v6]:port`, the brackets removed.
fn split_host_port(text: &str) -> Option<(String, u16)> {
    let (host, port) = text.rsplit_once(':')?;
    let host = host.trim_start_matches('[').trim_end_matches(']');
    let port: u16 = port.parse().ok()?;
    (!host.is_empty() && port > 0).then(|| (host.to_string(), port))
}

pub struct Bridge {
    listener: Arc<Loopback>,
    stop: Arc<AtomicBool>,
    open: Arc<Mutex<HashMap<u64, TcpStream>>>,
    token: String,
}

/// The user name clients give with the bridge's token as the password.
pub const USER: &str = "lumtub";

impl Bridge {
    /// Listens on a random loopback port, and again when the system takes
    /// the socket away (see [Loopback]), and forwards through [proxy] for
    /// clients that log in with [USER] and [Bridge::token]. The proxy's
    /// name is looked up for each connection, not here: this runs on the
    /// caller's thread, and the address may change with the network.
    pub fn start(proxy: Proxy) -> std::io::Result<Bridge> {
        let mut secret = [0u8; 16];
        getrandom::fill(&mut secret).map_err(|e| std::io::Error::other(e.to_string()))?;
        let token: String = secret.iter().map(|b| format!("{b:02x}")).collect();
        let login: Arc<[u8]> = format!(
            "Basic {}",
            crate::edge_tts::base64(format!("{USER}:{token}").as_bytes())
        )
        .into_bytes()
        .into();
        let stop = Arc::new(AtomicBool::new(false));
        let open = Arc::new(Mutex::new(HashMap::new()));
        let (stopping, tracked) = (stop.clone(), open.clone());
        let serving = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let ids = AtomicU64::new(0);
        let listener = Loopback::start(
            "socks-bridge",
            Box::new(move |client| {
                if stopping.load(Ordering::SeqCst) {
                    return;
                }
                let _ = client.set_nodelay(true);
                while serving.load(Ordering::SeqCst) >= MAX_CLIENTS
                    && !stopping.load(Ordering::SeqCst)
                {
                    std::thread::sleep(Duration::from_millis(20));
                }
                let id = ids.fetch_add(1, Ordering::Relaxed);
                if let Ok(copy) = client.try_clone() {
                    tracked.lock().unwrap().insert(id, copy);
                }
                serving.fetch_add(1, Ordering::SeqCst);
                let (proxy, login, mine, count) = (
                    proxy.clone(),
                    login.clone(),
                    tracked.clone(),
                    serving.clone(),
                );
                let spawned = std::thread::Builder::new()
                    .name("socks-client".into())
                    .stack_size(STACK)
                    .spawn(move || {
                        handle(client, &proxy, &login, &mine, id);
                        mine.lock().unwrap().remove(&id);
                        count.fetch_sub(1, Ordering::SeqCst);
                    });
                if spawned.is_err() {
                    // The client was moved into the closure that never
                    // ran; its tracked copy closes the socket.
                    if let Some(socket) = tracked.lock().unwrap().remove(&id) {
                        let _ = socket.shutdown(Shutdown::Both);
                    }
                    serving.fetch_sub(1, Ordering::SeqCst);
                }
            }),
            Box::new(|_| {}),
        )?;
        Ok(Bridge {
            listener,
            stop,
            open,
            token,
        })
    }

    /// The port, listening again first when the socket was taken away.
    pub fn port(&self) -> u16 {
        self.listener.ensure()
    }

    /// The password clients give with [USER] in `Proxy-Authorization`.
    pub fn token(&self) -> &str {
        &self.token
    }

    /// Stops listening and drops the connections still open.
    pub fn close(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        self.listener.stop();
        for (_, socket) in self.open.lock().unwrap().drain() {
            let _ = socket.shutdown(Shutdown::Both);
        }
    }
}

impl Drop for Bridge {
    fn drop(&mut self) {
        self.close();
    }
}

enum Bad {
    Request,
    Login,
    Gateway,
}

fn handle(
    client: TcpStream,
    proxy: &Proxy,
    login: &[u8],
    open: &Mutex<HashMap<u64, TcpStream>>,
    id: u64,
) {
    let Ok(mut writer) = client.try_clone() else {
        return;
    };
    let mut reader = BufReader::new(client);
    let _ = reader.get_ref().set_read_timeout(Some(TIMEOUT));
    let upstream = match open_tunnel(&mut reader, proxy, login) {
        Ok(tunnel) => tunnel,
        Err(bad) => {
            let status = match bad {
                Bad::Request => "400 Bad Request",
                Bad::Login => {
                    "407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm=\"lumtub\""
                }
                Bad::Gateway => "502 Bad Gateway",
            };
            let _ = write!(
                writer,
                "HTTP/1.1 {status}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
            );
            let _ = writer.flush();
            let _ = writer.shutdown(Shutdown::Write);
            // Windows resets a connection closed with bytes unread, which
            // could discard the answer before the client reads it.
            let _ = reader
                .get_ref()
                .set_read_timeout(Some(Duration::from_secs(2)));
            let mut rest = [0u8; 4096];
            let mut left = HEAD_MAX;
            while left > 0
                && let Ok(n @ 1..) = reader.read(&mut rest)
            {
                left = left.saturating_sub(n);
            }
            return;
        }
    };
    let (mut upstream, forward) = upstream;
    if let Ok(copy) = upstream.try_clone() {
        open.lock().unwrap().insert(id | 1 << 63, copy);
    }
    let _ = reader.get_ref().set_read_timeout(None);
    let sent = match &forward {
        None => writer.write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n"),
        Some(bytes) => upstream.write_all(bytes),
    };
    // What the client sent after the head, already read into the buffer.
    let early = reader.buffer().to_vec();
    reader.consume(early.len());
    if sent.is_err() || upstream.write_all(&early).is_err() {
        let _ = upstream.shutdown(Shutdown::Both);
        open.lock().unwrap().remove(&(id | 1 << 63));
        return;
    }
    let (Ok(mut up_read), Ok(mut up_write)) = (upstream.try_clone(), upstream.try_clone()) else {
        let _ = upstream.shutdown(Shutdown::Both);
        open.lock().unwrap().remove(&(id | 1 << 63));
        return;
    };
    let mut client_read = reader.into_inner();
    let to_upstream = std::thread::Builder::new()
        .name("socks-upload".into())
        .stack_size(STACK)
        .spawn(move || {
            pipe(&mut client_read, &mut up_write);
            let _ = up_write.shutdown(Shutdown::Write);
        });
    let Ok(to_upstream) = to_upstream else {
        let _ = writer.shutdown(Shutdown::Both);
        let _ = upstream.shutdown(Shutdown::Both);
        open.lock().unwrap().remove(&(id | 1 << 63));
        return;
    };
    pipe(&mut up_read, &mut writer);
    let _ = writer.shutdown(Shutdown::Write);
    let _ = to_upstream.join();
    let _ = upstream.shutdown(Shutdown::Both);
    open.lock().unwrap().remove(&(id | 1 << 63));
}

/// Copies [from] to [to] until either side ends.
fn pipe(from: &mut TcpStream, to: &mut TcpStream) {
    let mut buffer = vec![0u8; 64 << 10];
    loop {
        match from.read(&mut buffer) {
            Ok(0) => return,
            Ok(n) => {
                if to.write_all(&buffer[..n]).is_err() {
                    return;
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(_) => return,
        }
    }
}

/// Reads the client's request head and opens the SOCKS tunnel it asks for;
/// the request to forward for plain HTTP, none for CONNECT. Only a client
/// whose `Proxy-Authorization` is [login] is served.
fn open_tunnel(
    reader: &mut BufReader<TcpStream>,
    proxy: &Proxy,
    login: &[u8],
) -> Result<(TcpStream, Option<Vec<u8>>), Bad> {
    let head = read_head(reader).ok_or(Bad::Request)?;
    let end = head
        .windows(2)
        .position(|w| w == b"\r\n")
        .ok_or(Bad::Request)?;
    // The other headers, without the login: it is not sent on.
    const FIELD: &[u8] = b"proxy-authorization:";
    let mut allowed = false;
    let mut fields = Vec::with_capacity(head.len() - end);
    for field in head[end + 2..].split_inclusive(|&b| b == b'\n') {
        match field.get(..FIELD.len()) {
            Some(name) if name.eq_ignore_ascii_case(FIELD) => {
                allowed |= same(field[FIELD.len()..].trim_ascii(), login);
            }
            _ => fields.extend_from_slice(field),
        }
    }
    if !allowed {
        return Err(Bad::Login);
    }
    let line = String::from_utf8_lossy(&head[..end]).into_owned();
    let parts: Vec<&str> = line.split(' ').collect();
    let [method, target, version] = parts[..] else {
        return Err(Bad::Request);
    };
    let (host, port, forward) = if method.eq_ignore_ascii_case("CONNECT") {
        let (host, port) = split_host_port(target).ok_or(Bad::Request)?;
        (host, port, None)
    } else {
        let rest = target.strip_prefix("http://").ok_or(Bad::Request)?;
        let (authority, path) = rest
            .find(['/', '?'])
            .map_or((rest, "/"), |i| (&rest[..i], &rest[i..]));
        let path = if path.starts_with('?') {
            format!("/{path}")
        } else {
            path.to_string()
        };
        let (host, port) = split_host_port(authority)
            .or_else(|| (!authority.is_empty()).then(|| (authority.to_string(), 80)))
            .ok_or(Bad::Request)?;
        let mut forward = format!("{method} {path} {version}\r\n").into_bytes();
        forward.extend_from_slice(&fields);
        (host, port, Some(forward))
    };
    let upstream = connect(proxy, &host, port).map_err(|_| Bad::Gateway)?;
    Ok((upstream, forward))
}

/// Whether [a] and [b] are equal, compared in time that does not depend
/// on where they differ.
fn same(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0, |d, (x, y)| d | (x ^ y)) == 0
}

const HEAD_MAX: usize = 64 << 10;

/// An HTTP request head, up to and including the blank line; none past
/// [HEAD_MAX] bytes, which are never read.
fn read_head(reader: &mut BufReader<TcpStream>) -> Option<Vec<u8>> {
    let mut head = Vec::new();
    loop {
        let room = (HEAD_MAX + 1 - head.len()) as u64;
        let n = reader
            .by_ref()
            .take(room)
            .read_until(b'\n', &mut head)
            .ok()?;
        if n == 0 || head.len() > HEAD_MAX {
            return None;
        }
        if head.ends_with(b"\r\n\r\n") {
            return Some(head);
        }
    }
}

/// Opens a tunnel to [host]:[port] through [proxy].
pub fn connect(proxy: &Proxy, host: &str, port: u16) -> std::io::Result<TcpStream> {
    // This PC (the app's own relay) is reached directly: through the proxy,
    // 127.0.0.1 would be the proxy server's own machine.
    if host.eq_ignore_ascii_case("localhost")
        || host.parse::<IpAddr>().is_ok_and(|ip| ip.is_loopback())
    {
        let socket = TcpStream::connect((host, port))?;
        socket.set_nodelay(true)?;
        return Ok(socket);
    }
    let address = (proxy.host.as_str(), proxy.port)
        .to_socket_addrs()?
        .next()
        .ok_or_else(|| err("no address for the SOCKS proxy"))?;
    let mut socket = TcpStream::connect_timeout(&address, TIMEOUT)?;
    socket.set_nodelay(true)?;
    socket.set_read_timeout(Some(TIMEOUT))?;
    socket.set_write_timeout(Some(TIMEOUT))?;
    if proxy.v4 {
        socks4(&mut socket, proxy, host, port)?;
    } else {
        socks5(&mut socket, proxy, host, port)?;
    }
    socket.set_read_timeout(None)?;
    socket.set_write_timeout(None)?;
    Ok(socket)
}

fn err(message: &str) -> std::io::Error {
    std::io::Error::other(message.to_string())
}

fn resolve(host: &str, port: u16, v4_only: bool) -> std::io::Result<IpAddr> {
    if let Ok(ip) = host.parse::<IpAddr>() {
        return Ok(ip);
    }
    (host, port)
        .to_socket_addrs()?
        .map(|a: SocketAddr| a.ip())
        .find(|ip| !v4_only || ip.is_ipv4())
        .ok_or_else(|| err("no address for the host"))
}

/// RFC 1928, with the username/password step of RFC 1929.
fn socks5(socket: &mut TcpStream, proxy: &Proxy, host: &str, port: u16) -> std::io::Result<()> {
    let login = !proxy.user.is_empty();
    socket.write_all(if login { &[5, 2, 0, 2] } else { &[5, 1, 0] })?;
    let mut choice = [0u8; 2];
    socket.read_exact(&mut choice)?;
    if choice[0] != 5 {
        return Err(err("not a SOCKS5 server"));
    }
    match (choice[1], login) {
        (2, true) => {
            let (user, pass) = (proxy.user.as_bytes(), proxy.pass.as_bytes());
            if user.len() > 255 || pass.len() > 255 {
                return Err(err("SOCKS5 login too long"));
            }
            let mut message = vec![1, user.len() as u8];
            message.extend_from_slice(user);
            message.push(pass.len() as u8);
            message.extend_from_slice(pass);
            socket.write_all(&message)?;
            let mut answer = [0u8; 2];
            socket.read_exact(&mut answer)?;
            if answer[1] != 0 {
                return Err(err("SOCKS5 login refused"));
            }
        }
        (0, _) => {}
        _ => return Err(err("SOCKS5 method refused")),
    }
    let ip = if proxy.remote_dns {
        host.parse::<IpAddr>().ok()
    } else {
        Some(resolve(host, port, false)?)
    };
    let mut request = vec![5, 1, 0];
    match ip {
        Some(IpAddr::V4(v4)) => {
            request.push(1);
            request.extend_from_slice(&v4.octets());
        }
        Some(IpAddr::V6(v6)) => {
            request.push(4);
            request.extend_from_slice(&v6.octets());
        }
        None => {
            if host.len() > 255 {
                return Err(err("host name too long"));
            }
            request.push(3);
            request.push(host.len() as u8);
            request.extend_from_slice(host.as_bytes());
        }
    }
    request.extend_from_slice(&port.to_be_bytes());
    socket.write_all(&request)?;
    let mut reply = [0u8; 4];
    socket.read_exact(&mut reply)?;
    if reply[1] != 0 {
        return Err(err(&format!("SOCKS5 connect failed ({})", reply[1])));
    }
    let skip = match reply[3] {
        1 => 4,
        4 => 16,
        _ => {
            let mut length = [0u8; 1];
            socket.read_exact(&mut length)?;
            length[0] as usize
        }
    };
    let mut bound = vec![0u8; skip + 2];
    socket.read_exact(&mut bound)
}

fn socks4(socket: &mut TcpStream, proxy: &Proxy, host: &str, port: u16) -> std::io::Result<()> {
    let ip = if proxy.remote_dns {
        host.parse::<IpAddr>().ok()
    } else {
        Some(resolve(host, port, true)?)
    };
    let mut request = vec![4, 1];
    request.extend_from_slice(&port.to_be_bytes());
    match ip {
        Some(IpAddr::V4(v4)) => request.extend_from_slice(&v4.octets()),
        Some(IpAddr::V6(_)) => return Err(err("SOCKS4 has no IPv6")),
        None => request.extend_from_slice(&[0, 0, 0, 1]),
    }
    request.extend_from_slice(proxy.user.as_bytes());
    request.push(0);
    if ip.is_none() {
        request.extend_from_slice(host.as_bytes());
        request.push(0);
    }
    socket.write_all(&request)?;
    let mut reply = [0u8; 8];
    socket.read_exact(&mut reply)?;
    if reply[1] != 90 {
        return Err(err(&format!("SOCKS4 connect failed ({})", reply[1])));
    }
    Ok(())
}

/// Starts a bridge to the SOCKS proxy at the URL in [url]; null when the
/// URL is not one or it cannot listen. Close it with [lumtub_socks_close].
///
/// # Safety
/// [url] points at [len] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_socks_start(url: *const u8, len: usize) -> *mut Bridge {
    let Some(proxy) = Proxy::parse(unsafe { crate::taste::text(url, len) }) else {
        return std::ptr::null_mut();
    };
    Bridge::start(proxy).map_or(std::ptr::null_mut(), |b| Box::into_raw(Box::new(b)))
}

/// The bridge's loopback port.
///
/// # Safety
/// [bridge] came from [lumtub_socks_start] and is not closed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_socks_port(bridge: *const Bridge) -> u16 {
    unsafe { bridge.as_ref() }.map_or(0, Bridge::port)
}

/// The password the bridge asks clients for, with the user name `lumtub`;
/// empty for a null bridge. Free it with `lumtub_string_free`.
///
/// # Safety
/// [bridge] came from [lumtub_socks_start] and is not closed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_socks_token(bridge: *const Bridge) -> *mut std::os::raw::c_char {
    crate::taste::give(unsafe { bridge.as_ref() }.map_or(String::new(), |b| b.token().to_owned()))
}

/// Stops the bridge, drops its connections and frees it.
///
/// # Safety
/// [bridge] came from [lumtub_socks_start] and is closed once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_socks_close(bridge: *mut Bridge) {
    if !bridge.is_null() {
        drop(unsafe { Box::from_raw(bridge) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_proxy_urls() {
        let p = Proxy::parse("socks5h://me:p%40ss@127.0.0.1:1080").unwrap();
        assert_eq!(
            (
                p.host.as_str(),
                p.port,
                p.user.as_str(),
                p.pass.as_str(),
                p.v4,
                p.remote_dns
            ),
            ("127.0.0.1", 1080, "me", "p@ss", false, true)
        );
        let p = Proxy::parse("socks4://[::1]:9050/").unwrap();
        assert_eq!(
            (p.host.as_str(), p.port, p.v4, p.remote_dns),
            ("::1", 9050, true, false)
        );
        assert_eq!(Proxy::parse("http://127.0.0.1:8080"), None);
        assert_eq!(Proxy::parse("socks5://127.0.0.1"), None);
    }

    #[test]
    fn closing_stops_listening() {
        let mut bridge = Bridge::start(Proxy::parse("socks5://127.0.0.1:1").unwrap()).unwrap();
        let port = bridge.port();
        bridge.close();
        assert!(TcpStream::connect(("127.0.0.1", port)).is_err());
    }

    #[test]
    fn a_dead_proxy_answers_502_and_nonsense_400() {
        let dead = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = dead.local_addr().unwrap().port();
        drop(dead);
        let bridge =
            Bridge::start(Proxy::parse(&format!("socks5://127.0.0.1:{port}")).unwrap()).unwrap();
        let login = login_of(&bridge);
        let ask = |request: &str| {
            let mut s = TcpStream::connect(("127.0.0.1", bridge.port())).unwrap();
            s.write_all(request.as_bytes()).unwrap();
            let mut answer = String::new();
            let _ = s.read_to_string(&mut answer);
            answer
        };
        assert!(
            ask(&format!("CONNECT 127.0.0.1:9 HTTP/1.1\r\n{login}\r\n\r\n"))
                .starts_with("HTTP/1.1 502")
        );
        assert!(ask(&format!("nonsense\r\n{login}\r\n\r\n")).starts_with("HTTP/1.1 400"));
        let refused = ask("CONNECT 127.0.0.1:9 HTTP/1.1\r\n\r\n");
        assert!(refused.starts_with("HTTP/1.1 407"), "{refused}");
        assert!(refused.contains("Proxy-Authenticate: Basic"));
        assert!(
            ask("CONNECT 127.0.0.1:9 HTTP/1.1\r\nProxy-Authorization: Basic bHVtdHViOng=\r\n\r\n")
                .starts_with("HTTP/1.1 407")
        );
        let endless = "a".repeat(HEAD_MAX + 4096);
        assert!(ask(&endless).starts_with("HTTP/1.1 400"));
    }

    fn login_of(bridge: &Bridge) -> String {
        let pair = format!("{USER}:{}", bridge.token());
        format!(
            "Proxy-Authorization: Basic {}",
            crate::edge_tts::base64(pair.as_bytes())
        )
    }

    #[test]
    fn the_login_is_not_sent_on() {
        let server = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = server.local_addr().unwrap().port();
        let bridge = Bridge::start(Proxy::parse("socks5://127.0.0.1:1").unwrap()).unwrap();
        let mut s = TcpStream::connect(("127.0.0.1", bridge.port())).unwrap();
        write!(
            s,
            "GET http://127.0.0.1:{port}/x HTTP/1.1\r\nHost: 127.0.0.1\r\n{}\r\nAccept: */*\r\n\r\n",
            login_of(&bridge)
        )
        .unwrap();
        let (upstream, _) = server.accept().unwrap();
        upstream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let mut head = BufReader::new(upstream);
        let mut got = String::new();
        while !got.ends_with("\r\n\r\n") {
            assert!(head.read_line(&mut got).unwrap() > 0);
        }
        assert_eq!(
            got,
            "GET /x HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: */*\r\n\r\n"
        );
    }
}
