//! View counts as YouTube writes them in the language it was asked in:
//! "1.2K", "1,2 Mio.", "12 mil", "1,2 млн", "10.9万", "3,4 B" (Turkish,
//! thousands), "1.2 lakh". The language is the one Lumtub asks YouTube for
//! ([set_language]), as the same unit means different things in different
//! languages ("B" is a thousand in Turkish, "M" a billion in Indonesian).

use std::os::raw::c_char;
use std::sync::RwLock;

use crate::taste::text;

static LANGUAGE: RwLock<String> = RwLock::new(String::new());

/// The `hl` YouTube is asked in, such as `zh-CN` or `de`.
pub fn set_language(hl: &str) {
    if let Ok(mut language) = LANGUAGE.write() {
        *language = hl.to_owned();
    }
}

fn language() -> String {
    LANGUAGE.read().map(|l| l.clone()).unwrap_or_default()
}

/// Units written right after the number, with no space: they match the
/// start of what follows ("万次观看").
const GLUED: &[(&str, f64)] = &[
    ("万", 1e4),
    ("萬", 1e4),
    ("만", 1e4),
    ("亿", 1e8),
    ("億", 1e8),
    ("억", 1e8),
    ("千", 1e3),
    ("천", 1e3),
    ("พัน", 1e3),
    ("หมื่น", 1e4),
    ("แสน", 1e5),
    ("ล้าน", 1e6),
    ("ពាន់", 1e3),
    ("ម៉ឺន", 1e4),
    ("សែន", 1e5),
    ("លាន", 1e6),
    ("ພັນ", 1e3),
    ("ແສນ", 1e5),
    ("ລ້ານ", 1e6),
    ("ထောင်", 1e3),
    ("သောင်း", 1e4),
    ("သိန်း", 1e5),
    ("သန်း", 1e6),
];

