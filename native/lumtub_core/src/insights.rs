//! Text and numbers Lumtub works out from what it already has: a video's
//! subtitles as a transcript for AI 总结, 语音识别 results as subtitles, and
//! 观看统计 from the watch time kept on this computer.

use serde_json::{Value, json};
use std::collections::HashMap;
use std::ffi::c_char;

use crate::subtitles::{Cue, cues};
use crate::taste::{give, text};

/// `m:ss`, or `h:mm:ss` from an hour on.
fn clock(ms: u64) -> String {
    let seconds = ms / 1000;
    let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60);
    if h > 0 { format!("{h}:{m:02}:{s:02}") } else { format!("{m}:{s:02}") }
}

fn ends_sentence(line: &str) -> bool {
    line.trim_end().ends_with(['.', '!', '?', '。', '！', '？', '…'])
}

fn wide(c: char) -> bool {
    matches!(c as u32, 0x3000..=0x30FF | 0x3400..=0x9FFF | 0xF900..=0xFAFF | 0xFF00..=0xFFEF)
}

/// [cues] as paragraphs, each starting with its time: lines are joined
/// until a pause, a sentence end after a while, or half a minute.
pub fn paragraphs(cues: &[Cue]) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut started = 0;
    let mut last_end = 0;
    for cue in cues {
        let line = cue.text.trim();
        if line.is_empty() {
            continue;
        }
        let pause = cue.start.saturating_sub(last_end) > 2000;
        let long = cue.start.saturating_sub(started) >= 30_000;
        let sentence = ends_sentence(&current) && cue.start.saturating_sub(started) >= 12_000;
        if !current.is_empty() && (pause || long || sentence) {
            out.push(format!("[{}] {}", clock(started), current));
            current.clear();
        }
        if current.is_empty() {
            started = cue.start;
        } else if !(current.chars().last().is_some_and(wide) || line.chars().next().is_some_and(wide)) {
            current.push(' ');
        }
        current.push_str(line);
        last_end = cue.end;
    }
    if !current.is_empty() {
        out.push(format!("[{}] {}", clock(started), current));
    }
    out
}

/// [paragraphs] cut into pieces of at most [budget] characters, each sent
/// to the AI in one request. Past [most] pieces the rest is left out.
pub fn transcript(source: &str, budget: usize, most: usize) -> Value {
    let lines = paragraphs(&cues(source));
    let mut chunks: Vec<String> = Vec::new();
    let mut current = String::new();
    let mut size = 0;
    let mut cut = false;
    for line in &lines {
        let length = line.chars().count();
        if size > 0 && size + length + 1 > budget {
            chunks.push(std::mem::take(&mut current));
            size = 0;
            if chunks.len() == most {
                cut = true;
                break;
            }
        }
        if size > 0 {
            current.push('\n');
        }
        current.push_str(line);
        size += length + 1;
    }
    if !current.is_empty() && chunks.len() < most {
        chunks.push(current);
    }
    json!({"chunks": chunks, "paragraphs": lines.len(), "cut": cut})
}

/// Days since 1970-01-01 of `YYYY-MM-DD`.
fn day_number(day: &str) -> Option<i64> {
    let mut parts = day.splitn(3, '-').map(|p| p.parse::<i64>().ok());
    let (y, m, d) = (parts.next()??, parts.next()??, parts.next()??);
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    Some(era * 146_097 + doe - 719_468)
}

