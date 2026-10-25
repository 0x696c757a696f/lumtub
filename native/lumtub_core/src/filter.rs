//! Tests that keep videos out of a list: the language a title reads as,
//! bait titles, Shorts, and the channels of the block lists.

use std::collections::HashSet;

use serde::Deserialize;

use crate::taste::text;

/// The languages a title can read as, in the order of Lumtub's
/// `ExploreLanguage`; [Language::Any] when the title gives nothing to go by.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum Language {
    Any,
    Zh,
    Ja,
    Ko,
    En,
    Es,
    Fr,
    De,
    Pt,
    Ru,
    Ar,
    Hi,
    Th,
    Vi,
}

const VIETNAMESE: &str = "ăâđêôơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ";

/// Small words that mark a Latin-script language.
const LATIN_WORDS: [(Language, &[&str]); 5] = [
    (
        Language::En,
        &[
            "the", "and", "of", "to", "in", "is", "for", "with", "how", "what", "why", "you", "my",
            "this", "your", "from", "on", "are", "i", "we", "best", "vs",
        ],
    ),
    (
        Language::Es,
        &[
            "el", "los", "las", "del", "y", "que", "con", "una", "por", "para", "es", "como", "mi",
            "más", "qué", "cómo", "muy", "pero", "su",
        ],
    ),
    (
        Language::Fr,
        &[
            "le", "les", "des", "et", "du", "est", "une", "pour", "dans", "avec", "sur", "pas",
            "qui", "mon", "ce", "je", "au", "aux", "c'est", "vous",
        ],
    ),
    (
        Language::De,
        &[
            "der", "die", "das", "und", "ist", "mit", "ein", "eine", "nicht", "für", "auf", "den",
            "ich", "wie", "was", "zu", "im", "von", "auch", "wir",
        ],
    ),
    (
        Language::Pt,
        &[
            "o", "os", "do", "da", "dos", "das", "e", "que", "com", "um", "uma", "para", "não",
            "é", "em", "no", "na", "mais", "você", "como",
        ],
    ),
];

/// Letters only one Latin-script language uses, lower case.
fn latin_letters(language: Language, lower: &str) -> bool {
    match language {
        Language::Es => lower.contains(['ñ', '¿', '¡']),
        Language::Fr => lower.contains(['œ', 'ç', 'è', 'ù', 'û']),
        Language::De => lower.contains(['ä', 'ö', 'ü', 'ß']),
        Language::Pt => lower.contains(['ã', 'õ']) || lower.contains("ção"),
        _ => false,
    }
}

fn any_in(title: &str, ranges: &[(u32, u32)]) -> bool {
    title.chars().any(|c| {
        ranges
            .iter()
            .any(|&(low, high)| (low..=high).contains(&(c as u32)))
    })
}

/// The language [title] is most likely in: by its script, and for Latin
/// letters by its small words. A Latin title with no small words at all,
/// such as "Minecraft Speedrun", is taken as English.
pub fn title_language(title: &str) -> Language {
    if any_in(title, &[(0x3040, 0x30FF)]) {
        return Language::Ja;
    }
    if any_in(title, &[(0xAC00, 0xD7AF), (0x1100, 0x11FF)]) {
        return Language::Ko;
    }
    if any_in(title, &[(0x4E00, 0x9FFF), (0x3400, 0x4DBF)]) {
        return Language::Zh;
    }
    if any_in(title, &[(0x0E00, 0x0E7F)]) {
        return Language::Th;
    }
    if any_in(title, &[(0x0900, 0x097F)]) {
        return Language::Hi;
    }
    if any_in(title, &[(0x0600, 0x06FF)]) {
        return Language::Ar;
    }
    if any_in(title, &[(0x0400, 0x04FF)]) {
        return Language::Ru;
    }
    let lower = title.to_lowercase();
    if lower.chars().any(|c| VIETNAMESE.contains(c)) {
        return Language::Vi;
    }
    if !title.chars().any(|c| c.is_ascii_alphabetic()) {
        return Language::Any;
    }
    let words: Vec<&str> = lower
        .split(|c: char| !(c.is_alphabetic() || c == '\''))
        .filter(|w| !w.is_empty())
        .collect();
    let mut best = Language::En;
    let mut best_score = 0.0;
    for (language, small) in LATIN_WORDS {
        let mut score = words.iter().filter(|w| small.contains(w)).count() as f64;
        if latin_letters(language, &lower) {
            score += 1.5;
        }
        if score > best_score {
            (best, best_score) = (language, score);
        }
    }
    best
}

const BAIT_WORDS: [&str; 17] = [
    "震惊",
    "炸裂",
    "吊打",
    "打脸",
    "怒怼",
    "惊呆",
    "毁三观",
    "跪了",
    "destroy",
    "owned",
    "exposed",
    "humiliat",
    "wreck",
    "shocking",
    "obliterat",
    "demolish",
    "triggered",
];