/// The short units of [hl]'s language, lower case, without their dot.
fn units(hl: &str) -> &'static [(&'static str, f64)] {
    let base = hl
        .split(['-', '_'])
        .next()
        .unwrap_or("")
        .to_ascii_lowercase();
    match base.as_str() {
        "de" => &[("tsd", 1e3), ("mio", 1e6), ("mrd", 1e9)],
        "fr" => &[("k", 1e3), ("m", 1e6), ("md", 1e9), ("mrd", 1e9)],
        "es" | "gl" => &[("mil", 1e3), ("m", 1e6), ("mil m", 1e9)],
        "ca" => &[("k", 1e3), ("m", 1e6), ("mil", 1e3)],
        "pt" => &[("mil", 1e3), ("mi", 1e6), ("bi", 1e9)],
        "it" => &[("mila", 1e3), ("k", 1e3), ("mln", 1e6), ("mrd", 1e9)],
        "nl" => &[("k", 1e3), ("mln", 1e6), ("mld", 1e9)],
        "ru" => &[("тыс", 1e3), ("млн", 1e6), ("млрд", 1e9)],
        "uk" => &[("тис", 1e3), ("млн", 1e6), ("млрд", 1e9)],
        "be" => &[("тыс", 1e3), ("млн", 1e6), ("млрд", 1e9)],
        "bg" => &[("хил", 1e3), ("млн", 1e6), ("млрд", 1e9)],
        "sr" | "mk" => &[
            ("хиљ", 1e3),
            ("хил", 1e3),
            ("мил", 1e6),
            ("млрд", 1e9),
            ("млн", 1e6),
            ("hilj", 1e3),
            ("hil", 1e3),
            ("mil", 1e6),
            ("mlrd", 1e9),
        ],
        "sq" => &[("mijë", 1e3), ("mln", 1e6), ("mld", 1e9)],
        "eu" => &[("mila", 1e3), ("k", 1e3), ("m", 1e6)],
        "hy" => &[("հզր", 1e3), ("մլն", 1e6), ("մլրդ", 1e9)],
        "ka" => &[("ათ", 1e3), ("მლნ", 1e6), ("მლრდ", 1e9)],
        "am" => &[("ሺ", 1e3), ("ሚ", 1e6), ("ቢ", 1e9)],
        "si" => &[("ද", 1e3), ("මි", 1e6), ("බි", 1e9)],
        "ta" => &[
            ("ஆ", 1e3),
            ("ஆயிரம்", 1e3),
            ("லட்சம்", 1e5),
            ("மி", 1e6),
            ("கோடி", 1e7),
            ("பி", 1e9),
        ],
        "te" => &[
            ("వే", 1e3),
            ("లక్ష", 1e5),
            ("లక్షలు", 1e5),
            ("మి", 1e6),
            ("కోటి", 1e7),
            ("బి", 1e9),
        ],
        "kn" => &[
            ("ಸಾ", 1e3),
            ("ಸಾವಿರ", 1e3),
            ("ಲಕ್ಷ", 1e5),
            ("ಮಿ", 1e6),
            ("ಕೋಟಿ", 1e7),
            ("ಬಿ", 1e9),
        ],
        "ml" => &[
            ("ആ", 1e3),
            ("ആയിരം", 1e3),
            ("ലക്ഷം", 1e5),
            ("ദശലക്ഷം", 1e6),
            ("കോടി", 1e7),
        ],
        "gu" => &[("હજાર", 1e3), ("લાખ", 1e5), ("કરોડ", 1e7)],
        "pa" => &[("ਹਜ਼ਾਰ", 1e3), ("ਲੱਖ", 1e5), ("ਕਰੋੜ", 1e7)],
        "or" => &[("ହଜାର", 1e3), ("ଲକ୍ଷ", 1e5), ("କୋଟି", 1e7)],
        "as" => &[
            ("হাজাৰ", 1e3),
            ("হা", 1e3),
            ("লাখ", 1e5),
            ("লা", 1e5),
            ("কোটি", 1e7),
            ("কো", 1e7),
        ],
        "jv" => &[
            ("èwu", 1e3),
            ("ewu", 1e3),
            ("rb", 1e3),
            ("yuta", 1e6),
            ("jt", 1e6),
            ("m", 1e9),
        ],
        "su" => &[("rb", 1e3), ("rébu", 1e3), ("jt", 1e6), ("m", 1e9)],
        "kk" | "ky" | "mn" => &[("мың", 1e3), ("мин", 1e3), ("млн", 1e6), ("млрд", 1e9)],
        "pl" => &[("tys", 1e3), ("mln", 1e6), ("mld", 1e9)],
        "cs" | "sk" => &[("tis", 1e3), ("mil", 1e6), ("mld", 1e9)],
        "hr" | "bs" | "sl" => &[
            ("tis", 1e3),
            ("mil", 1e6),
            ("mlr", 1e9),
            ("mlrd", 1e9),
            ("mld", 1e9),
        ],
        "ro" => &[("k", 1e3), ("mii", 1e3), ("mil", 1e6), ("mld", 1e9)],
        "hu" => &[("e", 1e3), ("m", 1e6), ("mrd", 1e9)],
        "lt" => &[("tūkst", 1e3), ("mln", 1e6), ("mlrd", 1e9)],
        "lv" => &[("tūkst", 1e3), ("milj", 1e6), ("mljrd", 1e9)],
        "et" => &[("tuh", 1e3), ("mln", 1e6), ("mld", 1e9)],
        "sv" => &[("tn", 1e3), ("mn", 1e6), ("md", 1e9), ("mdr", 1e9)],
        "da" => &[("t", 1e3), ("mio", 1e6), ("mia", 1e9)],
        "no" | "nb" | "nn" => &[("k", 1e3), ("mill", 1e6), ("mrd", 1e9)],
        "fi" => &[("t", 1e3), ("milj", 1e6), ("mrd", 1e9)],
        "is" => &[("þ", 1e3), ("m", 1e6), ("ma", 1e9)],
        "el" => &[("χιλ", 1e3), ("εκ", 1e6), ("δισ", 1e9)],
        "tr" => &[("b", 1e3), ("mn", 1e6), ("mr", 1e9), ("n", 1e3)],
        "az" => &[("min", 1e3), ("mln", 1e6), ("mlrd", 1e9)],
        "uz" => &[("ming", 1e3), ("mln", 1e6), ("mlrd", 1e9)],
        "ar" => &[
            ("ألف", 1e3),
            ("آلاف", 1e3),
            ("مليون", 1e6),
            ("ملايين", 1e6),
            ("مليار", 1e9),
        ],
        "fa" => &[("هزار", 1e3), ("میلیون", 1e6), ("میلیارد", 1e9)],
        "ur" => &[("ہزار", 1e3), ("لاکھ", 1e5), ("کروڑ", 1e7), ("ارب", 1e9)],
        "iw" | "he" => &[
            ("k", 1e3),
            ("m", 1e6),
            ("b", 1e9),
            ("אלף", 1e3),
            ("מיליון", 1e6),
        ],
        "hi" | "mr" | "ne" => &[
            ("हज़ार", 1e3),
            ("हजार", 1e3),
            ("ह", 1e3),
            ("लाख", 1e5),
            ("ला", 1e5),
            ("करोड़", 1e7),
            ("क॰", 1e7),
            ("कोटी", 1e7),
            ("को", 1e7),
        ],
        "bn" => &[
            ("হা", 1e3),
            ("হাজার", 1e3),
            ("লা", 1e5),
            ("লাখ", 1e5),
            ("কো", 1e7),
            ("কোটি", 1e7),
        ],
        "vi" => &[("n", 1e3), ("k", 1e3), ("tr", 1e6), ("t", 1e9)],
        "id" => &[("rb", 1e3), ("jt", 1e6), ("m", 1e9)],
        "ms" => &[("k", 1e3), ("rb", 1e3), ("j", 1e6), ("jt", 1e6), ("b", 1e9)],
        "sw" => &[("elfu", 1e3), ("k", 1e3), ("m", 1e6), ("b", 1e9)],
        "af" => &[("k", 1e3), ("m", 1e6), ("mjd", 1e9)],
        _ => &[
            ("k", 1e3),
            ("m", 1e6),
            ("b", 1e9),
            ("kk", 1e6),
            ("lakh", 1e5),
            ("crore", 1e7),
        ],
    }
}

