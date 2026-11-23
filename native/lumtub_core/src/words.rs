//! Subtitle lines cut into the words a tap looks up.
//!
//! Languages written with spaces are cut here: French and Italian
//! elision (`l'amico`, `j'ai`) and French inverted pronouns
//! (`parlez-vous`, `a-t-il`) and Portuguese hyphenated pronouns
//! (`dá-me`, `fazê-lo`) become separate words, each with its own place on
//! screen. Pronouns joined to the end of a Spanish or Italian
//! word (`hacerlo`, `dammelo`) stay one word on screen; the dictionary
//! looks for the word under them only when it does not know the whole
//! ([without_pronouns]).
//!
//! Japanese, Korean and Chinese are cut by Lindera with a dictionary the
//! learning pack downloads (ipadic, ko-dic, jieba), read in place from
//! disk. A Japanese verb keeps its endings and a Korean word its
//! particles, as a learner reads them; the key looked up is the word's
//! dictionary form.
//!
//! Places are in UTF-16 code units, as Flutter counts text.

use std::borrow::Cow;
use std::collections::HashMap;
use std::os::raw::c_char;
use std::sync::{Mutex, OnceLock};

use lindera::dictionary::load_dictionary;
use lindera::mode::Mode;
use lindera::segmenter::Segmenter;
use serde::{Deserialize, Serialize};

use crate::taste::{give_json, text};

/// Most lines cut in one call.
const MOST_LINES: usize = 2000;

/// A word: where it is, the keys to look it up by (best first), and its
/// reading when the line shows one above it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Word {
    #[serde(rename = "s")]
    pub start: usize,
    #[serde(rename = "e")]
    pub end: usize,
    #[serde(rename = "k")]
    pub keys: Vec<String>,
    #[serde(rename = "r", skip_serializing_if = "Option::is_none")]
    pub reading: Option<String>,
}

/// A word found in bytes, before places become UTF-16.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Piece {
    start: usize,
    end: usize,
    keys: Vec<String>,
    reading: Option<String>,
}

impl Piece {
    fn new(start: usize, end: usize, key: String) -> Piece {
        Piece {
            start,
            end,
            keys: vec![key],
            reading: None,
        }
    }
}

/// [text] as a lookup key: curly apostrophes made straight. The text on
/// screen is never changed, so places stay right.
fn key_of(text: &str) -> String {
    text.chars()
        .map(|c| match c {
            '’' | '‘' | 'ʼ' => '\'',
            other => other,
        })
        .collect()
}

fn is_apostrophe(c: char) -> bool {
    matches!(c, '\'' | '’' | 'ʼ')
}

fn is_word_char(c: char) -> bool {
    c.is_alphabetic() || is_mark(c) || is_apostrophe(c) || c == '-'
}

/// Combining marks, such as the stress mark Russian learners' texts carry.
fn is_mark(c: char) -> bool {
    matches!(c as u32, 0x0300..=0x036F | 0x1AB0..=0x1AFF | 0x1DC0..=0x1DFF | 0x20D0..=0x20FF)
}

/// Cuts a line of a language written with spaces. [known] tells whether
/// the dictionary has a whole word, so `aujourd'hui` and `c'est-à-dire`
/// stay whole.
fn cut_spaced(language: &str, line: &str, known: &dyn Fn(&str) -> bool) -> Vec<Piece> {
    let mut out = Vec::new();
    let mut chars = line.char_indices().peekable();
    while let Some((at, c)) = chars.next() {
        // [Music], [Applaus]: what is heard, not said.
        if c == '['
            && let Some(close) = line[at..].find(']').filter(|n| *n <= 60)
        {
            while chars.peek().is_some_and(|(i, _)| *i <= at + close) {
                chars.next();
            }
            continue;
        }
        if !is_word_char(c) {
            continue;
        }
        let mut end = at + c.len_utf8();
        while let Some(&(i, next)) = chars.peek() {
            if !is_word_char(next) {
                break;
            }
            end = i + next.len_utf8();
            chars.next();
        }
        word(language, line, at, end, known, &mut out);
    }
    out
}

/// Italian words cut short with an apostrophe: `po'`, `fa'`.
fn italian_apocope(lower: &str) -> bool {
    matches!(
        lower,
        "po'" | "da'" | "di'" | "fa'" | "sta'" | "va'" | "mo'" | "be'" | "to'"
    )
}

