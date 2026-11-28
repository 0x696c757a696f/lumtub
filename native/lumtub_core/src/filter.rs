//! Tests that keep videos out of a list: the language a title reads as,
//! bait titles, Shorts, and the channels of the block lists.

use std::collections::{HashMap, HashSet};

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
    It,
    Nl,
    Tr,
    Id,
    Ms,
    Tl,
    Pl,
    Uk,
    Cs,
    Ro,
    Hu,
    El,
    Sv,
    No,
    Da,
    Fi,
    He,
    Fa,
    Ur,
    Bn,
    Ta,
    Te,
    Af,
    Am,
    Az,
    Be,
    Bg,
    Eo,
    Et,
    Eu,
    Gl,
    Gu,
    Hy,
    Is,
    Jv,
    Ka,
    Km,
    Kn,
    La,
    Lo,
    Lt,
    Lv,
    Mk,
    Ml,
    Mn,
    Mr,
    My,
    Ne,
    Pa,
    Si,
    Sk,
    Sq,
    Su,
    Sw,
    Ti,
    Tk,
    Uz,
}

/// Letters only Vietnamese uses among explore's languages: not ă, â or
/// ê alone, which Romanian and French write too.
const VIETNAMESE: &str = "đơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ";

/// Small words that mark a Latin-script language. A word two of them
/// share (in, con, una, e, da) marks neither.
const LATIN_WORDS: [(Language, &[&str]); 17] = [
    (
        Language::En,
        &[
            "the", "and", "of", "to", "is", "for", "with", "how", "what", "why", "you", "my",
            "this", "your", "from", "on", "are", "i", "we", "best", "vs",
        ],
    ),
    (
        Language::Es,
        &[
            "el", "los", "las", "y", "que", "por", "para", "es", "como", "mi", "más", "qué",
            "cómo", "muy", "pero", "su", "noticias",
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
            "o", "os", "do", "dos", "das", "que", "com", "um", "uma", "para", "não", "é", "em",
            "no", "na", "mais", "você", "como",
        ],
    ),
    (
        Language::It,
        &[
            "il", "di", "della", "delle", "dello", "dei", "degli", "gli", "che", "per", "nel",
            "nella", "sul", "sulla", "alla", "allo", "agli", "è", "sono", "questo", "questa",
            "anche", "molto", "perché", "più", "cosa", "come", "non",
        ],
    ),
    (
        Language::Ro,
        &[
            "și", "în", "cu", "pe", "care", "este", "din", "pentru", "sau", "despre", "cum", "ce",
            "sunt", "acest", "această", "mai",
        ],
    ),
    (
        Language::Nl,
        &[
            "het", "een", "niet", "voor", "zijn", "naar", "deze", "bij", "maar", "wordt", "geen",
            "nieuws", "hoe", "maak",
        ],
    ),
    (
        Language::Af,
        &["nie", "vir", "ek", "jy", "hierdie", "baie", "julle", "nuus"],
    ),
    (
        Language::Tl,
        &[
            "ang", "mga", "ng", "nang", "ito", "siya", "tayo", "natin", "ngayon", "balita",
        ],
    ),
    (
        Language::Eu,
        &[
            "eta",
            "ere",
            "dira",
            "gaur",
            "nola",
            "zer",
            "baina",
            "albisteak",
            "euskara",
            "euskal",
        ],
    ),
    (
        Language::Fi,
        &[
            "että",
            "mutta",
            "kun",
            "tämä",
            "myös",
            "mitä",
            "miten",
            "kanssa",
            "joka",
            "sekä",
            "uutiset",
            "matkavlogi",
        ],
    ),
    (
        Language::Sq,
        &[
            "dhe", "në", "të", "për", "një", "është", "që", "lajme", "lajmet",
        ],
    ),
    (
        Language::Jv,
        &["lan", "ing", "karo", "iki", "kuwi", "wong", "saka"],
    ),
    (
        Language::Su,
        &[
            "jeung", "teh", "téh", "urang", "ieu", "kana", "sareng", "mah",
        ],
    ),
    (
        Language::Et,
        &["ning", "kuidas", "uudised", "reisivlog", "eesti", "täna"],
    ),
    (
        Language::Sw,
        &["kwa", "katika", "habari", "kutoka", "hii", "sana"],
    ),
];

/// [latin_letters] that only [language] writes: ä, ö and ü are German's
/// but Turkish, Hungarian, Swedish and Estonian write them too ("Haber
/// bülteni" was read surely as German), so for German only ß is sure.
fn sure_letters(language: Language, lower: &str) -> bool {
    match language {
        Language::De => lower.contains('ß'),
        _ => latin_letters(language, lower),
    }
}

