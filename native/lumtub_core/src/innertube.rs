//! Reading YouTube's own web responses (InnerTube). They decode to megabytes
//! of nested objects of which a few fields are used, so they are read here
//! and Dart gets only the result.

use serde::Serialize;
use serde_json::{Map, Value};
use std::os::raw::c_char;

use crate::taste::{give_json, text};

/// The first object under [key] anywhere in [node], depth first.
pub(crate) fn find<'a>(node: &'a Value, key: &str) -> Option<&'a Map<String, Value>> {
    match node {
        Value::Object(map) => {
            if let Some(Value::Object(found)) = map.get(key) {
                return Some(found);
            }
            map.values().find_map(|value| find(value, key))
        }
        Value::Array(list) => list.iter().find_map(|value| find(value, key)),
        _ => None,
    }
}

/// The value at [path] of nested objects.
pub(crate) fn at<'a>(node: &'a Value, path: &[&str]) -> Option<&'a Value> {
    path.iter().try_fold(node, |current, key| current.as_object()?.get(*key))
}

/// Text from YouTube's `simpleText`, `runs` or `content` shapes, or an
/// accessibility label.
pub(crate) fn text_of(node: Option<&Value>) -> String {
    match node {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Object(map)) => {
            if let Some(Value::String(simple)) = map.get("simpleText").or_else(|| map.get("content")) {
                return simple.clone();
            }
            if let Some(Value::Array(runs)) = map.get("runs") {
                return runs
                    .iter()
                    .map(|run| match run.get("text") {
                        Some(Value::String(s)) => s.clone(),
                        Some(Value::Null) | None => String::new(),
                        Some(other) => other.to_string(),
                    })
                    .collect();
            }
            match map.get("accessibility").and_then(|a| at(a, &["accessibilityData", "label"])) {
                Some(Value::String(label)) => label.clone(),
                _ => String::new(),
            }
        }
        Some(Value::Array(list)) => list.iter().map(|v| text_of(Some(v))).collect::<Vec<_>>().join(" "),
        _ => String::new(),
    }
}

/// The first `UC…` channel id under [node].
pub(crate) fn browse_id(node: Option<&Value>) -> Option<String> {
    match node? {
        Value::Object(map) => {
            if let Some(Value::String(id)) = map.get("browseId")
                && id.starts_with("UC")
            {
                return Some(id.clone());
            }
            map.values().find_map(|value| browse_id(Some(value)))
        }
        Value::Array(list) => list.iter().find_map(|value| browse_id(Some(value))),
        _ => None,
    }
}

/// `1:02:03` or `4:05` as seconds.
pub(crate) fn seconds(text: &str) -> Option<u32> {
    let parts: Vec<&str> = text.trim().split(':').collect();
    let digits = |s: &str, max: usize| (!s.is_empty() && s.len() <= max && s.bytes().all(|b| b.is_ascii_digit())).then(|| s.parse::<u32>().ok()).flatten();
    let (hours, minutes, secs) = match parts.as_slice() {
        [m, s] => (0, digits(m, 2)?, *s),
        [h, m, s] => (digits(h, 9)?, digits(m, 2)?, *s),
        _ => return None,
    };
    if secs.len() != 2 {
        return None;
    }
    Some(hours * 3600 + minutes * 60 + digits(secs, 2)?)
}

fn contains_ignore_case(text: &str, words: &[&str]) -> bool {
    let lower = text.to_lowercase();
    words.iter().any(|word| lower.contains(word))
}

/// View counts such as `1,234 次观看`, `12万次观看`, `3.4亿`, `12萬次觀看` or
/// `1.2M views`.
pub(crate) fn count(text: &str) -> Option<u64> {
    if !contains_ignore_case(text, &["观看", "觀看", "views", "次"]) {
        return None;
    }
    let start = text.find(|c: char| c.is_ascii_digit() || c == '.' || c == ',')?;
    let rest = &text[start..];
    let end = rest.find(|c: char| !(c.is_ascii_digit() || c == '.' || c == ',')).unwrap_or(rest.len());
    let number: f64 = rest[..end].replace(',', "").parse().ok()?;
    let factor = match rest[end..].trim_start().chars().next().map(|c| c.to_ascii_uppercase()) {
        Some('万' | '萬') => 1e4,
        Some('亿' | '億') => 1e8,
        Some('K') => 1e3,
        Some('M') => 1e6,
        Some('B') => 1e9,
        _ => 1.0,
    };
    Some((number * factor).round() as u64)
}

/// A video as Dart's VideoItem takes it.
#[derive(Serialize, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Video {
    pub id: String,
    pub title: String,
    pub channel: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub channel_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub view_count: Option<u64>,
    pub live: bool,
}

fn video_id(node: &Map<String, Value>, key: &str) -> Option<String> {
    node.get(key).and_then(Value::as_str).filter(|id| id.chars().count() == 11).map(str::to_owned)
}

