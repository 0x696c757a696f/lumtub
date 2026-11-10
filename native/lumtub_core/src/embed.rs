//! What a saved file carries besides picture and sound: subtitle tracks,
//! a title and a cover picture.

use crate::cast::Subtitles;

/// The extras of a saved file.
#[derive(Default)]
pub struct Extras {
    pub texts: Vec<Subtitles>,
    pub title: Option<String>,
    /// A JPEG or PNG picture.
    pub cover: Option<Vec<u8>>,
}

impl Extras {
    pub fn is_empty(&self) -> bool {
        self.texts.is_empty() && self.title.is_none() && self.cover.is_none()
    }
}

/// Whether `bytes` are a PNG picture (else JPEG is assumed).
pub fn is_png(bytes: &[u8]) -> bool {
    bytes.starts_with(b"\x89PNG")
}

/// The ISO 639-2 code of a BCP 47 `language` (`zh-Hans` → `chi`), or
/// `und`, for players that read only the old three-letter field.
pub fn iso639_2(language: &str) -> &'static str {
    let primary = language.split(['-', '_']).next().unwrap_or("").to_ascii_lowercase();
    match primary.as_str() {
        "af" => "afr",
        "am" => "amh",
        "ar" => "ara",
        "az" => "aze",
        "be" => "bel",
        "bg" => "bul",
        "bn" => "ben",
        "bs" => "bos",
        "ca" => "cat",
        "cs" => "cze",
        "cy" => "wel",
        "da" => "dan",
        "de" => "ger",
        "el" => "gre",
        "en" => "eng",
        "es" => "spa",
        "et" => "est",
        "eu" => "baq",
        "fa" => "per",
        "fi" => "fin",
        "fil" | "tl" => "fil",
        "fr" => "fre",
        "ga" => "gle",
        "gl" => "glg",
        "gu" => "guj",
        "he" | "iw" => "heb",
        "hi" => "hin",
        "hr" => "hrv",
        "hu" => "hun",
        "hy" => "arm",
        "id" | "in" => "ind",
        "is" => "ice",
        "it" => "ita",
        "ja" => "jpn",
        "ka" => "geo",
        "kk" => "kaz",
        "km" => "khm",
        "kn" => "kan",
        "ko" => "kor",
        "ky" => "kir",
        "lo" => "lao",
        "lt" => "lit",
        "lv" => "lav",
        "mk" => "mac",
        "ml" => "mal",
        "mn" => "mon",
        "mr" => "mar",
        "ms" => "may",
        "my" => "bur",
        "nb" | "no" => "nor",
        "ne" => "nep",
        "nl" => "dut",
        "pa" => "pan",
        "pl" => "pol",
        "pt" => "por",
        "ro" => "rum",
        "ru" => "rus",
        "si" => "sin",
        "sk" => "slo",
        "sl" => "slv",
        "sq" => "alb",
        "sr" => "srp",
        "sv" => "swe",
        "sw" => "swa",
        "ta" => "tam",
        "te" => "tel",
        "th" => "tha",
        "tr" => "tur",
        "uk" => "ukr",
        "ur" => "urd",
        "uz" => "uzb",
        "vi" => "vie",
        "yue" => "chi",
        "zh" => "chi",
        "zu" => "zul",
        _ => "und",
    }
}

/// The terminology form of [iso639_2] that MP4 takes (`zho`, not `chi`).
pub fn iso639_2t(language: &str) -> &'static str {
    match iso639_2(language) {
        "alb" => "sqi",
        "arm" => "hye",
        "baq" => "eus",
        "bur" => "mya",
        "chi" => "zho",
        "cze" => "ces",
        "dut" => "nld",
        "fre" => "fra",
        "geo" => "kat",
        "ger" => "deu",
        "gre" => "ell",
        "ice" => "isl",
        "mac" => "mkd",
        "may" => "msa",
        "per" => "fas",
        "rum" => "ron",
        "slo" => "slk",
        "wel" => "cym",
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_languages_in_three_letters() {
        assert_eq!(iso639_2("zh-Hans"), "chi");
        assert_eq!(iso639_2("en-US"), "eng");
        assert_eq!(iso639_2("pt_BR"), "por");
        assert_eq!(iso639_2(""), "und");
        assert_eq!(iso639_2("xx"), "und");
        assert_eq!(iso639_2t("zh-Hant"), "zho");
        assert_eq!(iso639_2t("ja"), "jpn");
    }
}
