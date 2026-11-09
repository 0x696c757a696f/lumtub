//! A quick start for a video (see `StreamResolver.quick` in
//! lib/stream_resolver.dart): YouTube's `/player` answer for its visionOS
//! client, whose stream addresses need neither JavaScript nor a PO token,
//! turned into the shape of yt-dlp's answer with the formats the playback
//! rules pick. yt-dlp still resolves the video alongside; anything this
//! cannot play directly is left to it.

use std::ffi::c_char;

use serde_json::{json, Map, Value};

use crate::format_policy::{Audio, Codec, Settings};

/// The client, as yt-dlp's `visionos` sends it.
pub const CLIENT_NAME: &str = "VISIONOS";
pub const CLIENT_ID: u32 = 101;
pub const CLIENT_VERSION: &str = "1.02";
pub const USER_AGENT: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";

/// The `/player` request body for [video_id].
pub fn request(video_id: &str) -> Value {
    json!({
        "context": {"client": {
            "clientName": CLIENT_NAME,
            "clientVersion": CLIENT_VERSION,
            "deviceMake": "Apple",
            "deviceModel": "RealityDevice17,1",
            "userAgent": USER_AGENT,
            "osName": "visionOS",
            "osVersion": "26.5.23O471",
            "hl": "en",
            "timeZone": "UTC",
            "utcOffsetMinutes": 0
        }},
        "videoId": video_id,
        "playbackContext": {"contentPlaybackContext": {"html5Preference": "HTML5_PREF_WANTS"}},
        "contentCheckOk": true,
        "racyCheckOk": true
    })
}

struct Format<'a> {
    raw: &'a Value,
    itag: String,
    url: &'a str,
    codec: String,
    video: bool,
    height: u32,
    fps: u32,
    bitrate: u64,
    default_audio: bool,
}

fn number(value: Option<&Value>) -> Option<u64> {
    value.and_then(|v| v.as_u64().or_else(|| v.as_str()?.parse().ok()))
}

fn format(raw: &Value) -> Option<Format<'_>> {
    let url = raw.get("url")?.as_str()?;
    if !url.starts_with("https://") || raw.get("drmFamilies").is_some() {
        return None;
    }
    let mime = raw.get("mimeType")?.as_str()?;
    let video = mime.starts_with("video/");
    if !video && !mime.starts_with("audio/") {
        return None;
    }
    let codec = mime.split_once("codecs=\"")?.1.split(['"', ',']).next()?.trim().to_owned();
    let track = raw.get("audioTrack");
    // Dubbed tracks, and the loudness-normalised copies of a track, are
    // never the default; the original is, or the only one.
    let drc = raw.get("isDrc").and_then(Value::as_bool) == Some(true) || raw.get("xtags").and_then(Value::as_str).is_some_and(|x| x.contains("drc"));
    let default_audio = !drc && track.is_none_or(|t| t.get("audioIsDefault").and_then(Value::as_bool) == Some(true));
    Some(Format {
        raw,
        itag: number(raw.get("itag"))?.to_string(),
        url,
        codec,
        video,
        height: number(raw.get("height")).unwrap_or(0) as u32,
        fps: number(raw.get("fps")).unwrap_or(0) as u32,
        bitrate: number(raw.get("bitrate")).or_else(|| number(raw.get("averageBitrate"))).unwrap_or(0),
        default_audio,
    })
}

fn as_ytdlp(f: &Format) -> Value {
    let mut out = Map::new();
    out.insert("format_id".into(), json!(f.itag));
    out.insert("url".into(), json!(f.url));
    out.insert("protocol".into(), json!("https"));
    if f.video {
        out.insert("vcodec".into(), json!(f.codec));
        out.insert("acodec".into(), json!("none"));
        out.insert("height".into(), json!(f.height));
        if let Some(width) = number(f.raw.get("width")) {
            out.insert("width".into(), json!(width));
        }
        out.insert("fps".into(), json!(f.fps));
    } else {
        out.insert("vcodec".into(), json!("none"));
        out.insert("acodec".into(), json!(f.codec));
        out.insert("abr".into(), json!(f.bitrate as f64 / 1000.0));
    }
    out.insert("tbr".into(), json!(f.bitrate as f64 / 1000.0));
    if let Some(size) = number(f.raw.get("contentLength")) {
        out.insert("filesize".into(), json!(size));
    }
    out.insert("http_headers".into(), json!({"User-Agent": USER_AGENT}));
    Value::Object(out)
}

