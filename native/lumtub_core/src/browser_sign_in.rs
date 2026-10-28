//! Signing in to YouTube in a browser window of its own: Edge, or the
//! default browser when it is Chromium-based, or Chrome, opened with a
//! fresh profile of its own. The user signs in there as on any browser;
//! once YouTube has set its sign-in cookies they are read from the browser
//! through its DevTools port on 127.0.0.1, the browser is closed and its
//! profile deleted. The user's own browser profiles are never opened.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use serde_json::{Value, json};
use zeroize::Zeroize;

use crate::web_account::Jar;

/// Where the browser lands: Google's sign-in, going on to YouTube's.
pub const SIGN_IN_URL: &str = "https://accounts.google.com/ServiceLogin?service=youtube&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26next%3Dhttps%253A%252F%252Fwww.youtube.com%252F";

/// Bumped by every new sign-in and by cancelling, so an older one stops.
pub static ATTEMPT: AtomicU64 = AtomicU64::new(0);

/// How long the user has to sign in.
const PATIENCE: Duration = Duration::from_secs(15 * 60);

/// Executable names of Chromium-based browsers, which take the flags used here.
const CHROMIUM: [&str; 8] = ["msedge.exe", "chrome.exe", "brave.exe", "vivaldi.exe", "chromium.exe", "opera.exe", "thorium.exe", "browser.exe"];

pub fn is_chromium(exe: &Path) -> bool {
    let path = exe.to_string_lossy().to_ascii_lowercase();
    let name = path.rsplit(['\\', '/']).next().unwrap_or("");
    // Yandex's is browser.exe; Opera's launcher is launcher.exe.
    match name {
        "browser.exe" => path.contains("yandex"),
        "launcher.exe" => path.contains("opera"),
        _ => CHROMIUM.contains(&name),
    }
}

/// The browser to open: Edge, then the default browser if it is
/// Chromium-based, then Chrome.
pub fn find_browser() -> Option<PathBuf> {
    let installed = |parts: &[&str]| {
        ["ProgramFiles(x86)", "ProgramFiles", "LOCALAPPDATA"]
            .iter()
            .filter_map(std::env::var_os)
            .map(|root| parts.iter().fold(PathBuf::from(root), |p, part| p.join(part)))
            .find(|p| p.is_file())
    };
    installed(&["Microsoft", "Edge", "Application", "msedge.exe"])
        .or_else(|| default_browser().filter(|p| is_chromium(p)))
        .or_else(|| installed(&["Google", "Chrome", "Application", "chrome.exe"]))
}

#[cfg(windows)]
fn default_browser() -> Option<PathBuf> {
    use windows_sys::Win32::UI::Shell::{ASSOCF_IS_PROTOCOL, ASSOCSTR_EXECUTABLE, AssocQueryStringW};
    let scheme: Vec<u16> = "https\0".encode_utf16().collect();
    let verb: Vec<u16> = "open\0".encode_utf16().collect();
    let mut buffer = [0u16; 1024];
    let mut length = buffer.len() as u32;
    // SAFETY: the strings are NUL-terminated and [buffer] holds [length] characters.
    let status = unsafe { AssocQueryStringW(ASSOCF_IS_PROTOCOL, ASSOCSTR_EXECUTABLE, scheme.as_ptr(), verb.as_ptr(), buffer.as_mut_ptr(), &mut length) };
    if status != 0 {
        return None;
    }
    let end = buffer.iter().position(|&c| c == 0).unwrap_or(0);
    Some(PathBuf::from(String::from_utf16_lossy(&buffer[..end]))).filter(|p| p.is_file())
}

#[cfg(not(windows))]
fn default_browser() -> Option<PathBuf> {
    None
}

/// The browser's name for messages, from its executable.
pub fn browser_name(exe: &Path) -> String {
    let name = exe.file_stem().and_then(|n| n.to_str()).unwrap_or("browser").to_ascii_lowercase();
    match name.as_str() {
        "msedge" => "Microsoft Edge".into(),
        "chrome" => "Google Chrome".into(),
        "brave" => "Brave".into(),
        "vivaldi" => "Vivaldi".into(),
        "opera" | "launcher" => "Opera".into(),
        _ => name,
    }
}

/// A minimal WebSocket client for the browser's DevTools port, which only
/// ever listens on 127.0.0.1.
struct Socket {
    stream: TcpStream,
    next: u64,
}

impl Socket {
    fn connect(port: u16, path: &str) -> std::io::Result<Socket> {
        let mut stream = TcpStream::connect(("127.0.0.1", port))?;
        stream.set_read_timeout(Some(Duration::from_secs(10)))?;
        stream.set_nodelay(true)?;
        write!(stream, "GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n")?;
        let mut head = Vec::new();
        let mut byte = [0u8; 1];
        while !head.ends_with(b"\r\n\r\n") {
            if stream.read(&mut byte)? == 0 || head.len() > 8192 {
                return Err(std::io::Error::other("the browser closed the DevTools connection"));
            }
            head.push(byte[0]);
        }
        if !head.starts_with(b"HTTP/1.1 101") {
            return Err(std::io::Error::other("the browser refused the DevTools connection"));
        }
        Ok(Socket { stream, next: 1 })
    }

