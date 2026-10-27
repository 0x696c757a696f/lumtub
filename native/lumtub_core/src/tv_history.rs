//! Adds what is watched in Lumtub to the YouTube account's watch history,
//! the way SmartTube does for the TV app: a `player` request made signed in
//! as the older TV client gives the tracking values (`ei`, `vm`, `of`),
//! then `api/stats/playback` creates the record and `api/stats/watchtime`
//! says how far it was watched. Only when the user turns it on.

use std::time::Duration;

use serde::Deserialize;
use serde_json::{Value, json};

use crate::http::{Item, client, post, runtime};
use crate::innertube::at;
use crate::taste::text;
use crate::tv_account::{NoToken, access_token, base, forget_access};

/// SmartTube's `TV_DOWNGRADED`: the TV client the history works with.
const CLIENT_VERSION: &str = "5.20260901";
const USER_AGENT: &str = "Mozilla/5.0 (DirectFB; Linux x86_64) Cobalt/4.13031-qa (unlike Gecko) Starboard/1";

#[derive(Deserialize, Debug)]
pub struct Watched {
    pub video_id: String,
    /// Seconds into the video where watching started and stopped.
    pub from: f64,
    pub to: f64,
    /// The video's length in seconds; 0 when not known.
    #[serde(default)]
    pub length: f64,
    #[serde(default)]
    pub hl: String,
}

/// A client playback nonce: 16 characters of `A-Za-z0-9-_`.
fn cpn() -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let seed = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0) ^ (std::process::id() as u128) << 64;
    let digest = <sha2::Sha256 as sha2::Digest>::digest(seed.to_le_bytes());
    digest[..16].iter().map(|b| ALPHABET[(b & 63) as usize] as char).collect()
}

/// The `player` request body of the older TV client.
pub fn player_body(video_id: &str, cpn: &str, hl: &str) -> Value {
    json!({
        "context": {
            "client": {"clientName": "TVHTML5", "clientVersion": CLIENT_VERSION, "clientScreen": "WATCH", "userAgent": USER_AGENT, "hl": if hl.is_empty() { "en" } else { hl }},
            "user": {"enableSafetyMode": false, "lockedSafetyMode": false},
        },
        "playbackContext": {
            "contentPlaybackContext": {"html5Preference": "HTML5_PREF_WANTS", "lactMilliseconds": 60000, "isInlinePlaybackNoAd": true},
            "devicePlaybackCapabilities": {"supportsVp9Encoding": true, "supportXhr": false},
        },
        "racyCheckOk": true,
        "contentCheckOk": true,
        "videoId": video_id,
        "cpn": cpn,
    })
}

/// The tracking values in a `player` answer: `ei`, `vm`, `of` as they
/// stand in its watch-time address (still URL-encoded), and the length.
#[derive(Debug, PartialEq)]
pub struct Tracking {
    pub ei: String,
    pub vm: String,
    pub of: String,
    pub length: f64,
}

pub fn tracking(player: &Value) -> Option<Tracking> {
    let url = at(player, &["playbackTracking", "videostatsWatchtimeUrl", "baseUrl"])
        .or_else(|| at(player, &["playbackTracking", "videostatsPlaybackUrl", "baseUrl"]))
        .and_then(Value::as_str)?;
    let query = url.split_once('?')?.1;
    let field = |name: &str| query.split('&').find_map(|pair| pair.strip_prefix(name)?.strip_prefix('=')).map(str::to_owned);
    let length = at(player, &["videoDetails", "lengthSeconds"]).and_then(Value::as_str).and_then(|t| t.parse().ok()).unwrap_or(0.0);
    Some(Tracking { ei: field("ei")?, vm: field("vm")?, of: field("of")?, length })
}

/// The two `api/stats` addresses for [watched] as SmartTube builds them:
/// the record (from where watching started) and the watch time. Near the
/// end (less than 5% left) both say `final=1`, which marks it watched.
pub fn stats(base: &str, watched: &Watched, tracking: &Tracking, cpn: &str) -> [String; 2] {
    let length = if watched.length > 0.0 { watched.length } else { tracking.length };
    let done = length > 0.0 && length - watched.to < 0.05 * length;
    let (from, to) = if done { (length, length) } else { (watched.from, watched.to) };
    let common = format!("docid={}&cpn={cpn}&ei={}&vm={}&of={}&len={length:.3}", watched.video_id, tracking.ei, tracking.vm, tracking.of);
    let last = if done { "&final=1" } else { "" };
    [
        format!("{base}/api/stats/playback?ns=yt&ver=2&{common}&cmt={from:.3}{last}"),
        format!("{base}/api/stats/watchtime?ns=yt&ver=2&{common}&st={from:.3}&et={to:.3}&cmt={to:.3}{last}"),
    ]
}