/// Letters only one Latin-script language uses, lower case.
fn latin_letters(language: Language, lower: &str) -> bool {
    match language {
        Language::Es => lower.contains(['ñ', '¿', '¡']),
        Language::Fr => lower.contains(['œ', 'ç', 'è', 'ù', 'û']),
        Language::De => lower.contains(['ä', 'ö', 'ü', 'ß']),
        // Portuguese writes õ before e (lições, põe); Estonian anywhere
        // (Praamisõit, kõik).
        Language::Pt => {
            lower.contains('ã') || ["ção", "õe", "ões"].iter().any(|s| lower.contains(s))
        }
        Language::Et => lower.contains('õ') && !latin_letters(Language::Pt, lower),
        // ş with a cedilla is Turkish too (Şi, "Xi", in a Turkish title).
        Language::Ro => lower.contains(['ș', 'ț', 'ţ']),
        Language::Is => lower.contains(['þ', 'ð']),
        // Albanian writes ë in most sentences; Dutch and French only in a
        // few names (België, Noël).
        Language::Sq => lower.matches('ë').count() >= 2,
        // Estonian doubles ä too, but writes õ.
        Language::Fi => {
            ["ää", "öö", "yy"].iter().any(|pair| lower.contains(pair)) && !lower.contains('õ')
        }
        Language::Eu => lower.contains("tx"),
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

/// Whether kana in [title] make it Japanese. Chinese titles borrow `の`
/// for 的, `・` and `ー` as punctuation and the odd katakana letter, so a
/// title with Han characters needs other hiragana or two katakana.
fn kana_say_japanese(title: &str) -> bool {
    let mut hiragana = 0;
    let mut katakana = 0;
    let mut han = false;
    for c in title.chars() {
        match c as u32 {
            0x3041..=0x309f if c != 'の' => hiragana += 1,
            0x30a1..=0x30fa => katakana += 1,
            0x4e00..=0x9fff | 0x3400..=0x4dbf => han = true,
            _ => {}
        }
    }
    if han {
        hiragana > 0 || katakana >= 2
    } else {
        hiragana + katakana > 0 || title.contains('の')
    }
}

/// The language [title] is most likely in: by its script, and for Latin
/// letters by its small words. A Latin title with no small words at all,
/// such as "Minecraft Speedrun", is taken as English.
pub fn title_language(title: &str) -> Language {
    reading(title).0
}

/// [title_language], and whether the reading is sure: a script only one
/// language writes, letters or small words of one language, or a sure
/// statistical reading. A short Latin, Cyrillic, Devanagari or Arabic
/// title read by default (English, Russian, Hindi, Arabic) is not sure:
/// any language of its script may have written it.
pub fn reading(title: &str) -> (Language, bool) {
    let found = read(title);
    let sure = match found {
        Language::Any => false,
        Language::Hi => devanagari(title).is_some(),
        Language::Ar => title.chars().filter(|c| c.is_alphabetic()).count() >= 12,
        Language::Ru => cyrillic(title).is_some(),
        language if is_latin(language) && language != Language::Vi => {
            letters_allow(title).is_none_or(|allowed| allowed.contains(&language))
                && latin_sure(title, language)
        }
        _ => true,
    };
    (found, sure)
}

/// Letters only a few Latin-script languages write, lower case, and
/// those languages: a title with ø is Norwegian or Danish whatever its
/// small words say.
const LETTER_FAMILIES: [(&[char], &[Language]); 14] = {
    use Language::*;
    [
        (&['ø'], &[No, Da]),
        (&['å'], &[No, Da, Sv]),
        (&['æ'], &[No, Da, Is]),
        (&['ą', 'ę', 'ł', 'ś', 'ź', 'ż'], &[Pl]),
        (&['ř', 'ě', 'ů'], &[Cs]),
        (&['ľ', 'ĺ', 'ŕ'], &[Sk]),
        (&['ğ', 'ı'], &[Tr, Az]),
        (&['ə'], &[Az]),
        (&['ő', 'ű'], &[Hu]),
        (&['ā', 'ē', 'ī', 'ķ', 'ļ', 'ņ', 'ģ'], &[Lv]),
        (&['ė', 'į', 'ų'], &[Lt]),
        (&['ä'], &[De, Sv, Fi, Et, Sk, Tk]),
        (&['ö'], &[De, Tr, Hu, Sv, Fi, Et, Az, Tk, Is]),
        (&['ü'], &[De, Tr, Hu, Et, Az, Tk]),
    ]
};

/// The Latin-script languages [title]'s rarer letters leave, when it has
/// any of [LETTER_FAMILIES]: those every such letter allows.
fn letters_allow(title: &str) -> Option<Vec<Language>> {
    let lower = title.to_lowercase();
    let mut allowed: Option<Vec<Language>> = None;
    for (letters, languages) in LETTER_FAMILIES {
        if lower.contains(letters) {
            allowed = Some(match allowed {
                None => languages.to_vec(),
                Some(so_far) => so_far
                    .into_iter()
                    .filter(|l| languages.contains(l))
                    .collect(),
            });
        }
    }
    allowed
}

/// For a guess: the languages that may have written [title], read as
/// [guessed] without being sure. Those of its script, narrowed by its
/// letters; English only when guessed, as English titles are read surely
/// by their small words. Measured on 1590 videos in 70 languages
/// (2026-11-20): every guess let in wrongly was between such neighbours.
/// A text with a sign of [guessed] that another language does not share
/// (a small word, a letter, an English word) passes for that one only
/// when it has a sign of its own too: Indian English tech titles were
/// let in for German, as any Latin language might have written them
/// (2026-11-26). A text with no sign of anything ("Dagsrevyen 21") stays
/// open to its whole script.
pub fn alike(title: &str, guessed: Language) -> Vec<Language> {
    use Language::*;
    let lower = title.to_lowercase();
    if !is_latin(guessed) {
        return same_script(guessed)
            .into_iter()
            .filter(|l| *l == guessed || script_allows(&lower, *l))
            .collect();
    }
    // Languages that share nearly all their words with a bigger one
    // (Afrikaans with Dutch, Javanese and Sundanese with Indonesian) are
    // told by their own small words, never by a guess: a Polish title
    // read loosely was let in as Javanese.
    let mut languages = match letters_allow(title) {
        Some(allowed) if !allowed.is_empty() => allowed,
        _ => same_script(guessed)
            .into_iter()
            .filter(|l| !matches!(l, En | Af | Jv | Su | Ms))
            .filter(|l| sign_of(&lower, *l, guessed) || !sign_of(&lower, guessed, *l))
            .collect(),
    };
    if !languages.contains(&guessed) {
        languages.insert(0, guessed);
    }
    languages
}

/// Whether a text in a script several languages write, read as
/// another language without being sure, may be [language]'s by its
/// letters.
/// Russian read by default may be Ukrainian or Belarusian only when their
/// own letters say so, which makes the reading sure; Mongolian and
/// Uzbek likewise (ө, ү; қ, ғ, ҳ). Bulgarian writes no ы, э or ё,
/// Macedonian none of й, щ, ъ, ы, э, ю, я, ё. Persian and Urdu write
/// letters Arabic does not (ی, ے…), which make the reading theirs.
fn script_allows(lower: &str, language: Language) -> bool {
    use Language::*;
    match language {
        Uk | Be | Mn | Uz | Fa | Ur => false,
        Bg => !lower.contains(['ы', 'э', 'ё']),
        Mk => !lower.contains(['й', 'щ', 'ъ', 'ы', 'э', 'ю', 'я', 'ё']),
        _ => true,
    }
}

/// Words of English titles that no other Latin language of explore
/// writes as a word of its own; with [LATIN_WORDS]' English ones only
/// English writes, they tell a guess of English from a title in another
/// language that is read as English only by default ("Dagsrevyen 21").
/// Words other languages borrow in titles of their own ("budget", "tips",
/// "smart", "official", "live") are left out.
const ENGLISH_HINTS: [&str; 52] = [
    "it",
    "it's",
    "i'm",
    "don't",
    "isn't",
    "can't",
    "you're",
    "they",
    "their",
    "there",
    "here",
    "who",
    "when",
    "about",
    "into",
    "every",
    "never",
    "ever",
    "which",
    "should",
    "really",
    "better",
    "before",
    "after",
    "years",
    "days",
    "month",
    "first",
    "look",
    "hands",
    "new",
    "worst",
    "cheapest",
    "make",
    "made",
    "get",
    "got",
    "buy",
    "price",
    "worth",
    "review",
    "unboxing",
    "cheap",
    "honest",
    "explained",
    "features",
    "watch",
    "life",
    "world",
    "people",
    "things",
    "way",
];

/// Whether [lower] has a sign of [language] that [other] does not
/// share: a letter only it writes, one of its small words of three
/// letters or more that is not [other]'s too ("es", "la", "do" are words
/// of many languages), or for English one of [ENGLISH_HINTS] in a text with no
/// letter English does not write.
fn sign_of(lower: &str, language: Language, other: Language) -> bool {
    if sure_letters(language, lower) {
        return true;
    }
    let bit = |of: Language| {
        LATIN_WORDS
            .iter()
            .position(|(l, _)| *l == of)
            .map_or(0, |at| 1u32 << at)
    };
    let (own, theirs) = (bit(language), bit(other));
    if own != 0
        && words_of(lower)
            .filter(|w| w.chars().count() > 2)
            .map(small_word_languages)
            .any(|langs| langs & own != 0 && langs & theirs == 0)
    {
        return true;
    }
    language == Language::En
        && !lower.chars().any(|c| c.is_alphabetic() && !c.is_ascii())
        && words_of(lower).any(|w| ENGLISH_HINTS.contains(&w))
}

fn words_of(lower: &str) -> impl Iterator<Item = &str> {
    lower
        .split(|c: char| !(c.is_alphabetic() || c == '\''))
        .filter(|w| !w.is_empty())
}

/// The languages explore offers that write [language]'s script, itself
/// included; only [language] for a script of its own.
pub fn same_script(language: Language) -> Vec<Language> {
    use Language::*;
    let groups: [&[Language]; 3] = [&[Ru, Uk, Be, Bg, Mk, Mn, Uz], &[Hi, Mr, Ne], &[Ar, Fa, Ur]];
    if is_latin(language) {
        return (0..=Uz as u32)
            .filter_map(language_at)
            .filter(|l| is_latin(*l) && *l != Vi)
            .collect();
    }
    groups
        .iter()
        .find(|group| group.contains(&language))
        .map_or_else(|| vec![language], |group| group.to_vec())
}

/// Every language, in the order of its number ([Language::Any] is 0).
const LANGUAGES: [Language; 71] = [
    Language::Any,
    Language::Zh,
    Language::Ja,
    Language::Ko,
    Language::En,
    Language::Es,
    Language::Fr,
    Language::De,
    Language::Pt,
    Language::Ru,
    Language::Ar,
    Language::Hi,
    Language::Th,
    Language::Vi,
    Language::It,
    Language::Nl,
    Language::Tr,
    Language::Id,
    Language::Ms,
    Language::Tl,
    Language::Pl,
    Language::Uk,
    Language::Cs,
    Language::Ro,
    Language::Hu,
    Language::El,
    Language::Sv,
    Language::No,
    Language::Da,
    Language::Fi,
    Language::He,
    Language::Fa,
    Language::Ur,
    Language::Bn,
    Language::Ta,
    Language::Te,
    Language::Af,
    Language::Am,
    Language::Az,
    Language::Be,
    Language::Bg,
    Language::Eo,
    Language::Et,
    Language::Eu,
    Language::Gl,
    Language::Gu,
    Language::Hy,
    Language::Is,
    Language::Jv,
    Language::Ka,
    Language::Km,
    Language::Kn,
    Language::La,
    Language::Lo,
    Language::Lt,
    Language::Lv,
    Language::Mk,
    Language::Ml,
    Language::Mn,
    Language::Mr,
    Language::My,
    Language::Ne,
    Language::Pa,
    Language::Si,
    Language::Sk,
    Language::Sq,
    Language::Su,
    Language::Sw,
    Language::Ti,
    Language::Tk,
    Language::Uz,
];

/// The language at explore's index [index].
pub fn language_at(index: u32) -> Option<Language> {
    LANGUAGES.get(usize::try_from(index).ok()?).copied()
}

/// Whether [language] is written in Latin letters.
pub fn is_latin(language: Language) -> bool {
    use Language::*;
    matches!(
        language,
        En | Es
            | Fr
            | De
            | Pt
            | It
            | Nl
            | Tr
            | Id
            | Ms
            | Tl
            | Pl
            | Cs
            | Ro
            | Hu
            | Sv
            | No
            | Da
            | Fi
            | Af
            | Az
            | Eo
            | Et
            | Eu
            | Gl
            | Is
            | Jv
            | La
            | Lt
            | Lv
            | Sk
            | Sq
            | Su
            | Sw
            | Tk
            | Uz
            | Vi
    )
}

/// The languages of [LATIN_WORDS], as bits by their place there, that
/// have [word] among their small words.
fn small_word_languages(word: &str) -> u32 {
    static BY_WORD: std::sync::LazyLock<HashMap<&'static str, u32>> =
        std::sync::LazyLock::new(|| {
            let mut by_word: HashMap<&'static str, u32> = HashMap::new();
            for (at, (_, small)) in LATIN_WORDS.iter().enumerate() {
                for word in *small {
                    *by_word.entry(word).or_default() |= 1 << at;
                }
            }
            by_word
        });
    BY_WORD.get(word).copied().unwrap_or(0)
}

/// Whether a Latin [title] read as [language] is surely in it: two of its
/// small words, a letter only it writes, or a sure statistical reading of
/// four words or more.
fn latin_sure(title: &str, language: Language) -> bool {
    let lower = title.to_lowercase();
    if sure_letters(language, &lower) {
        return true;
    }
    let words: Vec<&str> = lower
        .split(|c: char| !(c.is_alphabetic() || c == '\''))
        .filter(|w| !w.is_empty())
        .collect();
    let small = LATIN_WORDS
        .iter()
        .position(|(l, _)| *l == language)
        .map_or(Vec::new(), |at| {
            words
                .iter()
                .filter(|w| small_word_languages(w) & (1 << at) != 0)
                .collect::<Vec<_>>()
        });
    // Two small words, one of them longer than two letters: "o", "do",
    // "em", "no", "na" are words of many languages.
    if small.len() >= 2 && small.iter().any(|w| w.chars().count() > 2) {
        return true;
    }
    words.len() >= 4
        && latin_detector().detect(title).is_some_and(|info| {
            info.confidence() >= 0.8 && latin_language(info.lang()) == Some(language)
        })
}

fn read(title: &str) -> Language {
    if kana_say_japanese(title) {
        return Language::Ja;
    }
    if any_in(title, &[(0xac00, 0xd7af), (0x1100, 0x11ff)]) {
        return Language::Ko;
    }
    if any_in(title, &[(0x4e00, 0x9fff), (0x3400, 0x4dbf)]) {
        return Language::Zh;
    }
    if any_in(title, &[(0x0e00, 0x0e7f)]) {
        return Language::Th;
    }
    // Scripts of one language each among explore's.
    for (ranges, language) in [
        (&[(0x0a80u32, 0x0affu32)][..], Language::Gu),
        (&[(0x0a00, 0x0a7f)], Language::Pa),
        (&[(0x0c80, 0x0cff)], Language::Kn),
        (&[(0x0d00, 0x0d7f)], Language::Ml),
        (&[(0x0d80, 0x0dff)], Language::Si),
        (&[(0x0e80, 0x0eff)], Language::Lo),
        (&[(0x1000, 0x109f)], Language::My),
        (&[(0x10a0, 0x10ff), (0x1c90, 0x1cbf)], Language::Ka),
        (&[(0x0530, 0x058f)], Language::Hy),
        (&[(0x1780, 0x17ff)], Language::Km),
        // Ge'ez: Amharic, the more common of the two that write it.
        (&[(0x1200, 0x137f)], Language::Am),
    ] {
        if any_in(title, ranges) {
            return language;
        }
    }
    if any_in(title, &[(0x0900, 0x097f)]) {
        // Devanagari: Hindi unless the words are Marathi's or Nepali's.
        return devanagari(title).unwrap_or(Language::Hi);
    }
    if any_in(title, &[(0x0980, 0x09ff)]) {
        return Language::Bn;
    }
    if any_in(title, &[(0x0b80, 0x0bff)]) {
        return Language::Ta;
    }
    if any_in(title, &[(0x0c00, 0x0c7f)]) {
        return Language::Te;
    }
    if any_in(title, &[(0x0590, 0x05ff)]) {
        return Language::He;
    }
    if any_in(title, &[(0x0370, 0x03ff)]) {
        return Language::El;
    }
    if any_in(title, &[(0x0600, 0x06ff)]) {
        // Letters Arabic itself does not use.
        if title.contains(['ٹ', 'ڈ', 'ڑ', 'ں', 'ے']) {
            return Language::Ur;
        }
        // Persian words Arabic does not use, for titles without Persian
        // letters ("اخبار ساعت شش عصر").
        let persian_word = title
            .split(|c: char| !c.is_alphabetic())
            .any(|w| matches!(w, "شش" | "است" | "های" | "برای" | "امروز" | "خبر‌ها"));
        if title.contains(['پ', 'چ', 'ژ', 'گ', 'ی']) || persian_word {
            return Language::Fa;
        }
        return Language::Ar;
    }
    if any_in(title, &[(0x0400, 0x04ff)]) {
        let lower = title.to_lowercase();
        if lower.contains(['ї', 'є', 'ґ']) {
            return Language::Uk;
        }
        // Uzbek writes ў too, with қ, ғ and ҳ, which Belarusian does not.
        if lower.contains(['қ', 'ғ', 'ҳ']) {
            return Language::Uz;
        }
        if lower.contains('ў') {
            return Language::Be;
        }
        if lower.contains(['ѓ', 'ќ', 'ѕ', 'љ', 'њ', 'џ']) {
            return Language::Mk;
        }
        if lower.contains(['ө', 'ү']) {
            return Language::Mn;
        }
        return cyrillic(title).unwrap_or(if lower.contains('і') {
            Language::Uk
        } else {
            Language::Ru
        });
    }
    let lower = title.to_lowercase();
    if lower.chars().any(|c| VIETNAMESE.contains(c)) {
        return Language::Vi;
    }
    if !title.chars().any(|c| c.is_ascii_alphabetic()) {
        return Language::Any;
    }
    // Only Icelandic writes þ and ð among explore's languages.
    if lower.contains(['þ', 'ð']) {
        return Language::Is;
    }
    let words: Vec<&str> = lower
        .split(|c: char| !(c.is_alphabetic() || c == '\''))
        .filter(|w| !w.is_empty())
        .collect();
    // How many of the words are small words of each language, from one
    // lookup per word.
    let mut counts = [0usize; LATIN_WORDS.len()];
    for word in &words {
        let mask = small_word_languages(word);
        for (at, count) in counts.iter_mut().enumerate() {
            *count += (mask >> at & 1) as usize;
        }
    }
    let mut best = Language::En;
    let mut best_score = 0.0;
    for (at, (language, _)) in LATIN_WORDS.into_iter().enumerate() {
        let mut score = counts[at] as f64;
        if latin_letters(language, &lower) {
            score += 1.5;
        }
        if score > best_score {
            (best, best_score) = (language, score);
        }
    }
    // Trigrams tell the other Latin-script languages, such as Italian or
    // Dutch, where there is text enough to go by.
    // A title of a word or two, such as a game's name, is too little.
    // Small words of one language are overruled only by a sure reading,
    // and not by a language whose own small words are fewer.
    let enough = if words.len() >= 4 { 0.2 } else { 0.5 };
    let listed = |language: Language| LATIN_WORDS.iter().any(|(l, _)| *l == language);
    let score_of = |language: Language| {
        LATIN_WORDS
            .iter()
            .position(|(l, _)| *l == language)
            .map_or(0.0, |at| counts[at] as f64)
    };
    if let Some(info) = latin_detector()
        .detect(title)
        .filter(|info| info.confidence() >= enough)
        && let Some(found) = latin_language(info.lang())
        && (best_score == 0.0
            || found == best
            || (best_score < 2.0
                && info.confidence() >= 0.5
                && (!listed(found) || score_of(found) >= score_of(best))))
    {
        return found;
    }
    best
}

fn latin_detector() -> &'static whatlang::Detector {
    use whatlang::Lang::*;
    static DETECTOR: std::sync::OnceLock<whatlang::Detector> = std::sync::OnceLock::new();
    DETECTOR.get_or_init(|| {
        whatlang::Detector::with_allowlist(vec![
            Eng, Spa, Fra, Deu, Por, Ita, Nld, Tur, Ind, Tgl, Pol, Ces, Slk, Ron, Hun, Swe, Nob,
            Dan, Fin, Aze, Epo, Est, Jav, Lat, Lit, Lav, Tuk, Uzb,
        ])
    })
}

/// The language whatlang reads [title] as among [langs], which share its
/// script (Devanagari or Cyrillic), when it is sure enough.
fn shared_script(
    cell: &'static std::sync::OnceLock<whatlang::Detector>,
    langs: &[whatlang::Lang],
    title: &str,
) -> Option<Language> {
    use whatlang::Lang::*;
    let detector = cell.get_or_init(|| whatlang::Detector::with_allowlist(langs.to_vec()));
    let info = detector
        .detect(title)
        .filter(|info| info.confidence() >= 0.5)?;
    Some(match info.lang() {
        Hin => Language::Hi,
        Mar => Language::Mr,
        Nep => Language::Ne,
        Rus => Language::Ru,
        Ukr => Language::Uk,
        Bel => Language::Be,
        Bul => Language::Bg,
        Mkd => Language::Mk,
        _ => return None,
    })
}

fn devanagari(title: &str) -> Option<Language> {
    use whatlang::Lang::*;
    static DETECTOR: std::sync::OnceLock<whatlang::Detector> = std::sync::OnceLock::new();
    shared_script(&DETECTOR, &[Hin, Mar, Nep], title)
}

fn cyrillic(title: &str) -> Option<Language> {
    use whatlang::Lang::*;
    static DETECTOR: std::sync::OnceLock<whatlang::Detector> = std::sync::OnceLock::new();
    shared_script(&DETECTOR, &[Rus, Ukr, Bel, Bul, Mkd], title)
}

fn latin_language(lang: whatlang::Lang) -> Option<Language> {
    use whatlang::Lang::*;
    Some(match lang {
        Eng => Language::En,
        Spa => Language::Es,
        Fra => Language::Fr,
        Deu => Language::De,
        Por => Language::Pt,
        Ita => Language::It,
        Nld => Language::Nl,
        Tur => Language::Tr,
        Ind => Language::Id,
        Tgl => Language::Tl,
        Pol => Language::Pl,
        Ces => Language::Cs,
        Slk => Language::Sk,
        Aze => Language::Az,
        Epo => Language::Eo,
        Est => Language::Et,
        Jav => Language::Jv,
        Lat => Language::La,
        Lit => Language::Lt,
        Lav => Language::Lv,
        Tuk => Language::Tk,
        Uzb => Language::Uz,
        Ron => Language::Ro,
        Hun => Language::Hu,
        Swe => Language::Sv,
        Nob => Language::No,
        Dan => Language::Da,
        Fin => Language::Fi,
        _ => return None,
    })
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
    channels: HashSet<String>,
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
        !lower.is_empty() && (self.exact.contains(&lower) || self.starts_listed(&lower))
    }

    /// Whether [name] starts with one of [Self::channels] as
    /// [name_starts_with] has it: each of the name's own beginnings is
    /// looked up, rather than every listed word tried against the name.
    fn starts_listed(&self, name: &str) -> bool {
        std::iter::once(0)
            .chain(name.char_indices().map(|(i, c)| i + c.len_utf8()))
            .any(|end| {
                let word = &name[..end];
                self.channels.contains(word) && name_starts_with(name, word)
            })
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
    word.chars().last().is_some_and(|c| c as u32 > 0x2e7f) || !next.is_alphanumeric()
}

/// The language of the UTF-8 title, as its place in [Language].
///
/// # Safety
/// `title` points at `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_title_language(title: *const u8, length: usize) -> u32 {
    // SAFETY: The caller passes `title` pointing at `length` readable bytes, as this function
    // requires.
    title_language(unsafe { text(title, length) }) as u32
}