fn word(
    language: &str,
    line: &str,
    mut start: usize,
    mut end: usize,
    known: &dyn Fn(&str) -> bool,
    out: &mut Vec<Piece>,
) {
    while let Some(c) = line[start..end].chars().next() {
        if c == '-' || is_apostrophe(c) || is_mark(c) {
            start += c.len_utf8();
        } else {
            break;
        }
    }
    while let Some(c) = line[start..end].chars().next_back() {
        let apocope = is_apostrophe(c)
            && language == "it"
            && italian_apocope(&key_of(&line[start..end]).to_lowercase());
        if c == '-' || (is_apostrophe(c) && !apocope) {
            end -= c.len_utf8();
        } else {
            break;
        }
    }
    if start >= end {
        return;
    }
    let whole = key_of(&line[start..end]);
    let joined = whole.contains(['\'', '-']);
    if !joined || !matches!(language, "fr" | "it" | "pt") || known(&whole) {
        out.push(Piece::new(start, end, whole));
        return;
    }
    if language == "pt" {
        if whole.contains('-') {
            hyphen_parts(line, start, end, out);
        } else {
            out.push(Piece::new(start, end, whole));
        }
        return;
    }
    if language == "fr" && whole.contains('-') && french_inversion(line, start, end, known, out) {
        return;
    }
    elision(language, line, start, end, known, out);
}

/// `l'amico`, `qu'il`, `dell'anno`: the article or word cut short, then
/// the rest, each a word of its own.
fn elision(
    language: &str,
    line: &str,
    mut start: usize,
    end: usize,
    known: &dyn Fn(&str) -> bool,
    out: &mut Vec<Piece>,
) {
    while start < end {
        let rest = &line[start..end];
        let whole = key_of(rest);
        if known(&whole) {
            break;
        }
        let Some((at, mark)) = rest.char_indices().find(|(_, c)| is_apostrophe(*c)) else {
            break;
        };
        let split = start + at + mark.len_utf8();
        let left = key_of(&rest[..at]).to_lowercase();
        if split >= end || !elided(language, &left) {
            break;
        }
        out.push(Piece::new(
            start,
            split,
            format!("{}'", key_of(&rest[..at])),
        ));
        start = split;
    }
    if start < end {
        out.push(Piece::new(start, end, key_of(&line[start..end])));
    }
}

fn elided(language: &str, left: &str) -> bool {
    match language {
        "fr" => matches!(
            left,
            "l" | "d"
                | "j"
                | "m"
                | "t"
                | "s"
                | "c"
                | "n"
                | "qu"
                | "jusqu"
                | "lorsqu"
                | "puisqu"
                | "quoiqu"
                | "presqu"
        ),
        "it" => matches!(
            left,
            "l" | "d"
                | "un"
                | "c"
                | "s"
                | "m"
                | "t"
                | "v"
                | "n"
                | "all"
                | "dall"
                | "dell"
                | "nell"
                | "sull"
                | "coll"
                | "quell"
                | "quest"
                | "bell"
                | "buon"
                | "grand"
                | "sant"
                | "mezz"
                | "tutt"
                | "anch"
                | "com"
                | "dov"
                | "cos"
                | "senz"
        ),
        _ => false,
    }
}

/// `dá-me`, `fazê-lo`, `dir-te-ei`: a Portuguese verb and the pronouns
/// joined to it by hyphens, each a word of its own. Called only when the
/// dictionary does not know the whole, so `guarda-chuva` stays whole.
fn hyphen_parts(line: &str, start: usize, end: usize, out: &mut Vec<Piece>) {
    let mut from = start;
    for (i, c) in line[start..end].char_indices() {
        if c == '-' {
            if start + i > from {
                out.push(Piece::new(from, start + i, key_of(&line[from..start + i])));
            }
            from = start + i + 1;
        }
    }
    if end > from {
        out.push(Piece::new(from, end, key_of(&line[from..end])));
    }
}

/// `parlez-vous`, `a-t-il`, `donne-le-moi`: the verb and its pronouns as
/// words of their own, the `t` between them left out. Other joined words
/// (`week-end`, `peut-être`) stay whole.
fn french_inversion(
    line: &str,
    start: usize,
    end: usize,
    known: &dyn Fn(&str) -> bool,
    out: &mut Vec<Piece>,
) -> bool {
    const PRONOUNS: &[&str] = &[
        "je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles", "ce", "ci", "là", "moi",
        "toi", "lui", "leur", "le", "la", "les", "y", "en",
    ];
    let mut parts = Vec::new();
    let mut from = start;
    for (i, c) in line[start..end].char_indices() {
        if c == '-' {
            if start + i > from {
                parts.push((from, start + i));
            }
            from = start + i + 1;
        }
    }
    if end > from {
        parts.push((from, end));
    }
    let last = parts
        .last()
        .map(|(s, e)| key_of(&line[*s..*e]).to_lowercase());
    if parts.len() < 2 || !last.is_some_and(|l| PRONOUNS.contains(&l.as_str())) {
        return false;
    }
    for (s, e) in parts {
        if line[s..e].eq_ignore_ascii_case("t") {
            continue;
        }
        elision("fr", line, s, e, known, out);
    }
    true
}

