//! Just enough WebVTT to translate a track cue by cue, and to show automatic
//! captions as whole lines: the cues of a track, the sentences they make,
//! the lines a sentence shows in, and a translation cut to those lines.
//!
//! It works the way the app's Dart did before (`WebVtt` in
//! lib/subtitle_files.dart), to the character: widths count UTF-16 units as
//! Dart's `String.length` does, `\s` is JavaScript's, trimming is Dart's,
//! and times are Dart `Duration`s in microseconds. Where the Dart looked
//! again at the whole text on every step (the width of a sentence as it
//! grew, every place to cut for every cut), this keeps running totals and
//! stops looking once no later place can be better.

use std::ffi::c_char;

use serde::{Deserialize, Serialize};

use crate::caption_lines::{
    clause_tail, join, joins_unspaced, sentence_end, spaced, unspaced, width,
};
use crate::taste::{give_json, outside};

/// One cue: its timing line and its text on one line.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Cue {
    pub timing: String,
    pub text: String,
}

/// Microseconds, as Dart's `Duration` keeps them.
type Micros = i64;

const MS: Micros = 1000;
/// How far apart two cues may be and still run on into one sentence.
const GAP: Micros = 1200 * MS;

/// JavaScript's `\s`, which Dart's `RegExp` uses.
fn js_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n' | '\u{0B}' | '\u{0C}' | '\r' | ' ' | '\u{A0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200A}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202F}'
                | '\u{205F}'
                | '\u{3000}'
                | '\u{FEFF}'
    )
}

/// What Dart's `String.trim` removes.
fn dart_space(c: char) -> bool {
    c.is_whitespace() || c == '\u{FEFF}'
}

pub(crate) fn dart_trim(s: &str) -> &str {
    s.trim_matches(dart_space)
}

fn char_width(c: char) -> usize {
    c.len_utf16() + usize::from(unspaced(c))
}

fn cjk_stop(c: char) -> bool {
    matches!(
        c,
        '，' | '。' | '、' | '！' | '？' | '；' | '：' | '…' | '）' | '」' | '』'
    )
}

/// `^\s*[\d:.]+\s+-->\s+[\d:.]+`: [line] is a timing line.
fn is_timing(line: &str) -> bool {
    let stamp = |c: char| c.is_ascii_digit() || c == ':' || c == '.';
    let rest = line.trim_start_matches(js_space);
    let after = rest.trim_start_matches(stamp);
    if after.len() == rest.len() {
        return false;
    }
    let rest = after.trim_start_matches(js_space);
    if rest.len() == after.len() {
        return false;
    }
    let Some(rest) = rest.strip_prefix("-->") else {
        return false;
    };
    let after = rest.trim_start_matches(js_space);
    after.len() != rest.len() && after.starts_with(stamp)
}

/// [line] without `<…>` tags.
fn untagged(line: &str) -> String {
    let mut out = String::with_capacity(line.len());
    let mut rest = line;
    while let Some(open) = rest.find('<') {
        let Some(close) = rest[open..].find('>') else {
            break;
        };
        out.push_str(&rest[..open]);
        rest = &rest[open + close + 1..];
    }
    out.push_str(rest);
    out
}

fn unescape(text: &str) -> String {
    let mut text = text.to_owned();
    for (from, to) in [
        ("&nbsp;", " "),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&amp;", "&"),
    ] {
        if text.contains(from) {
            text = text.replace(from, to);
        }
    }
    text
}

/// The cues of [vtt], each with its text on one line and without the word
/// timings of automatic captions. Automatic captions repeat the line before
/// as the first line of the next cue; only new lines stay.
pub fn cues(vtt: &str) -> Vec<Cue> {
    let vtt = vtt.replace("\r\n", "\n");
    let mut out = Vec::new();
    let mut previous: Option<String> = None;
    for block in vtt.split("\n\n").filter(|b| !b.is_empty()) {
        // Runs of three or more line breaks leave empty pieces here, as
        // Dart's split on `\n{2,}` would not; neither has a timing line.
        let block = block.trim_start_matches('\n');
        let mut lines = block.split('\n');
        let Some(timing) = lines.by_ref().find(|l| is_timing(l)) else {
            continue;
        };
        let mut text: Vec<String> = lines
            .filter_map(|line| {
                let clean = unescape(&untagged(line));
                let clean = dart_trim(&clean);
                (!clean.is_empty()).then(|| clean.to_owned())
            })
            .collect();
        if text.first().is_some_and(|f| Some(f) == previous.as_ref()) {
            text.remove(0);
        }
        let Some(last) = text.last() else {
            continue;
        };
        previous = Some(last.clone());
        out.push(Cue {
            timing: dart_trim(timing).to_owned(),
            text: text.join(" "),
        });
    }
    out
}