    fn send(&mut self, opcode: u8, payload: &[u8]) -> std::io::Result<()> {
        let mut frame = vec![0x80 | opcode];
        match payload.len() {
            n if n < 126 => frame.push(0x80 | n as u8),
            n if n <= 0xffff => {
                frame.push(0x80 | 126);
                frame.extend_from_slice(&(n as u16).to_be_bytes());
            }
            n => {
                frame.push(0x80 | 127);
                frame.extend_from_slice(&(n as u64).to_be_bytes());
            }
        }
        let mask = (std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.subsec_nanos()) ^ 0x5a17_c3e9).to_be_bytes();
        frame.extend_from_slice(&mask);
        frame.extend(payload.iter().enumerate().map(|(i, b)| b ^ mask[i % 4]));
        self.stream.write_all(&frame)
    }

    /// The next whole text message.
    fn receive(&mut self) -> std::io::Result<Vec<u8>> {
        let mut message = Vec::new();
        loop {
            let mut head = [0u8; 2];
            self.stream.read_exact(&mut head)?;
            let opcode = head[0] & 0x0f;
            let mut length = (head[1] & 0x7f) as u64;
            if length == 126 {
                let mut bytes = [0u8; 2];
                self.stream.read_exact(&mut bytes)?;
                length = u16::from_be_bytes(bytes) as u64;
            } else if length == 127 {
                let mut bytes = [0u8; 8];
                self.stream.read_exact(&mut bytes)?;
                length = u64::from_be_bytes(bytes);
            }
            if length > 64 << 20 {
                return Err(std::io::Error::other("the browser sent too much"));
            }
            let mut payload = vec![0u8; length as usize];
            self.stream.read_exact(&mut payload)?;
            match opcode {
                0x8 => return Err(std::io::Error::other("the browser closed the DevTools connection")),
                0x9 => self.send(0xA, &payload)?,
                0x0..=0x2 => {
                    message.extend_from_slice(&payload);
                    payload.zeroize();
                    if head[0] & 0x80 != 0 {
                        return Ok(message);
                    }
                }
                _ => {}
            }
        }
    }

    /// Calls DevTools [method]; its answer's raw bytes, to be wiped by the caller.
    fn call(&mut self, method: &str, params: Value) -> std::io::Result<Vec<u8>> {
        let id = self.next;
        self.next += 1;
        self.send(0x1, json!({"id": id, "method": method, "params": params}).to_string().as_bytes())?;
        loop {
            let mut message = self.receive()?;
            let answer: Value = serde_json::from_slice(&message).unwrap_or_default();
            if answer.get("id").and_then(Value::as_u64) == Some(id) {
                return Ok(message);
            }
            message.zeroize();
        }
    }
}

/// The youtube.com cookies in a DevTools `Storage.getCookies` answer.
pub fn youtube_cookies(answer: &[u8]) -> Jar {
    let value: Value = serde_json::from_slice(answer).unwrap_or_default();
    let mut jar = Jar::default();
    for cookie in value.pointer("/result/cookies").and_then(Value::as_array).into_iter().flatten() {
        let domain = cookie.get("domain").and_then(Value::as_str).unwrap_or("").trim_start_matches('.');
        if domain != "youtube.com" && !domain.ends_with(".youtube.com") {
            continue;
        }
        if let (Some(name), Some(value)) = (cookie.get("name").and_then(Value::as_str), cookie.get("value").and_then(Value::as_str)) {
            jar.set(name, value);
        }
    }
    jar
}

/// Whether YouTube has finished signing the browser in: it has the API
/// cookies and its own sign-in one.
pub fn finished(jar: &Jar) -> bool {
    jar.signed_in() && jar.get("LOGIN_INFO").is_some()
}

/// The DevTools port and path the browser wrote into its profile.
fn devtools(profile: &Path) -> Option<(u16, String)> {
    let text = std::fs::read_to_string(profile.join("DevToolsActivePort")).ok()?;
    let mut lines = text.lines();
    let port = lines.next()?.trim().parse().ok()?;
    let path = lines.next()?.trim().to_owned();
    Some((port, path))
}

pub enum Outcome {
    SignedIn(Jar),
    /// The window was closed before signing in, or the user cancelled.
    Closed,
    Failed(String),
}

fn remove_profile(profile: &Path) {
    for _ in 0..20 {
        if std::fs::remove_dir_all(profile).is_ok() || !profile.exists() {
            return;
        }
        std::thread::sleep(Duration::from_millis(500));
    }
}

fn close(browser: &mut Child, socket: Option<&mut Socket>) {
    if let Some(socket) = socket {
        let _ = socket.call("Browser.close", json!({}));
    }
    let deadline = Instant::now() + Duration::from_secs(10);
    while Instant::now() < deadline {
        if !matches!(browser.try_wait(), Ok(None)) {
            return;
        }
        std::thread::sleep(Duration::from_millis(200));
    }
    let _ = browser.kill();
    let _ = browser.wait();
}