async fn report(port: i64, watched: Watched) {
    let fail = |why: String| {
        post(port, vec![Item::Int(0), Item::Text(why)]);
    };
    let token = match access_token().await {
        Ok(token) => token,
        Err(NoToken::SignedOut | NoToken::Revoked) => return fail("signed out".into()),
        Err(NoToken::Failed(why)) => return fail(why),
    };
    let base = base();
    let nonce = cpn();
    let request = |url: String| {
        client()
            .request(if url.contains("/youtubei/") { reqwest::Method::POST } else { reqwest::Method::GET }, url)
            .bearer_auth(&token)
            .header("User-Agent", USER_AGENT)
            .header("Referer", "https://www.youtube.com/tv")
            .header("X-YouTube-Client-Name", "7")
            .header("X-YouTube-Client-Version", CLIENT_VERSION)
            .timeout(Duration::from_secs(20))
    };
    let player = request(format!("{base}/youtubei/v1/player?prettyPrint=false"))
        .header("Content-Type", "application/json")
        .body(player_body(&watched.video_id, &nonce, &watched.hl).to_string())
        .send()
        .await;
    let player = match player {
        Ok(response) if response.status().is_success() => response.bytes().await.ok().and_then(|b| serde_json::from_slice::<Value>(&b).ok()),
        Ok(response) => {
            if response.status().as_u16() == 401 {
                forget_access();
            }
            return fail(format!("player answered {}", response.status().as_u16()));
        }
        Err(e) => return fail(e.to_string()),
    };
    let Some(tracking) = player.as_ref().and_then(tracking) else {
        return fail("no tracking in the player answer".into());
    };
    for url in stats(&base, &watched, &tracking, &nonce) {
        match request(url).send().await {
            Ok(response) if response.status().is_success() => {}
            Ok(response) => return fail(format!("stats answered {}", response.status().as_u16())),
            Err(e) => return fail(e.to_string()),
        }
    }
    post(port, vec![Item::Int(1)]);
}

/// Adds [json] (a [Watched]) to the account's history, answering `[1]` on
/// [port], or `[0, why]`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_tv_watched(port: i64, json: *const u8, length: usize) -> bool {
    let Ok(watched) = serde_json::from_str::<Watched>(unsafe { text(json, length) }) else {
        return false;
    };
    runtime().spawn(report(port, watched));
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn player() -> Value {
        json!({
            "playbackTracking": {"videostatsWatchtimeUrl": {"baseUrl": "https://s.youtube.com/api/stats/watchtime?cl=1&docid=abc&ei=EI%3D&fexp=2&ns=yt&len=600&of=OF&vm=VM_1"}},
            "videoDetails": {"lengthSeconds": "600"}
        })
    }

    #[test]
    fn reads_the_tracking_values() {
        assert_eq!(tracking(&player()), Some(Tracking { ei: "EI%3D".into(), vm: "VM_1".into(), of: "OF".into(), length: 600.0 }));
        assert_eq!(tracking(&json!({})), None);
    }

    #[test]
    fn builds_the_stats_addresses() {
        let track = tracking(&player()).unwrap();
        let watched = Watched { video_id: "abcdefghijk".into(), from: 0.0, to: 120.5, length: 0.0, hl: String::new() };
        let [record, time] = stats("https://www.youtube.com", &watched, &track, "CPN");
        assert_eq!(record, "https://www.youtube.com/api/stats/playback?ns=yt&ver=2&docid=abcdefghijk&cpn=CPN&ei=EI%3D&vm=VM_1&of=OF&len=600.000&cmt=0.000");
        assert_eq!(time, "https://www.youtube.com/api/stats/watchtime?ns=yt&ver=2&docid=abcdefghijk&cpn=CPN&ei=EI%3D&vm=VM_1&of=OF&len=600.000&st=0.000&et=120.500&cmt=120.500");

        let ended = Watched { to: 590.0, ..watched };
        let [record, time] = stats("https://www.youtube.com", &ended, &track, "CPN");
        assert!(record.ends_with("&cmt=600.000&final=1"));
        assert!(time.ends_with("&st=600.000&et=600.000&cmt=600.000&final=1"));
    }

    #[test]
    fn makes_a_nonce() {
        let nonce = cpn();
        assert_eq!(nonce.len(), 16);
        assert!(nonce.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_'));
    }
}