/// What a Spanish or Italian word may be under the pronouns joined to
/// its end, most likely first: `hacerlo` → `hacer`, `dímelo` → `di`,
/// `vámonos` → `vamos`, `parlarne` → `parlare`, `dammelo` → `dare`.
/// Only asked when the dictionary does not know the whole word.
pub fn without_pronouns(language: &str, word: &str) -> Vec<String> {
    let word = word.to_lowercase();
    match language {
        "es" => spanish_stems(&unaccented(&word)),
        "it" => italian_stems(&word),
        "pt" => portuguese_verb(&word),
        _ => Vec::new(),
    }
}

fn unaccented(word: &str) -> String {
    word.chars()
        .map(|c| match c {
            'á' => 'a',
            'é' => 'e',
            'í' => 'i',
            'ó' => 'o',
            'ú' => 'u',
            other => other,
        })
        .collect()
}

fn push_new(out: &mut Vec<String>, stem: String) {
    if !out.contains(&stem) {
        out.push(stem);
    }
}

fn spanish_stems(word: &str) -> Vec<String> {
    const PRONOUNS: &[&str] = &[
        "selos", "selas", "selo", "sela", "melos", "melas", "melo", "mela", "telos", "telas",
        "telo", "tela", "noslos", "noslas", "noslo", "nosla", "oslos", "oslas", "oslo", "osla",
        "los", "las", "les", "nos", "lo", "la", "le", "me", "te", "se", "os",
    ];
    let mut out = Vec::new();
    for pronoun in PRONOUNS {
        let Some(stem) = word.strip_suffix(pronoun) else {
            continue;
        };
        if stem.chars().count() < 2 {
            continue;
        }
        push_new(&mut out, stem.to_string());
        // vámonos → vamos, sentémonos → sentemos.
        if (pronoun.starts_with("nos") || pronoun.starts_with("se")) && stem.ends_with("mo") {
            push_new(&mut out, format!("{stem}s"));
        }
        // sentaos → sentad.
        if *pronoun == "os" && stem.ends_with(['a', 'e', 'i']) {
            push_new(&mut out, format!("{stem}d"));
        }
    }
    out
}

/// A Portuguese infinitive that lost its `r` before `-lo`, `-la`, `-los`,
/// `-las`: `fazê` → `fazer`, `comprá` → `comprar`, `parti` → `partir`,
/// `pô` → `pôr`.
fn portuguese_verb(word: &str) -> Vec<String> {
    let Some(last) = word.chars().last() else {
        return Vec::new();
    };
    let stem = &word[..word.len() - last.len_utf8()];
    if stem.chars().count() < 1 {
        return Vec::new();
    }
    match last {
        'á' => vec![format!("{stem}ar")],
        'ê' => vec![format!("{stem}er")],
        'í' | 'i' => vec![format!("{stem}ir")],
        'ô' if stem == "p" => vec!["pôr".to_string()],
        'ô' => vec![format!("{stem}or")],
        _ => Vec::new(),
    }
}

fn italian_stems(word: &str) -> Vec<String> {
    const PRONOUNS: &[&str] = &[
        "glielo", "gliela", "glieli", "gliele", "gliene", "melo", "mela", "meli", "mele", "mene",
        "telo", "tela", "teli", "tele", "tene", "celo", "cela", "celi", "cele", "cene", "velo",
        "vela", "veli", "vele", "vene", "selo", "sela", "seli", "sele", "sene", "gli", "mi", "ti",
        "si", "ci", "vi", "lo", "la", "li", "le", "ne",
    ];
    let mut out = Vec::new();
    for pronoun in PRONOUNS {
        let Some(stem) = word.strip_suffix(pronoun) else {
            continue;
        };
        if stem.chars().count() < 2 {
            continue;
        }
        // An infinitive loses its -e: parlarne → parlare, porlo → porre.
        if stem.ends_with('r') && stem.chars().count() >= 3 {
            push_new(&mut out, format!("{stem}e"));
            push_new(&mut out, format!("{stem}re"));
        }
        // dammelo, dimmi, fallo, stacci, vacci: the pronoun's first letter doubled.
        if let Some(first) = pronoun.chars().next()
            && let Some(short) = stem.strip_suffix(first)
        {
            let verb = match short {
                "da" => Some("dare"),
                "di" => Some("dire"),
                "fa" => Some("fare"),
                "sta" => Some("stare"),
                "va" => Some("andare"),
                _ => None,
            };
            if let Some(verb) = verb {
                push_new(&mut out, verb.to_string());
            }
        }
        // guardandola → guardando, andiamoci → andiamo.
        push_new(&mut out, stem.to_string());
    }
    out
}

/// Which Lindera dictionary a segmenter has.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Kind {
    Ipadic,
    KoDic,
    Jieba,
}

struct Cutter {
    kind: Kind,
    segmenter: Segmenter,
}