fn compact(node: &Map<String, Value>) -> Option<Video> {
    let id = video_id(node, "videoId")?;
    let byline = node.get("longBylineText").filter(|v| !v.is_null()).or_else(|| node.get("shortBylineText"));
    let badges = text_of(node.get("badges"));
    let watching = matches!(node.get("viewCountText"), Some(Value::Object(_))) && contains_ignore_case(&text_of(node.get("viewCountText")), &["正在观看", "正在觀看", "watching"]);
    Some(Video {
        id,
        title: text_of(node.get("title")),
        channel: text_of(byline),
        channel_id: browse_id(byline),
        duration: seconds(&text_of(node.get("lengthText"))),
        view_count: count(&text_of(node.get("viewCountText"))),
        live: badges.contains("直播") || badges.to_uppercase().contains("LIVE") || watching,
    })
}

fn lockup(value: &Value) -> Option<Video> {
    let node = value.as_object()?;
    let id = video_id(node, "contentId")?;
    if let Some(Value::String(kind)) = node.get("contentType")
        && kind != "LOCKUP_CONTENT_TYPE_VIDEO"
    {
        return None;
    }
    let metadata = at(value, &["metadata", "lockupMetadataViewModel"]);
    let title = text_of(metadata.and_then(|m| at(m, &["title"])));
    let mut parts = Vec::new();
    if let Some(Value::Array(rows)) = metadata.and_then(|m| at(m, &["metadata", "contentMetadataViewModel", "metadataRows"])) {
        for row in rows {
            if let Some(Value::Array(list)) = at(row, &["metadataParts"]) {
                parts.extend(list.iter().map(|part| text_of(at(part, &["text"]))));
            }
        }
    }
    parts.retain(|part| !part.is_empty());
    // The first row names the channel; the next holds views and age.
    let channel = parts.first().cloned().unwrap_or_default();
    let view_count = parts.iter().skip(1).find_map(|part| count(part));
    let mut badges = Vec::new();
    fn badges_in(node: &Value, out: &mut Vec<String>) {
        match node {
            Value::Object(map) => {
                if let Some(badge @ Value::Object(_)) = map.get("thumbnailBadgeViewModel") {
                    out.push(text_of(badge.get("text")));
                }
                map.values().for_each(|v| badges_in(v, out));
            }
            Value::Array(list) => list.iter().for_each(|v| badges_in(v, out)),
            _ => {}
        }
    }
    if let Some(image) = node.get("contentImage") {
        badges_in(image, &mut badges);
    }
    Some(Video {
        id,
        title,
        channel,
        channel_id: browse_id(metadata.and_then(|m| at(m, &["image"]))),
        duration: badges.iter().find_map(|badge| seconds(badge)),
        view_count,
        live: badges.iter().any(|b| b.contains("直播") || b.to_uppercase() == "LIVE"),
    })
}

/// The videos in a `/next` response, in YouTube's order: the older
/// `compactVideoRenderer` and the newer `lockupViewModel` shapes.
pub fn related(data: &Value) -> Vec<Video> {
    fn walk(node: &Value, out: &mut Vec<Video>) {
        match node {
            Value::Object(map) => {
                let found = if let Some(Value::Object(c)) = map.get("compactVideoRenderer") {
                    Some(compact(c))
                } else if let Some(l @ Value::Object(_)) = map.get("lockupViewModel") {
                    Some(lockup(l))
                } else {
                    None
                };
                match found {
                    Some(Some(video)) => {
                        if !out.iter().any(|v| v.id == video.id) {
                            out.push(video);
                        }
                    }
                    Some(None) => {}
                    None => map.values().for_each(|v| walk(v, out)),
                }
            }
            Value::Array(list) => list.iter().for_each(|v| walk(v, out)),
            _ => {}
        }
    }
    let mut out = Vec::new();
    walk(data, &mut out);
    out
}

/// A video's title and description in the interface language, and its likes.
#[derive(Serialize, Debug, PartialEq)]
pub struct Localized {
    pub title: String,
    pub description: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub likes: Option<i64>,
}

