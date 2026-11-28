//! Edge's online voices: the read-aloud service Microsoft Edge itself uses,
//! with no account or key. A word or a line goes over one WebSocket and
//! comes back as MP3, which the app keeps so each is fetched once.
//!
//! The connection goes the app's way: through its proxy when one is set
//! (HTTP or SOCKS), never directly instead, and with the certificates
//! chosen in its settings. Microsoft changes the service now and then
//! (the Sec-MS-GEC token went to v2 in October 2026); a refusal is an
//! error the app answers with the computer's own voice.

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::os::raw::c_char;
use std::sync::Arc;
use std::sync::atomic::{AtomicI64, Ordering};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tungstenite::Message;
use tungstenite::client::IntoClientRequest;
use tungstenite::http::HeaderValue;

use crate::taste::{give_json, text};

const HOST: &str = "speech.platform.bing.com";
const TRUSTED_CLIENT_TOKEN: &str = "6A5AA1D4EAFF4E9FB37E23D68491D6F4";
/// `2-` asks for the v2 token; the rest is the Edge version, which the
/// service does not check.
const GEC_VERSION: &str = "2-143.0.3650.75";
const USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0";
const ORIGIN: &str = "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold";
const TIMEOUT: Duration = Duration::from_secs(15);
/// At most this many characters are read: a word or a subtitle line.
const MAX_CHARS: usize = 400;
/// The most sound one answer may bring: a line is far less.
const MAX_BYTES: usize = 4 << 20;

/// The server's clock less this computer's, in seconds, learnt from a
/// refusal: the token is made from the time, so a wrong clock is refused.
static SKEW: AtomicI64 = AtomicI64::new(0);

/// Why a word could not be read.
#[derive(Debug, PartialEq)]
pub enum Failure {
    /// The service turned the connection away (HTTP status).
    Refused(u16),
    /// Anything else: no network, a proxy refused, a broken answer.
    Other(String),
}

impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Failure::Refused(status) => write!(f, "Edge voice refused (HTTP {status})"),
            Failure::Other(text) => f.write_str(text),
        }
    }
}

fn other(error: impl std::fmt::Display) -> Failure {
    Failure::Other(error.to_string())
}

/// Reads [text] with Edge's [voice] (such as `ja-JP-NanamiNeural`) and
/// answers the MP3. A refusal for a wrong clock is tried once more with
/// the server's time.
pub fn speak(text: &str, voice: &str) -> Result<Vec<u8>, Failure> {
    let text: String = text.chars().take(MAX_CHARS).collect();
    if text.trim().is_empty() {
        return Err(other("nothing to read"));
    }
    if !voice.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        return Err(other("voice name looks wrong"));
    }
    match speak_once(&text, voice) {
        Err(Attempt::Clock(skew)) => {
            SKEW.store(skew, Ordering::Relaxed);
            speak_once(&text, voice).map_err(Attempt::into_failure)
        }
        answer => answer.map_err(Attempt::into_failure),
    }
}

enum Attempt {
    Failed(Failure),
    /// Refused while the clocks differ by this many seconds.
    Clock(i64),
}

impl Attempt {
    fn into_failure(self) -> Failure {
        match self {
            Attempt::Failed(failure) => failure,
            Attempt::Clock(_) => Failure::Refused(403),
        }
    }
}

impl From<Failure> for Attempt {
    fn from(failure: Failure) -> Self {
        Attempt::Failed(failure)
    }
}