impl Cutter {
    fn open(language: &str, path: &str) -> Result<Cutter, String> {
        let kind = match language {
            "ja" => Kind::Ipadic,
            "ko" => Kind::KoDic,
            "zh" => Kind::Jieba,
            other => return Err(format!("no segmenter for {other}")),
        };
        let dictionary = load_dictionary(path).map_err(|e| format!("{path}: {e}"))?;
        Ok(Cutter {
            kind,
            segmenter: Segmenter::new(Mode::Normal, dictionary, None),
        })
    }

    fn cut(&self, line: &str) -> Vec<Piece> {
        let Ok(mut tokens) = self.segmenter.segment(Cow::Borrowed(line)) else {
            return Vec::new();
        };
        let morphemes: Vec<Morpheme> = tokens
            .iter_mut()
            .filter(|t| !t.surface.trim().is_empty())
            .map(|t| Morpheme {
                start: t.byte_start,
                end: t.byte_end,
                surface: t.surface.to_string(),
                details: t.details().iter().map(|s| s.to_string()).collect(),
            })
            .collect();
        match self.kind {
            Kind::Ipadic => japanese(&morphemes),
            Kind::KoDic => korean(line, &morphemes),
            Kind::Jieba => chinese(&morphemes),
        }
    }
}

/// A token as Lindera gives it, owned.
#[derive(Debug, Clone)]
struct Morpheme {
    start: usize,
    end: usize,
    surface: String,
    details: Vec<String>,
}

impl Morpheme {
    /// Detail [i], or "" where the dictionary has none (`*`).
    fn at(&self, i: usize) -> &str {
        match self.details.get(i).map(String::as_str) {
            Some("*") | None => "",
            Some(value) => value,
        }
    }
}

fn punctuation(text: &str) -> bool {
    text.chars().all(|c| !c.is_alphanumeric())
}

fn has_kanji(text: &str) -> bool {
    text.chars()
        .any(|c| matches!(c as u32, 0x4E00..=0x9FFF | 0x3400..=0x4DBF | 0xF900..=0xFAFF | 0x20000..=0x323AF | 0x3005))
}

fn hiragana(katakana: &str) -> String {
    katakana
        .chars()
        .map(|c| match c as u32 {
            code @ 0x30A1..=0x30F6 => char::from_u32(code - 0x60).unwrap_or(c),
            _ => c,
        })
        .collect()
}

/// IPADIC details: 0 part of speech, 1 its kind, 6 dictionary form,
/// 7 reading. A verb or adjective takes the auxiliaries and `て` after
/// it (`食べました`), a noun taking する takes it (`勉強します`); the
/// key is the first word's dictionary form.
fn japanese(morphemes: &[Morpheme]) -> Vec<Piece> {
    let mut out: Vec<Piece> = Vec::new();
    // Whether the last word can take endings, and whether it is a noun
    // that can take する.
    let mut open = false;
    let mut suru_noun = false;
    let mut last_end = usize::MAX;
    for m in morphemes {
        let pos = m.at(0);
        let kind = m.at(1);
        if pos == "記号" || punctuation(&m.surface) {
            open = false;
            continue;
        }
        let touching = m.start == last_end;
        let ending = pos == "助動詞"
            || (pos == "動詞" && matches!(kind, "非自立" | "接尾"))
            || (pos == "形容詞" && kind == "非自立")
            || (pos == "助詞" && kind == "接続助詞" && matches!(m.surface.as_str(), "て" | "で"));
        let suru = pos == "動詞" && m.at(6) == "する";
        if let Some(last) = out.last_mut()
            && touching
            && ((open && ending) || (suru_noun && suru))
        {
            if suru_noun && suru {
                let noun = last.keys[0].clone();
                last.keys.insert(0, format!("{noun}する"));
            }
            last.end = m.end;
            if let Some(reading) = &mut last.reading {
                reading.push_str(&hiragana(if m.at(7).is_empty() {
                    &m.surface
                } else {
                    m.at(7)
                }));
            }
            open = true;
            suru_noun = false;
            last_end = m.end;
            continue;
        }
        let base = m.at(6);
        let key = if base.is_empty() {
            m.surface.clone()
        } else {
            base.to_string()
        };
        let mut piece = Piece::new(m.start, m.end, key);
        if !m.at(7).is_empty() {
            piece.reading = Some(hiragana(m.at(7)));
        }
        if piece.keys[0] != m.surface {
            piece.keys.push(m.surface.clone());
        }
        out.push(piece);
        open = matches!(pos, "動詞" | "形容詞" | "助動詞");
        suru_noun = pos == "名詞" && kind == "サ変接続";
        last_end = m.end;
    }
    // A reading goes above words with kanji only.
    for piece in &mut out {
        let surface_has_kanji = piece.keys.iter().any(|k| has_kanji(k));
        if !surface_has_kanji {
            piece.reading = None;
        }
    }
    out
}

