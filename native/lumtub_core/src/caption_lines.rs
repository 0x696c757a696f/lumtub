//! Automatic captions as the lines Lumtub shows them in: YouTube's rolling
//! fragments joined into sentences, a long sentence cut into lines after a
//! comma where one is near the end. The original and each translation of
//! it are shown in these same lines, so the two always say the same thing.
//! Every step is one pass over the fragments.

use std::ffi::c_char;

use crate::subtitles::{Cue, cues};
use crate::taste::{give, text};

/// How far apart two fragments of one sentence may be.
const GAP: i64 = 1200;
/// How long and how wide a sentence may grow.
const SENTENCE_TIME: i64 = 30_000;
const SENTENCE_WIDTH: usize = 400;
/// How long and how wide a line on screen may grow.
const LINE_TIME: i64 = 7_000;
const LINE_WIDTH: usize = 84;

/// One line: when it shows, which sentence it is part of, and its text.
#[derive(Debug, PartialEq)]
pub struct Line {
    pub start: u64,
    pub end: u64,
    pub sentence: usize,
    pub text: String,
}

/// A letter of a script written without spaces between words, or between
/// syllables as a line runs on: Thai, Lao, Tibetan, Burmese, Khmer, New Tai
/// Lue, kana, CJK, Myanmar extended, Hangul and CJK compatibility.
pub(crate) fn unspaced(c: char) -> bool {
    matches!(c as u32,
        0x0E00..=0x0EFF | 0x0F00..=0x0FFF | 0x1000..=0x109F | 0x1780..=0x17FF | 0x19E0..=0x19FF
        | 0x3040..=0x30FF | 0x31F0..=0x31FF | 0x3400..=0x9FFF | 0xAA60..=0xAA7F | 0xAC00..=0xD7AF
        | 0xF900..=0xFAFF)
}

fn hangul(c: char) -> bool {
    matches!(c as u32, 0x1100..=0x11FF | 0x3130..=0x318F | 0xAC00..=0xD7AF)
}

/// Whether [a] and [b] go together without a space. Korean is spaced
/// between words, and automatic captions break between words.
pub(crate) fn joins_unspaced(a: char, b: char) -> bool {
    unspaced(a) && unspaced(b) && !(hangul(a) && hangul(b))
}

/// How wide [text] shows, in Latin letters (UTF-16 units, as Dart counts):
/// a letter of a script written without spaces is about two.
pub(crate) fn width(text: &str) -> usize {
    text.chars()
        .map(|c| c.len_utf16() + usize::from(unspaced(c)))
        .sum()
}

/// Whether [a] and [b] are put together with a space.
pub(crate) fn spaced(a: &str, b: &str) -> bool {
    match (a.chars().next_back(), b.chars().next()) {
        (Some(x), Some(y)) => !joins_unspaced(x, y),
        _ => false,
    }
}

pub(crate) fn join(a: &str, b: &str) -> String {
    let mut out = String::with_capacity(a.len() + b.len() + 1);
    out.push_str(a);
    if spaced(a, b) {
        out.push(' ');
    }
    out.push_str(b);
    out
}

/// Whether [text] ends a sentence, closing quotes and brackets aside.
pub(crate) fn sentence_end(text: &str) -> bool {
    let core = text.trim_end_matches(['"', '”', '’', '」', '』', '»', ')', '）']);
    core.ends_with([
        '.', '!', '?', '。', '！', '？', '…', '؟', '۔', '।', '॥', '։', '።', '။', '།', '‼', '⁇',
    ])
}

/// Whether [text] ends after a clause, where a line may break.
pub(crate) fn clause_tail(text: &str) -> bool {
    text.ends_with([
        ';', ':', ',', '；', '：', '，', '、', '…', ')', '）', '」', '』', '"', '”', '»', '،', '؛',
        '፣', '၊',
    ])
}

fn ms(t: u64) -> i64 {
    i64::try_from(t).unwrap_or(i64::MAX)
}