/// Whether the UTF-8 title reads like bait.
///
/// # Safety
/// `title` points at `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_looks_like_bait(title: *const u8, length: usize) -> bool {
    // SAFETY: The caller passes `title` pointing at `length` readable bytes, as this function
    // requires.
    looks_like_bait(unsafe { text(title, length) })
}

/// Whether the video described by the JSON [ShortInfo] is a Short.
///
/// # Safety
/// `json` points at `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_is_short(json: *const u8, length: usize) -> bool {
    // SAFETY: The caller passes `json` pointing at `length` readable bytes, as this function
    // requires.
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
    // SAFETY: The caller passes `json` pointing at `length` readable bytes, as this function
    // requires.
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
    // SAFETY: `blocks` is null (`as_ref` gives None) or a live pointer from `lumtub_blocks_new`
    // that Dart has not freed.
    let Some(blocks) = (unsafe { blocks.as_ref() }) else {
        return false;
    };
    // SAFETY: The caller passes `json` pointing at `length` readable bytes, as this function
    // requires.
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
        // SAFETY: `blocks` is non-null here and, per this function's `# Safety`, came from
        // `lumtub_blocks_new` and is freed once.
        drop(unsafe { Box::from_raw(blocks) });
    }
}

#[cfg(test)]
mod tests {

