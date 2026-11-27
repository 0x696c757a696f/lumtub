//! Subtitle lines for 字幕列表 and the script-based language guess that lets
//! 翻译 skip text already in the target language.

use std::collections::HashSet;
use std::ffi::c_char;
use std::sync::LazyLock;

use crate::taste::{give, text};

/// One line of a track: start and end in milliseconds, and its text.
#[derive(Debug, PartialEq)]
pub struct Cue {
    pub start: u64,
    pub end: u64,
    pub text: String,
}

/// `HH:MM:SS.mmm`, `MM:SS.mmm` or SRT's `HH:MM:SS,mmm`, in milliseconds.
fn time(stamp: &str) -> Option<u64> {
    let stamp = stamp.trim().replace(',', ".");
    let parts: Vec<&str> = stamp.split(':').collect();
    if !(2..=3).contains(&parts.len()) {
        return None;
    }
    let (secs, frac) = parts.last()?.split_once('.')?;
    if secs.len() != 2
        || frac.is_empty()
        || frac.len() > 3
        || !frac.bytes().all(|b| b.is_ascii_digit())
    {
        return None;
    }
    let seconds: u64 = secs.parse().ok()?;
    let millis: u64 = format!("{frac:0<3}").parse().ok()?;
    let minutes: u64 = parts[parts.len() - 2].parse().ok()?;
    let hours: u64 = if parts.len() == 3 {
        parts[0].parse().ok()?
    } else {
        0
    };
    hours
        .checked_mul(60)?
        .checked_add(minutes)?
        .checked_mul(60)?
        .checked_add(seconds)?
        .checked_mul(1000)?
        .checked_add(millis)
}

/// The start and end of a `start --> end` line, which may carry settings after.
fn timing(line: &str) -> Option<(u64, u64)> {
    let (start, rest) = line.split_once("-->")?;
    let end = rest.split_whitespace().next()?;
    Some((time(start)?, time(end)?))
}

/// [line] without tags (`<c>`, `<00:00:01.000>`, `{\an8}`) and with the
/// common entities decoded.
fn clean(line: &str) -> String {
    let mut out = String::with_capacity(line.len());
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '<' => {
                for d in chars.by_ref() {
                    if d == '>' {
                        break;
                    }
                }
            }
            '{' if chars.peek() == Some(&'\\') => {
                for d in chars.by_ref() {
                    if d == '}' {
                        break;
                    }
                }
            }
            _ => out.push(c),
        }
    }
    out.replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
        .trim()
        .to_string()
}

/// The cues of a WebVTT or SRT file in time order, each on one line.
/// Automatic captions repeat the line before as the first line of the next
/// cue; only new lines stay. Other formats give none.
pub fn cues(source: &str) -> Vec<Cue> {
    cues_in(source, false)
}

/// [cues], or with `keep_lines` each cue's lines kept as they are, joined by
/// line breaks, for a file Lumtub wrote such as a bilingual track.
pub fn cues_in(source: &str, keep_lines: bool) -> Vec<Cue> {
    let normalized = source.replace("\r\n", "\n").replace('\r', "\n");
    let mut out = Vec::new();
    let mut previous: Option<String> = None;
    for block in normalized.split("\n\n") {
        let lines: Vec<&str> = block.split('\n').collect();
        let Some((at, (start, end))) = lines
            .iter()
            .enumerate()
            .find_map(|(i, l)| timing(l).map(|t| (i, t)))
        else {
            continue;
        };
        let mut body: Vec<String> = lines[at + 1..]
            .iter()
            .map(|l| clean(l))
            .filter(|l| !l.is_empty())
            .collect();
        if !keep_lines && previous.is_some() && body.first() == previous.as_ref() {
            body.remove(0);
        }
        let Some(last) = body.last() else { continue };
        previous = Some(last.clone());
        out.push(Cue {
            start,
            end,
            text: body.join(if keep_lines { "\n" } else { " " }),
        });
    }
    out.sort_by_key(|c| c.start);
    out
}

static SIMPLIFIED: LazyLock<HashSet<char>> = LazyLock::new(|| {
    "这们来时会说为国后还与对过开关体学发点从个么见长门问间听车东边头实现话让认没给经样张导书买卖钱电视频网层万专业亿".chars().collect()
});
static TRADITIONAL: LazyLock<HashSet<char>> = LazyLock::new(|| {
    "這們來時會說為國後還與對過開關體學發點從個麼見長門問間聽車東邊頭實現話讓認沒給經樣張導書買賣錢電視頻網層萬專業億".chars().collect()
});
const ENGLISH: &[&str] = &[
    "the", "a", "an", "and", "or", "but", "is", "are", "was", "were", "be", "been", "to", "of",
    "in", "on", "at", "for", "with", "this", "that", "it", "i", "you", "he", "she", "we", "they",
    "my", "your", "not", "no", "so", "just", "have", "has", "do", "does", "did", "what", "how",
    "can", "will", "would", "if", "all", "from", "like", "me", "his", "her", "their", "there",
    "about", "one", "more", "video", "when", "love", "it's", "i'm", "don't", "really", "great",
    "thanks", "good", "very", "who", "why", "out", "up", "get", "know", "see", "think",
];