/// yt-dlp's answer, as far as playback reads it, for the `/player` answer
/// [player], with the formats [settings] pick as `requested_formats`; none
/// when the video cannot be started this way (not playable, live or about
/// to be, no plain addresses, nothing in an allowed codec).
pub fn info(player: &Value, settings: &Settings) -> Option<Value> {
    if player.get("playabilityStatus")?.get("status")?.as_str()? != "OK" {
        return None;
    }
    let details = player.get("videoDetails")?;
    let flag = |key: &str| details.get(key).and_then(Value::as_bool) == Some(true);
    if flag("isLive") || flag("isUpcoming") || flag("isPostLiveDvr") {
        return None;
    }
    let data = player.get("streamingData")?;
    let raw = data.get("adaptiveFormats")?.as_array()?;
    if raw.iter().any(|f| f.get("url").is_none()) {
        // Ciphered addresses need YouTube's JavaScript: yt-dlp's work.
        return None;
    }
    let formats: Vec<Format> = raw.iter().filter_map(format).collect();
    let order = settings.codec_order();
    let rank = |f: &Format| Codec::of(&f.codec).and_then(|c| order.iter().position(|o| *o == c));
    let cap = settings.max_height;
    let video = formats
        .iter()
        .filter(|f| f.video && f.height > 0 && (cap == 0 || f.height <= cap) && rank(f).is_some())
        .max_by(|a, b| {
            (a.height, a.fps)
                .cmp(&(b.height, b.fps))
                .then(rank(b).cmp(&rank(a)))
                .then(a.bitrate.cmp(&b.bitrate))
        })?;
    let limit = match settings.audio {
        Audio::Best => u64::MAX,
        Audio::Medium => 128_000,
        Audio::Low => 64_000,
    };
    let sounds = || formats.iter().filter(|f| !f.video && f.default_audio);
    let audio = sounds()
        .filter(|f| f.bitrate <= limit.saturating_add(limit / 10))
        .max_by_key(|f| f.bitrate)
        .or_else(|| sounds().min_by_key(|f| f.bitrate))?;
    Some(json!({
        "id": details.get("videoId"),
        "title": details.get("title"),
        "duration": number(details.get("lengthSeconds")),
        "live_status": "not_live",
        "formats": formats.iter().map(as_ytdlp).collect::<Vec<_>>(),
        "requested_formats": [as_ytdlp(video), as_ytdlp(audio)],
        "http_headers": {"User-Agent": USER_AGENT}
    }))
}

/// The `/player` request body for the video id [id], as JSON. Free it with
/// `lumtub_string_free`.
///
/// # Safety
/// [id] must point to [len] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_quick_request(id: *const u8, len: usize) -> *mut c_char {
    let id = unsafe { crate::taste::text(id, len) };
    crate::taste::give_json(&json!({"body": request(id), "headers": headers()}))
}

/// The headers the `/player` request goes with.
pub fn headers() -> Value {
    json!({
        "X-YouTube-Client-Name": CLIENT_ID.to_string(),
        "X-YouTube-Client-Version": CLIENT_VERSION,
        "User-Agent": USER_AGENT,
        "Origin": "https://www.youtube.com"
    })
}

