//! SHA-256: of downloaded files, and the hash prefix SponsorBlock and
//! DeArrow get instead of the video id; and reading their answers.
//!
//! Only the first four hex digits of the id's SHA-256 leave the computer, so
//! the servers cannot tell which video is watched; they answer for every
//! video sharing the prefix and the match happens here.

use serde::Serialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::os::raw::c_char;

use crate::taste::{give, give_json, text};

/// The first four hex digits of the SHA-256 of [video_id].
pub fn hash_prefix(video_id: &str) -> String {
    let digest = Sha256::digest(video_id.as_bytes());
    format!("{:02x}{:02x}", digest[0], digest[1])
}

/// A part of a video to skip, in milliseconds.
#[derive(Serialize, Debug, PartialEq)]
pub struct Segment {
    pub start: i64,
    pub end: i64,
    pub category: String,
}

/// The skip segments of [video_id] in [categories] from a SponsorBlock
/// answer, in order. Mutes and points are left out.
pub fn segments(answer: &Value, video_id: &str, categories: &[String]) -> Vec<Segment> {
    let mut found = Vec::new();
    let videos = answer.as_array().map(Vec::as_slice).unwrap_or_default();
    for video in videos.iter().filter(|video| video.get("videoID").and_then(Value::as_str) == Some(video_id)) {
        let Some(list) = video.get("segments").and_then(Value::as_array) else { continue };
        for segment in list {
            if segment.get("actionType").map_or("skip", |a| a.as_str().unwrap_or("")) != "skip" {
                continue;
            }
            let Some([start, end]) = segment.get("segment").and_then(Value::as_array).and_then(|b| <&[Value; 2]>::try_from(b.as_slice()).ok()) else {
                continue;
            };
            let (Some(start), Some(end)) = (start.as_f64(), end.as_f64()) else { continue };
            let category = match segment.get("category") {
                Some(Value::String(s)) => s.clone(),
                Some(Value::Null) | None => String::new(),
                Some(other) => other.to_string(),
            };
            if !categories.contains(&category) {
                continue;
            }
            let (start, end) = ((start * 1000.0).round() as i64, (end * 1000.0).round() as i64);
            if end > start {
                found.push(Segment { start, end, category });
            }
        }
    }
    found.sort_by_key(|segment| segment.start);
    found
}

/// The title and thumbnail time DeArrow users gave a video.
#[derive(Serialize, Debug, PartialEq, Default)]
pub struct Branding {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(rename = "thumbnailTime", skip_serializing_if = "Option::is_none")]
    pub thumbnail_time: Option<f64>,
}

fn custom(entry: Option<&Value>) -> Option<&Value> {
    entry.filter(|e| e.get("original") != Some(&Value::Bool(true)))
}

/// The branding of [video_id] in a DeArrow answer: the first title and
/// thumbnail that are locked or not voted down, unless it is YouTube's own.
pub fn branding(answer: &Value, video_id: &str) -> Branding {
    let Some(video) = answer.get(video_id).filter(|v| v.is_object()) else {
        return Branding::default();
    };
    let trusted = |entry: &&Value| entry.get("locked") == Some(&Value::Bool(true)) || entry.get("votes").and_then(Value::as_f64).is_some_and(|votes| votes >= 0.0);
    let best = |key: &str| video.get(key).and_then(Value::as_array)?.iter().filter(|e| e.is_object()).find(trusted);
    let title = custom(best("titles")).map(|title| match title.get("title") {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Null) | None => String::new(),
        Some(other) => other.to_string(),
    });
    // A title starting with ">" asks not to be re-cased; the mark is not shown.
    let title = title.map(|t| t.strip_prefix('>').map_or(t.as_str(), str::trim_start).trim().to_owned()).filter(|t| !t.is_empty());
    let thumbnail_time = custom(best("thumbnails")).and_then(|t| t.get("timestamp")).and_then(Value::as_f64);
    Branding { title, thumbnail_time }
}

/// The SHA-256 of the file at [path] in lowercase hex.
pub fn file_sha256(path: &str) -> std::io::Result<String> {
    use std::io::Read;
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0; 1 << 20];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hasher.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

/// [file_sha256] for Dart; null when the file cannot be read. Free the text
/// with `lumtub_string_free`.
///
/// # Safety
/// [path] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_file_sha256(path: *const u8, length: usize) -> *mut c_char {
    file_sha256(unsafe { text(path, length) }).map_or(std::ptr::null_mut(), give)
}

/// [hash_prefix] for Dart. Free the text with `lumtub_string_free`.
///
/// # Safety
/// [video_id] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_hash_prefix(video_id: *const u8, length: usize) -> *mut c_char {
    give(hash_prefix(unsafe { text(video_id, length) }))
}

