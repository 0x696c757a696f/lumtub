//! The streams a Piped server or an Invidious instance lists for a video,
//! read from its answer (see lib/piped_streams.dart and
//! lib/invidious_streams.dart for the side that calls this).
//!
//! It reads only the stream lists out of answers that also carry the
//! description, related videos and captions, and gives each stream's
//! address, codec, height, bitrate and container. Whether an address may be
//! played is decided in Dart (media_url_policy.dart), with the server's own
//! hosts, as for every other address the app opens.

use std::ffi::c_char;

use serde::Serialize;
use serde_json::{Map, Value};

use crate::taste::give_json;

/// The most an answer may be: Invidious's are about 100 KB, Piped's a
/// little more with related videos.
const MAX_ANSWER: usize = 8 << 20;
/// The most streams of one kind kept: YouTube lists a few dozen.
const MAX_STREAMS: usize = 400;

/// One stream: [address, codec, height, bitrate, container, video only].
/// The codec is
/// in yt-dlp's names (avc1, vp9, av01, mp4a, opus); the container is a MIME
/// type such as video/mp4, or empty.
#[derive(Serialize, Debug, PartialEq)]
pub struct Stream(
    pub String,
    pub String,
    pub i64,
    pub i64,
    pub String,
    pub bool,
);

#[derive(Serialize, Debug, Default, PartialEq)]
pub struct RelayVideo {
    /// Video-only streams, audio-only streams, and files with both.
    pub video: Vec<Stream>,
    pub audio: Vec<Stream>,
    pub muxed: Vec<Stream>,
    pub live: bool,
    /// Piped's `proxyUrl`, whose host is the server's own.
    #[serde(rename = "proxyUrl", skip_serializing_if = "Option::is_none")]
    pub proxy_url: Option<String>,
    /// What the server said went wrong (Piped's `message`, Invidious's
    /// `error`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// What Dart's `'$value'` writes, as far as anything here depends on it.
fn dart_text(value: Option<&Value>) -> String {
    match value {
        None | Some(Value::Null) => "null".into(),
        Some(Value::String(s)) => s.clone(),
        Some(Value::Bool(b)) => b.to_string(),
        Some(Value::Number(n)) => match (n.as_i64(), n.as_f64()) {
            (Some(i), _) => i.to_string(),
            (None, Some(f)) if f.fract() == 0.0 && f.abs() < 1e21 => format!("{f:.1}"),
            (None, Some(f)) => f.to_string(),
            _ => n.to_string(),
        },
        // A list or a map is never a stream's address, type or size.
        Some(_) => String::new(),
    }
}

/// Dart's `value?.toString() ?? ''`.
fn text_or_empty(value: Option<&Value>) -> String {
    match value {
        None | Some(Value::Null) => String::new(),
        other => dart_text(other),
    }
}

/// A number field as the Dart read it: a number cut to a whole one, or a
/// text of one; 0 otherwise.
fn number(value: Option<&Value>) -> i64 {
    match value {
        Some(Value::Number(n)) => n
            .as_i64()
            .unwrap_or_else(|| n.as_f64().map_or(0, |f| f as i64)),
        other => crate::vtt::dart_int(&dart_text(other)).unwrap_or(0),
    }
}

/// [codec] in yt-dlp's names, guessed from the container [mime] when the
/// server named none.
fn codec_of(codec: &str, mime: &str) -> String {
    let mut codec = codec.to_lowercase();
    if codec.starts_with("vp09") {
        codec = "vp9".into();
    }
    if codec.is_empty() && mime.contains("mp4") {
        codec = if mime.starts_with("audio") {
            "mp4a"
        } else {
            "avc1"
        }
        .into();
    }
    codec
}

/// The container of a MIME type with parameters: `video/mp4; codecs=…` →
/// `video/mp4`.
fn container(mime: &str) -> String {
    crate::vtt::dart_trim(mime.split(';').next().unwrap_or("")).to_owned()
}

fn list<'a>(
    json: &'a Map<String, Value>,
    key: &str,
) -> impl Iterator<Item = &'a Map<String, Value>> {
    json.get(key)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_object)
}