fn speak_once(text: &str, voice: &str) -> Result<Vec<u8>, Attempt> {
    #[cfg(test)]
    let started = std::time::Instant::now();
    let socket = open(HOST, 443)?;
    #[cfg(test)]
    eprintln!("  connected in {:?}", started.elapsed());
    socket.set_read_timeout(Some(TIMEOUT)).map_err(other)?;
    socket.set_write_timeout(Some(TIMEOUT)).map_err(other)?;
    socket.set_nodelay(true).map_err(other)?;
    let mut config = crate::tls::config(crate::tls::current()).map_err(other)?;
    // A WebSocket handshake is HTTP/1.1.
    config.alpn_protocols = vec![b"http/1.1".to_vec()];
    let name = rustls::pki_types::ServerName::try_from(HOST).map_err(other)?;
    let connection = rustls::ClientConnection::new(Arc::new(config), name).map_err(other)?;
    let stream = rustls::StreamOwned::new(connection, socket);

    let url = format!(
        "wss://{HOST}/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken={TRUSTED_CLIENT_TOKEN}&ConnectionId={}&Sec-MS-GEC={}&Sec-MS-GEC-Version={GEC_VERSION}",
        random_hex(),
        crate::edge_drm::token(SKEW.load(Ordering::Relaxed)),
    );
    let mut request = url.into_client_request().map_err(other)?;
    let headers = request.headers_mut();
    for (name, value) in [
        ("Pragma", "no-cache"),
        ("Cache-Control", "no-cache"),
        ("Origin", ORIGIN),
        ("User-Agent", USER_AGENT),
        ("Accept-Language", "en-US,en;q=0.9"),
    ] {
        headers.insert(name, HeaderValue::from_static(value));
    }
    headers.insert(
        "Cookie",
        HeaderValue::from_str(&format!("muid={};", random_hex().to_ascii_uppercase()))
            .map_err(other)?,
    );

    let (mut socket, _) = match tungstenite::client(request, stream) {
        Ok(open) => open,
        Err(tungstenite::HandshakeError::Failure(tungstenite::Error::Http(response))) => {
            let status = response.status().as_u16();
            if status == 403 {
                let date = response.headers().get("date").and_then(|d| d.to_str().ok());
                if let Some(server) = date.and_then(parse_http_date) {
                    let skew = server - now();
                    // Only a clock off by more than the token's window.
                    if (skew - SKEW.load(Ordering::Relaxed)).abs() > 120 {
                        return Err(Attempt::Clock(skew));
                    }
                }
            }
            return Err(Failure::Refused(status).into());
        }
        Err(error) => return Err(other(error).into()),
    };

    let stamp = js_date();
    let config = format!(
        "X-Timestamp:{stamp}\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{{\"context\":{{\"synthesis\":{{\"audio\":{{\"metadataoptions\":{{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"}},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}}}}}\r\n"
    );
    socket.send(Message::text(config)).map_err(other)?;
    let language = voice.splitn(3, '-').take(2).collect::<Vec<_>>().join("-");
    let ssml = format!(
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='{language}'><voice name='{voice}'><prosody pitch='+0Hz' rate='+0%' volume='+0%'>{}</prosody></voice></speak>",
        escape(text)
    );
    let message = format!(
        "X-RequestId:{}\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:{stamp}Z\r\nPath:ssml\r\n\r\n{ssml}",
        random_hex()
    );
    socket.send(Message::text(message)).map_err(other)?;

    #[cfg(test)]
    eprintln!("  asked in {:?}", started.elapsed());
    let mut audio = Vec::new();
    loop {
        match socket.read().map_err(other)? {
            Message::Text(text) => {
                let head = text.split("\r\n\r\n").next().unwrap_or("");
                #[cfg(test)]
                eprintln!(
                    "  {:?} text: {}",
                    started.elapsed(),
                    head.replace("\r\n", " | ")
                );
                if head.lines().any(|line| line.trim() == "Path:turn.end") {
                    break;
                }
            }
            Message::Binary(data) => {
                if let Some(sound) = audio_part(&data) {
                    audio.extend_from_slice(sound);
                    if audio.len() > MAX_BYTES {
                        return Err(other("Edge voice sent too much").into());
                    }
                }
            }
            Message::Close(_frame) => {
                #[cfg(test)]
                eprintln!("  closed: {_frame:?}");
                break;
            }
            _ => {}
        }
    }
    let _ = socket.close(None);
    if audio.is_empty() {
        return Err(other("Edge voice sent no sound").into());
    }
    Ok(audio)
}

/// The sound in a binary message: two bytes of header length, the
/// header (`Path:audio` …), then MP3.
fn audio_part(data: &[u8]) -> Option<&[u8]> {
    if data.len() < 2 {
        return None;
    }
    let length = u16::from_be_bytes([data[0], data[1]]) as usize;
    let head = std::str::from_utf8(data.get(2..2 + length)?).ok()?;
    if !head.lines().any(|line| line.trim() == "Path:audio") {
        return None;
    }
    let sound = &data[2 + length..];
    (!sound.is_empty()).then_some(sound)
}

fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            c if c.is_control() => out.push(' '),
            c => out.push(c),
        }
    }
    out
}

fn random_hex() -> String {
    let mut bytes = [0u8; 16];
    if getrandom::fill(&mut bytes).is_err() {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        bytes = nanos.to_le_bytes();
    }
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Days since 1970-01-01 of a proleptic Gregorian date.
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// Year, month and day of [days] since 1970-01-01.
fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    (
        if month <= 2 {
            yoe + era * 400 + 1
        } else {
            yoe + era * 400
        },
        month,
        day,
    )
}

const MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];
const WEEKDAYS: [&str; 7] = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"];

