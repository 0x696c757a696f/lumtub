//! What a video yt-dlp resolved for playback offers (see
//! lib/stream_resolver.dart for the side that calls this): how long its
//! stream addresses last, which picture heights exist in which codecs, and
//! whether mpv can play the picked formats straight from their addresses.
//! It reads yt-dlp's `--dump-single-json` answer as yt-dlp printed it.

use std::collections::BTreeMap;
use std::ffi::c_char;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::format_policy::Codec;

/// What is asked about: the codecs the playback rules disable, the height
/// cap (0 for none) and when the answer was fetched, in Unix seconds.
#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
pub struct Ask {
    pub disabled: Vec<Codec>,
    pub cap: u32,
    pub fetched: i64,
}

#[derive(Serialize, Debug, PartialEq)]
pub struct Stream {
    pub url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
}

/// The tallest picture up to the cap exists only in disabled codecs.
#[derive(Serialize, Debug, PartialEq)]
pub struct Lost {
    pub height: u32,
    pub codecs: Vec<Codec>,
    pub playing: u32,
}

#[derive(Serialize, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Summary {
    /// When the addresses stop being used, in Unix seconds: an hour after
    /// they were fetched, or 15 minutes before YouTube's `expire`.
    pub expires: i64,
    /// The YouTube clients (`c=`) the addresses came from, and the formats.
    pub clients: Vec<String>,
    pub formats: Vec<String>,
    /// Heights offered in an allowed codec, highest first.
    pub heights: Vec<u32>,
    pub all_heights: Vec<u32>,
    /// The most frames a second of each height in [heights], when above 30,
    /// for labels such as 1080p60.
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub frame_rates: BTreeMap<u32, u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lost: Option<Lost>,
    /// The picked streams, when mpv can open them directly; none for live
    /// streams and fragmented formats, which only ytdl_hook plays.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub streams: Option<Vec<Stream>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_agent: Option<String>,
}

/// The formats yt-dlp picked: `requested_formats`, or the answer itself
/// for a single format.
fn tracks(info: &Value) -> Vec<&Value> {
    match info.get("requested_formats").and_then(Value::as_array) {
        Some(list) if !list.is_empty() => list.iter().filter(|t| t.is_object()).collect(),
        _ if info.get("url").is_some_and(Value::is_string) => vec![info],
        _ => Vec::new(),
    }
}

fn query<'a>(url: &'a str, key: &str) -> Option<&'a str> {
    let query = url.split_once('?')?.1.split('#').next()?;
    query
        .split('&')
        .find_map(|pair| pair.strip_prefix(key)?.strip_prefix('='))
}

fn streams(info: &Value, tracks: &[&Value]) -> Option<Vec<Stream>> {
    if info.get("is_live") == Some(&Value::Bool(true))
        || info.get("live_status").and_then(Value::as_str) == Some("is_live")
        || tracks.is_empty()
    {
        return None;
    }
    tracks
        .iter()
        .map(|track| {
            let url = track.get("url").and_then(Value::as_str).unwrap_or("");
            let protocol = track.get("protocol").and_then(Value::as_str).unwrap_or("");
            let fragmented = track.get("fragments").is_some_and(|f| !f.is_null());
            if fragmented
                || !(protocol == "https" || protocol == "http")
                || !url.starts_with("http")
            {
                return None;
            }
            Some(Stream {
                url: url.to_owned(),
                size: track.get("filesize").and_then(Value::as_u64),
            })
        })
        .collect()
}