/// Opens [exe] with a fresh profile under [folder] at the sign-in page and
/// waits, on this thread, for the user to sign in. [opened] runs once the
/// browser is up.
pub fn sign_in(exe: &Path, folder: &Path, url: &str, opened: impl FnOnce()) -> Outcome {
    let attempt = ATTEMPT.fetch_add(1, Ordering::SeqCst) + 1;
    let current = || ATTEMPT.load(Ordering::SeqCst) == attempt;
    let profile = folder.join("browser-sign-in");
    remove_profile(&profile);
    if std::fs::create_dir_all(&profile).is_err() {
        return Outcome::Failed("could not make the browser's profile folder".into());
    }
    let started = Command::new(exe)
        .arg(format!("--user-data-dir={}", profile.display()))
        .args(["--remote-debugging-port=0", "--no-first-run", "--no-default-browser-check", "--disable-sync", "--new-window"])
        .arg(url)
        .spawn();
    let mut browser = match started {
        Ok(child) => child,
        Err(e) => {
            remove_profile(&profile);
            return Outcome::Failed(format!("could not open {}: {e}", browser_name(exe)));
        }
    };
    let begun = Instant::now();
    let mut socket: Option<Socket> = None;
    let mut opened = Some(opened);
    let outcome = loop {
        if !current() {
            break Outcome::Closed;
        }
        if begun.elapsed() > PATIENCE {
            break Outcome::Closed;
        }
        if socket.is_none() {
            match devtools(&profile).map(|(port, path)| Socket::connect(port, &path)) {
                Some(Ok(connected)) => {
                    socket = Some(connected);
                    if let Some(opened) = opened.take() {
                        opened();
                    }
                }
                // The browser went before its DevTools port came up.
                _ if begun.elapsed() > Duration::from_secs(30) => break Outcome::Failed(format!("{} did not start", browser_name(exe))),
                _ => {}
            }
        }
        if let Some(open) = socket.as_mut() {
            match open.call("Storage.getCookies", json!({})) {
                Ok(mut answer) => {
                    let jar = youtube_cookies(&answer);
                    answer.zeroize();
                    if finished(&jar) {
                        // The last cookies of the sign-in redirect land a moment later.
                        std::thread::sleep(Duration::from_secs(2));
                        let jar = match open.call("Storage.getCookies", json!({})) {
                            Ok(mut answer) => {
                                let fresh = youtube_cookies(&answer);
                                answer.zeroize();
                                if fresh.signed_in() { fresh } else { jar }
                            }
                            Err(_) => jar,
                        };
                        break Outcome::SignedIn(jar);
                    }
                }
                // The user closed the browser.
                Err(_) => break Outcome::Closed,
            }
        }
        std::thread::sleep(Duration::from_millis(1500));
    };
    close(&mut browser, socket.as_mut());
    drop(socket);
    remove_profile(&profile);
    outcome
}

/// Stops a sign-in that is waiting.
pub fn cancel() {
    ATTEMPT.fetch_add(1, Ordering::SeqCst);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn knows_chromium_browsers() {
        assert!(is_chromium(Path::new(r"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe")));
        assert!(is_chromium(Path::new(r"C:\Users\a\AppData\Local\Programs\Opera\launcher.exe")));
        assert!(is_chromium(Path::new(r"C:\Users\a\AppData\Local\Yandex\YandexBrowser\Application\browser.exe")));
        assert!(!is_chromium(Path::new(r"C:\Program Files\Mozilla Firefox\firefox.exe")));
        assert!(!is_chromium(Path::new(r"C:\Other\browser.exe")));
        assert_eq!(browser_name(Path::new("msedge.exe")), "Microsoft Edge");
    }

    #[test]
    fn reads_youtube_cookies_from_devtools() {
        let answer = json!({"id": 1, "result": {"cookies": [
            {"name": "SAPISID", "value": "a/b", "domain": ".youtube.com"},
            {"name": "SID", "value": "g", "domain": ".google.com"},
            {"name": "LOGIN_INFO", "value": "L", "domain": ".youtube.com"},
            {"name": "PREF", "value": "hl=en", "domain": "www.youtube.com"},
        ]}});
        let jar = youtube_cookies(answer.to_string().as_bytes());
        assert_eq!(jar.header(), "SAPISID=a/b; LOGIN_INFO=L; PREF=hl=en");
        assert!(finished(&jar));
        let mut half = Jar::default();
        half.set("SAPISID", "a");
        assert!(!finished(&half));
    }

    #[test]
    fn reads_the_devtools_port_file() {
        let folder = std::env::temp_dir().join(format!("lumtub-devtools-{}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        std::fs::write(folder.join("DevToolsActivePort"), "51234\n/devtools/browser/abc\n").unwrap();
        assert_eq!(devtools(&folder), Some((51234, "/devtools/browser/abc".into())));
        std::fs::remove_dir_all(&folder).unwrap();
    }
}
