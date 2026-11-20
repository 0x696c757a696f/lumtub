//! Which video formats may play and in what order (see lib/format_policy.dart
//! for the side that calls this): first the disabled codecs are removed,
//! then the rest is ordered by the playback strategy. A fallback only ever
//! goes to another allowed codec.

#![allow(clippy::missing_safety_doc)]

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::ffi::c_char;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Codec {
    Av1,
    Vp9,
    H264,
    Vp8,
}

impl Codec {
    /// The order codecs are listed in when nothing else decides.
    pub(crate) const ALL: [Codec; 4] = [Codec::Av1, Codec::Vp9, Codec::H264, Codec::Vp8];

    /// The family of a codec name such as `av01.0.08M.08` or `avc1.640028`;
    /// none for audio-only (`none`), missing or unknown codecs.
    pub(crate) fn of(name: &str) -> Option<Codec> {
        let name = name.trim().to_lowercase();
        Codec::ALL
            .into_iter()
            .find(|c| c.prefixes().iter().any(|p| name.starts_with(p)))
    }

    /// Lower-case name prefixes that mean this codec.
    fn prefixes(self) -> &'static [&'static str] {
        match self {
            Codec::Av1 => &["av01", "av1"],
            Codec::Vp9 => &["vp09", "vp9"],
            Codec::H264 => &["avc1", "avc3", "h264"],
            Codec::Vp8 => &["vp08", "vp8"],
        }
    }

    /// yt-dlp's name for it in `--format-sort`.
    fn sort_name(self) -> &'static str {
        match self {
            Codec::Av1 => "av01",
            Codec::Vp9 => "vp9",
            Codec::H264 => "avc",
            Codec::Vp8 => "vp8",
        }
    }

    /// yt-dlp filters dropping this codec, one per name prefix.
    fn exclude_filter(self) -> String {
        self.prefixes()
            .iter()
            .map(|p| format!("[vcodec!^={p}]"))
            .collect()
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum Strategy {
    #[default]
    Auto,
    Quality,
    LowResource,
}

#[derive(Clone, Copy, PartialEq, Eq, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum Audio {
    #[default]
    Best,
    Medium,
    Low,
}

/// Which version of a video with high dynamic range plays.
#[derive(Clone, Copy, PartialEq, Eq, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum Hdr {
    /// Standard range, except with the quality strategy.
    #[default]
    Auto,
    Sdr,
    Hdr,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub strategy: Strategy,
    pub disabled: Vec<Codec>,
    /// Codecs whose hardware decoding was verified, with hardware decoding on.
    pub hardware: Vec<Codec>,
    /// The tallest picture each of [Settings::hardware] decodes in
    /// hardware, where the probe measured it (a phone's VP9 decoder may stop
    /// at 1080p while its screen and YouTube go higher).
    pub hardware_heights: HashMap<Codec, u32>,
    /// 0 for no cap.
    pub max_height: u32,
    pub audio: Audio,
    pub hdr: Hdr,
    /// The language of the audio track to play instead of the original,
    /// as YouTube names it (`it`, `es-US`); empty for the original.
    pub audio_language: String,
    /// The tallest display in physical pixels; 0 when unknown.
    pub display: u32,
}

#[derive(Serialize, PartialEq, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Policy {
    /// The allowed codecs, most preferred first.
    pub order: Vec<&'static str>,
    /// The yt-dlp format expression.
    pub expression: String,
    /// yt-dlp's `--format-sort`, or none for its own ranking.
    pub format_sort: Option<String>,
    /// The quality cap for [Settings::display], 0 for none.
    pub display_height: u32,
}

fn name(codec: Codec) -> &'static str {
    match codec {
        Codec::Av1 => "av1",
        Codec::Vp9 => "vp9",
        Codec::H264 => "h264",
        Codec::Vp8 => "vp8",
    }
}

impl Settings {
    fn allows(&self, codec: Codec) -> bool {
        !self.disabled.contains(&codec)
    }

    fn hardware(&self, codec: Codec) -> bool {
        codec != Codec::Vp8 && self.hardware.contains(&codec)
    }

    /// How tall [codec] decodes in hardware; 0 when unknown.
    fn hardware_height(&self, codec: Codec) -> u32 {
        self.hardware_heights.get(&codec).copied().unwrap_or(0)
    }