/// The streams of a Piped `/streams/<id>` answer.
pub fn piped(json: &Map<String, Value>) -> RelayVideo {
    let stream = |raw: &Map<String, Value>| {
        let mime = text_or_empty(raw.get("mimeType"));
        let codec = codec_of(&text_or_empty(raw.get("codec")), &mime);
        let only = raw.get("videoOnly") == Some(&Value::Bool(true));
        let stream = Stream(
            text_or_empty(raw.get("url")),
            codec,
            number(raw.get("height")),
            number(raw.get("bitrate")),
            container(&mime),
            only,
        );
        (stream, only)
    };
    let mut out = RelayVideo {
        live: json.get("livestream") == Some(&Value::Bool(true)),
        proxy_url: Some(dart_text(json.get("proxyUrl"))),
        ..RelayVideo::default()
    };
    for (s, only) in list(json, "videoStreams").map(stream) {
        if s.2 <= 0 {
            continue;
        }
        if only {
            out.video.push(s);
        } else if s.4.is_empty() || s.4.contains("mp4") {
            out.muxed.push(s);
        }
    }
    out.audio = list(json, "audioStreams")
        .map(|raw| stream(raw).0)
        .collect();
    out
}

/// `codecs="?([^",;]+)`: the first codec named in a MIME type.
fn codecs(kind: &str) -> String {
    let stop = |c: char| matches!(c, '"' | ',' | ';');
    let mut from = 0;
    while let Some(at) = kind[from..].find("codecs=") {
        let rest = &kind[from + at + "codecs=".len()..];
        for start in [rest.strip_prefix('"'), Some(rest)].into_iter().flatten() {
            let end = start.find(stop).unwrap_or(start.len());
            if end > 0 {
                return start[..end].to_owned();
            }
        }
        from += at + 1;
    }
    String::new()
}

/// `^(\d+)x(\d+)$`: the height of a `WIDTHxHEIGHT` size.
fn size_height(size: &str) -> Option<i64> {
    let (width, height) = size.split_once('x')?;
    let digits = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit());
    // Dart's int.parse failed on a height past 64 bits; that is no height.
    (digits(width) && digits(height)).then(|| height.parse().unwrap_or(0))
}

/// `^\d+` of [label], such as 1080 of `1080p60`; 0 without one.
fn leading_number(label: &str) -> i64 {
    let end = label
        .bytes()
        .position(|b| !b.is_ascii_digit())
        .unwrap_or(label.len());
    label[..end].parse().unwrap_or(0)
}

/// The streams of an Invidious `/api/v1/videos/<id>` answer: the
/// video-only and audio-only `adaptiveFormats`, and the `formatStreams`
/// with picture and sound together. Addresses are as the instance wrote
/// them; Dart makes those without a host its own.
pub fn invidious(json: &Map<String, Value>) -> RelayVideo {
    let mut out = RelayVideo {
        live: json.get("liveNow") == Some(&Value::Bool(true)),
        ..RelayVideo::default()
    };
    for format in list(json, "adaptiveFormats") {
        let kind = dart_text(format.get("type"));
        let mime = container(&kind);
        let video = mime.starts_with("video/");
        if !video && !mime.starts_with("audio/") {
            continue;
        }
        let height = match size_height(&dart_text(format.get("size"))) {
            Some(height) => height,
            None => {
                let label = match format.get("qualityLabel") {
                    None | Some(Value::Null) => format.get("resolution"),
                    label => label,
                };
                leading_number(&dart_text(label))
            }
        };
        let stream = Stream(
            dart_text(format.get("url")),
            codec_of(&codecs(&kind), &mime),
            if video { height } else { 0 },
            number(format.get("bitrate")),
            mime,
            video,
        );
        if !video {
            out.audio.push(stream);
        } else if height > 0 {
            out.video.push(stream);
        }
    }
    for format in list(json, "formatStreams") {
        let kind = dart_text(format.get("type"));
        let height = size_height(&dart_text(format.get("size")))
            .unwrap_or_else(|| leading_number(&dart_text(format.get("qualityLabel"))));
        let mime = container(&kind);
        if height > 0 && mime == "video/mp4" {
            out.muxed.push(Stream(
                dart_text(format.get("url")),
                codec_of(&codecs(&kind), &kind),
                height,
                number(format.get("bitrate")),
                mime,
                false,
            ));
        }
    }
    out
}