/// Dart's `double.tryParse`: a sign, digits with a point and an exponent,
/// `Infinity` or `NaN`.
fn dart_double(s: &str) -> Option<f64> {
    let s = dart_trim(s);
    let body = s.strip_prefix(['+', '-']).unwrap_or(s);
    if body == "Infinity" || body == "NaN" {
        let value = if body == "NaN" {
            f64::NAN
        } else {
            f64::INFINITY
        };
        return Some(if s.starts_with('-') { -value } else { value });
    }
    let (mantissa, exponent) = match body.find(['e', 'E']) {
        Some(at) => (&body[..at], Some(&body[at + 1..])),
        None => (body, None),
    };
    let (whole, fraction) = mantissa.split_once('.').unwrap_or((mantissa, ""));
    let digits = |p: &str| p.bytes().all(|b| b.is_ascii_digit());
    if whole.is_empty() && fraction.is_empty() || !digits(whole) || !digits(fraction) {
        return None;
    }
    if let Some(e) = exponent {
        let e = e.strip_prefix(['+', '-']).unwrap_or(e);
        if e.is_empty() || !digits(e) {
            return None;
        }
    }
    s.parse().ok()
}

/// Dart's `int.tryParse`: a sign and decimal digits, or `0x` and hex digits;
/// none past 64 bits.
pub(crate) fn dart_int(s: &str) -> Option<i64> {
    let s = dart_trim(s);
    let (negative, body) = match s.as_bytes().first() {
        Some(b'-') => (true, &s[1..]),
        Some(b'+') => (false, &s[1..]),
        _ => (false, s),
    };
    let (radix, digits) = match body.get(..2) {
        Some("0x" | "0X") => (16, &body[2..]),
        _ => (10, body),
    };
    if digits.is_empty() || !digits.chars().all(|c| c.is_digit(radix)) {
        return None;
    }
    let value = i128::from_str_radix(digits, radix).ok()?;
    let value = if negative { -value } else { value };
    i64::try_from(value).ok()
}

/// When a cue with [timing] (`00:01:02.500 --> …`) starts.
pub fn start_of(timing: &str) -> Micros {
    let first = dart_trim(timing).split(js_space).next().unwrap_or("");
    let parts: Vec<&str> = first.split(':').collect();
    let n = parts.len();
    let seconds = dart_double(parts[n - 1]).unwrap_or(0.0);
    let minutes = if n > 1 {
        dart_int(parts[n - 2]).unwrap_or(0)
    } else {
        0
    };
    let hours = if n > 2 {
        dart_int(parts[n - 3]).unwrap_or(0)
    } else {
        0
    };
    // Dart's round() goes half away from zero and stops at the ends of int.
    let millis = (seconds * 1000.0).round() as i64;
    millis
        .wrapping_mul(MS)
        .wrapping_add(minutes.wrapping_mul(60_000_000))
        .wrapping_add(hours.wrapping_mul(3_600_000_000))
}

/// When a cue with [timing] ends.
pub fn end_of(timing: &str) -> Micros {
    let mut parts = timing.split("-->");
    let first = parts.next().unwrap_or("");
    match parts.next() {
        Some(second) => start_of(second),
        None => start_of(first),
    }
}