/// `YYYY-MM-DD` of a [day_number].
fn day_text(number: i64) -> String {
    let z = number + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

/// 观看统计 of `{days: {day: {channel: seconds}}, names: {channel: name},
/// today, span}`: today, the last 7 and [span] days, all of it, the
/// seconds of each of the last [span] days and the channels watched most
/// in them.
pub fn watch_stats(input: &Value) -> Value {
    let today = input.get("today").and_then(Value::as_str).and_then(day_number).unwrap_or(0);
    let span = input.get("span").and_then(Value::as_i64).unwrap_or(30).clamp(1, 366);
    let names = input.get("names").and_then(Value::as_object);
    let mut daily: HashMap<i64, u64> = HashMap::new();
    let mut channels: HashMap<&str, u64> = HashMap::new();
    let (mut week, mut month, mut total) = (0u64, 0u64, 0u64);
    for (day, watched) in input.get("days").and_then(Value::as_object).into_iter().flatten() {
        let Some(number) = day_number(day) else { continue };
        let age = today - number;
        for (channel, seconds) in watched.as_object().into_iter().flatten() {
            let seconds = seconds.as_u64().unwrap_or(0);
            total += seconds;
            if (0..span).contains(&age) {
                month += seconds;
                *daily.entry(number).or_default() += seconds;
                *channels.entry(channel.as_str()).or_default() += seconds;
            }
            if (0..7).contains(&age) {
                week += seconds;
            }
        }
    }
    let days: Vec<Value> = (0..span).rev().map(|age| json!([day_text(today - age), daily.get(&(today - age)).copied().unwrap_or(0)])).collect();
    let mut top: Vec<(&str, u64)> = channels.into_iter().filter(|(_, s)| *s > 0).collect();
    top.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    let top: Vec<Value> = top
        .into_iter()
        .take(10)
        .map(|(key, seconds)| json!([key, names.and_then(|n| n.get(key)).and_then(Value::as_str).unwrap_or(""), seconds]))
        .collect();
    json!({
        "today": daily.get(&today).copied().unwrap_or(0),
        "week": week,
        "month": month,
        "total": total,
        "average": month / span as u64,
        "days": days,
        "top": top,
    })
}

/// `HH:MM:SS.mmm`, as WebVTT writes times.
fn vtt_time(ms: u64) -> String {
    format!("{:02}:{:02}:{:02}.{:03}", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
}

/// [text] in pieces of about [size] characters, broken after punctuation
/// or a space where one is near, so long recognized sentences fit on screen.
fn pieces(text: &str, size: usize) -> Vec<String> {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() <= size + size / 3 {
        return vec![text.to_string()];
    }
    let count = chars.len().div_ceil(size);
    let target = chars.len().div_ceil(count);
    let mut out = Vec::new();
    let mut start = 0;
    while start < chars.len() {
        let mut end = (start + target).min(chars.len());
        if end < chars.len() {
            let low = start + target * 2 / 3;
            let high = (start + target * 4 / 3).min(chars.len() - 1);
            let good = |c: char| matches!(c, '，' | '。' | '！' | '？' | '、' | '；' | ',' | '.' | '!' | '?' | ';');
            if let Some(at) = (low..=high).find(|&i| good(chars[i])) {
                end = at + 1;
            } else if let Some(at) = (low..=high).rev().find(|&i| chars[i] == ' ') {
                end = at;
            }
        }
        let piece: String = chars[start..end].iter().collect::<String>().trim().to_string();
        if !piece.is_empty() {
            out.push(piece);
        }
        start = end;
    }
    out
}

/// WebVTT of what an OpenAI-compatible `/audio/transcriptions` answered
/// (`verbose_json`) for each part of a video's audio:
/// `{parts: [{offset: ms, segments: [{start, end, text, no_speech_prob}]}]}`,
/// [start] and [end] in seconds from the part's start. Silence Whisper
/// filled with made-up words is left out and long sentences are split.
pub fn speech_vtt(input: &Value) -> String {
    let mut cues: Vec<(u64, u64, String)> = Vec::new();
    for part in input.get("parts").and_then(Value::as_array).into_iter().flatten() {
        let offset = part.get("offset").and_then(Value::as_u64).unwrap_or(0);
        for segment in part.get("segments").and_then(Value::as_array).into_iter().flatten() {
            let text = segment.get("text").and_then(Value::as_str).unwrap_or("").split_whitespace().collect::<Vec<_>>().join(" ");
            let quiet = segment.get("no_speech_prob").and_then(Value::as_f64).unwrap_or(0.0) > 0.8;
            if text.is_empty() || quiet {
                continue;
            }
            let second = |name: &str| (segment.get(name).and_then(Value::as_f64).unwrap_or(0.0).max(0.0) * 1000.0) as u64;
            let start = offset + second("start");
            let end = (offset + second("end")).max(start + 500);
            let size = if text.chars().any(wide) { 22 } else { 48 };
            let parts = pieces(&text, size);
            let total: usize = parts.iter().map(|p| p.chars().count()).sum::<usize>().max(1);
            let mut at = start;
            for (i, piece) in parts.iter().enumerate() {
                let next = if i + 1 == parts.len() { end } else { at + (end - start) * piece.chars().count() as u64 / total as u64 };
                cues.push((at, next.max(at + 300), piece.clone()));
                at = next;
            }
        }
    }
    cues.sort_by_key(|c| c.0);
    let mut out = String::from("WEBVTT\n\n");
    for i in 0..cues.len() {
        let (start, mut end, ref text) = cues[i];
        if let Some(next) = cues.get(i + 1) {
            end = end.min(next.0.max(start + 300));
        }
        out.push_str(&format!("{} --> {}\n{}\n\n", vtt_time(start), vtt_time(end), text));
    }
    out
}

/// [speech_vtt] for Dart.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_speech_vtt(json: *const u8, length: usize) -> *mut c_char {
    let input: Value = serde_json::from_str(unsafe { text(json, length) }).unwrap_or(Value::Null);
    give(speech_vtt(&input))
}

/// [transcript] for Dart, from `{source, budget, most}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_summary_transcript(json: *const u8, length: usize) -> *mut c_char {
    let input: Value = serde_json::from_str(unsafe { text(json, length) }).unwrap_or(Value::Null);
    let source = input.get("source").and_then(Value::as_str).unwrap_or("");
    let budget = input.get("budget").and_then(Value::as_u64).unwrap_or(12_000).max(500) as usize;
    let most = input.get("most").and_then(Value::as_u64).unwrap_or(8).max(1) as usize;
    give(transcript(source, budget, most).to_string())
}

