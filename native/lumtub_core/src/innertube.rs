//! Reading YouTube's own web responses (InnerTube). They decode to megabytes
//! of nested objects of which a few fields are used, so they are read here
//! and Dart gets only the result.

use serde::Serialize;
use serde_json::{Map, Value};
use std::os::raw::c_char;

use crate::filter::{Language, title_language};
use crate::taste::{give_json, text};

/// The value at [path] of nested objects.
pub(crate) fn at<'a>(node: &'a Value, path: &[&str]) -> Option<&'a Value> {
    path.iter()
        .try_fold(node, |current, key| current.as_object()?.get(*key))
}

/// Text from YouTube's `simpleText`, `runs` or `content` shapes, or an
/// accessibility label.
pub(crate) fn text_of(node: Option<&Value>) -> String {
    match node {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Object(map)) => {
            if let Some(Value::String(simple)) =
                map.get("simpleText").or_else(|| map.get("content"))
            {
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
            match map
                .get("accessibility")
                .and_then(|a| at(a, &["accessibilityData", "label"]))
            {
                Some(Value::String(label)) => label.clone(),
                _ => String::new(),
            }
        }
        Some(Value::Array(list)) => list
            .iter()
            .map(|v| text_of(Some(v)))
            .collect::<Vec<_>>()
            .join(" "),
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
    let digits = |s: &str, max: usize| {
        (!s.is_empty() && s.len() <= max && s.bytes().all(|b| b.is_ascii_digit()))
            .then(|| s.parse::<u32>().ok())
            .flatten()
    };
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
    let end = rest
        .find(|c: char| !(c.is_ascii_digit() || c == '.' || c == ','))
        .unwrap_or(rest.len());
    let number: f64 = rest[..end].replace(',', "").parse().ok()?;
    let factor = match rest[end..]
        .trim_start()
        .chars()
        .next()
        .map(|c| c.to_ascii_uppercase())
    {
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
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub members_only: bool,
    /// How long ago it was published, as YouTube wrote it in the language
    /// asked for ("3 days ago").
    #[serde(skip_serializing_if = "Option::is_none")]
    pub age: Option<String>,
}

/// Whether a listed video carries YouTube's members-only badge, whose style
/// is `BADGE_STYLE_TYPE_MEMBERS_ONLY` (or `BADGE_MEMBERS_ONLY` in the newer
/// view models) whatever the interface language says on it.
pub(crate) fn members_only(node: &Value) -> bool {
    match node {
        Value::String(text) => text.contains("MEMBERS_ONLY"),
        Value::Object(map) => members_only_in(map),
        Value::Array(list) => list.iter().any(members_only),
        _ => false,
    }
}

/// [members_only] for an object, skipping what the uploader writes.
fn members_only_in(map: &Map<String, Value>) -> bool {
    map.iter().any(|(key, value)| match key.as_str() {
        "title"
        | "headline"
        | "descriptionSnippet"
        | "detailedMetadataSnippets"
        | "navigationEndpoint" => false,
        _ => members_only(value),
    })
}

fn video_id(node: &Map<String, Value>, key: &str) -> Option<String> {
    node.get(key)
        .and_then(Value::as_str)
        .filter(|id| id.chars().count() == 11)
        .map(str::to_owned)
}

fn compact(node: &Map<String, Value>) -> Option<Video> {
    let id = video_id(node, "videoId")?;
    let byline = node
        .get("longBylineText")
        .filter(|v| !v.is_null())
        .or_else(|| node.get("shortBylineText"));
    let badges = text_of(node.get("badges"));
    let watching = matches!(node.get("viewCountText"), Some(Value::Object(_)))
        && contains_ignore_case(
            &text_of(node.get("viewCountText")),
            &["正在观看", "正在觀看", "watching"],
        );
    Some(Video {
        id,
        title: text_of(node.get("title")),
        channel: text_of(byline),
        channel_id: browse_id(byline),
        duration: seconds(&text_of(node.get("lengthText"))),
        view_count: count(&text_of(node.get("viewCountText"))),
        live: badges.contains("直播") || badges.to_uppercase().contains("LIVE") || watching,
        members_only: members_only_in(node),
        age: Some(text_of(node.get("publishedTimeText"))).filter(|t| !t.is_empty()),
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
    if let Some(Value::Array(rows)) =
        metadata.and_then(|m| at(m, &["metadata", "contentMetadataViewModel", "metadataRows"]))
    {
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
    // After the views comes the age, which holds no count of its own.
    let age = parts
        .iter()
        .skip(1)
        .skip_while(|part| count(part).is_none())
        .skip(1)
        .find(|part| count(part).is_none())
        .cloned();
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
        live: badges
            .iter()
            .any(|b| b.contains("直播") || b.to_uppercase() == "LIVE"),
        members_only: members_only(value),
        age,
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
                for (slot, key) in [
                    (&mut self.primary, "videoPrimaryInfoRenderer"),
                    (&mut self.secondary, "videoSecondaryInfoRenderer"),
                    (&mut self.like, "likeCountEntity"),
                ] {
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
        let title = text_of(self.primary.and_then(|p| p.get("title")))
            .trim()
            .to_owned();
        if title.is_empty() {
            return None;
        }
        let description = text_of(self.secondary.and_then(|s| {
            s.get("attributedDescription")
                .filter(|v| !v.is_null())
                .or_else(|| s.get("description"))
        }));
        Some(Localized {
            title,
            description,
            likes: self.likes(),
        })
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
    give_json(&Next {
        related: parts.related,
        text,
    })
}

/// [code], a YouTube language code such as `zh-Hant` or `en-US`, as one of
/// explore's languages; [Language::Any] for one explore does not offer.
fn language_of_code(code: &str) -> Option<Language> {
    let base = code
        .split(['-', '_', '.'])
        .next()
        .unwrap_or("")
        .to_ascii_lowercase();
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
        "af" => Language::Af,
        "am" => Language::Am,
        "az" => Language::Az,
        "be" => Language::Be,
        "bg" => Language::Bg,
        "eo" => Language::Eo,
        "et" => Language::Et,
        "eu" => Language::Eu,
        "gl" => Language::Gl,
        "gu" => Language::Gu,
        "hy" => Language::Hy,
        "is" => Language::Is,
        "jv" => Language::Jv,
        "ka" => Language::Ka,
        "km" => Language::Km,
        "kn" => Language::Kn,
        "la" => Language::La,
        "lo" => Language::Lo,
        "lt" => Language::Lt,
        "lv" => Language::Lv,
        "mk" => Language::Mk,
        "ml" => Language::Ml,
        "mn" => Language::Mn,
        "mr" => Language::Mr,
        "my" => Language::My,
        "ne" => Language::Ne,
        "pa" => Language::Pa,
        "si" => Language::Si,
        "sk" => Language::Sk,
        "sq" => Language::Sq,
        "su" => Language::Su,
        "sw" => Language::Sw,
        "ti" => Language::Ti,
        "tk" => Language::Tk,
        "uz" => Language::Uz,
        "" => return None,
        _ => Language::Any,
    })
}

/// What a `/player` response tells of the language a video is spoken in.
#[derive(Debug, PartialEq, Eq)]
pub struct Spoken {
    /// None when nothing tells.
    pub language: Option<Language>,
    /// The uploader's own title.
    pub title: String,
    /// What told: "audio", "captions", "text" or "none".
    pub source: &'static str,
    /// Whether YouTube would play the video to this client; an answer it
    /// would not play, such as one asking to sign in, has no captions.
    pub playable: bool,
}

/// The language a video is spoken in and its own title, from a `/player`
/// response. Listings show titles machine-translated into the listing's
/// language, so they cannot tell. In order: the original audio track, the
/// automatic captions (which are made in the spoken language), then the
/// uploader's own title and description.
pub fn spoken_language(data: &Value) -> Option<Spoken> {
    let details = at(data, &["videoDetails"])?;
    let title = details
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let playable = at(data, &["playabilityStatus", "status"])
        .and_then(Value::as_str)
        .is_none_or(|status| status == "OK");
    let tracks = at(data, &["streamingData", "adaptiveFormats"]).and_then(Value::as_array);
    if let Some(language) = tracks
        .and_then(|formats| original_audio(formats))
        .and_then(language_of_code)
    {
        return Some(Spoken {
            language: Some(language),
            title,
            source: "audio",
            playable,
        });
    }
    let captions = at(
        data,
        &[
            "captions",
            "playerCaptionsTracklistRenderer",
            "captionTracks",
        ],
    )
    .and_then(Value::as_array);
    let from_captions = captions
        .into_iter()
        .flatten()
        .find(|track| track.get("kind").and_then(Value::as_str) == Some("asr"))
        .and_then(|track| track.get("languageCode"))
        .and_then(Value::as_str)
        .and_then(language_of_code);
    if let Some(language) = from_captions {
        return Some(Spoken {
            language: Some(language),
            title,
            source: "captions",
            playable,
        });
    }
    let description: String = details
        .get("shortDescription")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .chars()
        .take(500)
        .collect();
    let by_title = title_language(&title);
    let by_description = title_language(&description);
    let latin = |l: Language| {
        matches!(
            l,
            Language::En
                | Language::Es
                | Language::Fr
                | Language::De
                | Language::Pt
                | Language::It
                | Language::Nl
                | Language::Tr
                | Language::Id
                | Language::Tl
                | Language::Pl
                | Language::Cs
                | Language::Ro
                | Language::Hu
                | Language::Sv
                | Language::No
                | Language::Da
                | Language::Fi
                | Language::Af
                | Language::Az
                | Language::Eo
                | Language::Et
                | Language::Eu
                | Language::Gl
                | Language::Is
                | Language::Jv
                | Language::La
                | Language::Lt
                | Language::Lv
                | Language::Sk
                | Language::Sq
                | Language::Su
                | Language::Sw
                | Language::Tk
                | Language::Uz
        )
    };
    let language = match (by_title, by_description) {
        (Language::Any, Language::Any) => None,
        (Language::Any, other) => Some(other),
        // A Latin title over a description in another script, such as an
        // English title for a Chinese video, goes by the description.
        (title, description)
            if latin(title) && !latin(description) && description != Language::Any =>
        {
            Some(description)
        }
        // Both Latin: the two together give the most text to go by.
        (title_says, description_says) if latin(title_says) && latin(description_says) => {
            Some(title_language(&format!("{title}\n{description}")))
        }
        (title, _) => Some(title),
    };
    let source = if language.is_some() { "text" } else { "none" };
    Some(Spoken {
        language,
        title,
        source,
        playable,
    })
}

/// The language code of the original audio track among [formats], when
/// the video has tracks in several languages: the one whose `xtags` say
/// `acont=original`, else the one whose name says so, else the only
/// language there is. Names are in the language asked in, so "original"
/// is looked for in a few; a default track is not taken for the original,
/// as YouTube makes a dub in the viewer's language the default.
fn original_audio(formats: &[Value]) -> Option<&str> {
    const ORIGINAL: [&str; 16] = [
        "original",
        "オリジナル",
        "原声",
        "原聲",
        "原始",
        "원본",
        "оригинал",
        "orijinal",
        "oryginał",
        "asli",
        "gốc",
        "ต้นฉบับ",
        "मूल",
        "أصلي",
        "מקורי",
        "πρωτότυπ",
    ];
    let tracks: Vec<(&str, &Value, &Value)> = formats
        .iter()
        .filter_map(|format| {
            let track = format.get("audioTrack")?;
            Some((track.get("id")?.as_str()?.split('.').next()?, track, format))
        })
        .filter(|(code, _, _)| !code.is_empty())
        .collect();
    let tagged = tracks.iter().find(|(_, _, format)| {
        format
            .get("xtags")
            .and_then(Value::as_str)
            .and_then(audio_content)
            .as_deref()
            == Some("original")
    });
    let named = || {
        tracks.iter().find(|(_, track, _)| {
            let name = track
                .get("displayName")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_lowercase();
            !name.contains("descriptive") && ORIGINAL.iter().any(|word| name.contains(word))
        })
    };
    if let Some((code, _, _)) = tagged.or_else(named) {
        return Some(code);
    }
    let first = tracks.first()?.0;
    tracks
        .iter()
        .all(|(code, _, _)| *code == first)
        .then_some(first)
}

/// The `acont` of a format's `xtags`: original, dubbed, dubbed-auto or
/// descriptive. They come as `key=value:key=value` text, or as base64 of
/// a protobuf list of key and value strings.
pub(crate) fn audio_content(xtags: &str) -> Option<String> {
    if let Some(value) = xtags
        .split(':')
        .find_map(|pair| pair.strip_prefix("acont="))
    {
        return Some(value.to_string());
    }
    let bytes = base64_any(xtags)?;
    let at = bytes.windows(5).position(|w| w == b"acont")? + 5;
    let rest = bytes.get(at..)?;
    if rest.first() != Some(&0x12) {
        return None;
    }
    let length = *rest.get(1)? as usize;
    String::from_utf8(rest.get(2..2 + length)?.to_vec()).ok()
}

/// [text] decoded from base64, standard or URL-safe, padded or not.
fn base64_any(text: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(text.len() * 3 / 4);
    let (mut buffer, mut bits) = (0u32, 0u32);
    for c in text.trim_end_matches('=').bytes() {
        let value = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' | b'-' => 62,
            b'/' | b'_' => 63,
            _ => return None,
        };
        buffer = (buffer << 6) | value as u32;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buffer >> bits) as u8);
            buffer &= (1 << bits) - 1;
        }
    }
    Some(out)
}