fn is_letter(c: char) -> bool {
    let c = c as u32;
    if c < 0x80 {
        return (0x41..=0x5a).contains(&c) || (0x61..=0x7a).contains(&c);
    }
    !((0x2000..=0x2bff).contains(&c)
        || (0x3000..=0x303f).contains(&c)
        || (0xff00..=0xff20).contains(&c)
        || c >= 0x1f000)
}

fn han(c: u32) -> bool {
    (0x4e00..=0x9fff).contains(&c)
        || (0x3400..=0x4dbf).contains(&c)
        || (0xf900..=0xfaff).contains(&c)
}

/// A guess from the script alone at whether [source] is in [target] (a
/// translation language code such as `zh-CN`). Latin-script languages
/// other than English are never recognised.
pub fn looks_like(source: &str, target: &str) -> bool {
    let letters: Vec<u32> = source
        .chars()
        .filter(|&c| is_letter(c))
        .map(|c| c as u32)
        .collect();
    if letters.len() < 2 {
        return false;
    }
    let count = |test: &dyn Fn(u32) -> bool| letters.iter().filter(|&&c| test(c)).count() as f64;
    let share = letters.len() as f64 * 0.6;
    let hans = count(&han);
    let kana = count(&|c| (0x3040..=0x30ff).contains(&c) || (0x31f0..=0x31ff).contains(&c));
    let range = |from: u32, to: u32| count(&|c| (from..=to).contains(&c));
    match target {
        "zh-CN" | "zh-TW" => {
            if hans < share || kana > 0.0 {
                return false;
            }
            let simplified = source.chars().filter(|c| SIMPLIFIED.contains(c)).count();
            let traditional = source.chars().filter(|c| TRADITIONAL.contains(c)).count();
            if target == "zh-CN" {
                simplified >= traditional
            } else {
                traditional >= simplified && (traditional > 0 || simplified == 0)
            }
        }
        "ja" => kana > 0.0 && hans + kana >= share,
        "ko" => {
            count(&|c| {
                (0xac00..=0xd7af).contains(&c)
                    || (0x1100..=0x11ff).contains(&c)
                    || (0x3130..=0x318f).contains(&c)
            }) >= share
        }
        "ru" => range(0x0400, 0x04ff) >= share,
        "ar" => range(0x0600, 0x06ff) >= share,
        "th" => range(0x0e00, 0x0e7f) >= share,
        "hi" => range(0x0900, 0x097f) >= share,
        "en" => {
            if count(&|c| (0x41..=0x5a).contains(&c) || (0x61..=0x7a).contains(&c)) < share {
                return false;
            }
            let lower = source.to_lowercase();
            let words: Vec<&str> = lower
                .split(|c: char| !(c.is_ascii_alphabetic() || c == '\''))
                .filter(|w| !w.is_empty())
                .collect();
            words.len() >= 3
                && words.iter().filter(|w| ENGLISH.contains(w)).count() as f64
                    >= words.len() as f64 * 0.2
        }
        _ => written_in(source, letters.len(), target),
    }
}

/// Whether whatlang is sure [source] is in [target], for the languages the
/// script alone cannot tell apart (German, French, Spanish, …). Short text
/// is never judged: a few words say too little.
fn written_in(source: &str, letters: usize, target: &str) -> bool {
    if letters < 12 {
        return false;
    }
    let Some(info) = whatlang::detect(source) else {
        return false;
    };
    info.confidence() >= 0.5 && translation_code(info.lang()) == Some(target)
}

/// The translation language code (Google's) of a whatlang language.
fn translation_code(lang: whatlang::Lang) -> Option<&'static str> {
    use whatlang::Lang::*;
    Some(match lang {
        Spa => "es",
        Fra => "fr",
        Deu => "de",
        Por => "pt",
        Ita => "it",
        Nld => "nl",
        Tur => "tr",
        Ind => "id",
        Pol => "pl",
        Ces => "cs",
        Slk => "sk",
        Ron => "ro",
        Hun => "hu",
        Swe => "sv",
        Nob => "no",
        Dan => "da",
        Fin => "fi",
        Aze => "az",
        Epo => "eo",
        Est => "et",
        Jav => "jw",
        Lat => "la",
        Lit => "lt",
        Lav => "lv",
        Tuk => "tk",
        Uzb => "uz",
        Vie => "vi",
        Tgl => "tl",
        Hrv => "hr",
        Srp => "sr",
        Slv => "sl",
        Cat => "ca",
        Afr => "af",
        Ukr => "uk",
        Bel => "be",
        Bul => "bg",
        Mkd => "mk",
        Ell => "el",
        Heb => "iw",
        Pes => "fa",
        Urd => "ur",
        Ben => "bn",
        Tam => "ta",
        Tel => "te",
        Mar => "mr",
        Nep => "ne",
        Guj => "gu",
        Pan => "pa",
        Kan => "kn",
        Mal => "ml",
        Sin => "si",
        Mya => "my",
        Kat => "ka",
        Hye => "hy",
        Khm => "km",
        Amh => "am",
        Zul => "zu",
        Sna => "sn",
        Yid => "yi",
        Ori => "or",
        _ => return None,
    })
}