/// The streams in a Piped ([invidious] false) or Invidious answer [body]:
/// JSON `{"video": [[address, codec, height, bitrate, container, video
/// only]…],
/// "audio": […], "muxed": […], "live": bool, "proxyUrl"?, "error"?}`; null
/// when it is not a JSON object or is too long.
///
/// # Safety
/// [body] must point to [len] bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_relay_video(
    invidious: bool,
    body: *const u8,
    len: usize,
) -> *mut c_char {
    if len > MAX_ANSWER || body.is_null() {
        return std::ptr::null_mut();
    }
    // SAFETY: `body` was just checked non-null and `len` is within `MAX_ANSWER`; the caller
    // guarantees `len` readable bytes, per this function's `# Safety`.
    let bytes = unsafe { std::slice::from_raw_parts(body, len) };
    let Ok(Value::Object(json)) = serde_json::from_slice::<Value>(bytes) else {
        return std::ptr::null_mut();
    };
    let mut video = if invidious {
        self::invidious(&json)
    } else {
        piped(&json)
    };
    for streams in [&mut video.video, &mut video.audio, &mut video.muxed] {
        streams.truncate(MAX_STREAMS);
    }
    video.error = json
        .get(if invidious { "error" } else { "message" })
        .filter(|v| !v.is_null())
        .map(|v| dart_text(Some(v)));
    give_json(&video)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn object(value: Value) -> Map<String, Value> {
        value.as_object().cloned().unwrap()
    }

    #[test]
    fn piped_streams_by_kind() {
        let answer = object(json!({
            "livestream": false,
            "proxyUrl": "https://proxy.example",
            "videoStreams": [
                {"url": "https://a/v", "codec": "VP09.00.40.08", "height": 1080, "bitrate": 2_000_000, "videoOnly": true, "mimeType": "video/webm; codecs=\"vp9\""},
                {"url": "https://a/m", "codec": null, "height": "360", "bitrate": 500_000.7, "videoOnly": false, "mimeType": "video/mp4"},
                {"url": "https://a/w", "height": 0, "videoOnly": true},
            ],
            "audioStreams": [{"url": "https://a/a", "mimeType": "audio/mp4", "bitrate": 128_000}],
        }));
        let video = piped(&answer);
        assert_eq!(
            video.video,
            [Stream(
                "https://a/v".into(),
                "vp9".into(),
                1080,
                2_000_000,
                "video/webm".into(),
                true
            )]
        );
        assert_eq!(
            video.muxed,
            [Stream(
                "https://a/m".into(),
                "avc1".into(),
                360,
                500_000,
                "video/mp4".into(),
                false
            )]
        );
        assert_eq!(
            video.audio,
            [Stream(
                "https://a/a".into(),
                "mp4a".into(),
                0,
                128_000,
                "audio/mp4".into(),
                false
            )]
        );
        assert_eq!(video.proxy_url.as_deref(), Some("https://proxy.example"));
    }

    #[test]
    fn invidious_streams_by_kind() {
        let answer = object(json!({
            "liveNow": false,
            "adaptiveFormats": [
                {"url": "/videoplayback?x", "type": "video/mp4; codecs=\"avc1.640028\"", "size": "1920x1080", "bitrate": "4000000"},
                {"url": "https://i/a", "type": "audio/webm; codecs=\"opus\"", "bitrate": 160_000},
                {"url": "https://i/v", "type": "video/webm; codecs=\"vp9\"", "qualityLabel": "720p60"},
                {"url": "https://i/t", "type": "text/vtt"},
            ],
            "formatStreams": [
                {"url": "https://i/m", "type": "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"", "qualityLabel": "360p"},
                {"url": "https://i/w", "type": "video/webm", "size": "640x360"},
            ],
        }));
        let video = invidious(&answer);
        assert_eq!(video.video.len(), 2);
        assert_eq!(
            video.video[0],
            Stream(
                "/videoplayback?x".into(),
                "avc1.640028".into(),
                1080,
                4_000_000,
                "video/mp4".into(),
                true
            )
        );
        assert_eq!(video.video[1].2, 720);
        assert_eq!(
            video.audio,
            [Stream(
                "https://i/a".into(),
                "opus".into(),
                0,
                160_000,
                "audio/webm".into(),
                false
            )]
        );
        assert_eq!(
            video.muxed,
            [Stream(
                "https://i/m".into(),
                "avc1.42001e".into(),
                360,
                0,
                "video/mp4".into(),
                false
            )]
        );
    }

    #[test]
    fn codecs_read_as_the_pattern_did() {
        assert_eq!(
            codecs("video/mp4; codecs=\"\"; codecs=\"avc1.4d\""),
            "avc1.4d"
        );
        assert_eq!(codecs("audio/webm; codecs=opus"), "opus");
        assert_eq!(codecs("video/mp4"), "");
    }
}