/// What [spoken_language] finds in a `/player` response, as JSON
/// `{language, title, source, playable}`: `language` is explore's index, 0
/// when nothing tells, and -1 for a language explore does not offer. Null
/// when [body] is not a player response.
///
/// # Safety
/// [body] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_spoken_language(body: *const u8, length: usize) -> *mut c_char {
    #[derive(Serialize)]
    struct Out {
        language: i64,
        title: String,
        source: &'static str,
        playable: bool,
    }
    let Ok(data) = serde_json::from_str::<Value>(unsafe { text(body, length) }) else {
        return std::ptr::null_mut();
    };
    let Some(spoken) = spoken_language(&data) else {
        return std::ptr::null_mut();
    };
    let language = match spoken.language {
        None => 0,
        Some(Language::Any) => -1,
        Some(other) => other as i64,
    };
    give_json(&Out {
        language,
        title: spoken.title,
        source: spoken.source,
        playable: spoken.playable,
    })
}

/// Whether YouTube labels a video as made with AI, from its `/next`
/// answer: a badge under the player in `videoPrimaryInfoRenderer`. The
/// "How this content was made" section alone is not enough, as dubbed
/// videos have it too. None when the answer has no primary info to tell.
pub fn ai_label(data: &Value) -> Option<bool> {
    let contents = at(
        data,
        &[
            "contents",
            "twoColumnWatchNextResults",
            "results",
            "results",
            "contents",
        ],
    )?
    .as_array()?;
    let primary = contents
        .iter()
        .find_map(|c| c.get("videoPrimaryInfoRenderer"))?;
    let badges = primary.get("badges").and_then(Value::as_array);
    Some(badges.is_some_and(|badges| {
        badges
            .iter()
            .filter_map(|b| b.get("metadataBadgeRenderer"))
            .any(|badge| {
                let style = badge
                    .get("style")
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                let icon = at(badge, &["icon", "iconType"])
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                let words = format!(
                    "{} {} {}",
                    text_of(badge.get("label")),
                    text_of(badge.get("tooltip")),
                    at(badge, &["accessibilityData", "label"])
                        .and_then(Value::as_str)
                        .unwrap_or_default()
                )
                .to_lowercase();
                (style.contains("SIMPLE") && icon.contains("INFO"))
                    || words.contains("made with ai")
                    || words.contains("synthetic")
                    || words.starts_with("ai:")
            })
    }))
}