/// The value of [c] as a decimal digit in any of the scripts YouTube
/// writes numbers in.
fn digit(c: char) -> Option<u32> {
    if let Some(d) = c.to_digit(10) {
        return Some(d);
    }
    const ZEROS: [u32; 16] = [
        0x0660, 0x06f0, 0x0966, 0x09e6, 0x0a66, 0x0ae6, 0x0b66, 0x0be6, 0x0c66, 0x0ce6, 0x0d66,
        0x0e50, 0x0ed0, 0x17e0, 0x1040, 0x0de6,
    ];
    let code = c as u32;
    ZEROS
        .iter()
        .find(|&&zero| (zero..zero + 10).contains(&code))
        .map(|zero| code - zero)
}

fn is_space(c: char) -> bool {
    c == ' ' || c == '\u{a0}' || c == '\u{202f}' || c == '\u{2009}'
}

/// The first count in [text] as YouTube writes it in [hl]; a number with
/// no unit after it is read whole, its separators left out ("12.345",
/// "1 234 567", "1,23,456").
pub fn count_in(text: &str, hl: &str) -> Option<u64> {
    let chars: Vec<char> = text.chars().collect();
    let start = chars.iter().position(|&c| digit(c).is_some())?;
    // The number: digits, separators between them, and spaces that group
    // digits ("1 234").
    let mut end = start;
    while end < chars.len() {
        let c = chars[end];
        let next_is_digit = chars.get(end + 1).is_some_and(|&n| digit(n).is_some());
        if digit(c).is_some()
            || (matches!(c, '.' | ',' | '\'' | '’' | '٫' | '٬') && next_is_digit)
            || (is_space(c) && next_is_digit)
        {
            end += 1;
        } else {
            break;
        }
    }
    let number = &chars[start..end];
    let mut rest = end;
    while rest < chars.len() && is_space(chars[rest]) {
        rest += 1;
    }
    let after: String = chars[rest..].iter().collect();
    let factor = unit_of(&after, hl);
    let whole: String = number
        .iter()
        .filter_map(|&c| digit(c))
        .map(|d| char::from_digit(d, 10).unwrap_or('0'))
        .collect();
    let Some(factor) = factor else {
        return whole.parse().ok();
    };
    // With a unit, the last separator is the decimal point ("1,2 Mio.").
    let decimals = number
        .iter()
        .rposition(|&c| matches!(c, '.' | ',' | '٫'))
        .map_or(0, |at| {
            number[at + 1..]
                .iter()
                .filter(|&&c| digit(c).is_some())
                .count()
        });
    let value: f64 = whole.parse::<f64>().ok()? / 10f64.powi(decimals as i32);
    Some((value * factor).round() as u64)
}