/// ko-dic details: 0 part of speech, 4 type (`Inflect` for a form made of
/// several morphemes), 7 those morphemes (`춥/VA/*+어서/EC/*`). A word is
/// what stands between spaces, particles and endings included; its keys
/// are the content word's dictionary form, such as `춥다` for `추워서`
/// or `공부하다` then `공부` for `공부했어요`.
fn korean(line: &str, morphemes: &[Morpheme]) -> Vec<Piece> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < morphemes.len() {
        // The morphemes of one spaced word, punctuation left out.
        let mut group: Vec<&Morpheme> = Vec::new();
        let mut j = i;
        while j < morphemes.len() {
            let m = &morphemes[j];
            if let Some(last) = group.last()
                && line[last.end..m.start].chars().any(char::is_whitespace)
            {
                break;
            }
            let pos = m.at(0);
            if matches!(pos, "SF" | "SE" | "SSO" | "SSC" | "SC" | "SY") || punctuation(&m.surface) {
                j += 1;
                if group.is_empty() {
                    continue;
                }
                break;
            }
            group.push(m);
            j += 1;
        }
        i = j.max(i + 1);
        let (Some(first), Some(last)) = (group.first(), group.last()) else {
            continue;
        };
        let mut piece = Piece::new(first.start, last.end, String::new());
        piece.keys = korean_keys(&group);
        out.push(piece);
    }
    out
}

fn korean_keys(group: &[&Morpheme]) -> Vec<String> {
    let mut keys = Vec::new();
    let surface: String = group.iter().map(|m| m.surface.as_str()).collect();
    let predicate = |pos: &str| matches!(pos, "VV" | "VA" | "VX" | "VCP" | "VCN" | "XSV" | "XSA");
    // The first morpheme of each token, with its own part of speech:
    // `했` is `하/XSV/*+았/EP/*`.
    let parts: Vec<(String, String, &Morpheme)> = group
        .iter()
        .map(|m| {
            if m.at(4) == "Inflect" && !m.at(7).is_empty() {
                let first = m.at(7).split('+').next().unwrap_or("");
                let mut fields = first.split('/');
                let stem = fields.next().unwrap_or("").to_string();
                let pos = fields.next().unwrap_or("").to_string();
                (stem, pos, *m)
            } else {
                (
                    m.surface.clone(),
                    m.at(0).split('+').next().unwrap_or("").to_string(),
                    *m,
                )
            }
        })
        .collect();
    if let Some((stem, pos, _)) = parts.first() {
        if predicate(pos) {
            keys.push(format!("{stem}다"));
        } else {
            // 공부 + 하: 공부하다 before 공부.
            if let Some((next, next_pos, _)) = parts.get(1)
                && matches!(next_pos.as_str(), "XSV" | "XSA")
            {
                keys.push(format!("{stem}{next}다"));
            }
            keys.push(stem.clone());
        }
    }
    if !keys.contains(&surface) {
        keys.push(surface);
    }
    keys.retain(|k| !k.is_empty() && k != "다");
    keys
}

/// jieba details: 0 part of speech (`x`, `w`: punctuation).
fn chinese(morphemes: &[Morpheme]) -> Vec<Piece> {
    morphemes
        .iter()
        .filter(|m| !matches!(m.at(0), "x" | "w") && !punctuation(&m.surface))
        .map(|m| Piece::new(m.start, m.end, m.surface.clone()))
        .collect()
}

fn cutters() -> &'static Mutex<HashMap<String, Cutter>> {
    static OPEN: OnceLock<Mutex<HashMap<String, Cutter>>> = OnceLock::new();
    OPEN.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Byte places in [line] as UTF-16 places.
fn utf16_places(line: &str, pieces: Vec<Piece>) -> Vec<Word> {
    let mut map = Vec::with_capacity(line.len() + 1);
    let mut units = 0;
    for c in line.chars() {
        for _ in 0..c.len_utf8() {
            map.push(units);
        }
        units += c.len_utf16();
    }
    map.push(units);
    pieces
        .into_iter()
        .filter(|p| p.start < p.end && p.end <= line.len())
        .map(|p| Word {
            start: map[p.start],
            end: map[p.end],
            keys: p.keys,
            reading: p.reading,
        })
        .collect()
}