/// Whether [title] reads like bait: three or more exclamation marks, a
/// title mostly in capitals, or words such as "destroys" and 吊打.
pub fn looks_like_bait(title: &str) -> bool {
    if title.chars().filter(|&c| c == '!' || c == '！').count() >= 3 {
        return true;
    }
    let lower = title.to_lowercase();
    if BAIT_WORDS.iter().any(|w| lower.contains(w)) {
        return true;
    }
    // "you won't believe", with any apostrophe.
    if let Some(at) = lower.find("you won") {
        let rest = &lower[at + "you won".len()..];
        let mut chars = rest.chars();
        if chars.next().is_some() && chars.as_str().starts_with("t believe") {
            return true;
        }
    }
    let letters: Vec<char> = title.chars().filter(char::is_ascii_alphabetic).collect();
    letters.len() >= 12
        && letters.iter().filter(|c| c.is_ascii_uppercase()).count() as f64
            > letters.len() as f64 * 0.7
}

/// What [is_short] looks at.
#[derive(Deserialize, Default)]
#[serde(default)]
pub struct ShortInfo {
    /// The address.
    #[serde(rename = "u")]
    pub url: String,
    /// The title and description.
    #[serde(rename = "t")]
    pub text: String,
    /// Seconds, when known.
    #[serde(rename = "d")]
    pub duration: Option<i64>,
    /// Listed as a Short.
    #[serde(rename = "l")]
    pub listed: bool,
}

/// A Short: listed as one or at a /shorts/ address, a minute or less, or
/// up to three minutes tagged #shorts.
pub fn is_short(info: &ShortInfo) -> bool {
    if info.listed || info.url.contains("/shorts/") {
        return true;
    }
    let Some(seconds) = info.duration.filter(|&s| s > 0) else {
        return false;
    };
    seconds <= 60 || (seconds <= 180 && tagged_shorts(&info.text.to_lowercase()))
}

/// Whether [lower] has #short or #shorts as a whole tag.
fn tagged_shorts(lower: &str) -> bool {
    lower.match_indices("#short").any(|(at, tag)| {
        let rest = &lower[at + tag.len()..];
        let rest = rest.strip_prefix('s').unwrap_or(rest);
        !rest
            .chars()
            .next()
            .is_some_and(|c| c.is_alphanumeric() || c == '_')
    })
}

/// The channels of the block lists the user has on.
#[derive(Deserialize, Default)]
#[serde(default)]
pub struct Blocks {
    /// Names, or what a name starts with as a whole word, lower case.
    channels: Vec<String>,
    /// Whole names, lower case.
    exact: HashSet<String>,
    /// @handles, lower case.
    handles: HashSet<String>,
    ids: HashSet<String>,
}

/// One channel to test against [Blocks].
#[derive(Deserialize, Default)]
#[serde(default)]
pub struct Channel {
    #[serde(rename = "n")]
    pub name: String,
    #[serde(rename = "i")]
    pub id: Option<String>,
    #[serde(rename = "h")]
    pub handle: Option<String>,
}

impl Blocks {
    pub fn is_empty(&self) -> bool {
        self.channels.is_empty()
            && self.exact.is_empty()
            && self.handles.is_empty()
            && self.ids.is_empty()
    }

    /// Whether [channel] is listed, by id, @handle or name.
    pub fn matches(&self, channel: &Channel) -> bool {
        if channel.id.as_ref().is_some_and(|id| self.ids.contains(id)) {
            return true;
        }
        if let Some(handle) = channel.handle.as_deref().filter(|h| !h.is_empty()) {
            let handle = if handle.starts_with('@') {
                handle.to_lowercase()
            } else {
                format!("@{}", handle.to_lowercase())
            };
            if self.handles.contains(&handle) {
                return true;
            }
        }
        let lower = channel.name.trim().to_lowercase();
        !lower.is_empty()
            && (self.exact.contains(&lower)
                || self
                    .channels
                    .iter()
                    .any(|word| name_starts_with(&lower, word)))
    }
}

/// Whether channel [name] is [word] or starts with it as a whole word:
/// "RT Documentary" for RT but not "RTL"; a Chinese name may run on
/// ("央视新闻"). Both lower case.
pub fn name_starts_with(name: &str, word: &str) -> bool {
    let Some(rest) = name.strip_prefix(word) else {
        return false;
    };
    let Some(next) = rest.chars().next() else {
        return true;
    };
    word.chars().last().is_some_and(|c| c as u32 > 0x2E7F) || !next.is_alphanumeric()
}

/// The language of the UTF-8 title, as its place in [Language].
///
/// # Safety
/// `title` points at `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_title_language(title: *const u8, length: usize) -> u32 {
    title_language(unsafe { text(title, length) }) as u32
}

/// Whether the UTF-8 title reads like bait.
///
/// # Safety
/// `title` points at `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_looks_like_bait(title: *const u8, length: usize) -> bool {
    looks_like_bait(unsafe { text(title, length) })
}