/// [cues] for Dart, as JSON `[[start_ms, end_ms, "text"], …]`. Free the text
/// with `lumtub_string_free`.
///
/// # Safety
/// [source] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_subtitle_cues(source: *const u8, length: usize) -> *mut c_char {
    // SAFETY: The caller passes `source` pointing at `length` readable bytes, as this function
    // requires.
    let list: Vec<serde_json::Value> = cues(unsafe { text(source, length) })
        .into_iter()
        .map(|c| serde_json::json!([c.start, c.end, c.text]))
        .collect();
    give(serde_json::Value::Array(list).to_string())
}

/// [looks_like] for Dart.
///
/// # Safety
/// [source] and [target] must point to their lengths of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_looks_like(
    source: *const u8,
    length: usize,
    target: *const u8,
    target_length: usize,
) -> bool {
    // SAFETY: The caller passes `source` and `target` pointing at `length` and `target_length`
    // readable bytes, as this function requires.
    looks_like(unsafe { text(source, length) }, unsafe {
        text(target, target_length)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_webvtt_and_srt() {
        let vtt = "WEBVTT\n\n00:00:01.000 --> 00:00:02.500 align:start\n<c>Hello</c> &amp; hi\n\n00:00:02.500 --> 00:00:04.000\nHello &amp; hi\nworld\n";
        assert_eq!(
            cues(vtt),
            vec![
                Cue {
                    start: 1000,
                    end: 2500,
                    text: "Hello & hi".into()
                },
                Cue {
                    start: 2500,
                    end: 4000,
                    text: "world".into()
                }
            ]
        );
        let srt = "1\r\n01:02:03,040 --> 01:02:04,5\r\n{\\an8}Line one\r\nLine two\r\n\r\n";
        assert_eq!(
            cues(srt),
            vec![Cue {
                start: 3_723_040,
                end: 3_724_500,
                text: "Line one Line two".into()
            }]
        );
        assert!(cues("[Script Info]\nDialogue: 0,0:00:01.00").is_empty());
    }

    #[test]
    fn keeps_the_lines_of_a_bilingual_track() {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\n你好\nHello\n\n2\n00:00:02,000 --> 00:00:03,000\nHello\nAgain\n";
        let kept = cues_in(srt, true);
        assert_eq!(kept[0].text, "你好\nHello");
        assert_eq!(kept[1].text, "Hello\nAgain");
        assert_eq!(cues(srt)[1].text, "Again");
    }

    #[test]
    fn guesses_languages_by_script() {
        assert!(looks_like("这个视频真不错，学到了", "zh-CN"));
        assert!(!looks_like("這個視頻真不錯，學到了", "zh-CN"));
        assert!(looks_like("這個視頻真不錯，學到了", "zh-TW"));
        assert!(looks_like("このビデオは本当に良かった", "ja"));
        assert!(!looks_like("このビデオは本当に良かった", "zh-CN"));
        assert!(looks_like("이 영상 정말 좋네요", "ko"));
        assert!(looks_like("This is a really great video, thanks!", "en"));
        assert!(!looks_like("Cette vidéo est vraiment super", "en"));
        assert!(!looks_like("😂😂", "zh-CN"));
        assert!(looks_like(
            "Dieses Video ist wirklich sehr gut gemacht, danke dafür",
            "de"
        ));
        assert!(looks_like(
            "Cette vidéo est vraiment super, merci beaucoup pour le travail",
            "fr"
        ));
        assert!(!looks_like(
            "Dieses Video ist wirklich sehr gut gemacht, danke dafür",
            "fr"
        ));
        assert!(!looks_like("Sehr gut", "de"));
    }

    #[test]
    fn a_time_too_large_to_count_is_skipped() {
        let source = String::from_utf8_lossy(&[
            0, 10, 0, 10, 0, 0, 7, 52, 10, 10, 0, 10, 0, 10, 10, 6, 8, 45, 45, 62, 95, 48, 48, 48,
            48, 48, 48, 48, 48, 49, 52, 55, 50, 57, 62, 10, 48, 48, 48, 48, 78, 111, 45, 62, 74,
            10, 51, 53, 54, 48, 48, 48, 48, 48, 48, 48, 49, 52, 55, 50, 57, 58, 56, 56, 44, 49, 45,
            45, 62, 78, 111, 45, 62, 74, 10, 51, 53, 54, 50, 53, 58, 56, 56, 44, 49, 45, 45, 62,
            78, 10, 9, 111, 10, 0, 10, 14, 45, 62, 10, 74,
        ])
        .into_owned();
        let _ = cues(&source);
        assert_eq!(time("99999999999999999:00:00.000"), None);
    }
}