/// `HH:MM:SS.mmm`.
pub fn stamp(at: Micros) -> String {
    let pad = |n: i64, width: usize| format!("{n:0>width$}");
    let hours = at / 3_600_000_000;
    let minutes = (at / 60_000_000).rem_euclid(60);
    let seconds = (at / 1_000_000).rem_euclid(60);
    let millis = (at / 1000).rem_euclid(1000);
    // Dart pads the sign along with the digits: -1 stays "-1".
    let hours = if hours < 0 {
        format!("{hours:>2}").replace(' ', "0")
    } else {
        pad(hours, 2)
    };
    format!(
        "{hours}:{}:{}.{}",
        pad(minutes, 2),
        pad(seconds, 2),
        pad(millis, 3)
    )
}

/// A cue's times, read once.
struct Timed {
    start: Micros,
    end: Micros,
}

fn times(cues: &[Cue]) -> Vec<Timed> {
    cues.iter()
        .map(|c| Timed {
            start: start_of(&c.timing),
            end: end_of(&c.timing),
        })
        .collect()
}

/// Where the sentences of [cues] start and end, as (first cue, cue after
/// the last): a cue runs on into the next while it has no sentence end, the
/// next follows within [GAP], and the sentence stays within [max_width] and
/// [max_length] on screen. One pass: the width adds up as cues join, and a
/// sentence end is looked for in the last cue only.
fn sentence_spans(
    cues: &[Cue],
    times: &[Timed],
    max_length: Micros,
    max_width: usize,
) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < cues.len() {
        let start = times[i].start;
        let mut end = times[i].end;
        let mut last = cues[i].text.as_str();
        let mut wide = width(last);
        let mut j = i + 1;
        while j < cues.len() && !sentence_end(last) {
            let next = &cues[j];
            let joined = wide + width(&next.text) + usize::from(spaced(last, &next.text));
            let next_end = times[j].end;
            if times[j].start.wrapping_sub(end) > GAP
                || next_end.wrapping_sub(start) > max_length
                || joined > max_width
            {
                break;
            }
            wide = joined;
            end = next_end;
            if !next.text.is_empty() {
                last = &next.text;
            }
            j += 1;
        }
        out.push((i, j));
        i = j;
    }
    out
}

/// The text of [cues] from [from] up to [to] as one line.
fn text_of(cues: &[Cue], from: usize, to: usize) -> String {
    cues[from + 1..to]
        .iter()
        .fold(cues[from].text.clone(), |a, c| join(&a, &c.text))
}

/// [cues] joined into sentences, each spanning from its first cue's start
/// to its last cue's end; a sentence of one cue keeps that cue's timing.
pub fn sentences(cues: &[Cue], max_length: Micros, max_width: usize) -> Vec<Cue> {
    let times = times(cues);
    sentence_spans(cues, &times, max_length, max_width)
        .into_iter()
        .map(|(i, j)| {
            if j == i + 1 {
                cues[i].clone()
            } else {
                Cue {
                    timing: format!("{} --> {}", stamp(times[i].start), stamp(times[j - 1].end)),
                    text: text_of(cues, i, j),
                }
            }
        })
        .collect()
}

/// How long and how wide a sentence to translate may grow.
pub const SENTENCE_TIME: Micros = 30_000 * MS;
pub const SENTENCE_WIDTH: usize = 400;

/// A cue a sentence's translation shows in: its timing, and how wide the
/// original is there, for [split_like].
#[derive(Debug, PartialEq, Serialize)]
pub struct Piece {
    pub timing: String,
    pub weight: usize,
}

/// What to translate in a track's own cues (not automatic captions, which
/// caption_lines.rs plans): its sentences, and for each the cues it shows
/// in.
#[derive(Debug, Default, Serialize)]
pub struct Plan {
    pub cues: Vec<Cue>,
    pub pieces: Vec<Vec<Piece>>,
}

pub fn plan(vtt: &str) -> Plan {
    let fragments = cues(vtt);
    let times = times(&fragments);
    let spans = sentence_spans(&fragments, &times, SENTENCE_TIME, SENTENCE_WIDTH);
    let cues = spans
        .iter()
        .map(|&(i, j)| Cue {
            timing: format!("{} --> {}", stamp(times[i].start), stamp(times[j - 1].end)),
            text: text_of(&fragments, i, j),
        })
        .collect();
    let pieces = spans
        .iter()
        .map(|&(i, j)| {
            fragments[i..j]
                .iter()
                .map(|f| Piece {
                    timing: f.timing.clone(),
                    weight: width(&f.text),
                })
                .collect()
        })
        .collect();
    Plan { cues, pieces }
}