/// [info] for the `/player` answer [player] and the format policy settings
/// [settings] (as `lumtub_format_policy` takes them), as JSON; null when the
/// video cannot be started this way. Free it with `lumtub_string_free`.
///
/// # Safety
/// Both must point to that many bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_quick_info(player: *const u8, player_len: usize, settings: *const u8, settings_len: usize) -> *mut c_char {
    let settings: Settings = serde_json::from_str(unsafe { crate::taste::text(settings, settings_len) }).unwrap_or_default();
    let Ok(player) = serde_json::from_str::<Value>(unsafe { crate::taste::text(player, player_len) }) else { return std::ptr::null_mut() };
    match info(&player, &settings) {
        Some(info) => crate::taste::give_json(&info),
        None => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::resolved::{summary, Ask};

    fn stream(itag: u32, mime: &str, height: u32, bitrate: u64) -> Value {
        let mut f = json!({"itag": itag, "url": format!("https://rr1.googlevideo.com/videoplayback?expire=1900003600&c=VISIONOS&itag={itag}"), "mimeType": mime, "bitrate": bitrate, "contentLength": "1000"});
        if height > 0 {
            f["height"] = json!(height);
            f["width"] = json!(height * 16 / 9);
            f["fps"] = json!(30);
        }
        f
    }

    fn player() -> Value {
        json!({
            "playabilityStatus": {"status": "OK"},
            "videoDetails": {"videoId": "abc", "title": "T", "lengthSeconds": "60"},
            "streamingData": {"adaptiveFormats": [
                stream(137, "video/mp4; codecs=\"avc1.640028\"", 1080, 4_000_000),
                stream(248, "video/webm; codecs=\"vp9\"", 1080, 2_500_000),
                stream(399, "video/mp4; codecs=\"av01.0.08M.08\"", 1080, 2_000_000),
                stream(313, "video/webm; codecs=\"vp9\"", 2160, 15_000_000),
                stream(136, "video/mp4; codecs=\"avc1.4d401f\"", 720, 1_500_000),
                stream(140, "audio/mp4; codecs=\"mp4a.40.2\"", 0, 130_000),
                stream(251, "audio/webm; codecs=\"opus\"", 0, 140_000),
                stream(250, "audio/webm; codecs=\"opus\"", 0, 70_000),
            ]}
        })
    }

    fn picked(info: &Value) -> Vec<String> {
        info["requested_formats"].as_array().unwrap().iter().map(|f| f["format_id"].as_str().unwrap().to_owned()).collect()
    }

    fn settings(json: &str) -> Settings {
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn picks_like_the_format_policy() {
        // Without verified hardware decoding: 1080p is the cap and H.264 first.
        let auto = info(&player(), &settings(r#"{"maxHeight":1080}"#)).unwrap();
        assert_eq!(picked(&auto), ["137", "251"]);
        let vp9 = info(&player(), &settings(r#"{"hardware":["vp9"]}"#)).unwrap();
        assert_eq!(picked(&vp9), ["313", "251"]);
        let no_vp9 = info(&player(), &settings(r#"{"hardware":["av1"],"disabled":["vp9"]}"#)).unwrap();
        assert_eq!(picked(&no_vp9), ["399", "251"]);
        let low = info(&player(), &settings(r#"{"maxHeight":720,"audio":"low"}"#)).unwrap();
        assert_eq!(picked(&low), ["136", "250"]);
    }

    #[test]
    fn plays_directly_through_the_resolved_summary() {
        let info = info(&player(), &settings(r#"{"maxHeight":1080}"#)).unwrap();
        let s = summary(&info, &Ask { fetched: 1_900_000_000, ..Ask::default() });
        assert_eq!(s.clients, ["VISIONOS"]);
        assert_eq!(s.streams.unwrap().len(), 2);
        assert_eq!(s.all_heights, [2160, 1080, 720]);
        assert_eq!(s.user_agent.as_deref(), Some(USER_AGENT));
    }

    #[test]
    fn prefers_the_original_audio_track() {
        let mut p = player();
        let list = p["streamingData"]["adaptiveFormats"].as_array_mut().unwrap();
        let mut dub = stream(251, "audio/webm; codecs=\"opus\"", 0, 160_000);
        dub["audioTrack"] = json!({"audioIsDefault": false});
        list.push(dub);
        let mut drc = stream(251, "audio/webm; codecs=\"opus\"", 0, 150_000);
        drc["isDrc"] = json!(true);
        list.push(drc);
        let info = info(&p, &settings("{}")).unwrap();
        assert_eq!(info["requested_formats"][1]["abr"], json!(140.0));
    }

    #[test]
    fn leaves_the_rest_to_ytdlp() {
        let s = settings("{}");
        let mut live = player();
        live["videoDetails"]["isLive"] = json!(true);
        assert!(info(&live, &s).is_none());
        let mut refused = player();
        refused["playabilityStatus"]["status"] = json!("LOGIN_REQUIRED");
        assert!(info(&refused, &s).is_none());
        let mut ciphered = player();
        ciphered["streamingData"]["adaptiveFormats"][0].as_object_mut().unwrap().remove("url");
        assert!(info(&ciphered, &s).is_none());
        assert!(info(&player(), &settings(r#"{"disabled":["h264","vp9","av1"]}"#)).is_none());
    }
}
