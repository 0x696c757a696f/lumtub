//! Casting to AirPlay receivers (Apple TV, TVs with AirPlay): pairing with
//! the PIN the TV shows, then handing it an address to play and steering
//! playback. Nothing is mirrored and no media passes through here.

pub mod bplist;
pub mod conn;
pub mod crypto;
pub mod pairing;
pub mod player;
pub mod srp;

use conn::Conn;
use pairing::Credentials;
use player::{Auth, Player};
use serde::Deserialize;
use serde_json::{Value as Json, json};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

struct Pairing {
    conn: Conn,
    salt: Vec<u8>,
    server: Vec<u8>,
}

#[derive(Default)]
struct State {
    pairings: HashMap<u64, Pairing>,
    players: HashMap<u64, Arc<Player>>,
}

fn state() -> &'static Mutex<State> {
    static STATE: OnceLock<Mutex<State>> = OnceLock::new();
    STATE.get_or_init(Default::default)
}

fn next() -> u64 {
    static ID: AtomicU64 = AtomicU64::new(1);
    ID.fetch_add(1, Ordering::Relaxed)
}

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "camelCase")]
enum Ask {
    PairStart { address: String },
    PairFinish { pairing: u64, pin: String },
    #[serde(rename_all = "camelCase")]
    Play { address: String, credentials: Option<String>, #[serde(default)] transient: bool, #[serde(default)] v2: bool, url: String, #[serde(default)] position: f64 },
    Status { session: u64 },
    Rate { session: u64, value: f64 },
    Seek { session: u64, seconds: f64 },
    Stop { session: u64 },
}

fn address(text: &str) -> Result<SocketAddr, String> {
    text.parse().map_err(|_| format!("not an address: {text}"))
}

fn player(id: u64) -> Result<Arc<Player>, String> {
    state().lock().unwrap().players.get(&id).cloned().ok_or_else(|| "no such session".to_string())
}

/// Carries out one request; blocks while the device answers.
pub fn handle(ask: &str) -> Json {
    let answer = (|| -> Result<Json, String> {
        match serde_json::from_str::<Ask>(ask).map_err(|e| e.to_string())? {
            Ask::PairStart { address: a } => {
                let mut conn = Conn::open(address(&a)?).map_err(|e| format!("could not reach the device: {e}"))?;
                let (salt, server) = pairing::start(&mut conn)?;
                let id = next();
                state().lock().unwrap().pairings.insert(id, Pairing { conn, salt, server });
                Ok(json!({ "pairing": id }))
            }
            Ask::PairFinish { pairing: id, pin } => {
                let mut p = state().lock().unwrap().pairings.remove(&id).ok_or("pairing ended; start again")?;
                let credentials = pairing::finish(&mut p.conn, &p.salt, &p.server, pin.trim())?;
                p.conn.shutdown();
                Ok(json!({ "credentials": credentials.text() }))
            }
            Ask::Play { address: a, credentials, transient, v2, url, position } => {
                let auth = match credentials.as_deref() {
                    Some(c) => Auth::Paired(Credentials::parse(c).ok_or("unreadable credentials")?),
                    None if transient => Auth::Transient,
                    None => Auth::None,
                };
                let played = Player::play(address(&a)?, auth, v2, &url, position)?;
                let id = next();
                let mut s = state().lock().unwrap();
                for (_, old) in s.players.drain() {
                    old.close();
                }
                s.players.insert(id, Arc::new(played));
                Ok(json!({ "session": id }))
            }
            Ask::Status { session } => {
                let st = player(session)?.status()?;
                Ok(json!({ "position": st.position, "duration": st.duration, "rate": st.rate, "ready": st.ready, "error": st.error }))
            }
            Ask::Rate { session, value } => player(session)?.rate(value).map(|_| json!({})),
            Ask::Seek { session, seconds } => player(session)?.seek(seconds).map(|_| json!({})),
            Ask::Stop { session } => {
                if let Some(p) = state().lock().unwrap().players.remove(&session) {
                    p.stop();
                }
                Ok(json!({}))
            }
        }
    })();
    answer.unwrap_or_else(|error| json!({ "error": error }))
}

/// One AirPlay request as JSON (`op` names it); the answer as JSON, with
/// `error` when it failed. Blocks while the device answers.
///
/// # Safety
/// [json] points at [len] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_airplay(json: *const u8, len: usize) -> *mut std::os::raw::c_char {
    crate::taste::give_json(&handle(unsafe { crate::taste::text(json, len) }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ask(value: Json) -> Json {
        let answer = handle(&value.to_string());
        assert!(answer["error"].is_null(), "{value} → {answer}");
        answer
    }

    /// Against a receiver given in LUMTUB_AIRPLAY_FAKE (address, PIN 1111).
    #[test]
    fn plays_on_a_receiver() {
        let Ok(address) = std::env::var("LUMTUB_AIRPLAY_FAKE") else { return };
        let v2 = std::env::var("LUMTUB_AIRPLAY_V1").is_err();
        let pairing = ask(json!({ "op": "pairStart", "address": address }))["pairing"].as_u64().unwrap();
        let wrong = handle(&json!({ "op": "pairFinish", "pairing": pairing, "pin": "0000" }).to_string());
        assert!(wrong.get("error").is_some());
        let pairing = ask(json!({ "op": "pairStart", "address": address }))["pairing"].as_u64().unwrap();
        let credentials = ask(json!({ "op": "pairFinish", "pairing": pairing, "pin": " 1111 " }))["credentials"].as_str().unwrap().to_string();
        let session = ask(json!({ "op": "play", "address": address, "credentials": credentials, "v2": v2, "url": "http://127.0.0.1:1/x.m3u8", "position": 12.5 }))["session"].as_u64().unwrap();
        ask(json!({ "op": "rate", "session": session, "value": 0.0 }));
        ask(json!({ "op": "seek", "session": session, "seconds": 30.0 }));
        let status = ask(json!({ "op": "status", "session": session }));
        assert_eq!(status["duration"], 100.0);
        assert_eq!(status["position"], 30.0);
        assert_eq!(status["rate"], 0.0);
        assert_eq!(status["ready"], true);
        std::thread::sleep(std::time::Duration::from_millis(4500));
        ask(json!({ "op": "stop", "session": session }));
        assert!(handle(&json!({ "op": "status", "session": session }).to_string()).get("error").is_some());
        if v2 {
            let session = ask(json!({ "op": "play", "address": address, "transient": true, "v2": true, "url": "http://127.0.0.1:1/y.m3u8" }))["session"].as_u64().unwrap();
            assert_eq!(ask(json!({ "op": "status", "session": session }))["position"], 0.0);
            ask(json!({ "op": "stop", "session": session }));
        }
    }
}
