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
    if secs.len() != 2 || frac.is_empty() || frac.len() > 3 || !frac.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let seconds: u64 = secs.parse().ok()?;
    let millis: u64 = format!("{frac:0<3}").parse().ok()?;
    let minutes: u64 = parts[parts.len() - 2].parse().ok()?;
    let hours: u64 = if parts.len() == 3 { parts[0].parse().ok()? } else { 0 };
    Some(((hours * 60 + minutes) * 60 + seconds) * 1000 + millis)
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
    out.replace("&nbsp;", " ").replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&").trim().to_string()
}

/// The cues of a WebVTT or SRT file in time order, each on one line.
/// Automatic captions repeat the line before as the first line of the next
/// cue; only new lines stay. Other formats give none.
pub fn cues(source: &str) -> Vec<Cue> {
    let normalized = source.replace("\r\n", "\n").replace('\r', "\n");
    let mut out = Vec::new();
    let mut previous: Option<String> = None;
    for block in normalized.split("\n\n") {
        let lines: Vec<&str> = block.split('\n').collect();
        let Some((at, (start, end))) = lines.iter().enumerate().find_map(|(i, l)| timing(l).map(|t| (i, t))) else {
            continue;
        };
        let mut body: Vec<String> = lines[at + 1..].iter().map(|l| clean(l)).filter(|l| !l.is_empty()).collect();
        if previous.is_some() && body.first() == previous.as_ref() {
            body.remove(0);
        }
        let Some(last) = body.last() else { continue };
        previous = Some(last.clone());
        out.push(Cue { start, end, text: body.join(" ") });
    }
    out.sort_by_key(|c| c.start);
    out
}

static SIMPLIFIED: LazyLock<HashSet<char>> =
    LazyLock::new(|| "这们来时会说为国后还与对过开关体学发点从个么见长门问间听车东边头实现话让认没给经样张导书买卖钱电视频网层万专业亿".chars().collect());
static TRADITIONAL: LazyLock<HashSet<char>> =
    LazyLock::new(|| "這們來時會說為國後還與對過開關體學發點從個麼見長門問間聽車東邊頭實現話讓認沒給經樣張導書買賣錢電視頻網層萬專業億".chars().collect());
const ENGLISH: &[&str] = &[
    "the", "a", "an", "and", "or", "but", "is", "are", "was", "were", "be", "been", "to", "of", "in", "on", "at", "for", "with", "this", "that", "it", "i",
    "you", "he", "she", "we", "they", "my", "your", "not", "no", "so", "just", "have", "has", "do", "does", "did", "what", "how", "can", "will", "would",
    "if", "all", "from", "like", "me", "his", "her", "their", "there", "about", "one", "more", "video", "when", "love", "it's", "i'm", "don't", "really",
    "great", "thanks", "good", "very", "who", "why", "out", "up", "get", "know", "see", "think",
];

fn is_letter(c: char) -> bool {
    let c = c as u32;
    if c < 0x80 {
        return (0x41..=0x5A).contains(&c) || (0x61..=0x7A).contains(&c);
    }
    !((0x2000..=0x2BFF).contains(&c) || (0x3000..=0x303F).contains(&c) || (0xFF00..=0xFF20).contains(&c) || c >= 0x1F000)
}

fn han(c: u32) -> bool {
    (0x4E00..=0x9FFF).contains(&c) || (0x3400..=0x4DBF).contains(&c) || (0xF900..=0xFAFF).contains(&c)
}

/// A guess from the script alone at whether [source] is in [target] (a
/// translation language code such as `zh-CN`). Latin-script languages
/// other than English are never recognised.
pub fn looks_like(source: &str, target: &str) -> bool {
    let letters: Vec<u32> = source.chars().filter(|&c| is_letter(c)).map(|c| c as u32).collect();
    if letters.len() < 2 {
        return false;
    }
    let count = |test: &dyn Fn(u32) -> bool| letters.iter().filter(|&&c| test(c)).count() as f64;
    let share = letters.len() as f64 * 0.6;
    let hans = count(&han);
    let kana = count(&|c| (0x3040..=0x30FF).contains(&c) || (0x31F0..=0x31FF).contains(&c));
    let range = |from: u32, to: u32| count(&|c| (from..=to).contains(&c));
    match target {
        "zh-CN" | "zh-TW" => {
            if hans < share || kana > 0.0 {
                return false;
            }
            let simplified = source.chars().filter(|c| SIMPLIFIED.contains(c)).count();
            let traditional = source.chars().filter(|c| TRADITIONAL.contains(c)).count();
            if target == "zh-CN" { simplified >= traditional } else { traditional >= simplified && (traditional > 0 || simplified == 0) }
        }
        "ja" => kana > 0.0 && hans + kana >= share,
        "ko" => count(&|c| (0xAC00..=0xD7AF).contains(&c) || (0x1100..=0x11FF).contains(&c) || (0x3130..=0x318F).contains(&c)) >= share,
        "ru" => range(0x0400, 0x04FF) >= share,
        "ar" => range(0x0600, 0x06FF) >= share,
        "th" => range(0x0E00, 0x0E7F) >= share,
        "hi" => range(0x0900, 0x097F) >= share,
        "en" => {
            if count(&|c| (0x41..=0x5A).contains(&c) || (0x61..=0x7A).contains(&c)) < share {
                return false;
            }
            let lower = source.to_lowercase();
            let words: Vec<&str> = lower.split(|c: char| !(c.is_ascii_alphabetic() || c == '\'')).filter(|w| !w.is_empty()).collect();
            words.len() >= 3 && words.iter().filter(|w| ENGLISH.contains(w)).count() as f64 >= words.len() as f64 * 0.2
        }
        _ => false,
    }
}

/// [cues] for Dart, as JSON `[[start_ms, end_ms, "text"], …]`. Free the text
/// with `lumtub_string_free`.
///
/// # Safety
/// [source] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_subtitle_cues(source: *const u8, length: usize) -> *mut c_char {
    let list: Vec<serde_json::Value> = cues(unsafe { text(source, length) }).into_iter().map(|c| serde_json::json!([c.start, c.end, c.text])).collect();
    give(serde_json::Value::Array(list).to_string())
}

/// [looks_like] for Dart.
///
/// # Safety
/// [source] and [target] must point to their lengths of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_looks_like(source: *const u8, length: usize, target: *const u8, target_length: usize) -> bool {
    looks_like(unsafe { text(source, length) }, unsafe { text(target, target_length) })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_webvtt_and_srt() {
        let vtt = "WEBVTT\n\n00:00:01.000 --> 00:00:02.500 align:start\n<c>Hello</c> &amp; hi\n\n00:00:02.500 --> 00:00:04.000\nHello &amp; hi\nworld\n";
        assert_eq!(
            cues(vtt),
            vec![Cue { start: 1000, end: 2500, text: "Hello & hi".into() }, Cue { start: 2500, end: 4000, text: "world".into() }]
        );
        let srt = "1\r\n01:02:03,040 --> 01:02:04,5\r\n{\\an8}Line one\r\nLine two\r\n\r\n";
        assert_eq!(cues(srt), vec![Cue { start: 3_723_040, end: 3_724_500, text: "Line one Line two".into() }]);
        assert!(cues("[Script Info]\nDialogue: 0,0:00:01.00").is_empty());
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
    }
}