/// How good a place to cut between [prev] and [next] is: 3 after a stop or
/// a comma, 2 at a space, 1 between two letters of a script written without
/// spaces, 0 nowhere.
fn quality(prev: char, next: char) -> u8 {
    if cjk_stop(prev) && !dart_space(next) {
        return 3;
    }
    if dart_space(next) {
        if dart_space(prev) {
            return 0;
        }
        let mut one = [0u8; 4];
        let prev = prev.encode_utf8(&mut one);
        return if clause_tail(prev) || sentence_end(prev) {
            3
        } else {
            2
        };
    }
    if joins_unspaced(prev, next) {
        return 1;
    }
    0
}

/// [text] cut into as many pieces as [weights], each about as wide as its
/// share: after punctuation where one is near, else at a space, else
/// between two letters of a script written without spaces. Just [text]
/// when there is nowhere to cut.
pub fn split_like(text: &str, weights: &[i64]) -> Vec<String> {
    let text = dart_trim(text);
    let total: i64 = weights.iter().fold(0i64, |a, &b| a.wrapping_add(b));
    if weights.len() < 2 || total <= 0 {
        return vec![text.to_owned()];
    }
    let chars: Vec<(usize, char)> = text.char_indices().collect();
    // Width of the text before each character.
    let mut before = Vec::with_capacity(chars.len() + 1);
    before.push(0i64);
    for &(_, c) in &chars {
        before.push(before[before.len() - 1] + char_width(c) as i64);
    }
    let full = before[chars.len()];
    let share = full as f64 / weights.len() as f64;
    let mut cuts: Vec<usize> = Vec::with_capacity(weights.len());
    let mut used = 0i64;
    for &weight in &weights[..weights.len() - 1] {
        used = used.wrapping_add(weight);
        let target = full.wrapping_mul(used) as f64 / total as f64;
        let mut best = None;
        let mut best_cost = f64::INFINITY;
        let last = cuts.last().copied().unwrap_or(0);
        for k in last + 1..chars.len() {
            let distance = (before[k] as f64 - target).abs();
            // Widths only grow from here: no later place can cost less.
            if before[k] as f64 > target && distance > best_cost {
                break;
            }
            let q = quality(chars[k - 1].1, chars[k].1);
            if q == 0 {
                continue;
            }
            let cost = distance + f64::from(3 - q) * 0.15 * share;
            if cost < best_cost {
                best_cost = cost;
                best = Some(k);
            }
        }
        let Some(best) = best else {
            return vec![text.to_owned()];
        };
        cuts.push(best);
    }
    let mut parts = Vec::with_capacity(weights.len());
    let mut from = 0;
    for k in cuts.into_iter().chain([chars.len()]) {
        let (a, b) = (chars[from].0, chars.get(k).map_or(text.len(), |c| c.0));
        let part = dart_trim(&text[a..b]);
        if part.is_empty() {
            return vec![text.to_owned()];
        }
        parts.push(part.to_owned());
        from = k;
    }
    parts
}

/// The [plan] of the track [vtt]: `{"cues": [[timing, text]…], "pieces":
/// [[[timing, weight]…]…]}`, with no cues when the track has none.
///
/// # Safety
/// [vtt] must point to [len] bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_vtt_plan(vtt: *const u8, len: usize) -> *mut c_char {
    let plan = plan(unsafe { outside(vtt, len) });
    let cues: Vec<(&str, &str)> = plan
        .cues
        .iter()
        .map(|c| (c.timing.as_str(), c.text.as_str()))
        .collect();
    let pieces: Vec<Vec<(&str, usize)>> = plan
        .pieces
        .iter()
        .map(|p| p.iter().map(|p| (p.timing.as_str(), p.weight)).collect())
        .collect();
    give_json(&serde_json::json!({"cues": cues, "pieces": pieces}))
}