    /// The tallest picture VP9 or AV1 decodes in hardware, when every one
    /// of them decoding in hardware has a measured height; else 0.
    fn tallest_hardware(&self) -> u32 {
        let heights: Vec<u32> = [Codec::Vp9, Codec::Av1]
            .into_iter()
            .filter(|&c| self.allows(c) && self.hardware(c))
            .map(|c| self.hardware_height(c))
            .collect();
        if heights.is_empty() || heights.contains(&0) {
            return 0;
        }
        heights.into_iter().max().unwrap_or(0)
    }

    /// AV1 in hardware goes before VP9 in hardware unless its decoder stops
    /// lower than VP9's, as both measured.
    fn av1_first(&self) -> bool {
        let (av1, vp9) = (
            self.hardware_height(Codec::Av1),
            self.hardware_height(Codec::Vp9),
        );
        !(self.hardware(Codec::Vp9) && av1 > 0 && vp9 > av1)
    }

    /// - auto: AV1 hardware decoding, then VP9 hardware decoding, then H.264;
    ///   without verified hardware decoding H.264 first, then VP9 and AV1.
    /// - lowResource: H.264, then codecs with verified hardware decoding,
    ///   then the rest. Above 1080p the verified ones go first, as H.264
    ///   cannot reach that height.
    /// - quality: no preference (VP9, AV1, H.264, VP8 as a tie-break),
    ///   except that without AV1 hardware decoding VP9 comes first: at the
    ///   same size and frame rate it looks as good and costs the CPU less.
    pub fn codec_order(&self) -> Vec<Codec> {
        let all: Vec<Codec> = Codec::ALL.into_iter().filter(|&c| self.allows(c)).collect();
        let verified: Vec<Codec> = all
            .iter()
            .copied()
            .filter(|&c| matches!(c, Codec::Vp9 | Codec::Av1) && self.hardware(c))
            .collect();
        let h264: Vec<Codec> = all.iter().copied().filter(|&c| c == Codec::H264).collect();
        let front: Vec<Codec> = match self.strategy {
            Strategy::Quality if self.hardware(Codec::Av1) => vec![],
            Strategy::Quality => vec![Codec::Vp9],
            Strategy::Auto if self.hardware(Codec::Av1) && self.av1_first() => {
                [vec![Codec::Av1, Codec::Vp9], h264].concat()
            }
            Strategy::Auto if self.hardware(Codec::Av1) => {
                [vec![Codec::Vp9, Codec::Av1], h264].concat()
            }
            Strategy::Auto if self.hardware(Codec::Vp9) => {
                [vec![Codec::Vp9], h264, vec![Codec::Av1]].concat()
            }
            Strategy::Auto => [h264, vec![Codec::Vp9, Codec::Av1]].concat(),
            Strategy::LowResource => {
                let tall = self.max_height > 1080;
                [if tall { verified.clone() } else { vec![] }, h264, verified].concat()
            }
        };
        let mut order: Vec<Codec> = Vec::new();
        for codec in front.into_iter().chain(all.iter().copied()) {
            if all.contains(&codec) && !order.contains(&codec) {
                order.push(codec);
            }
        }
        order
    }

    /// The automatic quality cap: the tallest display, and 1080p until VP9
    /// or AV1 has been verified in hardware. A chosen cap, a codec
    /// restriction or the quality strategy is left alone (0).
    pub fn display_height(&self) -> u32 {
        if self.max_height > 0 || self.strategy == Strategy::Quality || !self.disabled.is_empty() {
            return 0;
        }
        const LADDER: [u32; 5] = [720, 1080, 1440, 2160, 4320];
        let modern = self.hardware(Codec::Vp9) || self.hardware(Codec::Av1);
        // Without VP9 or AV1 in hardware, 1080p (H.264); with them, as tall
        // as their hardware decoders go, so a taller picture never falls
        // to the CPU.
        let decoder = if self.strategy == Strategy::Auto && !modern {
            1080
        } else if modern {
            self.tallest_hardware()
        } else {
            0
        };
        let display = if self.display == 0 {
            0
        } else {
            LADDER
                .into_iter()
                .find(|&h| h as f64 >= self.display as f64 * 0.95)
                .unwrap_or(0)
        };
        [decoder, display]
            .into_iter()
            .filter(|&h| h > 0)
            .min()
            .unwrap_or(0)
    }

    /// [Settings::audio_language] as a filter on yt-dlp's `language` of an
    /// audio format, none for the original audio. Descriptive tracks
    /// (`en-desc`) are never a dub.
    fn language_filter(&self) -> String {
        let code = self.audio_language.trim();
        let plain = code.chars().all(|c| c.is_ascii_alphanumeric() || c == '-');
        if code.is_empty() || !plain {
            return String::new();
        }
        format!("[language^={code}][language!*=desc]")
    }

