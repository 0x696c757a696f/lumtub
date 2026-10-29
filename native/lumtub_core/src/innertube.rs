//! Reading YouTube's own web responses (InnerTube). They decode to megabytes
//! of nested objects of which a few fields are used, so they are read here
//! and Dart gets only the result.

use serde::Serialize;
use serde_json::{Map, Value};
use std::os::raw::c_char;

use crate::filter::{title_language, Language};
use crate::taste::{give_json, text};

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

/// What one pass over a `/next` response finds: the related videos and the
/// first (depth first, as [find]) object under each of the renderers read.
#[derive(Default)]
struct Parts<'a> {
    related: Vec<Video>,
    primary: Option<&'a Map<String, Value>>,
    secondary: Option<&'a Map<String, Value>>,
    like: Option<&'a Map<String, Value>>,
}

impl<'a> Parts<'a> {
    fn of(data: &'a Value) -> Parts<'a> {
        let mut parts = Parts::default();
        parts.walk(data, true);
        parts
    }

    fn walk(&mut self, node: &'a Value, collect: bool) {
        match node {
            Value::Object(map) => {
                for (slot, key) in [(&mut self.primary, "videoPrimaryInfoRenderer"), (&mut self.secondary, "videoSecondaryInfoRenderer"), (&mut self.like, "likeCountEntity")] {
                    if slot.is_none()
                        && let Some(Value::Object(found)) = map.get(key)
                    {
                        *slot = Some(found);
                    }
                }
                let mut collect = collect;
                if collect {
                    let found = if let Some(Value::Object(c)) = map.get("compactVideoRenderer") {
                        Some(compact(c))
                    } else if let Some(l @ Value::Object(_)) = map.get("lockupViewModel") {
                        Some(lockup(l))
                    } else {
                        None
                    };
                    if let Some(found) = found {
                        collect = false;
                        if let Some(video) = found
                            && !self.related.iter().any(|v| v.id == video.id)
                        {
                            self.related.push(video);
                        }
                    }
                }
                if collect || self.wants_more() {
                    for value in map.values() {
                        self.walk(value, collect);
                    }
                }
            }
            Value::Array(list) if collect || self.wants_more() => {
                for value in list {
                    self.walk(value, collect);
                }
            }
            _ => {}
        }
    }

    fn wants_more(&self) -> bool {
        self.primary.is_none() || self.secondary.is_none() || self.like.is_none()
    }

    fn likes(&self) -> Option<i64> {
        match self.like?.get("likeCountIfIndifferentNumber")? {
            Value::Number(n) => n.as_f64().map(|n| n as i64),
            Value::String(s) => s.parse().ok(),
            _ => None,
        }
    }

    fn localized(&self) -> Option<Localized> {
        let title = text_of(self.primary.and_then(|p| p.get("title"))).trim().to_owned();
        if title.is_empty() {
            return None;
        }
        let description = text_of(self.secondary.and_then(|s| s.get("attributedDescription").filter(|v| !v.is_null()).or_else(|| s.get("description"))));
        Some(Localized { title, description, likes: self.likes() })
    }
}

/// The videos in a `/next` response, in YouTube's order: the older
/// `compactVideoRenderer` and the newer `lockupViewModel` shapes.
pub fn related(data: &Value) -> Vec<Video> {
    Parts::of(data).related
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
    Parts::of(data).likes()
}

/// The title and description of a `/next` response as YouTube shows them.
pub fn localized(data: &Value) -> Option<Localized> {
    Parts::of(data).localized()
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
    let parts = Parts::of(&data);
    let text = parts.localized();
    give_json(&Next { related: parts.related, text })
}

/// [code], a YouTube language code such as `zh-Hant` or `en-US`, as one of
/// explore's languages; [Language::Any] for one explore does not offer.
fn language_of_code(code: &str) -> Option<Language> {
    let base = code.split(['-', '_', '.']).next().unwrap_or("").to_ascii_lowercase();
    Some(match base.as_str() {
        "zh" | "yue" | "cmn" => Language::Zh,
        "ja" => Language::Ja,
        "ko" => Language::Ko,
        "en" => Language::En,
        "es" => Language::Es,
        "fr" => Language::Fr,
        "de" => Language::De,
        "pt" => Language::Pt,
        "ru" => Language::Ru,
        "ar" => Language::Ar,
        "hi" => Language::Hi,
        "th" => Language::Th,
        "vi" => Language::Vi,
        "it" => Language::It,
        "nl" => Language::Nl,
        "tr" => Language::Tr,
        "id" | "in" => Language::Id,
        "ms" => Language::Ms,
        "tl" | "fil" => Language::Tl,
        "pl" => Language::Pl,
        "uk" => Language::Uk,
        "cs" => Language::Cs,
        "ro" => Language::Ro,
        "hu" => Language::Hu,
        "el" => Language::El,
        "sv" => Language::Sv,
        "no" | "nb" | "nn" => Language::No,
        "da" => Language::Da,
        "fi" => Language::Fi,
        "he" | "iw" => Language::He,
        "fa" => Language::Fa,
        "ur" => Language::Ur,
        "bn" => Language::Bn,
        "ta" => Language::Ta,
        "te" => Language::Te,
        "" => return None,
        _ => Language::Any,
    })
}

/// The language a video is spoken in and its own title, from a `/player`
/// response. Listings show titles machine-translated into the listing's
/// language, so they cannot tell. In order: the original audio track, the
/// automatic captions (which are made in the spoken language), then the
/// script of the uploader's own title and description.
pub fn spoken_language(data: &Value) -> Option<(Option<Language>, String)> {
    let details = at(data, &["videoDetails"])?;
    let title = details.get("title").and_then(Value::as_str).unwrap_or_default().to_string();
    let tracks = at(data, &["streamingData", "adaptiveFormats"]).and_then(Value::as_array);
    let audio = tracks.into_iter().flatten().filter_map(|f| f.get("audioTrack")).find(|track| {
        let name = track.get("displayName").and_then(Value::as_str).unwrap_or_default().to_lowercase();
        name.contains("original")
    });
    let from_audio = audio.and_then(|track| track.get("id")).and_then(Value::as_str).and_then(language_of_code);
    let captions = at(data, &["captions", "playerCaptionsTracklistRenderer", "captionTracks"]).and_then(Value::as_array);
    let from_captions = captions
        .into_iter()
        .flatten()
        .find(|track| track.get("kind").and_then(Value::as_str) == Some("asr"))
        .and_then(|track| track.get("languageCode"))
        .and_then(Value::as_str)
        .and_then(language_of_code);
    let language = from_audio.or(from_captions).or_else(|| {
        let by_title = title_language(&title);
        let description: String = details.get("shortDescription").and_then(Value::as_str).unwrap_or_default().chars().take(500).collect();
        let by_description = title_language(&description);
        // A Latin title over a description in another script, such as an
        // English title for a Chinese video, goes by the description.
        let latin = |l: Language| matches!(l, Language::En | Language::Es | Language::Fr | Language::De | Language::Pt);
        match (by_title, by_description) {
            (Language::Any, Language::Any) => None,
            (Language::Any, other) => Some(other),
            (title, description) if latin(title) && !latin(description) && description != Language::Any => Some(description),
            (title, _) => Some(title),
        }
    });
    Some((language, title))
}

/// What [spoken_language] finds in a `/player` response, as JSON
/// `{language, title}`: `language` is explore's index, 0 when nothing
/// tells, and -1 for a language explore does not offer. Null when [body]
/// is not a player response.
///
/// # Safety
/// [body] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_spoken_language(body: *const u8, length: usize) -> *mut c_char {
    #[derive(Serialize)]
    struct Spoken {
        language: i64,
        title: String,
    }
    let Ok(data) = serde_json::from_str::<Value>(unsafe { text(body, length) }) else {
        return std::ptr::null_mut();
    };
    let Some((language, title)) = spoken_language(&data) else {
        return std::ptr::null_mut();
    };
    let language = match language {
        None => 0,
        Some(Language::Any) => -1,
        Some(other) => other as i64,
    };
    give_json(&Spoken { language, title })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn tells_the_spoken_language() {
        let asr = json!({
            "videoDetails": {"title": "How to cook rice", "shortDescription": ""},
            "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [
                {"languageCode": "en", "kind": "standard"},
                {"languageCode": "ja", "kind": "asr"}
            ]}}
        });
        assert_eq!(spoken_language(&asr), Some((Some(Language::Ja), "How to cook rice".into())));
        let original = json!({
            "videoDetails": {"title": "Voyage", "shortDescription": ""},
            "streamingData": {"adaptiveFormats": [
                {"audioTrack": {"id": "en.3", "displayName": "English"}},
                {"audioTrack": {"id": "fr.4", "displayName": "French original"}}
            ]},
            "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [{"languageCode": "en", "kind": "asr"}]}}
        });
        assert_eq!(spoken_language(&original).unwrap().0, Some(Language::Fr));
        let chinese = json!({"videoDetails": {"title": "My trip to Chengdu", "shortDescription": "这次去成都吃了很多好吃的"}});
        assert_eq!(spoken_language(&chinese).unwrap().0, Some(Language::Zh));
        let own = json!({"videoDetails": {"title": "成都旅行", "shortDescription": ""}});
        assert_eq!(spoken_language(&own).unwrap(), (Some(Language::Zh), "成都旅行".into()));
        let italian = json!({"videoDetails": {"title": "Ciao", "shortDescription": ""}, "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [{"languageCode": "it", "kind": "asr"}]}}});
        assert_eq!(spoken_language(&italian).unwrap().0, Some(Language::It));
        let swahili = json!({"videoDetails": {"title": "Habari", "shortDescription": ""}, "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [{"languageCode": "sw", "kind": "asr"}]}}});
        assert_eq!(spoken_language(&swahili).unwrap().0, Some(Language::Any));
        assert_eq!(spoken_language(&json!({"playabilityStatus": {}})), None);
    }

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
    fn takes_the_first_renderers_depth_first() {
        let data = json!({
            "a": [{"x": {"videoPrimaryInfoRenderer": {"title": {"simpleText": "first"}}}}, {"videoPrimaryInfoRenderer": {"title": {"simpleText": "second"}}}],
            "compactVideoRenderer": {"videoId": "v", "likeCountEntity": {"likeCountIfIndifferentNumber": 7}},
            "b": {"likeCountEntity": {"likeCountIfIndifferentNumber": 9}}
        });
        let parts = Parts::of(&data);
        assert_eq!(parts.localized().map(|l| l.title), Some("first".to_owned()));
        assert_eq!(parts.likes(), Some(7));
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
