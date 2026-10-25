//! Which video formats may play and in what order (see lib/format_policy.dart
//! for the side that calls this): first the disabled codecs are removed,
//! then the rest is ordered by the playback strategy. A fallback only ever
//! goes to another allowed codec.

#![allow(clippy::missing_safety_doc)]

use serde::{Deserialize, Serialize};
use std::ffi::c_char;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
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
        Codec::ALL.into_iter().find(|c| c.prefixes().iter().any(|p| name.starts_with(p)))
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
        self.prefixes().iter().map(|p| format!("[vcodec!^={p}]")).collect()
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

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub strategy: Strategy,
    pub disabled: Vec<Codec>,
    /// Codecs whose hardware decoding was verified, with hardware decoding on.
    pub hardware: Vec<Codec>,
    /// 0 for no cap.
    pub max_height: u32,
    pub audio: Audio,
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

    /// - auto: AV1 hardware decoding, then VP9 hardware decoding, then H.264;
    ///   without verified hardware decoding H.264 first, then VP9 and AV1.
    /// - lowResource: H.264, then codecs with verified hardware decoding,
    ///   then the rest. Above 1080p the verified ones go first, as H.264
    ///   cannot reach that height.
    /// - quality: no preference (VP9, AV1, H.264, VP8 as a tie-break).
    pub fn codec_order(&self) -> Vec<Codec> {
        let all: Vec<Codec> = Codec::ALL.into_iter().filter(|&c| self.allows(c)).collect();
        let verified: Vec<Codec> = all.iter().copied().filter(|&c| matches!(c, Codec::Vp9 | Codec::Av1) && self.hardware(c)).collect();
        let h264: Vec<Codec> = all.iter().copied().filter(|&c| c == Codec::H264).collect();
        let front: Vec<Codec> = match self.strategy {
            Strategy::Quality => vec![],
            Strategy::Auto if self.hardware(Codec::Av1) => [vec![Codec::Av1, Codec::Vp9], h264].concat(),
            Strategy::Auto if self.hardware(Codec::Vp9) => [vec![Codec::Vp9], h264, vec![Codec::Av1]].concat(),
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
        let decoder = if self.strategy == Strategy::Auto && !modern { 1080 } else { 0 };
        let display = if self.display == 0 {
            0
        } else {
            LADDER.into_iter().find(|&h| h as f64 >= self.display as f64 * 0.95).unwrap_or(0)
        };
        [decoder, display].into_iter().filter(|&h| h > 0).min().unwrap_or(0)
    }

    /// Every alternative, the last `best` included, carries the exclude
    /// filters of the disabled codecs. The quality strategy is yt-dlp's own
    /// `bestvideo`, written `ytdl` when nothing restricts it.
    pub fn expression(&self) -> String {
        let height = if self.max_height > 0 { format!("[height<=?{}]", self.max_height) } else { String::new() };
        let exclude: String = Codec::ALL.into_iter().filter(|&c| !self.allows(c)).map(Codec::exclude_filter).collect();
        let audio = match self.audio {
            Audio::Best => "bestaudio",
            Audio::Medium => "bestaudio[abr<=?128]",
            Audio::Low => "bestaudio[abr<=?64]",
        };
        if self.strategy == Strategy::Quality {
            if height.is_empty() && exclude.is_empty() && self.audio == Audio::Best {
                return "ytdl".into();
            }
            return format!("bestvideo{exclude}{height}+{audio}/best{exclude}{height}/best{exclude}");
        }
        let mut parts = vec![format!("bestvideo{exclude}{height}+{audio}")];
        if audio != "bestaudio" {
            parts.push(format!("bestvideo{exclude}{height}+bestaudio"));
        }
        parts.push(format!("best{exclude}{height}"));
        parts.push(format!("best{exclude}"));
        parts.join("/")
    }

    /// Picture quality first, then the preferred codec as a tie-break.
    pub fn format_sort(&self) -> Option<String> {
        if self.strategy == Strategy::Quality {
            return None;
        }
        self.codec_order().first().map(|c| format!("res,fps,vcodec:{}", c.sort_name()))
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
        assert!(s.expression().starts_with("bestvideo+bestaudio/"));
        assert_eq!(settings(r#"{"hardware":["av1","vp9"]}"#).policy().order[..3], ["av1", "vp9", "h264"]);
        assert_eq!(settings(r#"{"hardware":["vp9"]}"#).policy().order[..3], ["vp9", "h264", "av1"]);
        assert_eq!(settings(r#"{"hardware":["av1"],"maxHeight":720}"#).format_sort().unwrap(), "res,fps,vcodec:av01");
    }

    #[test]
    fn disabled_codecs_are_never_picked() {
        let s = settings(r#"{"disabled":["av1"],"hardware":["av1"]}"#);
        assert_eq!(s.policy().order, ["vp9", "h264", "vp8"]);
        assert_eq!(s.expression(), "bestvideo[vcodec!^=av01][vcodec!^=av1]+bestaudio/best[vcodec!^=av01][vcodec!^=av1]/best[vcodec!^=av01][vcodec!^=av1]");
    }

    #[test]
    fn low_resource_and_quality() {
        let s = settings(r#"{"strategy":"lowResource","hardware":["av1"]}"#);
        assert_eq!(s.policy().order, ["h264", "av1", "vp9", "vp8"]);
        let tall = settings(r#"{"strategy":"lowResource","maxHeight":2160,"hardware":["vp9"]}"#);
        assert_eq!(tall.policy().order[..2], ["vp9", "h264"]);
        assert_eq!(settings(r#"{"strategy":"quality"}"#).expression(), "ytdl");
        assert_eq!(settings(r#"{"strategy":"quality","maxHeight":480}"#).expression(), "bestvideo[height<=?480]+bestaudio/best[height<=?480]/best");
        assert_eq!(settings(r#"{"strategy":"quality"}"#).format_sort(), None);
        assert_eq!(settings(r#"{"audio":"low"}"#).expression(), "bestvideo+bestaudio[abr<=?64]/bestvideo+bestaudio/best/best");
    }

    #[test]
    fn display_cap() {
        assert_eq!(settings(r#"{"display":2160}"#).display_height(), 1080);
        assert_eq!(settings(r#"{"display":2160,"hardware":["vp9"]}"#).display_height(), 2160);
        assert_eq!(settings(r#"{"display":1440,"hardware":["vp9"]}"#).display_height(), 1440);
        assert_eq!(settings(r#"{"display":0,"hardware":["vp9"]}"#).display_height(), 0);
        assert_eq!(settings(r#"{"display":2160,"maxHeight":720}"#).display_height(), 0);
    }
}