/// `Sun, 06 Nov 1994 08:49:37 GMT` as Unix seconds.
fn parse_http_date(date: &str) -> Option<i64> {
    let mut parts = date.split_whitespace().skip(1);
    let day: i64 = parts.next()?.parse().ok()?;
    let name = parts.next()?;
    let month = MONTHS.iter().position(|m| *m == name)? as i64 + 1;
    let year: i64 = parts.next()?.parse().ok()?;
    let mut time = parts.next()?.split(':').map(|n| n.parse::<i64>().ok());
    let (h, m, s) = (time.next()??, time.next()??, time.next()??);
    Some(days_from_civil(year, month, day) * 86_400 + h * 3600 + m * 60 + s)
}

/// The time as JavaScript's Date prints it, in UTC, which the service
/// expects in its messages.
fn js_date() -> String {
    let seconds = now() + SKEW.load(Ordering::Relaxed);
    let days = seconds.div_euclid(86_400);
    let rest = seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    format!(
        "{} {} {day:02} {year} {:02}:{:02}:{:02} GMT+0000 (Coordinated Universal Time)",
        WEEKDAYS[days.rem_euclid(7) as usize],
        MONTHS[month as usize - 1],
        rest / 3600,
        rest / 60 % 60,
        rest % 60
    )
}

/// A connection to [host]:[port] the app's way: through its proxy when
/// one is set, which is never skipped.
fn open(host: &str, port: u16) -> Result<TcpStream, Failure> {
    match crate::http::proxy_address() {
        None => {
            let mut last = None;
            for address in (host, port).to_socket_addrs().map_err(other)? {
                match TcpStream::connect_timeout(&address, TIMEOUT) {
                    Ok(socket) => return Ok(socket),
                    Err(error) => last = Some(error),
                }
            }
            Err(other(
                last.map_or("no address for the Edge voice".into(), |e| e.to_string()),
            ))
        }
        Some(proxy) => {
            if let Some(socks) = crate::socks::Proxy::parse(&proxy) {
                return crate::socks::connect(&socks, host, port).map_err(other);
            }
            if proxy.to_ascii_lowercase().starts_with("http://") {
                return tunnel(&proxy, host, port);
            }
            Err(other("the proxy address could not be read"))
        }
    }
}

/// A CONNECT tunnel through the HTTP proxy at [proxy].
fn tunnel(proxy: &str, host: &str, port: u16) -> Result<TcpStream, Failure> {
    let rest = proxy[7..].trim_end_matches('/');
    let (login, address) = rest.rsplit_once('@').unwrap_or(("", rest));
    let address = if address
        .rsplit_once(':')
        .is_some_and(|(_, p)| p.parse::<u16>().is_ok())
    {
        address.to_string()
    } else {
        format!("{address}:80")
    };
    let target = address
        .to_socket_addrs()
        .map_err(other)?
        .next()
        .ok_or_else(|| other("no address for the proxy"))?;
    let mut socket = TcpStream::connect_timeout(&target, TIMEOUT).map_err(other)?;
    socket.set_read_timeout(Some(TIMEOUT)).map_err(other)?;
    let mut ask = format!("CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n");
    if !login.is_empty() {
        let login = crate::relay::decode(&login.replace('+', "%2B"));
        ask.push_str(&format!(
            "Proxy-Authorization: Basic {}\r\n",
            base64(login.as_bytes())
        ));
    }
    ask.push_str("\r\n");
    socket.write_all(ask.as_bytes()).map_err(other)?;
    let mut reader = BufReader::new(&socket);
    let mut status = String::new();
    reader.read_line(&mut status).map_err(other)?;
    if status.split_whitespace().nth(1) != Some("200") {
        return Err(other(format!("the proxy refused: {}", status.trim())));
    }
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).map_err(other)? == 0 || line == "\r\n" || line == "\n" {
            break;
        }
    }
    // Nothing should follow the proxy's answer before the TLS handshake.
    if !reader.buffer().is_empty() {
        return Err(other("the proxy sent more than its answer"));
    }
    drop(reader);
    Ok(socket)
}