/// The factor of the unit at the start of [after], if it is one of [hl]'s.
fn unit_of(after: &str, hl: &str) -> Option<f64> {
    if let Some((_, factor)) = GLUED.iter().find(|(unit, _)| after.starts_with(unit)) {
        return Some(*factor);
    }
    // A unit of the language first, then the common K, M and B: a list
    // may be in another language than the one asked for. Units are short,
    // so only the start of the text is lowercased, once.
    let lower = after.chars().take(32).collect::<String>().to_lowercase();
    word_unit(&lower, units(hl))
        .or_else(|| word_unit(&lower, units("")))
        .or_else(|| anywhere(&lower))
}

/// Languages with units of their own, for [anywhere].
const LANGUAGES: &[&str] = &[
    "de", "fr", "es", "ca", "pt", "it", "nl", "ru", "uk", "be", "bg", "sr", "kk", "pl", "cs", "hr",
    "ro", "hu", "lt", "lv", "et", "sv", "da", "no", "fi", "is", "el", "tr", "az", "uz", "ar", "fa",
    "ur", "he", "hi", "bn", "vi", "id", "ms", "sw", "af", "sq", "eu", "hy", "ka", "am", "si", "ta",
    "te", "kn", "ml", "gu", "pa", "or", "as", "jv", "su",
];

/// A unit of any language, when every language that has it gives it the
/// same value ("Mio." is a million wherever it is written, "B" is not).
fn anywhere(after: &str) -> Option<f64> {
    let mut found: Option<f64> = None;
    for hl in LANGUAGES {
        if let Some(factor) = word_unit(after, units(hl)) {
            match found {
                Some(seen) if seen != factor => return None,
                _ => found = Some(factor),
            }
        }
    }
    found
}

/// The unit of [table] that is the whole first word of [lower].
fn word_unit(lower: &str, table: &[(&str, f64)]) -> Option<f64> {
    // A unit is a whole word: "mil m" before "mil", "mill" never as "mil".
    let mut best: Option<(usize, f64)> = None;
    for &(unit, factor) in table {
        if !lower.starts_with(unit) {
            continue;
        }
        let tail = &lower[unit.len()..];
        let ends = tail
            .chars()
            .next()
            .is_none_or(|c| !c.is_alphanumeric() || c == '॰');
        if ends && best.is_none_or(|(len, _)| unit.len() > len) {
            best = Some((unit.len(), factor));
        }
    }
    best.map(|(_, factor)| factor)
}

/// [count_in] in the language set with [set_language].
pub fn count(text: &str) -> Option<u64> {
    count_in(text, &language())
}

/// Whether [text]'s first number has a unit after it ("1,2 Mio."), so it
/// is a count and not "3 days".
pub fn has_unit(text: &str) -> bool {
    let chars: Vec<char> = text.chars().collect();
    let Some(start) = chars.iter().position(|&c| digit(c).is_some()) else {
        return false;
    };
    let mut end = start;
    while end < chars.len()
        && (digit(chars[end]).is_some()
            || (matches!(chars[end], '.' | ',' | '٫')
                && chars.get(end + 1).is_some_and(|&n| digit(n).is_some())))
    {
        end += 1;
    }
    let after: String = chars[end..].iter().collect();
    unit_of(after.trim_start_matches(is_space), &language()).is_some()
}