    /// Every alternative, the last `best` included, carries the exclude
    /// filters of the disabled codecs. The quality strategy is yt-dlp's own
    /// `bestvideo`, written `ytdl` when nothing restricts it.
    pub fn expression(&self) -> String {
        let height = if self.max_height > 0 {
            format!("[height<=?{}]", self.max_height)
        } else {
            String::new()
        };
        let exclude: String = Codec::ALL
            .into_iter()
            .filter(|&c| !self.allows(c))
            .map(Codec::exclude_filter)
            .collect();
        let audio = match self.audio {
            Audio::Best => "bestaudio",
            Audio::Medium => "bestaudio[abr<=?128]",
            Audio::Low => "bestaudio[abr<=?64]",
        };
        let language = self.language_filter();
        let limit = audio
            .strip_prefix("bestaudio")
            .unwrap_or_default()
            .to_owned();
        // The sound a video's own track says is the original comes before
        // whatever yt-dlp ranks first: YouTube can flag an automatic dub as
        // the default, and an old yt-dlp ranks by that.
        let originals = |exclude: &str, height: &str, limit: &str| {
            let mut out = vec![format!(
                "bestvideo{exclude}{height}+bestaudio[format_note*=original]{limit}"
            )];
            if !limit.is_empty() {
                out.push(format!(
                    "bestvideo{exclude}{height}+bestaudio[format_note*=original]"
                ));
            }
            out
        };
        // A dub in the language asked for comes first, then the original.
        let mut dubs: Vec<String> = Vec::new();
        if !language.is_empty() {
            dubs.push(format!(
                "bestvideo{exclude}{height}+bestaudio{language}{limit}"
            ));
            if !limit.is_empty() {
                dubs.push(format!("bestvideo{exclude}{height}+bestaudio{language}"));
            }
        }
        if self.strategy == Strategy::Quality {
            if height.is_empty()
                && exclude.is_empty()
                && self.audio == Audio::Best
                && dubs.is_empty()
            {
                return "ytdl".into();
            }
            dubs.extend(originals(&exclude, &height, &limit));
            dubs.push(format!("bestvideo{exclude}{height}+{audio}"));
            dubs.push(format!("best{exclude}{height}"));
            dubs.push(format!("best{exclude}"));
            return dubs.join("/");
        }
        let mut parts = dubs;
        parts.extend(originals(&exclude, &height, &limit));
        parts.push(format!("bestvideo{exclude}{height}+{audio}"));
        if audio != "bestaudio" {
            parts.push(format!("bestvideo{exclude}{height}+bestaudio"));
        }
        parts.push(format!("best{exclude}{height}"));
        parts.push(format!("best{exclude}"));
        parts.join("/")
    }

    /// Whether HDR pictures rank above standard range ones of the same size
    /// and frame rate: when asked for, or automatically with the quality
    /// strategy.
    pub(crate) fn prefers_hdr(&self) -> bool {
        match self.hdr {
            Hdr::Auto => self.strategy == Strategy::Quality,
            Hdr::Sdr => false,
            Hdr::Hdr => true,
        }
    }

    /// Picture quality first, then standard range before HDR, then the
    /// preferred codec as a tie-break. The picture reaches the screen
    /// through an 8-bit standard range texture, so HDR only costs: a
    /// 10-bit decode (VP9 profile 2, which some hardware decoders lack,
    /// sending it to the CPU) and tone mapping on the GPU every frame.
    /// YouTube has every HDR video in standard range too.
    /// The quality strategy keeps yt-dlp's own ranking, but without AV1
    /// hardware decoding VP9 (HDR VP9 too) ranks above AV1 of the same
    /// size and frame rate; a size only AV1 has still wins.
    /// The HDR choice ([Settings::hdr]) turns the range rule around.
    pub fn format_sort(&self) -> Option<String> {
        let range = if self.prefers_hdr() {
            "hdr:12"
        } else {
            "hdr:sdr"
        };
        if self.strategy == Strategy::Quality {
            let av1 = self.hardware(Codec::Av1) || !self.allows(Codec::Vp9);
            return match (av1, self.prefers_hdr()) {
                (true, true) => None,
                (true, false) => Some(format!("res,fps,{range}")),
                (false, _) => Some(format!("res,fps,{range},vcodec:vp9.2")),
            };
        }
        self.codec_order()
            .first()
            .map(|c| format!("res,fps,{range},vcodec:{}", c.sort_name()))
    }