/// `{"ai": true | false | null}` for a `/next` answer; see [`ai_label`].
///
/// # Safety
/// `body` must point to `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_ai_label(body: *const u8, length: usize) -> *mut c_char {
    #[derive(Serialize)]
    struct Label {
        ai: Option<bool>,
    }
    let ai = serde_json::from_str::<Value>(unsafe { text(body, length) })
        .ok()
        .and_then(|data| ai_label(&data));
    give_json(&Label { ai })
}

/// The channels of KillSlop's list of AI channels (CC BY-SA 4.0,
/// https://killslop.app): channel ids and lower-case @handles. Entries
/// with a score above zero are left out; they read as disputed.
pub fn ai_channels(data: &Value) -> Vec<String> {
    let Some(channels) = data.get("channels").and_then(Value::as_array) else {
        return Vec::new();
    };
    channels
        .iter()
        .filter(|c| c.get("score").and_then(Value::as_f64).unwrap_or(0.0) <= 0.0)
        .filter_map(|c| c.get("id").and_then(Value::as_str))
        .map(|id| {
            if id.starts_with('@') {
                id.to_lowercase()
            } else {
                id.to_string()
            }
        })
        .filter(|id| id.starts_with("UC") || id.starts_with('@'))
        .collect()
}

/// The channel ids of an AiSList channel id list: one id per line,
/// comments starting with `!`.
pub fn listed_channel_ids(list: &str) -> Vec<String> {
    list.lines()
        .map(str::trim)
        .filter(|line| {
            line.len() == 24
                && line.starts_with("UC")
                && line
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
        })
        .map(str::to_string)
        .collect()
}