pub fn summary(info: &Value, ask: &Ask) -> Summary {
    let tracks = tracks(info);
    let limit = ask.fetched + 3600;
    let expire = tracks
        .first()
        .and_then(|t| t.get("url")?.as_str())
        .and_then(|url| query(url, "expire")?.parse::<i64>().ok());
    let mut clients: Vec<String> = Vec::new();
    for track in &tracks {
        let client = track
            .get("url")
            .and_then(Value::as_str)
            .and_then(|u| query(u, "c"))
            .unwrap_or("?")
            .to_owned();
        if !clients.contains(&client) {
            clients.push(client);
        }
    }
    let formats = tracks
        .iter()
        .map(|t| {
            t.get("format_id")
                .map(|v| v.as_str().map_or_else(|| v.to_string(), str::to_owned))
                .unwrap_or_else(|| "null".into())
        })
        .collect();
    let mut by_height: Vec<(u32, Vec<Codec>)> = Vec::new();
    let mut all = Vec::new();
    for format in info
        .get("formats")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let Some(height) = format
            .get("height")
            .and_then(Value::as_u64)
            .filter(|h| *h > 0)
            .map(|h| h as u32)
        else {
            continue;
        };
        let Some(codec) = format
            .get("vcodec")
            .and_then(Value::as_str)
            .and_then(Codec::of)
        else {
            continue;
        };
        if ask.cap > 0 && height > ask.cap {
            continue;
        }
        match by_height.iter_mut().find(|(h, _)| *h == height) {
            Some((_, codecs)) if !codecs.contains(&codec) => codecs.push(codec),
            Some(_) => {}
            None => by_height.push((height, vec![codec])),
        }
    }
    let allows = |codec: &Codec| !ask.disabled.contains(codec);
    let mut heights: Vec<u32> = Vec::new();
    let mut frame_rates: BTreeMap<u32, u32> = BTreeMap::new();
    for format in info
        .get("formats")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let height = format
            .get("height")
            .and_then(Value::as_u64)
            .filter(|h| *h > 0)
            .map(|h| h as u32);
        let codec = format
            .get("vcodec")
            .and_then(Value::as_str)
            .filter(|c| *c != "none");
        let (Some(height), Some(codec)) = (height, codec) else {
            continue;
        };
        if !all.contains(&height) {
            all.push(height);
        }
        if Codec::of(codec).is_none_or(|c| allows(&c)) {
            if !heights.contains(&height) {
                heights.push(height);
            }
            let fps = format
                .get("fps")
                .and_then(Value::as_f64)
                .filter(|f| f.is_finite() && *f > 30.5)
                .map(|f| f.round() as u32);
            if let Some(fps) = fps {
                let most = frame_rates.entry(height).or_insert(fps);
                *most = (*most).max(fps);
            }
        }
    }
    heights.sort_unstable_by(|a, b| b.cmp(a));
    all.sort_unstable_by(|a, b| b.cmp(a));
    let lost = (|| {
        let tallest = by_height.iter().map(|(h, _)| *h).max()?;
        let allowed: Vec<u32> = by_height
            .iter()
            .filter(|(_, c)| c.iter().any(allows))
            .map(|(h, _)| *h)
            .collect();
        if allowed.is_empty() || allowed.contains(&tallest) {
            return None;
        }
        let mut codecs = by_height.iter().find(|(h, _)| *h == tallest)?.1.clone();
        codecs.sort_by_key(|c| Codec::ALL.iter().position(|a| a == c));
        Some(Lost {
            height: tallest,
            codecs,
            playing: allowed.into_iter().max()?,
        })
    })();
    let user_agent = tracks
        .iter()
        .copied()
        .chain(std::iter::once(info))
        .find_map(|t| t.get("http_headers")?.get("User-Agent"))
        .map(|v| v.as_str().map_or_else(|| v.to_string(), str::to_owned));
    Summary {
        expires: expire.map_or(limit, |e| (e - 900).min(limit)),
        clients,
        formats,
        heights,
        all_heights: all,
        frame_rates,
        lost,
        streams: streams(info, &tracks),
        user_agent,
    }
}

/// An mpv EDL address playing [addresses] as one video, the way mpv's
/// ytdl_hook builds it.
pub fn edl(addresses: &[String]) -> String {
    let parts: Vec<String> = addresses
        .iter()
        .map(|a| format!("!new_stream;!no_clip;!no_chapters;%{}%{a}", a.len()))
        .collect();
    format!("edl://{}", parts.join(";"))
}

/// The [Summary] of yt-dlp's answer [info] for [ask], as JSON; null when the
/// answer does not parse. Free it with `lumtub_string_free`.
///
/// # Safety
/// Both must point to that many bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_resolved(
    info: *const u8,
    info_len: usize,
    ask: *const u8,
    ask_len: usize,
) -> *mut c_char {
    let ask: Ask =
        serde_json::from_str(unsafe { crate::taste::text(ask, ask_len) }).unwrap_or_default();
    match serde_json::from_str::<Value>(unsafe { crate::taste::text(info, info_len) }) {
        Ok(info) if info.is_object() => crate::taste::give_json(&summary(&info, &ask)),
        _ => std::ptr::null_mut(),
    }
}