    #[test]
    fn languages_are_listed_in_the_order_of_their_numbers() {
        for (index, language) in super::LANGUAGES.iter().enumerate() {
            assert_eq!(*language as usize, index, "{language:?} is out of place");
        }
        assert_eq!(super::language_at(super::LANGUAGES.len() as u32), None);
    }

    #[test]
    fn no_small_word_marks_two_languages() {
        // The first seven lists (das, que, como, ...) shared a few words
        // before; the later ones share none with any list.
        let mut seen = std::collections::HashMap::new();
        for (index, (language, small)) in super::LATIN_WORDS.iter().enumerate() {
            let language = *language;
            for word in small.iter() {
                if let Some((other, other_index)) = seen.insert(*word, (language, index))
                    && (index >= 7 || other_index >= 7)
                {
                    assert_eq!(other, language, "{word} is listed twice");
                }
            }
        }
    }

    #[test]
    fn reads_the_smaller_latin_languages_by_their_words() {
        use super::Language::*;
        use super::reading;
        for (title, language) in [
            ("Balita ngayong umaga: ang mga pangunahing ulat", Tl),
            ("Gaur egungo albisteak eta euskara", Eu),
            ("Lajmet e mbrëmjes në Tiranë dhe Durrës", Sq),
            ("Hierdie is baie lekker, ek sê vir julle", Af),
            ("Het nieuws van vandaag, maar niet voor iedereen", Nl),
            ("Habari za leo kutoka Dar es Salaam kwa ufupi", Sw),
            ("Eesti uudised: kuidas täna ilm on", Et),
        ] {
            assert_eq!(reading(title), (language, true), "{title}");
        }
        assert_ne!(
            reading("Trump-Putin-Şi: Beden Dilleri Ne Dedi? | CANLI HABER").0,
            Ro
        );
        // A letter shared with a bigger language does not outweigh
        // Estonian's own word and trigrams.
        for title in [
            "Reisivlog 2 - Maldiivid - Praamisõit, kohalik saar",
            "Avastasime Malta SÜNGED saladused... REISIVLOG",
        ] {
            assert_eq!(reading(title).0, Et, "{title}");
        }
        assert_eq!(reading("As lições de hoje").0, Pt);
        // One word of its own is a guess, but one that names Finnish.
        assert_eq!(reading("Matkavlogi - Kreeta").0, Fi);
    }