/// [segments] as JSON `[{start, end, category}]`. [json] is `{answer,
/// videoId, categories}` with the answer as SponsorBlock's text.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_sponsor_segments(json: *const u8, length: usize) -> *mut c_char {
    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Ask {
        answer: String,
        video_id: String,
        categories: Vec<String>,
    }
    let Ok(ask) = serde_json::from_str::<Ask>(unsafe { text(json, length) }) else {
        return std::ptr::null_mut();
    };
    let answer = serde_json::from_str(&ask.answer).unwrap_or(Value::Null);
    give_json(&segments(&answer, &ask.video_id, &ask.categories))
}

/// [branding] as JSON `{title?, thumbnailTime?}`. [json] is the video id,
/// a newline and DeArrow's answer, or `{answer, videoId}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_dearrow_branding(json: *const u8, length: usize) -> *mut c_char {
    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Ask {
        answer: String,
        video_id: String,
    }
    let input = unsafe { text(json, length) };
    // The video id, a newline and the answer as it came, which spares the
    // app escaping the answer into JSON; or the older JSON object.
    if let Some((video_id, body)) = input.split_once('\n')
        && !video_id.starts_with('{')
    {
        let answer = serde_json::from_str(body).unwrap_or(Value::Null);
        return give_json(&branding(&answer, video_id));
    }
    let Ok(ask) = serde_json::from_str::<Ask>(input) else {
        return std::ptr::null_mut();
    };
    let answer = serde_json::from_str(&ask.answer).unwrap_or(Value::Null);
    give_json(&branding(&answer, &ask.video_id))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn hashes_files() {
        let path = std::env::temp_dir().join(format!("lumtub-sha-{}", std::process::id()));
        std::fs::write(&path, b"abc").unwrap();
        assert_eq!(file_sha256(path.to_str().unwrap()).unwrap(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        std::fs::remove_file(&path).unwrap();
        assert!(file_sha256("/no/such/file").is_err());
    }

    #[test]
    fn hashes_the_video_id() {
        assert_eq!(hash_prefix("dQw4w9WgXcQ"), "5f6b");
    }

    #[test]
    fn keeps_the_skip_segments_of_the_video() {
        let answer = json!([
            {"videoID": "otherVideo1", "segments": [{"segment": [1, 20], "category": "sponsor", "actionType": "skip"}]},
            {"videoID": "dQw4w9WgXcQ", "segments": [
                {"segment": [120.5, 150], "category": "selfpromo", "actionType": "skip"},
                {"segment": [10, 30.25], "category": "sponsor", "actionType": "skip"},
                {"segment": [40, 50], "category": "sponsor", "actionType": "mute"},
                {"segment": [60, 70], "category": "music_offtopic", "actionType": "skip"},
                {"segment": [80, 80], "category": "sponsor"},
                {"segment": [90], "category": "sponsor"}
            ]}
        ]);
        let categories = ["sponsor".to_owned(), "selfpromo".to_owned()];
        assert_eq!(
            segments(&answer, "dQw4w9WgXcQ", &categories),
            [
                Segment { start: 10_000, end: 30_250, category: "sponsor".into() },
                Segment { start: 120_500, end: 150_000, category: "selfpromo".into() },
            ]
        );
        assert!(segments(&json!({}), "dQw4w9WgXcQ", &categories).is_empty());
    }

    #[test]
    fn takes_trusted_custom_branding() {
        let answer = json!({"abc": {
            "titles": [
                {"title": "Voted down", "votes": -1, "locked": false},
                {"title": "> Keep this casing ", "votes": 0},
            ],
            "thumbnails": [{"timestamp": 12.5, "votes": 3}],
        }});
        assert_eq!(branding(&answer, "abc"), Branding { title: Some("Keep this casing".into()), thumbnail_time: Some(12.5) });
        let original = json!({"abc": {"titles": [{"title": "Same", "original": true, "votes": 5}], "thumbnails": [{"original": true, "locked": true}]}});
        assert_eq!(branding(&original, "abc"), Branding::default());
        assert_eq!(branding(&answer, "other"), Branding::default());
    }

    #[test]
    fn branding_takes_the_id_line_and_the_json_object_alike() {
        let read = |input: &str| {
            let out = unsafe { lumtub_dearrow_branding(input.as_ptr(), input.len()) };
            let text = unsafe { std::ffi::CStr::from_ptr(out) }.to_str().unwrap().to_owned();
            unsafe { crate::taste::lumtub_string_free(out) };
            text
        };
        let answer = r#"{"abc": {"titles": [{"title": "New\nline", "votes": 1}], "thumbnails": []}}"#;
        let line = read(&format!("abc\n{answer}"));
        assert!(line.contains("New"));
        assert_eq!(read(&json!({"answer": answer, "videoId": "abc"}).to_string()), line);
    }
}