/// [cues] of [vtt], or, with `"sentences": true`, the [sentences] they
/// make (`"time"` ms long and `"width"` wide at most), as [[timing, text]…];
/// null when [json] does not parse.
///
/// # Safety
/// [json] must point to [len] bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_vtt_cues(json: *const u8, len: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        #[serde(default)]
        vtt: String,
        #[serde(default)]
        sentences: bool,
        #[serde(default = "seven")]
        time: i64,
        #[serde(default = "ninety")]
        width: usize,
    }
    fn seven() -> i64 {
        7000
    }
    fn ninety() -> usize {
        90
    }
    let Ok(ask) = serde_json::from_str::<Ask>(unsafe { outside(json, len) }) else {
        return std::ptr::null_mut();
    };
    let mut cues = cues(&ask.vtt);
    if ask.sentences {
        cues = sentences(&cues, ask.time.saturating_mul(MS), ask.width);
    }
    let out: Vec<(&str, &str)> = cues
        .iter()
        .map(|c| (c.timing.as_str(), c.text.as_str()))
        .collect();
    give_json(&out)
}

/// [split_like] for each `[text, [weight…]]` of the JSON list [json]: the
/// pieces of each; null when it does not parse.
///
/// # Safety
/// [json] must point to [len] bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_vtt_split(json: *const u8, len: usize) -> *mut c_char {
    match serde_json::from_str::<Vec<(String, Vec<i64>)>>(unsafe { outside(json, len) }) {
        Ok(asks) => {
            let out: Vec<Vec<String>> = asks.iter().map(|(t, w)| split_like(t, w)).collect();
            give_json(&out)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn times_read_as_dart_did() {
        assert_eq!(start_of("00:01:02.500 --> 00:01:04.000"), 62_500_000);
        assert_eq!(
            end_of("00:01:02.500 --> 00:01:04.000 align:start"),
            64_000_000
        );
        assert_eq!(start_of("02.250"), 2_250_000);
        assert_eq!(start_of("1:00:00.000"), 3_600_000_000);
        assert_eq!(start_of("0x1:00.5"), 60_500_000);
        assert_eq!(start_of("junk"), 0);
        assert_eq!(stamp(3_723_004_000), "01:02:03.004");
        assert_eq!(stamp(-1_500_000), "00:00:59.500");
    }

    #[test]
    fn cues_keep_their_settings_and_lose_repeated_lines() {
        let vtt = "WEBVTT\n\n00:00:00.000 --> 00:00:01.000 line:10%\n<c>one</c>\n\n00:00:01.000 --> 00:00:02.000\none\ntwo &amp; three\n\n\n\n00:00:02.000 --> 00:00:03.000\ntwo &amp; three\n";
        let cues = cues(vtt);
        assert_eq!(cues[0].timing, "00:00:00.000 --> 00:00:01.000 line:10%");
        assert_eq!(
            cues.iter().map(|c| c.text.as_str()).collect::<Vec<_>>(),
            ["one", "two & three"]
        );
    }

    #[test]
    fn sentences_join_until_a_stop() {
        let vtt = "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nhello\n\n00:00:01.000 --> 00:00:02.000\nworld.\n\n00:00:02.000 --> 00:00:03.000\n你好\n\n00:00:03.000 --> 00:00:04.000\n世界。\n";
        let out = sentences(&cues(vtt), 7000 * MS, 90);
        assert_eq!(out[0].text, "hello world.");
        assert_eq!(out[0].timing, "00:00:00.000 --> 00:00:02.000");
        assert_eq!(out[1].text, "你好世界。");
        let plan = plan(vtt);
        assert_eq!(
            plan.pieces[0].iter().map(|p| p.weight).collect::<Vec<_>>(),
            [5, 6]
        );
    }

    #[test]
    fn translations_cut_where_the_cues_do() {
        assert_eq!(
            split_like("one two, three four", &[8, 10]),
            ["one two,", "three four"]
        );
        assert_eq!(
            split_like("我们今天，去公园散步", &[5, 5]),
            ["我们今天，", "去公园散步"]
        );
        assert_eq!(split_like("abcd", &[1, 1]), ["abcd"]);
    }

    #[test]
    fn no_cues_no_plan() {
        assert!(plan("not a track").cues.is_empty());
    }
}