    use super::*;

    #[test]
    fn tells_languages_apart() {
        assert_eq!(title_language("【4K】東京の夜景を歩く"), Language::Ja);
        assert_eq!(
            title_language("【小Pの遊戲實況】週一不想努力啦 今天輕鬆玩遊戲"),
            Language::Zh
        );
        assert_eq!(
            title_language("lijack的遊戲直播--光榮--PC--真・三國無雙 2 with 猛將傳"),
            Language::Zh
        );
        assert_eq!(title_language("東京大学の入試問題を解説"), Language::Ja);
        assert_eq!(title_language("【ホロライブ】新衣装お披露目"), Language::Ja);
        assert_eq!(title_language("初音ミク 千本桜"), Language::Ja);
        assert_eq!(title_language("ラーメン"), Language::Ja);
        assert_eq!(title_language("서울 맛집 투어"), Language::Ko);
        assert_eq!(title_language("中国历史纪录片 第一集"), Language::Zh);
        assert_eq!(title_language("Історія України"), Language::Uk);
        assert_eq!(title_language("История России"), Language::Ru);
        assert_eq!(title_language("Ταξίδι στην Αθήνα"), Language::El);
        assert_eq!(title_language("سفر به ایران"), Language::Fa);
        assert_eq!(title_language("رحلة إلى مصر"), Language::Ar);
        assert_eq!(title_language("How to build a PC in 2026"), Language::En);
        assert_eq!(title_language("Minecraft Speedrun"), Language::En);
        assert_eq!(title_language("Cómo hacer pan en casa"), Language::Es);
        assert_eq!(title_language("Lezione di filosofia: Kant"), Language::It);
        assert_eq!(
            title_language("La filosofia di Spinoza spiegata in modo semplice"),
            Language::It
        );
        assert_eq!(
            title_language(
                "Una lezione sulla Repubblica di Platone e sulla sua idea di giustizia, con una lettura dei passi più importanti del libro."
            ),
            Language::It
        );
        assert_eq!(
            title_language("Ricette di casa: la pasta al forno della nonna"),
            Language::It
        );
        assert_eq!(
            title_language("Cum să faci cea mai bună pâine în casă"),
            Language::Ro
        );
        assert_eq!(
            title_language("Les meilleures recettes pour l'été"),
            Language::Fr
        );
        assert_eq!(title_language("Wie man das Brot backt"), Language::De);
        assert_eq!(title_language("Como fazer pão em casa"), Language::Pt);
        assert_eq!(title_language("Как приготовить борщ"), Language::Ru);
        assert_eq!(title_language("Phở bò Hà Nội"), Language::Vi);
        assert_eq!(title_language("2026 12 31"), Language::Any);
        assert_eq!(
            title_language("Come coltivare i pomodori sul balcone di casa"),
            Language::It
        );
        assert_eq!(
            title_language("Notizie internazionali di oggi: cosa sta succedendo"),
            Language::It
        );
        assert_eq!(
            title_language("Hoe maak je de lekkerste appeltaart van Nederland"),
            Language::Nl
        );
        assert_eq!(
            title_language("Jak zrobić najlepszą pizzę w domu"),
            Language::Pl
        );
        assert_eq!(
            title_language("Evde en güzel pizza nasıl yapılır"),
            Language::Tr
        );
        assert_eq!(title_language("ગુજરાતી ભોજન બનાવવાની રીત"), Language::Gu);
        assert_eq!(title_language("ಬೆಂಗಳೂರು ನಗರ ಪ್ರವಾಸ"), Language::Kn);
        assert_eq!(title_language("ശ്രീലങ്കൻ യാത്ര"), Language::Ml);
        assert_eq!(title_language("ශ්‍රී ලංකා සංචාරය"), Language::Si);
        assert_eq!(title_language("ອາຫານລາວ"), Language::Lo);
        assert_eq!(title_language("မြန်မာ သီချင်း"), Language::My);
        assert_eq!(title_language("საქართველოს ისტორია"), Language::Ka);
        assert_eq!(title_language("Հայաստանի պատմություն"), Language::Hy);
        assert_eq!(title_language("ប្រវត្តិសាស្ត្រកម្ពុជា"), Language::Km);
        assert_eq!(title_language("የኢትዮጵያ ታሪክ"), Language::Am);
        assert_eq!(title_language("ਪੰਜਾਬੀ ਗੀਤ"), Language::Pa);
        assert_eq!(
            title_language("Гісторыя Беларусі ў XX стагоддзі"),
            Language::Be
        );
        assert_eq!(
            title_language("Историја на Македонија и Охрид, ѕвездите"),
            Language::Mk
        );
        assert_eq!(title_language("Монгол улсын түүх"), Language::Mn);
        assert_eq!(
            title_language("Как да си направим най-хубавата баница у дома"),
            Language::Bg
        );
        assert_eq!(title_language("भारत का इतिहास और संस्कृति"), Language::Hi);
        assert_eq!(
            title_language("Kaip išsikepti skaniausią duoną namuose"),
            Language::Lt
        );
        assert_eq!(
            title_language("Kā pagatavot garšīgāko maizi mājās"),
            Language::Lv
        );
        assert_eq!(
            title_language("Ako upiecť najlepší chlieb doma za hodinu"),
            Language::Sk
        );
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
    fn small_word_lookup_agrees_with_the_lists() {
        let every = LATIN_WORDS.iter().flat_map(|(_, small)| small.iter());
        for word in every.chain(["xyz", "", "l'"].iter()) {
            for (at, (_, small)) in LATIN_WORDS.iter().enumerate() {
                assert_eq!(
                    small_word_languages(word) & (1 << at) != 0,
                    small.contains(word),
                    "{word}"
                );
            }
        }
    }

    #[test]
    fn prefix_lookup_matches_as_trying_every_prefix() {
        let mut blocks = Blocks::default();
        let mut names: Vec<String> = Vec::new();
        for record in crate::lists::built_in().iter().flat_map(|l| &l.records) {
            blocks
                .channels
                .extend(record.prefixes.iter().map(|p| p.to_lowercase()));
            names.extend(record.names.iter().map(|n| n.to_lowercase()));
            names.extend(record.prefixes.iter().map(|p| p.to_lowercase()));
        }
        assert!(blocks.channels.len() > 100, "{}", blocks.channels.len());
        blocks.channels.insert(String::new());
        let listed: Vec<String> = blocks.channels.iter().cloned().collect();
        for word in &listed {
            for tail in [
                "", " news", "x", "1", "-tv", "新闻", "台", "é", ".", " ", "ab cd",
            ] {
                names.push(format!("{word}{tail}"));
            }
            let mut chars = word.chars();
            chars.next_back();
            names.push(chars.as_str().to_string());
        }
        names.extend(["ntd", "rtl", "rt documentary", "央视新闻", "-x", "a"].map(String::from));
        let mut differ = 0;
        for name in names.iter().filter(|n| !n.is_empty()) {
            let old = listed.iter().any(|word| name_starts_with(name, word));
            if old != blocks.starts_listed(name) {
                differ += 1;
            }
        }
        assert_eq!(differ, 0);
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
