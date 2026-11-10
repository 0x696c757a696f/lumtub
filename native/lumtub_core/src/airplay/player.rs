//! Plays an address on an AirPlay receiver and steers it: the receiver
//! fetches the stream itself (HLS here), and plays while the connection
//! that started it stays open.

use super::bplist::{self, Value, dict};
use super::conn::{Conn, message_end, parse_head};
use super::crypto::{Framing, hkdf};
use super::pairing::{self, Credentials};
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream, UdpSocket};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const USER_AGENT: &str = "AirPlay/550.10";

pub enum Auth {
    None,
    Transient,
    Paired(Credentials),
}

struct Control {
    conn: Conn,
    cseq: u32,
}

pub struct Player {
    control: Arc<Mutex<Control>>,
    v2: bool,
    session: String,
    uri: String,
    dacp: String,
    remote: u32,
    stop: Arc<AtomicBool>,
}

/// What `/playback-info` says.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Status {
    pub position: f64,
    pub duration: f64,
    pub rate: f64,
    pub ready: bool,
    pub error: Option<String>,
}

fn random_u32() -> u32 {
    let mut b = [0u8; 4];
    let _ = getrandom::fill(&mut b);
    u32::from_be_bytes(b)
}

fn uuid() -> String {
    let mut b = [0u8; 16];
    let _ = getrandom::fill(&mut b);
    let h: String = b.iter().map(|x| format!("{x:02X}")).collect();
    format!(
        "{}-{}-4{}-{}-{}",
        &h[0..8],
        &h[8..12],
        &h[13..16],
        &h[16..20],
        &h[20..32]
    )
}

impl Player {
    fn exchange(
        &self,
        method: &str,
        uri: &str,
        body: Option<&Value>,
    ) -> Result<super::conn::Response, String> {
        let mut control = self.control.lock().unwrap();
        let cseq = control.cseq;
        control.cseq += 1;
        let mut headers = vec![
            ("CSeq", cseq.to_string()),
            ("DACP-ID", self.dacp.clone()),
            ("Active-Remote", self.remote.to_string()),
            ("Client-Instance", self.dacp.clone()),
            ("User-Agent", USER_AGENT.to_string()),
        ];
        let data = body.map(bplist::write).unwrap_or_default();
        if body.is_some() {
            headers.push(("Content-Type", "application/x-apple-binary-plist".into()));
        }
        control.conn.request(
            method,
            uri,
            if self.v2 { "RTSP/1.0" } else { "HTTP/1.1" },
            &headers,
            &data,
        )
    }

    fn http(&self, method: &str, uri: &str, body: &[u8]) -> Result<super::conn::Response, String> {
        let headers = vec![
            ("User-Agent", USER_AGENT.to_string()),
            ("Content-Type", "application/x-apple-binary-plist".into()),
            ("X-Apple-ProtocolVersion", "1".into()),
            ("X-Apple-Stream-ID", "1".into()),
            ("X-Apple-Session-ID", self.session.clone()),
        ];
        self.control
            .lock()
            .unwrap()
            .conn
            .request(method, uri, "HTTP/1.1", &headers, body)
    }

    /// Connects, verifies and starts `url` at `position` seconds.
    pub fn play(
        address: SocketAddr,
        auth: Auth,
        v2: bool,
        url: &str,
        position: f64,
    ) -> Result<Player, String> {
        let mut conn =
            Conn::open(address).map_err(|e| format!("could not reach the device: {e}"))?;
        let shared: Option<Vec<u8>> = match &auth {
            Auth::None => None,
            Auth::Transient => Some(pairing::transient(&mut conn)?),
            Auth::Paired(c) => Some(pairing::verify(&mut conn, c)?.to_vec()),
        };
        if v2 {
            let shared = shared.as_ref().ok_or("this device needs pairing")?;
            let (write, read) = pairing::control_keys(shared);
            conn.encrypt(&write, &read);
        }
        let local = conn.local_ip();
        let player = Player {
            control: Arc::new(Mutex::new(Control { conn, cseq: 0 })),
            v2,
            session: uuid(),
            uri: format!("rtsp://{local}/{}", random_u32()),
            dacp: format!("{:08X}{:08X}", random_u32(), random_u32()),
            remote: random_u32(),
            stop: Arc::new(AtomicBool::new(false)),
        };
        if v2 {
            player.setup(address, shared.as_deref().unwrap_or_default())?;
        }
        let body = if v2 {
            dict(vec![
                ("Content-Location", Value::String(url.into())),
                ("Start-Position-Seconds", Value::Real(position)),
                ("uuid", Value::String(uuid())),
                ("streamType", Value::Int(1)),
                ("mediaType", Value::String("file".into())),
                ("mightSupportStorePastisKeyRequests", Value::Bool(true)),
                ("playbackRestrictions", Value::Int(0)),
                ("referenceRestrictions", Value::Int(3)),
                ("volume", Value::Real(1.0)),
                ("rate", Value::Real(1.0)),
                ("clientProcName", Value::String("Lumtub".into())),
            ])
        } else {
            dict(vec![
                ("Content-Location", Value::String(url.into())),
                ("Start-Position", Value::Real(position)),
                ("X-Apple-Session-ID", Value::String(player.session.clone())),
            ])
        };
        let data = bplist::write(&body);
        let mut answer = player.http("POST", "/play", &data)?;
        for _ in 0..3 {
            if answer.code != 500 {
                break;
            }
            std::thread::sleep(Duration::from_secs(1));
            answer = player.http("POST", "/play", &data)?;
        }
        if answer.code == 401 || answer.code == 403 || answer.code == 470 {
            return Err("the device refused to play; pair again".into());
        }
        if answer.code >= 400 {
            return Err(format!("the device answered {} to play", answer.code));
        }
        if v2 {
            let none = dict(vec![
                ("flags", Value::Int(0)),
                ("value", Value::Int(0)),
                ("epoch", Value::Int(0)),
                ("timescale", Value::Int(0)),
            ]);
            player.exchange(
                "PUT",
                "/setProperty?isInterestedInDateRange",
                Some(&dict(vec![("value", Value::Bool(true))])),
            )?;
            player.exchange(
                "PUT",
                "/setProperty?actionAtItemEnd",
                Some(&dict(vec![("value", Value::Int(0))])),
            )?;
            player.exchange("POST", "/rate?value=1.000000", None)?;
            player.exchange(
                "PUT",
                "/setProperty?forwardEndTime",
                Some(&dict(vec![("value", none.clone())])),
            )?;
            player.exchange(
                "PUT",
                "/setProperty?reverseEndTime",
                Some(&dict(vec![("value", none)])),
            )?;
        }
        Ok(player)
    }