/// The like count of a `/next` response: the like button's own number.
pub fn likes(data: &Value) -> Option<i64> {
    match find(data, "likeCountEntity")?.get("likeCountIfIndifferentNumber")? {
        Value::Number(n) => n.as_f64().map(|n| n as i64),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

/// The title and description of a `/next` response as YouTube shows them.
pub fn localized(data: &Value) -> Option<Localized> {
    let primary = find(data, "videoPrimaryInfoRenderer");
    let secondary = find(data, "videoSecondaryInfoRenderer");
    let title = text_of(primary.and_then(|p| p.get("title"))).trim().to_owned();
    if title.is_empty() {
        return None;
    }
    let description = text_of(secondary.and_then(|s| s.get("attributedDescription").filter(|v| !v.is_null()).or_else(|| s.get("description"))));
    Some(Localized { title, description, likes: likes(data) })
}

/// What Lumtub reads from a `/next` response, as JSON `{related, text}`;
/// null when [body] is not JSON.
///
/// # Safety
/// [body] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_youtube_next(body: *const u8, length: usize) -> *mut c_char {
    #[derive(Serialize)]
    struct Next {
        related: Vec<Video>,
        text: Option<Localized>,
    }
    let Ok(data) = serde_json::from_str::<Value>(unsafe { text(body, length) }) else {
        return std::ptr::null_mut();
    };
    give_json(&Next { related: related(&data), text: localized(&data) })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn reads_text_shapes() {
        assert_eq!(text_of(Some(&json!({"simpleText": "a"}))), "a");
        assert_eq!(text_of(Some(&json!({"runs": [{"text": "a"}, {"text": "b"}, {}]}))), "ab");
        assert_eq!(text_of(Some(&json!({"accessibility": {"accessibilityData": {"label": "c"}}}))), "c");
        assert_eq!(text_of(Some(&json!([{"simpleText": "a"}, "b"]))), "a b");
        assert_eq!(text_of(None), "");
    }

    #[test]
    fn reads_durations_and_counts() {
        assert_eq!(seconds("4:05"), Some(245));
        assert_eq!(seconds(" 1:02:03 "), Some(3723));
        assert_eq!(seconds("4:5"), None);
        assert_eq!(seconds("123:45"), None);
        assert_eq!(seconds("直播"), None);
        assert_eq!(count("1,234 次观看"), Some(1234));
        assert_eq!(count("12万次观看"), Some(120_000));
        assert_eq!(count("3.4亿次"), Some(340_000_000));
        assert_eq!(count("12萬次觀看"), Some(120_000));
        assert_eq!(count("1.2M views"), Some(1_200_000));
        assert_eq!(count("7k Views"), Some(7000));
        assert_eq!(count("3 years ago"), None);
    }

    #[test]
    fn reads_both_related_shapes_in_order() {
        let data = json!({"contents": [
            {"compactVideoRenderer": {
                "videoId": "aaaaaaaaaaa", "title": {"simpleText": "Old"},
                "longBylineText": {"runs": [{"text": "Chan", "navigationEndpoint": {"browseEndpoint": {"browseId": "UCabc"}}}]},
                "lengthText": {"simpleText": "10:00"}, "viewCountText": {"simpleText": "1,000 views"}
            }},
            {"lockupViewModel": {
                "contentId": "bbbbbbbbbbb", "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                "contentImage": {"thumbnailViewModel": {"overlays": [{"thumbnailBadgeViewModel": {"text": "1:02:03"}}]}},
                "metadata": {"lockupMetadataViewModel": {
                    "title": {"content": "New"},
                    "image": {"decoratedAvatarViewModel": {"rendererContext": {"commandContext": {"onTap": {"innertubeCommand": {"browseEndpoint": {"browseId": "UCdef"}}}}}}},
                    "metadata": {"contentMetadataViewModel": {"metadataRows": [
                        {"metadataParts": [{"text": {"content": "Other"}}]},
                        {"metadataParts": [{"text": {"content": "12万次观看"}}, {"text": {"content": "3天前"}}]}
                    ]}}
                }}
            }},
            {"lockupViewModel": {"contentId": "ccccccccccc", "contentType": "LOCKUP_CONTENT_TYPE_PLAYLIST"}},
            {"compactVideoRenderer": {"videoId": "aaaaaaaaaaa", "title": {"simpleText": "Again"}}},
            {"compactVideoRenderer": {"videoId": "short", "title": {"simpleText": "Bad id"}}},
            {"compactVideoRenderer": {"videoId": "ddddddddddd", "title": {"simpleText": "Live"}, "viewCountText": {"runs": [{"text": "123"}, {"text": " watching"}]}}}
        ]});
        let videos = related(&data);
        assert_eq!(videos.iter().map(|v| v.id.as_str()).collect::<Vec<_>>(), ["aaaaaaaaaaa", "bbbbbbbbbbb", "ddddddddddd"]);
        assert_eq!(videos[0], Video { id: "aaaaaaaaaaa".into(), title: "Old".into(), channel: "Chan".into(), channel_id: Some("UCabc".into()), duration: Some(600), view_count: Some(1000), live: false });
        assert_eq!(videos[1], Video { id: "bbbbbbbbbbb".into(), title: "New".into(), channel: "Other".into(), channel_id: Some("UCdef".into()), duration: Some(3723), view_count: Some(120_000), live: false });
        assert!(videos[2].live);
    }

    #[test]
    fn reads_the_localized_text_and_likes() {
        let data = json!({"contents": {
            "videoPrimaryInfoRenderer": {"title": {"runs": [{"text": " 标题 "}]}},
            "videoSecondaryInfoRenderer": {"attributedDescription": {"content": "说明"}},
        }, "frameworkUpdates": {"likeCountEntity": {"likeCountIfIndifferentNumber": "42"}}});
        assert_eq!(localized(&data), Some(Localized { title: "标题".into(), description: "说明".into(), likes: Some(42) }));
        assert_eq!(localized(&json!({})), None);
    }
}