pub(crate) fn base64(data: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in data.chunks(3) {
        let n = (chunk[0] as u32) << 16
            | (*chunk.get(1).unwrap_or(&0) as u32) << 8
            | *chunk.get(2).unwrap_or(&0) as u32;
        for i in 0..4 {
            if i <= chunk.len() {
                out.push(TABLE[(n >> (18 - 6 * i) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

#[derive(Serialize)]
struct Failed {
    error: String,
    /// The HTTP status the service refused with, if it did.
    #[serde(skip_serializing_if = "Option::is_none")]
    status: Option<u16>,
}

/// Reads [json]'s `{text, voice, out}` with Edge's online voice into an
/// MP3 file at `out`. Answers `{}` or `{"error", "status"?}`. Blocks
/// while it fetches: call it off the UI thread.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_speak_online(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        text: String,
        voice: String,
        out: String,
    }
    // SAFETY: The caller passes `json` pointing at `length` readable bytes, as this function
    // requires.
    let answer = serde_json::from_str::<Ask>(unsafe { text(json, length) })
        .map_err(|e| Failure::Other(e.to_string()))
        .and_then(|ask| {
            let sound = speak(&ask.text, &ask.voice)?;
            // Written beside, then moved, so a half file is never played.
            let part = format!("{}.part", ask.out);
            std::fs::write(&part, &sound).map_err(other)?;
            std::fs::rename(&part, &ask.out).map_err(other)
        });
    match answer {
        Ok(()) => give_json(&serde_json::json!({})),
        Err(failure) => give_json(&Failed {
            status: match failure {
                Failure::Refused(status) => Some(status),
                Failure::Other(_) => None,
            },
            error: failure.to_string(),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_http_dates() {
        assert_eq!(
            parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT"),
            Some(784_111_777)
        );
        assert_eq!(
            parse_http_date("Fri, 21 Nov 2026 10:00:00 GMT"),
            Some(1_795_255_200)
        );
        assert_eq!(parse_http_date("garbage"), None);
    }

    #[test]
    fn dates_round_trip() {
        for days in [-1, 0, 10_957, 20_413, 60_000] {
            let (y, m, d) = civil_from_days(days);
            assert_eq!(days_from_civil(y, m, d), days);
        }
        assert_eq!(civil_from_days(20_413), (2025, 11, 21));
    }

    #[test]
    fn finds_the_sound() {
        let head = b"X-RequestId:1\r\nContent-Type:audio/mpeg\r\nPath:audio\r\n";
        let mut data = (head.len() as u16).to_be_bytes().to_vec();
        data.extend_from_slice(head);
        data.extend_from_slice(b"ID3");
        assert_eq!(audio_part(&data), Some(&b"ID3"[..]));
        let mut empty = (head.len() as u16).to_be_bytes().to_vec();
        empty.extend_from_slice(head);
        assert_eq!(audio_part(&empty), None);
        assert_eq!(audio_part(&[0, 200, 1]), None);
    }

    #[test]
    fn escapes_ssml() {
        assert_eq!(escape("a<b>&'\"\n"), "a&lt;b&gt;&amp;&apos;&quot; ");
        assert_eq!(base64(b"user:pass"), "dXNlcjpwYXNz");
        assert_eq!(base64(b"ab"), "YWI=");
        assert_eq!(base64(b"a"), "YQ==");
    }

    #[test]
    fn refuses_odd_voice_names() {
        assert!(matches!(speak("hi", "en-US'><x"), Err(Failure::Other(_))));
        assert!(matches!(
            speak("  ", "en-US-JennyNeural"),
            Err(Failure::Other(_))
        ));
    }

    /// The real service (CI runs it, as the token and protocol change).
    #[test]
    #[ignore]
    fn live() {
        for (text, voice) in [
            ("Hello", "en-US-JennyNeural"),
            ("食べる", "ja-JP-NanamiNeural"),
            ("学习", "zh-CN-XiaoxiaoNeural"),
            (
                "The quick brown fox jumps over the lazy dog, twice.",
                "en-US-JennyNeural",
            ),
        ] {
            let started = std::time::Instant::now();
            let sound = speak(text, voice).unwrap_or_else(|e| panic!("{voice}: {e}"));
            let path = std::env::temp_dir().join(format!("{voice}.mp3"));
            std::fs::write(&path, &sound).unwrap();
            println!(
                "{voice}: {} bytes in {:?}, starts {:02x?}",
                sound.len(),
                started.elapsed(),
                &sound[..16.min(sound.len())]
            );
            // How long and how loud, where ffmpeg is installed.
            if let Ok(out) = std::process::Command::new("ffmpeg")
                .args(["-hide_banner", "-i"])
                .arg(&path)
                .args(["-af", "volumedetect", "-f", "null", "-"])
                .output()
            {
                for line in String::from_utf8_lossy(&out.stderr).lines() {
                    if line.contains("Duration")
                        || line.contains("mean_volume")
                        || line.contains("max_volume")
                    {
                        println!("  {}", line.trim());
                    }
                }
            }
            // For listening to it elsewhere.
            assert!(sound.len() > 1000, "{voice}");
        }
    }
}