    /// The AirPlay 2 session around the address: a timing service, the
    /// encrypted event channel the receiver connects back on, keep-alive
    /// feedback and RECORD.
    fn setup(&self, address: SocketAddr, shared: &[u8]) -> Result<(), String> {
        let timing = UdpSocket::bind("0.0.0.0:0").map_err(|e| e.to_string())?;
        let timing_port = timing.local_addr().map_err(|e| e.to_string())?.port();
        let stop = self.stop.clone();
        let _ = timing.set_read_timeout(Some(Duration::from_millis(500)));
        std::thread::spawn(move || answer_timing(timing, stop));
        let answer = self.exchange(
            "SETUP",
            &self.uri.clone(),
            Some(&dict(vec![
                ("deviceID", Value::String("AA:BB:CC:DD:EE:FF".into())),
                ("sessionUUID", Value::String(uuid())),
                ("timingPort", Value::Int(timing_port as i64)),
                ("timingProtocol", Value::String("NTP".into())),
                ("isMultiSelectAirPlay", Value::Bool(true)),
                ("groupContainsGroupLeader", Value::Bool(false)),
                ("macAddress", Value::String("AA:BB:CC:DD:EE:FF".into())),
                ("model", Value::String("iPhone14,3".into())),
                ("name", Value::String("Lumtub".into())),
                ("osBuildVersion", Value::String("20F66".into())),
                ("osName", Value::String("iPhone OS".into())),
                ("osVersion", Value::String("16.5".into())),
                ("senderSupportsRelay", Value::Bool(false)),
                ("sourceVersion", Value::String("690.7.1".into())),
                ("statsCollectionEnabled", Value::Bool(false)),
            ])),
        )?;
        if answer.code >= 400 {
            return Err(format!("the device answered {} to SETUP", answer.code));
        }
        let port = bplist::read(&answer.body)
            .and_then(|v| v.get("eventPort").and_then(Value::number))
            .unwrap_or(0.0) as u16;
        if port != 0 {
            let write = hkdf("Events-Salt", "Events-Read-Encryption-Key", shared);
            let read = hkdf("Events-Salt", "Events-Write-Encryption-Key", shared);
            let target = SocketAddr::new(address.ip(), port);
            let mut events = None;
            for _ in 0..5 {
                match TcpStream::connect_timeout(&target, Duration::from_secs(3)) {
                    Ok(s) => {
                        events = Some(s);
                        break;
                    }
                    Err(_) => std::thread::sleep(Duration::from_secs(1)),
                }
            }
            let events = events.ok_or("could not open the event channel")?;
            let stop = self.stop.clone();
            std::thread::spawn(move || answer_events(events, Framing::new(&write, &read), stop));
        }
        let control = self.control.clone();
        let (dacp, remote, stop) = (self.dacp.clone(), self.remote, self.stop.clone());
        std::thread::spawn(move || {
            while !stop.load(Ordering::Relaxed) {
                std::thread::sleep(Duration::from_secs(2));
                if stop.load(Ordering::Relaxed) {
                    break;
                }
                let mut c = control.lock().unwrap();
                let cseq = c.cseq;
                c.cseq += 1;
                let headers = vec![
                    ("CSeq", cseq.to_string()),
                    ("DACP-ID", dacp.clone()),
                    ("Active-Remote", remote.to_string()),
                    ("Client-Instance", dacp.clone()),
                    ("User-Agent", USER_AGENT.to_string()),
                ];
                if c.conn
                    .request("POST", "/feedback", "RTSP/1.0", &headers, &[])
                    .is_err()
                {
                    break;
                }
            }
        });
        let answer = self.exchange("RECORD", &self.uri.clone(), None)?;
        if answer.code >= 400 {
            return Err(format!("the device answered {} to RECORD", answer.code));
        }
        Ok(())
    }