/// Whether the video described by the JSON [ShortInfo] is a Short.
///
/// # Safety
/// `json` points at `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_is_short(json: *const u8, length: usize) -> bool {
    serde_json::from_str::<ShortInfo>(unsafe { text(json, length) })
        .is_ok_and(|info| is_short(&info))
}

/// Block lists from JSON [Blocks], for [lumtub_blocks_match]; null when
/// the JSON does not read or lists nothing. Free with [lumtub_blocks_free].
///
/// # Safety
/// `json` points at `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_blocks_new(json: *const u8, length: usize) -> *mut Blocks {
    match serde_json::from_str::<Blocks>(unsafe { text(json, length) }) {
        Ok(blocks) if !blocks.is_empty() => Box::into_raw(Box::new(blocks)),
        _ => std::ptr::null_mut(),
    }
}

/// Whether the channel in JSON [Channel] is on [blocks]; false for null.
///
/// # Safety
/// `blocks` is null or came from [lumtub_blocks_new] and is not freed;
/// `json` points at `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_blocks_match(
    blocks: *const Blocks,
    json: *const u8,
    length: usize,
) -> bool {
    let Some(blocks) = (unsafe { blocks.as_ref() }) else {
        return false;
    };
    serde_json::from_str::<Channel>(unsafe { text(json, length) })
        .is_ok_and(|channel| blocks.matches(&channel))
}

/// Frees what [lumtub_blocks_new] returned.
///
/// # Safety
/// `blocks` is null or came from [lumtub_blocks_new], and is freed once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_blocks_free(blocks: *mut Blocks) {
    if !blocks.is_null() {
        drop(unsafe { Box::from_raw(blocks) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tells_languages_apart() {
        assert_eq!(title_language("【4K】東京の夜景を歩く"), Language::Ja);
        assert_eq!(title_language("서울 맛집 투어"), Language::Ko);
        assert_eq!(title_language("中国历史纪录片 第一集"), Language::Zh);
        assert_eq!(title_language("How to build a PC in 2026"), Language::En);
        assert_eq!(title_language("Minecraft Speedrun"), Language::En);
        assert_eq!(title_language("Cómo hacer pan en casa"), Language::Es);
        assert_eq!(
            title_language("Les meilleures recettes pour l'été"),
            Language::Fr
        );
        assert_eq!(title_language("Wie man das Brot backt"), Language::De);
        assert_eq!(title_language("Como fazer pão em casa"), Language::Pt);
        assert_eq!(title_language("Как приготовить борщ"), Language::Ru);
        assert_eq!(title_language("Phở bò Hà Nội"), Language::Vi);
        assert_eq!(title_language("2026 12 31"), Language::Any);
    }

    #[test]
    fn finds_bait() {
        assert!(looks_like_bait("Atheist DESTROYS pastor in debate"));
        assert!(looks_like_bait("震惊！神父说出真相"));
        assert!(looks_like_bait("WHAT THE CHURCH WILL NOT TELL YOU"));
        assert!(looks_like_bait("You must see this!!!"));
        assert!(looks_like_bait("You won’t believe this"));
        assert!(!looks_like_bait("Holy Mass from St Peter's Basilica"));
        assert!(!looks_like_bait("天主教的七件圣事"));
        assert!(!looks_like_bait("EWTN Daily Mass"));
    }

    #[test]
    fn finds_shorts() {
        let short = |url: &str, text: &str, duration: Option<i64>, listed: bool| {
            is_short(&ShortInfo {
                url: url.into(),
                text: text.into(),
                duration,
                listed,
            })
        };
        assert!(short("https://www.youtube.com/shorts/a", "", None, false));
        assert!(short("", "", Some(500), true));
        assert!(short("", "", Some(45), false));
        assert!(!short("", "", Some(120), false));
        assert!(short("", "fun #Shorts", Some(120), false));
        assert!(short("", "fun #short", Some(120), false));
        assert!(!short("", "fun #shortstory", Some(120), false));
        assert!(!short("", "fun #shorts", Some(200), false));
        assert!(!short("", "", None, false));
    }

    #[test]
    fn matches_blocked_channels() {
        let blocks: Blocks = serde_json::from_str(
            r#"{"channels":["rt","央视"],"exact":["aa"],"handles":["@ntd"],"ids":["UC1"]}"#,
        )
        .unwrap();
        let channel = |name: &str, id: Option<&str>, handle: Option<&str>| {
            blocks.matches(&Channel {
                name: name.into(),
                id: id.map(Into::into),
                handle: handle.map(Into::into),
            })
        };
        assert!(channel("RT Documentary", None, None));
        assert!(channel("RT", None, None));
        assert!(!channel("RTL", None, None));
        assert!(channel("央视新闻", None, None));
        assert!(channel("AA", None, None));
        assert!(!channel("AA Travel", None, None));
        assert!(channel("Someone", Some("UC1"), None));
        assert!(channel("Someone", None, Some("NTD")));
        assert!(channel("Someone", None, Some("@ntd")));
        assert!(!channel("Someone", Some("UC2"), Some("other")));
        assert!(!channel("", None, None));
    }
}