/// [watch_stats] for Dart.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_watch_stats(json: *const u8, length: usize) -> *mut c_char {
    let input: Value = serde_json::from_str(unsafe { text(json, length) }).unwrap_or(Value::Null);
    give(watch_stats(&input).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cue(start: u64, end: u64, text: &str) -> Cue {
        Cue { start, end, text: text.into() }
    }

    #[test]
    fn joins_lines_into_timed_paragraphs() {
        let lines = paragraphs(&[
            cue(0, 2000, "hello there"),
            cue(2000, 4000, "this is a test."),
            cue(9000, 11_000, "after a pause"),
            cue(11_000, 12_000, "你好"),
            cue(12_000, 13_000, "世界"),
            cue(3_700_000, 3_701_000, "an hour in"),
        ]);
        assert_eq!(lines, vec!["[0:00] hello there this is a test.", "[0:09] after a pause你好世界", "[1:01:40] an hour in"]);
    }

    #[test]
    fn cuts_the_transcript_into_pieces() {
        let source: String = (0..40).map(|i| format!("{:02}:{:02}.000 --> {:02}:{:02}.500\nline number {i}.\n\n", i * 5 / 60, i * 5 % 60, i * 5 / 60, i * 5 % 60 + 4)).collect();
        let source = format!("WEBVTT\n\n{source}");
        let answer = transcript(&source, 60, 3);
        let chunks = answer["chunks"].as_array().unwrap();
        assert_eq!(chunks.len(), 3);
        assert!(chunks[0].as_str().unwrap().starts_with("[0:00] line number 0."));
        assert_eq!(answer["cut"], true);
        let whole = transcript(&source, 100_000, 3);
        assert_eq!(whole["chunks"].as_array().unwrap().len(), 1);
        assert_eq!(whole["cut"], false);
    }

    #[test]
    fn turns_recognized_speech_into_subtitles() {
        let vtt = speech_vtt(&json!({"parts": [
            {"offset": 0, "segments": [
                {"start": 0.0, "end": 2.5, "text": " Hello there. "},
                {"start": 3.0, "end": 4.0, "text": "Thanks for watching!", "no_speech_prob": 0.95},
            ]},
            {"offset": 600_000, "segments": [
                {"start": 1.0, "end": 9.0, "text": "这是一段很长的识别结果，里面有好几个分句，应该被拆成两条字幕显示，不然一行放不下。"},
            ]},
        ]}));
        assert!(vtt.starts_with("WEBVTT\n\n00:00:00.000 --> 00:00:02.500\nHello there.\n\n"));
        assert!(!vtt.contains("Thanks for watching"));
        assert!(vtt.contains("00:10:01.000 --> "));
        let cues = cues(&vtt);
        assert_eq!(cues.len(), 3);
        assert!(cues[1].text.ends_with('，'));
        assert_eq!(cues[2].end, 609_000);
        assert_eq!(cues[1].end, cues[2].start);
    }

    #[test]
    fn counts_days_both_ways() {
        assert_eq!(day_number("1970-01-01"), Some(0));
        assert_eq!(day_text(day_number("2024-02-29").unwrap()), "2024-02-29");
        assert_eq!(day_text(day_number("2026-10-27").unwrap() + 5), "2026-11-01");
        assert_eq!(day_number("2026-13-01"), None);
    }

    #[test]
    fn adds_up_watch_time() {
        let stats = watch_stats(&json!({
            "today": "2026-10-27",
            "span": 30,
            "names": {"UC1": "One", "UC2": "Two"},
            "days": {
                "2026-10-27": {"UC1": 600, "UC2": 60},
                "2026-10-21": {"UC2": 1200},
                "2026-10-01": {"UC1": 100},
                "2025-01-01": {"UC1": 5000},
            },
        }));
        assert_eq!(stats["today"], 660);
        assert_eq!(stats["week"], 1860);
        assert_eq!(stats["month"], 1960);
        assert_eq!(stats["total"], 6960);
        assert_eq!(stats["days"].as_array().unwrap().len(), 30);
        assert_eq!(stats["days"][29], json!(["2026-10-27", 660]));
        assert_eq!(stats["top"][0], json!(["UC2", "Two", 1260]));
        assert_eq!(stats["top"][1], json!(["UC1", "One", 700]));
    }
}