/// The words of [line] in [language]; None when the language needs a
/// segmenter that is not open.
pub fn words(language: &str, line: &str) -> Option<Vec<Word>> {
    let lexicons = crate::lexicon::open_lexicons().lock().ok();
    let lexicon = lexicons.as_ref().and_then(|open| open.get(language));
    let known = |key: &str| lexicon.is_some_and(|l| l.knows(key));
    let pieces = match language {
        "ja" | "ko" | "zh" => {
            let open = cutters().lock().ok()?;
            let cutter = open.get(language)?;
            let mut pieces = cutter.cut(line);
            // Keys the dictionary knows first.
            if let Some(lexicon) = lexicon {
                for piece in &mut pieces {
                    if let Some(at) = piece.keys.iter().position(|k| lexicon.knows(k))
                        && at > 0
                    {
                        let key = piece.keys.remove(at);
                        piece.keys.insert(0, key);
                    }
                }
            }
            pieces
        }
        _ => cut_spaced(language, line, &known),
    };
    Some(utf16_places(line, pieces))
}

#[derive(Serialize)]
struct Failed {
    error: String,
}

/// Opens [json]'s `{language, path}` Lindera dictionary folder as the
/// segmenter for Japanese (ipadic), Korean (ko-dic) or Chinese (jieba).
/// Answers `{}` or `{"error"}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_words_open(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        language: String,
        path: String,
    }
    let answer = serde_json::from_str::<Ask>(unsafe { text(json, length) })
        .map_err(|e| e.to_string())
        .and_then(|ask| {
            let cutter = Cutter::open(&ask.language, &ask.path)?;
            cutters()
                .lock()
                .map_err(|_| "segmenters poisoned".to_string())?
                .insert(ask.language, cutter);
            Ok(())
        });
    match answer {
        Ok(()) => give_json(&serde_json::json!({})),
        Err(error) => give_json(&Failed { error }),
    }
}

/// Closes [json]'s `{language}` segmenter, so its folder can be replaced.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_words_close(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        language: String,
    }
    if let Ok(ask) = serde_json::from_str::<Ask>(unsafe { text(json, length) })
        && let Ok(mut open) = cutters().lock()
    {
        open.remove(&ask.language);
    }
    give_json(&serde_json::json!({}))
}