    pub fn status(&self) -> Result<Status, String> {
        let answer = self.http("GET", "/playback-info", &[])?;
        let Some(info) = bplist::read(&answer.body) else {
            return Ok(Status::default());
        };
        let number = |k: &str| info.get(k).and_then(Value::number).unwrap_or(0.0);
        let error = info.get("error").map(|e| {
            let code = e.get("code").and_then(Value::number).unwrap_or(0.0);
            let domain = match e.get("domain") {
                Some(Value::String(d)) => d.clone(),
                _ => String::new(),
            };
            format!("{domain} {code}")
        });
        Ok(Status {
            position: number("position"),
            duration: number("duration"),
            rate: number("rate"),
            ready: info.get("readyToPlay") == Some(&Value::Bool(true)),
            error,
        })
    }

    pub fn rate(&self, rate: f64) -> Result<(), String> {
        self.check(self.exchange("POST", &format!("/rate?value={rate:.6}"), None)?)
    }

    pub fn seek(&self, seconds: f64) -> Result<(), String> {
        self.check(self.exchange("POST", &format!("/scrub?position={seconds:.6}"), None)?)
    }

    fn check(&self, answer: super::conn::Response) -> Result<(), String> {
        if answer.code >= 400 {
            Err(format!("the device answered {}", answer.code))
        } else {
            Ok(())
        }
    }

    pub fn stop(&self) {
        let _ = self.exchange("POST", "/stop", None);
        self.close();
    }

    pub fn close(&self) {
        self.stop.store(true, Ordering::Relaxed);
        self.control.lock().unwrap().conn.shutdown();
    }
}

impl Drop for Player {
    fn drop(&mut self) {
        self.close();
    }
}

fn ntp_now() -> (u32, u32) {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let seconds = (now.as_secs() + 0x83AA_7E80) as u32;
    let fraction = ((now.subsec_nanos() as u64) << 32) / 1_000_000_000;
    (seconds, fraction as u32)
}

/// Answers NTP-style timing requests: the asker's send time back as the
/// reference, and now as receive and send time.
fn answer_timing(socket: UdpSocket, stop: Arc<AtomicBool>) {
    let mut packet = [0u8; 64];
    while !stop.load(Ordering::Relaxed) {
        let Ok((n, from)) = socket.recv_from(&mut packet) else {
            continue;
        };
        if n < 32 {
            continue;
        }
        let (s, f) = ntp_now();
        let mut reply = [0u8; 32];
        reply[0] = packet[0];
        reply[1] = 0xD3;
        reply[2..4].copy_from_slice(&7u16.to_be_bytes());
        reply[8..16].copy_from_slice(&packet[24..32]);
        reply[16..20].copy_from_slice(&s.to_be_bytes());
        reply[20..24].copy_from_slice(&f.to_be_bytes());
        reply[24..28].copy_from_slice(&s.to_be_bytes());
        reply[28..32].copy_from_slice(&f.to_be_bytes());
        let _ = socket.send_to(&reply, from);
    }
}

/// Answers every request the receiver sends on the event channel with 200.
fn answer_events(mut stream: TcpStream, mut framing: Framing, stop: Arc<AtomicBool>) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
    let mut plain = Vec::new();
    let mut chunk = [0u8; 8192];
    while !stop.load(Ordering::Relaxed) {
        let n = match stream.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) => n,
            Err(e)
                if matches!(
                    e.kind(),
                    std::io::ErrorKind::WouldBlock
                        | std::io::ErrorKind::TimedOut
                        | std::io::ErrorKind::Interrupted
                ) =>
            {
                continue;
            }
            Err(_) => break,
        };
        let Some(more) = framing.decrypt(&chunk[..n]) else {
            break;
        };
        plain.extend(more);
        while let Some((head, length)) = message_end(&plain) {
            if plain.len() < head + length {
                break;
            }
            let (first, headers) = parse_head(&plain[..head - 4]);
            plain.drain(..head + length);
            let protocol = first.rsplit(' ').next().unwrap_or("RTSP/1.0").to_string();
            let mut reply =
                format!("{protocol} 200 OK\r\nContent-Length: 0\r\nAudio-Latency: 0\r\n");
            for (k, v) in &headers {
                if k.eq_ignore_ascii_case("CSeq") || k.eq_ignore_ascii_case("Server") {
                    reply.push_str(&format!("{k}: {v}\r\n"));
                }
            }
            reply.push_str("\r\n");
            if stream
                .write_all(&framing.encrypt(reply.as_bytes()))
                .is_err()
            {
                return;
            }
        }
    }
}