    pub fn policy(&self) -> Policy {
        Policy {
            order: self.codec_order().into_iter().map(name).collect(),
            expression: self.expression(),
            format_sort: self.format_sort(),
            display_height: self.display_height(),
        }
    }
}

/// The policy for the settings in [json], as JSON; null when it does not
/// parse. Free it with `lumtub_string_free`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_format_policy(json: *const u8, len: usize) -> *mut c_char {
    match serde_json::from_str::<Settings>(unsafe { crate::taste::text(json, len) }) {
        Ok(settings) => crate::taste::give_json(&settings.policy()),
        Err(_) => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings(json: &str) -> Settings {
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn auto_uses_h264_until_hardware_is_verified() {
        let s = settings("{}");
        assert_eq!(s.policy().order, ["h264", "vp9", "av1", "vp8"]);
        assert!(
            s.expression()
                .starts_with("bestvideo+bestaudio[format_note*=original]/bestvideo+bestaudio/")
        );
        assert_eq!(
            settings(r#"{"hardware":["av1","vp9"]}"#).policy().order[..3],
            ["av1", "vp9", "h264"]
        );
        assert_eq!(
            settings(r#"{"hardware":["vp9"]}"#).policy().order[..3],
            ["vp9", "h264", "av1"]
        );
        assert_eq!(
            settings(r#"{"hardware":["av1"],"maxHeight":720}"#)
                .format_sort()
                .unwrap(),
            "res,fps,hdr:sdr,vcodec:av01"
        );
    }

    #[test]
    fn disabled_codecs_are_never_picked() {
        let s = settings(r#"{"disabled":["av1"],"hardware":["av1"]}"#);
        assert_eq!(s.policy().order, ["vp9", "h264", "vp8"]);
        assert_eq!(
            s.expression(),
            "bestvideo[vcodec!^=av01][vcodec!^=av1]+bestaudio[format_note*=original]/bestvideo[vcodec!^=av01][vcodec!^=av1]+bestaudio/best[vcodec!^=av01][vcodec!^=av1]/best[vcodec!^=av01][vcodec!^=av1]"
        );
    }

    #[test]
    fn low_resource_and_quality() {
        let s = settings(r#"{"strategy":"lowResource","hardware":["av1"]}"#);
        assert_eq!(s.policy().order, ["h264", "av1", "vp9", "vp8"]);
        let tall = settings(r#"{"strategy":"lowResource","maxHeight":2160,"hardware":["vp9"]}"#);
        assert_eq!(tall.policy().order[..2], ["vp9", "h264"]);
        assert_eq!(settings(r#"{"strategy":"quality"}"#).expression(), "ytdl");
        assert_eq!(
            settings(r#"{"strategy":"quality","maxHeight":480}"#).expression(),
            "bestvideo[height<=?480]+bestaudio[format_note*=original]/bestvideo[height<=?480]+bestaudio/best[height<=?480]/best"
        );
        assert_eq!(
            settings(r#"{"strategy":"quality"}"#).format_sort().unwrap(),
            "res,fps,hdr:12,vcodec:vp9.2"
        );
        assert_eq!(
            settings(r#"{"strategy":"quality"}"#).policy().order[0],
            "vp9"
        );
        assert_eq!(
            settings(r#"{"strategy":"quality","hardware":["av1"]}"#).format_sort(),
            None
        );
        assert_eq!(
            settings(r#"{"strategy":"quality","hardware":["av1"]}"#)
                .policy()
                .order,
            ["av1", "vp9", "h264", "vp8"]
        );
        assert_eq!(
            settings(r#"{"strategy":"quality","disabled":["vp9"]}"#).format_sort(),
            None
        );
        assert_eq!(
            settings(r#"{"audio":"low"}"#).expression(),
            "bestvideo+bestaudio[format_note*=original][abr<=?64]/bestvideo+bestaudio[format_note*=original]/bestvideo+bestaudio[abr<=?64]/bestvideo+bestaudio/best/best"
        );
    }

    #[test]
    fn a_dub_language_comes_before_the_original() {
        let original = settings("{}").expression();
        assert_eq!(settings(r#"{"audioLanguage":""}"#).expression(), original);
        assert_eq!(
            settings(r#"{"audioLanguage":"it"}"#).expression(),
            "bestvideo+bestaudio[language^=it][language!*=desc]/bestvideo+bestaudio[format_note*=original]/bestvideo+bestaudio/best/best"
        );
        assert_eq!(
            settings(r#"{"audioLanguage":"es-US","audio":"low","maxHeight":720}"#).expression(),
            "bestvideo[height<=?720]+bestaudio[language^=es-US][language!*=desc][abr<=?64]/bestvideo[height<=?720]+bestaudio[language^=es-US][language!*=desc]/bestvideo[height<=?720]+bestaudio[format_note*=original][abr<=?64]/bestvideo[height<=?720]+bestaudio[format_note*=original]/bestvideo[height<=?720]+bestaudio[abr<=?64]/bestvideo[height<=?720]+bestaudio/best[height<=?720]/best"
        );
        assert_eq!(
            settings(r#"{"audioLanguage":"it","strategy":"quality","disabled":["av1"]}"#)
                .expression(),
            "bestvideo[vcodec!^=av01][vcodec!^=av1]+bestaudio[language^=it][language!*=desc]/bestvideo[vcodec!^=av01][vcodec!^=av1]+bestaudio[format_note*=original]/bestvideo[vcodec!^=av01][vcodec!^=av1]+bestaudio/best[vcodec!^=av01][vcodec!^=av1]/best[vcodec!^=av01][vcodec!^=av1]"
        );
        assert_eq!(
            settings(r#"{"audioLanguage":"it]x"}"#).expression(),
            original
        );
    }

    #[test]
    fn hdr_choice() {
        assert_eq!(
            settings(r#"{"hdr":"hdr","hardware":["av1"]}"#)
                .format_sort()
                .unwrap(),
            "res,fps,hdr:12,vcodec:av01"
        );
        assert!(settings(r#"{"hdr":"hdr"}"#).prefers_hdr());
        assert!(!settings(r#"{"hdr":"sdr","strategy":"quality"}"#).prefers_hdr());
        assert_eq!(
            settings(r#"{"hdr":"sdr","strategy":"quality"}"#)
                .format_sort()
                .unwrap(),
            "res,fps,hdr:sdr,vcodec:vp9.2"
        );
        assert_eq!(
            settings(r#"{"hdr":"sdr","strategy":"quality","hardware":["av1"]}"#)
                .format_sort()
                .unwrap(),
            "res,fps,hdr:sdr"
        );
        assert_eq!(
            settings(r#"{"hdr":"hdr","strategy":"quality","hardware":["av1"]}"#).format_sort(),
            None
        );
        assert_eq!(
            settings(r#"{"hdr":"auto"}"#).format_sort().unwrap(),
            "res,fps,hdr:sdr,vcodec:avc"
        );
    }

    #[test]
    fn hardware_heights_cap_and_order() {
        let phone = settings(
            r#"{"display":2160,"hardware":["vp9","av1"],"hardwareHeights":{"vp9":2160,"av1":1080}}"#,
        );
        assert_eq!(phone.display_height(), 2160);
        assert_eq!(phone.policy().order[..3], ["vp9", "av1", "h264"]);
        let small =
            settings(r#"{"display":2160,"hardware":["vp9"],"hardwareHeights":{"vp9":1440}}"#);
        assert_eq!(small.display_height(), 1440);
        let low = settings(
            r#"{"strategy":"lowResource","hardware":["vp9"],"hardwareHeights":{"vp9":1440}}"#,
        );
        assert_eq!(low.display_height(), 1440);
        // A height not measured leaves the cap to the display.
        let unknown =
            settings(r#"{"display":2160,"hardware":["vp9","av1"],"hardwareHeights":{"vp9":1440}}"#);
        assert_eq!(unknown.display_height(), 2160);
        assert_eq!(unknown.policy().order[0], "av1");
        let chosen =
            settings(r#"{"maxHeight":2160,"hardware":["vp9"],"hardwareHeights":{"vp9":1440}}"#);
        assert_eq!(chosen.display_height(), 0);
    }

    #[test]
    fn display_cap() {
        assert_eq!(settings(r#"{"display":2160}"#).display_height(), 1080);
        assert_eq!(
            settings(r#"{"display":2160,"hardware":["vp9"]}"#).display_height(),
            2160
        );
        assert_eq!(
            settings(r#"{"display":1440,"hardware":["vp9"]}"#).display_height(),
            1440
        );
        assert_eq!(
            settings(r#"{"display":0,"hardware":["vp9"]}"#).display_height(),
            0
        );
        assert_eq!(
            settings(r#"{"display":2160,"maxHeight":720}"#).display_height(),
            0
        );
    }
}