/// [edl] of the JSON list of addresses [json]; null when it does not parse.
///
/// # Safety
/// [json] must point to [len] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_edl(json: *const u8, len: usize) -> *mut c_char {
    match serde_json::from_str::<Vec<String>>(unsafe { crate::taste::text(json, len) }) {
        Ok(list) if !list.is_empty() => crate::taste::give(edl(&list)),
        _ => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn info() -> Value {
        json!({
            "formats": [
                {"format_id": "137", "height": 1080, "vcodec": "avc1.640028"},
                {"format_id": "248", "height": 1080, "vcodec": "vp09.00.40.08"},
                {"format_id": "401", "height": 2160, "vcodec": "av01.0.12M.08"},
                {"format_id": "313", "height": 2160, "vcodec": "vp9"},
                {"format_id": "140", "vcodec": "none"},
                {"format_id": "sb0", "height": 90, "vcodec": "none"}
            ],
            "requested_formats": [
                {"format_id": "248", "url": "https://r1.googlevideo.com/videoplayback?expire=1900003600&c=WEB&itag=248", "protocol": "https", "filesize": 1000, "http_headers": {"User-Agent": "UA"}},
                {"format_id": "140", "url": "https://r1.googlevideo.com/videoplayback?expire=1900003600&c=WEB&itag=140", "protocol": "https"}
            ]
        })
    }

    #[test]
    fn frame_rates_label_heights_above_30() {
        let info = json!({"formats": [
            {"height": 1080, "vcodec": "avc1.640028", "fps": 30},
            {"height": 1080, "vcodec": "vp09.00.40.08", "fps": 60},
            {"height": 720, "vcodec": "avc1.4d401f", "fps": 59.94},
            {"height": 480, "vcodec": "avc1.4d401e", "fps": 25},
            {"height": 1440, "vcodec": "vp09.00.50.08", "fps": 50}
        ]});
        let s = summary(&info, &Ask::default());
        assert_eq!(
            s.frame_rates,
            BTreeMap::from([(720, 60), (1080, 60), (1440, 50)])
        );
        let json = serde_json::to_value(&s).unwrap();
        assert_eq!(
            json["frameRates"],
            json!({"720": 60, "1080": 60, "1440": 50})
        );
        // A disabled codec's frames do not count.
        let s = summary(
            &info,
            &Ask {
                disabled: vec![Codec::Vp9],
                ..Ask::default()
            },
        );
        assert_eq!(s.frame_rates, BTreeMap::from([(720, 60)]));
    }

    #[test]
    fn reads_heights_expiry_and_streams() {
        let s = summary(
            &info(),
            &Ask {
                fetched: 1_900_000_000,
                ..Ask::default()
            },
        );
        assert_eq!(s.heights, [2160, 1080]);
        assert_eq!(s.all_heights, [2160, 1080]);
        assert_eq!(s.expires, 1_900_002_700);
        assert_eq!(s.clients, ["WEB"]);
        assert_eq!(s.formats, ["248", "140"]);
        assert_eq!(s.user_agent.as_deref(), Some("UA"));
        assert_eq!(s.lost, None);
        let streams = s.streams.unwrap();
        assert_eq!(streams[0].size, Some(1000));
        assert_eq!(streams[1].size, None);
        // A far expiry is capped at an hour after fetching.
        let late = summary(
            &info(),
            &Ask {
                fetched: 1_800_000_000,
                ..Ask::default()
            },
        );
        assert_eq!(late.expires, 1_800_003_600);
    }

    #[test]
    fn says_what_disabled_codecs_cost() {
        let ask = Ask {
            disabled: vec![Codec::Av1, Codec::Vp9],
            fetched: 0,
            cap: 0,
        };
        let s = summary(&info(), &ask);
        assert_eq!(s.heights, [1080]);
        assert_eq!(
            s.lost,
            Some(Lost {
                height: 2160,
                codecs: vec![Codec::Av1, Codec::Vp9],
                playing: 1080
            })
        );
        assert_eq!(summary(&info(), &Ask { cap: 1080, ..ask }).lost, None);
    }

    #[test]
    fn leaves_live_and_fragmented_streams_to_ytdl_hook() {
        let mut live = info();
        live["live_status"] = json!("is_live");
        assert_eq!(summary(&live, &Ask::default()).streams, None);
        let mut fragmented = info();
        fragmented["requested_formats"][0]["fragments"] = json!([{"url": "x"}]);
        assert_eq!(summary(&fragmented, &Ask::default()).streams, None);
        let single = json!({"url": "https://a/b?c=TV", "protocol": "https", "format_id": 18});
        let s = summary(&single, &Ask::default());
        assert_eq!(s.formats, ["18"]);
        assert_eq!(s.clients, ["TV"]);
        assert_eq!(s.streams.unwrap().len(), 1);
        assert_eq!(summary(&json!({}), &Ask::default()).streams, None);
    }

    #[test]
    fn builds_edl_with_byte_lengths() {
        assert_eq!(
            edl(&["https://a/é".into(), "https://b".into()]),
            "edl://!new_stream;!no_clip;!no_chapters;%12%https://a/é;!new_stream;!no_clip;!no_chapters;%9%https://b"
        );
    }
}