/// A JSON array of [`ai_channels`] for KillSlop's JSON list, or of
/// [`listed_channel_ids`] for a plain id list.
///
/// # Safety
/// `body` must point to `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_ai_channels(body: *const u8, length: usize) -> *mut c_char {
    let body = unsafe { text(body, length) };
    let channels = match serde_json::from_str::<Value>(body) {
        Ok(data) => ai_channels(&data),
        Err(_) => listed_channel_ids(body),
    };
    give_json(&channels)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn tells_the_ai_label() {
        fn next(badges: Value) -> Value {
            json!({"contents": {"twoColumnWatchNextResults": {"results": {"results": {"contents": [
                {"videoPrimaryInfoRenderer": {"title": {"runs": [{"text": "A"}]}, "badges": badges}}
            ]}}}}})
        }
        let ai = next(
            json!([{"metadataBadgeRenderer": {"style": "BADGE_STYLE_TYPE_SIMPLE", "icon": {"iconType": "INFO"}, "label": "AI"}}]),
        );
        assert_eq!(ai_label(&ai), Some(true));
        let worded = next(
            json!([{"metadataBadgeRenderer": {"style": "BADGE_STYLE_TYPE_COLLECTION", "accessibilityData": {"label": "AI: Content was made with AI"}}}]),
        );
        assert_eq!(ai_label(&worded), Some(true));
        let plain = next(
            json!([{"metadataBadgeRenderer": {"style": "BADGE_STYLE_TYPE_SIMPLE", "label": "4K"}}]),
        );
        assert_eq!(ai_label(&plain), Some(false));
        let none = json!({"contents": {"twoColumnWatchNextResults": {"results": {"results": {"contents": [{"videoPrimaryInfoRenderer": {}}]}}}}});
        assert_eq!(ai_label(&none), Some(false));
        assert_eq!(ai_label(&json!({"responseContext": {}})), None);
    }

    #[test]
    fn reads_the_ai_channel_list() {
        let list = json!({"license": "CC-BY-SA-4.0", "channels": [
            {"id": "UCs8kQREN6lwSKNgGUF9LYsA", "score": 0},
            {"id": "@SeaPop", "score": 0},
            {"id": "@wsj", "score": 1},
            {"id": "nonsense"}
        ]});
        assert_eq!(
            ai_channels(&list),
            vec![
                "UCs8kQREN6lwSKNgGUF9LYsA".to_string(),
                "@seapop".to_string()
            ]
        );
    }

    #[test]
    fn reads_a_channel_id_list() {
        let list = "! AiSList blocklist by YouTube channel ID\n! Channels: 2\nUC---VSS6clgbT9mXRPqzzZA\r\nUC--1M2MGDAWI1EBcEzWbKJQ\n\nnot an id\nUC--1M2MGDAWI1EBcEzWbKJ\n";
        assert_eq!(
            listed_channel_ids(list),
            vec![
                "UC---VSS6clgbT9mXRPqzzZA".to_string(),
                "UC--1M2MGDAWI1EBcEzWbKJQ".to_string()
            ]
        );
    }

    #[test]
    fn tells_the_spoken_language() {
        let asr = json!({
            "videoDetails": {"title": "How to cook rice", "shortDescription": ""},
            "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [
                {"languageCode": "en", "kind": "standard"},
                {"languageCode": "ja", "kind": "asr"}
            ]}}
        });
        assert_eq!(
            spoken_language(&asr),
            Some(Spoken {
                language: Some(Language::Ja),
                title: "How to cook rice".into(),
                source: "captions",
                playable: true
            })
        );
        let original = json!({
            "videoDetails": {"title": "Voyage", "shortDescription": ""},
            "streamingData": {"adaptiveFormats": [
                {"audioTrack": {"id": "en.3", "displayName": "English"}},
                {"audioTrack": {"id": "fr.4", "displayName": "French original"}}
            ]},
            "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [{"languageCode": "en", "kind": "asr"}]}}
        });
        assert_eq!(
            spoken_language(&original).unwrap().language,
            Some(Language::Fr)
        );
        assert_eq!(spoken_language(&original).unwrap().source, "audio");
        // Asked in Japanese, with the Italian dub as the default track.
        let tagged = json!({
            "videoDetails": {"title": "Viaggio", "shortDescription": ""},
            "streamingData": {"adaptiveFormats": [
                {"audioTrack": {"id": "it.3", "displayName": "イタリア語", "audioIsDefault": true}, "xtags": "acont=dubbed-auto:lang=it"},
                {"audioTrack": {"id": "en.4", "displayName": "英語"}, "xtags": "acont=original:lang=en"}
            ]}
        });
        assert_eq!(
            spoken_language(&tagged).unwrap().language,
            Some(Language::En)
        );
        let protobuf = |pairs: &[(&str, &str)]| {
            let mut bytes = Vec::new();
            for (key, value) in pairs {
                let entry = [
                    &[0x0a, key.len() as u8][..],
                    key.as_bytes(),
                    &[0x12, value.len() as u8],
                    value.as_bytes(),
                ]
                .concat();
                bytes.extend([0x0a, entry.len() as u8]);
                bytes.extend(entry);
            }
            const ALPHABET: &[u8] =
                b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
            let mut text = String::new();
            for chunk in bytes.chunks(3) {
                let n = chunk
                    .iter()
                    .enumerate()
                    .fold(0u32, |n, (i, b)| n | (*b as u32) << (16 - 8 * i));
                for i in 0..=chunk.len() {
                    text.push(ALPHABET[(n >> (18 - 6 * i) & 63) as usize] as char);
                }
            }
            text
        };
        assert_eq!(
            audio_content(&protobuf(&[("acont", "original"), ("lang", "en")])).as_deref(),
            Some("original")
        );
        assert_eq!(
            audio_content(&protobuf(&[("lang", "it"), ("acont", "dubbed-auto")])).as_deref(),
            Some("dubbed-auto")
        );
        let named = json!({
            "videoDetails": {"title": "Viaggio", "shortDescription": ""},
            "streamingData": {"adaptiveFormats": [
                {"audioTrack": {"id": "it.3", "displayName": "意大利语", "audioIsDefault": true}},
                {"audioTrack": {"id": "en.4", "displayName": "英语（原声）"}}
            ]}
        });
        assert_eq!(
            spoken_language(&named).unwrap().language,
            Some(Language::En)
        );
        // A dub made the default, and nothing says which is the original:
        // the captions tell.
        let untold = json!({
            "videoDetails": {"title": "Viaggio", "shortDescription": ""},
            "streamingData": {"adaptiveFormats": [
                {"audioTrack": {"id": "it.3", "displayName": "Italiano", "audioIsDefault": true}},
                {"audioTrack": {"id": "en.4", "displayName": "Inglese"}}
            ]},
            "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [{"languageCode": "en", "kind": "asr"}]}}
        });
        assert_eq!(
            (
                spoken_language(&untold).unwrap().language,
                spoken_language(&untold).unwrap().source
            ),
            (Some(Language::En), "captions")
        );
        let chinese = json!({"videoDetails": {"title": "My trip to Chengdu", "shortDescription": "这次去成都吃了很多好吃的"}});
        assert_eq!(
            spoken_language(&chinese).unwrap().language,
            Some(Language::Zh)
        );
        let own = json!({"videoDetails": {"title": "成都旅行", "shortDescription": ""}});
        let own = spoken_language(&own).unwrap();
        assert_eq!(
            (own.language, own.title.as_str(), own.source),
            (Some(Language::Zh), "成都旅行", "text")
        );
        let italian = json!({"videoDetails": {"title": "Ciao", "shortDescription": ""}, "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [{"languageCode": "it", "kind": "asr"}]}}});
        assert_eq!(
            spoken_language(&italian).unwrap().language,
            Some(Language::It)
        );
        let zulu = json!({"videoDetails": {"title": "Sawubona", "shortDescription": ""}, "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [{"languageCode": "zu", "kind": "asr"}]}}});
        assert_eq!(
            spoken_language(&zulu).unwrap().language,
            Some(Language::Any)
        );
        assert_eq!(spoken_language(&json!({"playabilityStatus": {}})), None);
        let signed_out = json!({
            "playabilityStatus": {"status": "LOGIN_REQUIRED"},
            "videoDetails": {"title": "Giardinaggio", "shortDescription": "Oggi vi mostro come coltivare i pomodori sul balcone di casa, passo dopo passo."}
        });
        let signed_out = spoken_language(&signed_out).unwrap();
        assert_eq!(
            (signed_out.language, signed_out.source, signed_out.playable),
            (Some(Language::It), "text", false)
        );
    }

    #[test]
    fn reads_text_shapes() {
        assert_eq!(text_of(Some(&json!({"simpleText": "a"}))), "a");
        assert_eq!(
            text_of(Some(&json!({"runs": [{"text": "a"}, {"text": "b"}, {}]}))),
            "ab"
        );
        assert_eq!(
            text_of(Some(
                &json!({"accessibility": {"accessibilityData": {"label": "c"}}})
            )),
            "c"
        );
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
                "lengthText": {"simpleText": "10:00"}, "viewCountText": {"simpleText": "1,000 views"},
                "publishedTimeText": {"simpleText": "2 weeks ago"}
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
        assert_eq!(
            videos.iter().map(|v| v.id.as_str()).collect::<Vec<_>>(),
            ["aaaaaaaaaaa", "bbbbbbbbbbb", "ddddddddddd"]
        );
        assert_eq!(
            videos[0],
            Video {
                id: "aaaaaaaaaaa".into(),
                title: "Old".into(),
                channel: "Chan".into(),
                channel_id: Some("UCabc".into()),
                duration: Some(600),
                view_count: Some(1000),
                live: false,
                members_only: false,
                age: Some("2 weeks ago".into())
            }
        );
        assert_eq!(
            videos[1],
            Video {
                id: "bbbbbbbbbbb".into(),
                title: "New".into(),
                channel: "Other".into(),
                channel_id: Some("UCdef".into()),
                duration: Some(3723),
                view_count: Some(120_000),
                live: false,
                members_only: false,
                age: Some("3天前".into())
            }
        );
        assert!(videos[2].live);
        assert_eq!(videos[2].age, None);
        assert!(videos.iter().all(|v| !v.members_only));
    }

    #[test]
    fn marks_members_only_videos_by_badge_style() {
        let data = json!({"contents": [
            {"compactVideoRenderer": {
                "videoId": "aaaaaaaaaaa", "title": {"simpleText": "BADGE_STYLE_TYPE_MEMBERS_ONLY in a title"},
                "badges": [{"metadataBadgeRenderer": {"style": "BADGE_STYLE_TYPE_MEMBERS_ONLY", "label": "会员专享"}}]
            }},
            {"lockupViewModel": {
                "contentId": "bbbbbbbbbbb", "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                "metadata": {"lockupMetadataViewModel": {"title": {"content": "New"}, "metadata": {"contentMetadataViewModel": {"metadataRows": [
                    {"badges": [{"badgeViewModel": {"badgeText": "Members only", "badgeStyle": "BADGE_MEMBERS_ONLY"}}]}
                ]}}}}
            }},
            {"compactVideoRenderer": {"videoId": "ccccccccccc", "title": {"simpleText": "BADGE_STYLE_TYPE_MEMBERS_ONLY"}}}
        ]});
        let videos = related(&data);
        assert_eq!(
            videos.iter().map(|v| v.members_only).collect::<Vec<_>>(),
            [true, true, false]
        );
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
        assert_eq!(
            localized(&data),
            Some(Localized {
                title: "标题".into(),
                description: "说明".into(),
                likes: Some(42)
            })
        );
        assert_eq!(localized(&json!({})), None);
    }
}