/// Tells the core which `hl` YouTube is asked in, for the counts it reads.
///
/// # Safety
/// [hl] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_set_language(hl: *const u8, length: usize) -> *mut c_char {
    set_language(unsafe { text(hl, length) });
    std::ptr::null_mut()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_counts_in_many_languages() {
        let cases: &[(&str, &str, u64)] = &[
            ("en", "358K views", 358_000),
            ("en", "1.2M views", 1_200_000),
            ("en", "1,234,567 views", 1_234_567),
            ("zh-CN", "10.9万次观看", 109_000),
            ("zh-TW", "5.1萬次觀看", 51_000),
            ("ja", "3.4億 回視聴", 340_000_000),
            ("ko", "조회수 1.2만회", 12_000),
            ("de", "1,2 Mio. Aufrufe", 1_200_000),
            ("de", "12.345 Aufrufe", 12_345),
            ("de", "51 Tsd. Aufrufe", 51_000),
            ("fr", "1,2 k vues", 1_200),
            ("fr", "3,4 M de vues", 3_400_000),
            ("fr", "1\u{202f}234 vues", 1_234),
            ("es", "12 mil visualizaciones", 12_000),
            ("es", "1,2 M de visualizaciones", 1_200_000),
            ("pt-BR", "1,2 mi de visualizações", 1_200_000),
            ("pt-BR", "35 mil visualizações", 35_000),
            ("it", "1,2 Mln di visualizzazioni", 1_200_000),
            ("ru", "1,2 млн просмотров", 1_200_000),
            ("ru", "35 тыс. просмотров", 35_000),
            ("ru", "1 234 просмотра", 1_234),
            ("uk", "35 тис. переглядів", 35_000),
            ("pl", "35 tys. wyświetleń", 35_000),
            ("tr", "35 B görüntüleme", 35_000),
            ("tr", "1,2 Mn görüntüleme", 1_200_000),
            ("id", "1,2 jt x ditonton", 1_200_000),
            ("id", "3 M x ditonton", 3_000_000_000),
            ("vi", "1,2 Tr lượt xem", 1_200_000),
            ("vi", "35 N lượt xem", 35_000),
            ("hi", "1.2 लाख बार देखा गया", 120_000),
            ("ar", "1.2 مليون مشاهدة", 1_200_000),
            ("ar", "٣٥ ألف مشاهدة", 35_000),
            ("th", "ดู 1.2 แสน ครั้ง", 120_000),
            ("sv", "35 tn visningar", 35_000),
            ("nl", "1,2 mln. weergaven", 1_200_000),
            ("cs", "35 tis. zhlédnutí", 35_000),
            ("hu", "35 E megtekintés", 35_000),
            ("el", "35 χιλ. προβολές", 35_000),
            ("sr-Latn", "35 hilj. pregleda", 35_000),
            ("hy", "35 հզր դիտում", 35_000),
            ("ka", "1,2 მლნ ნახვა", 1_200_000),
            ("km", "ការមើល 1.2ម៉ឺនដង", 12_000),
            ("my", "ကြည့်ရှုမှု ၁.၂သိန်း", 120_000),
            ("ta", "1.2ஆ பார்வைகள்", 1_200),
            ("gu", "1.2 લાખ વ્યૂ", 120_000),
            ("sq", "35 mijë shikime", 35_000),
        ];
        for (hl, text, want) in cases {
            assert_eq!(count_in(text, hl), Some(*want), "{hl}: {text}");
        }
        assert_eq!(count_in("no number", "en"), None);
        // "mil" is a thousand in Spanish, a million in Czech.
        assert_eq!(count_in("2 mil", "cs"), Some(2_000_000));
        // Words that only start like a unit are not one.
        assert_eq!(count_in("3 months ago", "en"), Some(3));
        assert_eq!(count_in("3 Monaten", "de"), Some(3));
        // In a language that has none, a unit no language reads otherwise.
        assert_eq!(count_in("1,2 Mio. Aufrufe", "en"), Some(1_200_000));
        assert_eq!(count_in("35 тыс. просмотров", "ja"), Some(35_000));
    }

    #[test]
    fn the_language_set_is_used() {
        set_language("tr");
        assert_eq!(count("35 B görüntüleme"), Some(35_000));
        set_language("en");
        assert_eq!(count("35B views"), Some(35_000_000_000));
    }
}