/// Where the sentences of [cues] start and end, as (first, after the last).
fn sentence_spans(cues: &[Cue]) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < cues.len() {
        let start = ms(cues[i].start);
        let mut end = ms(cues[i].end);
        let mut wide = width(&cues[i].text);
        let mut last = cues[i].text.as_str();
        let mut j = i + 1;
        while j < cues.len() && !sentence_end(last) {
            let next = &cues[j];
            let joined = wide + width(&next.text) + usize::from(spaced(last, &next.text));
            let next_end = ms(next.end);
            if ms(next.start) - end > GAP
                || next_end - start > SENTENCE_TIME
                || joined > SENTENCE_WIDTH
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

/// Sentence [from]..[to] of [cues] as lines: all of it when it fits
/// [LINE_WIDTH] and [LINE_TIME], else lines that do, each ending after a
/// comma where one is near the end.
fn line_spans(cues: &[Cue], from: usize, to: usize, out: &mut Vec<(usize, usize)>) {
    let mut i = from;
    while i < to {
        let start = ms(cues[i].start);
        let mut wide = width(&cues[i].text);
        let mut last = cues[i].text.as_str();
        let mut j = i + 1;
        let mut comma = None;
        let mut comma_width = 0;
        while j < to {
            let joined = wide + width(&cues[j].text) + usize::from(spaced(last, &cues[j].text));
            if joined > LINE_WIDTH || ms(cues[j].end) - start > LINE_TIME {
                break;
            }
            if clause_tail(last) {
                comma = Some(j);
                comma_width = wide;
            }
            wide = joined;
            if !cues[j].text.is_empty() {
                last = &cues[j].text;
            }
            j += 1;
        }
        if let Some(c) = comma
            && j < to
            && c > i
            && comma_width * 2 >= wide
        {
            j = c;
        }
        out.push((i, j));
        i = j;
    }
}

/// The lines automatic captions [cues] show in. A line ends where the next
/// begins when the fragments run on over it, so two never show at once.
pub fn lines_of(cues: &[Cue]) -> Vec<Line> {
    let mut spans = Vec::new();
    let mut sentence_of = Vec::new();
    for (s, (from, to)) in sentence_spans(cues).into_iter().enumerate() {
        let before = spans.len();
        line_spans(cues, from, to, &mut spans);
        sentence_of.resize(spans.len().max(before), s);
    }
    let mut out = Vec::with_capacity(spans.len());
    for (k, &(a, b)) in spans.iter().enumerate() {
        let start = cues[a].start;
        let mut end = cues[b - 1].end;
        if let Some(&(next, _)) = spans.get(k + 1) {
            let next = cues[next].start;
            if next < end && next > start {
                end = next;
            }
        }
        let mut text = cues[a].text.clone();
        for c in &cues[a + 1..b] {
            text = join(&text, &c.text);
        }
        out.push(Line {
            start,
            end,
            sentence: sentence_of[k],
            text,
        });
    }
    out
}

/// YouTube's translation [translated] of automatic captions [original], in
/// the lines the original shows in: each translated fragment goes into the
/// line it starts in. Lines nothing went into are left out.
pub fn translation_lines(original: &[Cue], translated: &[Cue]) -> Vec<Line> {
    if original.is_empty() || translated.is_empty() {
        return lines_of(translated);
    }
    let mut lines = lines_of(original);
    let mut texts = vec![String::new(); lines.len()];
    let mut k = 0;
    for piece in translated {
        while k + 1 < lines.len() && lines[k + 1].start <= piece.start {
            k += 1;
        }
        texts[k] = if texts[k].is_empty() {
            piece.text.clone()
        } else {
            join(&texts[k], &piece.text)
        };
    }
    for (line, text) in lines.iter_mut().zip(texts) {
        line.text = text;
    }
    lines.retain(|l| !l.text.is_empty());
    lines
}

fn json(lines: Vec<Line>) -> String {
    serde_json::Value::Array(
        lines
            .into_iter()
            .map(|l| serde_json::json!([l.start, l.end, l.sentence, l.text]))
            .collect(),
    )
    .to_string()
}

/// [lines_of] the cues of [source] for Dart, as JSON
/// `[[start_ms, end_ms, sentence, "text"], …]`. Free the text with
/// `lumtub_string_free`.
///
/// # Safety
/// [source] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_caption_lines(source: *const u8, length: usize) -> *mut c_char {
    give(json(lines_of(&cues(unsafe { text(source, length) }))))
}

/// [translation_lines] for Dart, as [lumtub_caption_lines] gives.
///
/// # Safety
/// [original] and [translated] must point to their lengths of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_caption_translation_lines(
    original: *const u8,
    original_length: usize,
    translated: *const u8,
    translated_length: usize,
) -> *mut c_char {
    let original = cues(unsafe { text(original, original_length) });
    let translated = cues(unsafe { text(translated, translated_length) });
    give(json(translation_lines(&original, &translated)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cue(start: u64, end: u64, text: &str) -> Cue {
        Cue {
            start,
            end,
            text: text.into(),
        }
    }

    #[test]
    fn sentences_and_lines_broken_at_commas() {
        let words = [
            "Io conoscevo tutte le parole,",
            "tutte, ma ho pensato così tanto alla",
            "risposta",
            "che lui ha ripetuto la domanda",
            "più lentamente,",
            "molto più lentamente,",
            "come se stesse parlando con una bambina.",
            "Io ho sorriso.",
        ];
        let cues: Vec<Cue> = words
            .iter()
            .enumerate()
            .map(|(i, w)| cue(77_000 + i as u64 * 2000, 80_000 + i as u64 * 2000, w))
            .collect();
        let lines = lines_of(&cues);
        let texts: Vec<&str> = lines.iter().map(|l| l.text.as_str()).collect();
        assert_eq!(
            texts,
            [
                "Io conoscevo tutte le parole, tutte, ma ho pensato così tanto alla risposta",
                "che lui ha ripetuto la domanda più lentamente,",
                "molto più lentamente, come se stesse parlando con una bambina.",
                "Io ho sorriso.",
            ]
        );
        for w in lines.windows(2) {
            assert_eq!(w[0].end, w[1].start);
        }
        assert_eq!(
            lines.iter().map(|l| l.sentence).collect::<Vec<_>>(),
            [0, 0, 0, 1]
        );
    }

    #[test]
    fn scripts_join_as_they_are_written() {
        let ko = lines_of(&[
            cue(0, 1000, "오늘은 자막에"),
            cue(1000, 2000, "대해 이야기"),
        ]);
        assert_eq!(ko[0].text, "오늘은 자막에 대해 이야기");
        let zh = lines_of(&[cue(0, 1000, "今天我们"), cue(1000, 2000, "来聊字幕")]);
        assert_eq!(zh[0].text, "今天我们来聊字幕");
        let hi = lines_of(&[cue(0, 1000, "यह लंबी कहानी है।"), cue(1000, 2000, "ठीक है।")]);
        assert_eq!(hi.len(), 2);
        let ar = lines_of(&[cue(0, 1000, "إنها قصة طويلة؟"), cue(1000, 2000, "حسنا.")]);
        assert_eq!(ar.len(), 2);
    }

    #[test]
    fn a_translation_goes_into_the_lines_of_its_original() {
        let original = [
            cue(0, 2000, "uno."),
            cue(2000, 4000, "due"),
            cue(4000, 6000, "tre."),
        ];
        let translated = [
            cue(0, 2000, "一。"),
            cue(2000, 4000, ""),
            cue(4000, 6000, "二三。"),
        ];
        let lines = translation_lines(&original, &translated);
        let shown = lines_of(&original);
        assert_eq!(lines.len(), shown.len());
        assert!(
            lines
                .iter()
                .zip(&shown)
                .all(|(a, b)| a.start == b.start && a.end == b.end)
        );
    }

    #[test]
    fn many_fragments_take_one_pass() {
        let cues: Vec<Cue> = (0..200_000u64)
            .map(|i| cue(i * 500, i * 500 + 600, "parola"))
            .collect();
        let started = std::time::Instant::now();
        let lines = lines_of(&cues);
        assert!(lines.iter().all(|l| width(&l.text) <= LINE_WIDTH));
        assert!(started.elapsed() < std::time::Duration::from_secs(5));
    }
}