/// Cuts [json]'s `{language, lines}` into words. Answers `{"lines":
/// [[{s, e, k, r}, …], …]}`, places in UTF-16 units, or `{"error"}` when
/// the language needs a segmenter that is not open.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_words(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        language: String,
        lines: Vec<String>,
    }
    #[derive(Serialize)]
    struct Answer {
        lines: Vec<Vec<Word>>,
    }
    let answer = serde_json::from_str::<Ask>(unsafe { text(json, length) })
        .map_err(|e| e.to_string())
        .and_then(|ask| {
            let mut lines = Vec::new();
            for line in ask.lines.iter().take(MOST_LINES) {
                lines.push(
                    words(&ask.language, line)
                        .ok_or_else(|| format!("no segmenter for {}", ask.language))?,
                );
            }
            Ok(Answer { lines })
        });
    match answer {
        Ok(found) => give_json(&found),
        Err(error) => give_json(&Failed { error }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spaced(language: &str, line: &str, known: &[&str]) -> Vec<(String, String)> {
        let known = |k: &str| known.contains(&k.to_lowercase().as_str());
        cut_spaced(language, line, &known)
            .into_iter()
            .map(|p| (line[p.start..p.end].to_string(), p.keys[0].clone()))
            .collect()
    }

    fn texts(cut: &[(String, String)]) -> Vec<&str> {
        cut.iter().map(|(t, _)| t.as_str()).collect()
    }

    #[test]
    fn cuts_elision_and_inversion() {
        assert_eq!(
            texts(&spaced(
                "fr",
                "J’ai vu l'homme, a-t-il dit. Parlez-vous ?",
                &[]
            )),
            [
                "J’", "ai", "vu", "l'", "homme", "a", "il", "dit", "Parlez", "vous"
            ]
        );
        assert_eq!(spaced("fr", "J’ai", &[])[0].1, "J'");
        assert_eq!(
            texts(&spaced(
                "fr",
                "aujourd'hui, c'est-à-dire un week-end",
                &["aujourd'hui", "c'est-à-dire", "week-end"]
            )),
            ["aujourd'hui", "c'est-à-dire", "un", "week-end"]
        );
        assert_eq!(
            texts(&spaced("it", "Dell'anno, un po' d'un'altra", &[])),
            ["Dell'", "anno", "un", "po'", "d'", "un'", "altra"]
        );
        assert_eq!(
            texts(&spaced("es", "[Música] ¿Hacerlo? ¡Dímelo!", &[])),
            ["Hacerlo", "Dímelo"]
        );
        assert_eq!(texts(&spaced("ru", "За́мок — ёлка", &[])), ["За́мок", "ёлка"]);
        assert_eq!(
            texts(&spaced(
                "pt",
                "Dá-me o guarda-chuva, vou fazê-lo",
                &["guarda-chuva"]
            )),
            ["Dá", "me", "o", "guarda-chuva", "vou", "fazê", "lo"]
        );
    }

    #[test]
    fn finds_words_under_pronouns() {
        assert!(without_pronouns("es", "hacerlo").contains(&"hacer".to_string()));
        assert!(without_pronouns("es", "dímelo").contains(&"di".to_string()));
        assert!(without_pronouns("es", "vámonos").contains(&"vamos".to_string()));
        assert!(without_pronouns("es", "sentaos").contains(&"sentad".to_string()));
        assert!(without_pronouns("es", "haciéndolo").contains(&"haciendo".to_string()));
        assert_eq!(without_pronouns("it", "parlarne")[0], "parlare");
        assert!(without_pronouns("it", "dammelo").contains(&"dare".to_string()));
        assert!(without_pronouns("it", "dimmi").contains(&"dire".to_string()));
        assert!(without_pronouns("it", "porlo").contains(&"porre".to_string()));
        assert!(without_pronouns("it", "guardandola").contains(&"guardando".to_string()));
        assert!(without_pronouns("fr", "parlerle").is_empty());
        assert_eq!(without_pronouns("pt", "fazê"), ["fazer"]);
        assert_eq!(without_pronouns("pt", "comprá"), ["comprar"]);
        assert_eq!(without_pronouns("pt", "parti"), ["partir"]);
        assert_eq!(without_pronouns("pt", "pô"), ["pôr"]);
        assert!(without_pronouns("pt", "casa").is_empty());
    }

    #[test]
    fn counts_places_in_utf16() {
        let line = "😀 l’été";
        let words = utf16_places(line, cut_spaced("fr", line, &|_| false));
        assert_eq!(
            words.iter().map(|w| (w.start, w.end)).collect::<Vec<_>>(),
            [(3, 5), (5, 8)]
        );
    }

    /// A Lindera dictionary of a few words in MeCab's source format.
    fn build(folder: &std::path::Path, metadata: &str, words: &str, categories: &str) {
        use lindera::dictionary::{DictionaryBuilder, Metadata};
        let source = folder.join("source");
        let _ = std::fs::remove_dir_all(folder);
        std::fs::create_dir_all(&source).unwrap();
        std::fs::write(source.join("words.csv"), words).unwrap();
        std::fs::write(source.join("matrix.def"), "1 1\n0 0 0\n").unwrap();
        std::fs::write(
            source.join("char.def"),
            format!("DEFAULT 0 1 0\nSPACE 0 1 0\n{categories}\n0x0020 SPACE\n"),
        )
        .unwrap();
        std::fs::write(
            source.join("unk.def"),
            "DEFAULT,0,0,10000,SY,*,*,*,*,*,*,*\nSPACE,0,0,10000,SY,*,*,*,*,*,*,*\n",
        )
        .unwrap();
        let metadata: Metadata = serde_json::from_str(metadata).unwrap();
        DictionaryBuilder::new(metadata)
            .build_dictionary(&source, &folder.join("dict"))
            .unwrap();
    }

    #[test]
    fn cuts_korean_and_japanese_with_lindera() {
        let base = std::env::temp_dir().join(format!("lumtub-words-{}", std::process::id()));
        let ko = base.join("ko");
        build(
            &ko,
            r#"{"name":"ko-dic","encoding":"UTF-8","default_word_cost":-10000,"default_left_context_id":0,"default_right_context_id":0,"default_field_value":"*","flexible_csv":false,"skip_invalid_cost_or_id":false,"normalize_details":false,
               "dictionary_schema":{"fields":["surface","left_context_id","right_context_id","cost","part_of_speech_tag","meaning","presence_absence","reading","type","first_part_of_speech","last_part_of_speech","expression"]},
               "user_dictionary_schema":{"fields":["surface","part_of_speech_tag","reading"]}}"#,
            "친구,0,0,100,NNG,*,F,친구,*,*,*,*\n가,0,0,100,JKS,*,F,가,*,*,*,*\n추워서,0,0,100,VA+EC,*,F,추워서,Inflect,VA,EC,춥/VA/*+어서/EC/*\n공부,0,0,100,NNG,*,F,공부,*,*,*,*\n했,0,0,100,XSV+EP,*,T,했,Inflect,XSV,EP,하/XSV/*+았/EP/*\n어요,0,0,100,EF,*,F,어요,*,*,*,*\n.,0,0,100,SF,*,*,*,*,*,*,*\n",
            "HANGUL 0 1 2\n0xAC00..0xD7A3 HANGUL",
        );
        let cutter = Cutter::open("ko", ko.join("dict").to_str().unwrap()).unwrap();
        let line = "친구가 추워서 공부했어요.";
        let cut: Vec<(String, Vec<String>)> = cutter
            .cut(line)
            .into_iter()
            .map(|p| (line[p.start..p.end].to_string(), p.keys))
            .collect();
        assert_eq!(
            cut,
            [
                (
                    "친구가".to_string(),
                    vec!["친구".to_string(), "친구가".to_string()]
                ),
                (
                    "추워서".to_string(),
                    vec!["춥다".to_string(), "추워서".to_string()]
                ),
                (
                    "공부했어요".to_string(),
                    vec![
                        "공부하다".to_string(),
                        "공부".to_string(),
                        "공부했어요".to_string()
                    ]
                ),
            ]
        );

        let ja = base.join("ja");
        build(
            &ja,
            r#"{"name":"ipadic","encoding":"UTF-8","default_word_cost":-10000,"default_left_context_id":0,"default_right_context_id":0,"default_field_value":"*","flexible_csv":true,"skip_invalid_cost_or_id":false,"normalize_details":true,
               "dictionary_schema":{"fields":["surface","left_context_id","right_context_id","cost","part_of_speech","part_of_speech_subcategory_1","part_of_speech_subcategory_2","part_of_speech_subcategory_3","conjugation_form","conjugation_type","base_form","reading","pronunciation"]},
               "user_dictionary_schema":{"fields":["surface","part_of_speech","reading"]}}"#,
            "私,0,0,100,名詞,代名詞,一般,*,*,*,私,ワタシ,ワタシ\nは,0,0,100,助詞,係助詞,*,*,*,*,は,ハ,ワ\n食べ,0,0,100,動詞,自立,*,*,一段,連用形,食べる,タベ,タベ\nまし,0,0,100,助動詞,*,*,*,特殊・マス,連用形,ます,マシ,マシ\nた,0,0,100,助動詞,*,*,*,特殊・タ,基本形,た,タ,タ\n勉強,0,0,100,名詞,サ変接続,*,*,*,*,勉強,ベンキョウ,ベンキョー\nし,0,0,100,動詞,自立,*,*,サ変・スル,連用形,する,シ,シ\n。,0,0,100,記号,句点,*,*,*,*,。,。,。\n",
            "KANJI 0 0 2\nHIRAGANA 0 1 2\n0x4E00..0x9FFF KANJI\n0x3040..0x309F HIRAGANA",
        );
        let cutter = Cutter::open("ja", ja.join("dict").to_str().unwrap()).unwrap();
        let line = "私は食べました。勉強しました";
        let cut: Vec<(String, String, Option<String>)> = cutter
            .cut(line)
            .into_iter()
            .map(|p| {
                (
                    line[p.start..p.end].to_string(),
                    p.keys[0].clone(),
                    p.reading,
                )
            })
            .collect();
        assert_eq!(
            cut,
            [
                (
                    "私".to_string(),
                    "私".to_string(),
                    Some("わたし".to_string())
                ),
                ("は".to_string(), "は".to_string(), None),
                (
                    "食べました".to_string(),
                    "食べる".to_string(),
                    Some("たべました".to_string())
                ),
                (
                    "勉強しました".to_string(),
                    "勉強する".to_string(),
                    Some("べんきょうしました".to_string())
                ),
            ]
        );
        std::fs::remove_dir_all(base).unwrap();
    }

    /// The packs' real dictionaries, built by the learning packs workflow
    /// into `$LUMTUB_SEGMENTERS/{ja,ko,zh}`.
    #[test]
    #[ignore]
    fn real_segmenters() {
        let folder = std::env::var("LUMTUB_SEGMENTERS").expect("LUMTUB_SEGMENTERS");
        let cut = |language: &str, line: &str| -> Vec<(String, Vec<String>, Option<String>)> {
            let path = format!("{folder}/{language}");
            let cutter = Cutter::open(language, &path).unwrap();
            let cut: Vec<_> = cutter
                .cut(line)
                .into_iter()
                .map(|p| (line[p.start..p.end].to_string(), p.keys, p.reading))
                .collect();
            println!("{language}: {cut:?}");
            cut
        };
        let has = |cut: &[(String, Vec<String>, Option<String>)], text: &str, key: &str| {
            cut.iter().any(|(t, keys, _)| t == text && keys[0] == key)
        };
        let ko = cut("ko", "날씨가 너무 추워서 집에서 공부했어요.");
        assert!(has(&ko, "추워서", "춥다"), "{ko:?}");
        assert!(has(&ko, "날씨가", "날씨"), "{ko:?}");
        assert!(has(&ko, "공부했어요", "공부하다"), "{ko:?}");
        let ja = cut("ja", "私は昨日りんごを食べました。日本語を勉強しています。");
        assert!(has(&ja, "食べました", "食べる"), "{ja:?}");
        assert!(
            ja.iter()
                .any(|(t, _, r)| t == "昨日" && r.as_deref() == Some("きのう")),
            "{ja:?}"
        );
        let zh = cut("zh", "我们今天去北京看朋友。");
        assert!(
            has(&zh, "北京", "北京") && has(&zh, "今天", "今天"),
            "{zh:?}"
        );
    }
}
