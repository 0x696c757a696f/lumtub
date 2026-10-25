//! What the download dialog offers and picks (see
//! lib/downloads/download_formats.dart and download_selection.dart for the
//! side that calls this): the video-only and audio-only streams of yt-dlp's
//! format list, the stream for a codec and height, the audio track and the
//! container they are copied into. Streams are never re-encoded.

#![allow(clippy::missing_safety_doc)]

use std::ffi::c_char;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::format_policy::Codec;
use crate::taste::{give_json, text};

/// A video-only stream.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct VideoFormat {
    pub id: String,
    pub codec: Codec,
    pub height: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fps: Option<f64>,
    #[serde(default)]
    pub ext: String,
    /// Bytes, exact or approximate.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tbr: Option<f64>,
    /// `SDR`, `HDR10`, ... when yt-dlp says.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub range: Option<String>,
}

impl VideoFormat {
    fn hdr(&self) -> bool {
        self.range.as_ref().is_some_and(|r| !r.eq_ignore_ascii_case("SDR"))
    }
}

/// An audio-only stream.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct AudioFormat {
    pub id: String,
    /// yt-dlp's `acodec`, such as `mp4a.40.2` or `opus`.
    pub codec: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub abr: Option<f64>,
    #[serde(default)]
    pub ext: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size: Option<i64>,
    /// yt-dlp's `language_preference`: higher is the video's original language.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub language: Option<i64>,
}

impl AudioFormat {
    fn starts(&self, prefix: &str) -> bool {
        self.codec.to_lowercase().starts_with(prefix)
    }
    fn aac(&self) -> bool {
        self.starts("mp4a")
    }
    fn opus(&self) -> bool {
        self.starts("opus")
    }
    fn vorbis(&self) -> bool {
        self.starts("vorbis")
    }
}

/// The streams a video offers for download.
#[derive(Default, Deserialize, Serialize)]
pub struct Formats {
    #[serde(default)]
    pub video: Vec<VideoFormat>,
    #[serde(default)]
    pub audio: Vec<AudioFormat>,
}

/// A value as text, as Dart's `toString` gives it; empty for null.
fn string(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

fn number(value: &Value) -> Option<f64> {
    match value {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    }
}

fn int(value: &Value) -> Option<i64> {
    match value {
        Value::Number(n) => n.as_i64().or_else(|| n.as_f64().map(|f| f.trunc() as i64)),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    }
}

impl Formats {
    /// The video-only and audio-only formats of yt-dlp's `--dump-single-json`
    /// result; storyboards, formats without an address, playlist streams and
    /// loudness-boosted copies are left out.
    pub fn parse(info: &Value) -> Formats {
        let mut formats = Formats::default();
        let Some(list) = info.get("formats").and_then(Value::as_array) else {
            return formats;
        };
        for f in list.iter().filter(|f| f.is_object()) {
            let field = |key: &str| f.get(key).unwrap_or(&Value::Null);
            let id = string(field("format_id"));
            let ext = string(field("ext"));
            if id.is_empty() || string(field("url")).is_empty() || ext == "mhtml" || string(field("protocol")).contains("m3u8") {
                continue;
            }
            let vcodec = string(field("vcodec"));
            let acodec = string(field("acodec"));
            let has_audio = !acodec.is_empty() && acodec != "none";
            let size = int(field("filesize")).or_else(|| int(field("filesize_approx")));
            let tbr = number(field("tbr"));
            let height = int(field("height")).filter(|&h| h > 0);
            match (Codec::of(&vcodec), height) {
                (Some(codec), Some(height)) if !has_audio => formats.video.push(VideoFormat {
                    id,
                    codec,
                    height: height as u32,
                    fps: number(field("fps")),
                    ext,
                    size,
                    tbr,
                    range: Some(string(field("dynamic_range"))).filter(|r| !r.is_empty()),
                }),
                _ if has_audio && (vcodec.is_empty() || vcodec == "none") => {
                    // Loudness-boosted copies (`251-drc`) duplicate the normal track.
                    if id.ends_with("-drc") || string(field("format_note")).to_uppercase().contains("DRC") {
                        continue;
                    }
                    formats.audio.push(AudioFormat { id, codec: acodec, abr: number(field("abr")).or(tbr), ext, size, language: int(field("language_preference")) });
                }
                _ => {}
            }
        }
        formats
    }

    /// Codecs this video has, in the order the dialog lists them.
    pub fn codecs(&self) -> Vec<Codec> {
        [Codec::Vp9, Codec::Av1, Codec::H264, Codec::Vp8].into_iter().filter(|&c| self.video.iter().any(|f| f.codec == c)).collect()
    }

    /// The codec an automatic pick takes: the first of [preference] the
    /// video has; none (any) when it has none of them.
    pub fn automatic(&self, preference: &[Codec]) -> Option<Codec> {
        preference.iter().copied().find(|&c| self.video.iter().any(|f| f.codec == c))
    }

    /// Heights offered for [codec], highest first.
    pub fn heights(&self, codec: Option<Codec>) -> Vec<u32> {
        let mut heights: Vec<u32> = self.video.iter().filter(|f| codec.is_none_or(|c| f.codec == c)).map(|f| f.height).collect();
        heights.sort_unstable_by(|a, b| b.cmp(a));
        heights.dedup();
        heights
    }

    /// The stream at [height] (see [pick_height]) in [codec] (any when
    /// none): more frames, then SDR, then the better codec, then the higher
    /// bitrate.
    pub fn pick_video(&self, codec: Option<Codec>, height: Option<u32>) -> Option<&VideoFormat> {
        let chosen = pick_height(&self.heights(codec), height)?;
        let rank = |c: Codec| Codec::ALL.iter().position(|&x| x == c);
        let mut candidates: Vec<&VideoFormat> = self.video.iter().filter(|f| f.height == chosen && codec.is_none_or(|c| f.codec == c)).collect();
        candidates.sort_by(|a, b| {
            b.fps
                .unwrap_or(0.0)
                .total_cmp(&a.fps.unwrap_or(0.0))
                .then(a.hdr().cmp(&b.hdr()))
                .then(rank(a.codec).cmp(&rank(b.codec)))
                .then(b.tbr.unwrap_or(0.0).total_cmp(&a.tbr.unwrap_or(0.0)))
        });
        candidates.first().copied()
    }

    /// Audio tracks, best first: the video's own language, then bitrate.
    pub fn audio_best(&self) -> Vec<&AudioFormat> {
        let mut best: Vec<&AudioFormat> = self.audio.iter().collect();
        best.sort_by(|a, b| b.language.unwrap_or(-1).cmp(&a.language.unwrap_or(-1)).then(b.abr.unwrap_or(0.0).total_cmp(&a.abr.unwrap_or(0.0))));
        best
    }
}

/// The entry of [available] (highest first) for a wish of [wanted]: it,
/// else the nearest below, else the lowest above; the highest without a
/// wish.
pub fn pick_height(available: &[u32], wanted: Option<u32>) -> Option<u32> {
    let wanted = match wanted {
        Some(w) => w,
        None => return available.first().copied(),
    };
    available.iter().copied().find(|&h| h <= wanted).or_else(|| available.last().copied())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum Container {
    #[default]
    Auto,
    Mkv,
    Mp4,
    Webm,
}

/// Why a container cannot hold the streams without re-encoding.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Problem {
    Mp4Vp8,
    Mp4Audio,
    WebmH264,
    WebmAudio,
}

/// The container a video and audio pair goes into.
#[derive(Debug, Serialize)]
pub struct ContainerPlan<'a> {
    /// Never [Container::Auto].
    pub container: Container,
    pub audio: Option<&'a AudioFormat>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub problem: Option<Problem>,
}

/// Picks the audio track of [audio_best] and the container for a [video]
/// stream. MKV holds anything, MP4 AV1/VP9/H.264 with AAC or Opus, WebM
/// VP8/VP9/AV1 with Opus or Vorbis. Auto takes MP4 for H.264 with AAC,
/// WebM when everything fits it, else MKV.
pub fn plan_container<'a>(wanted: Container, video: Codec, audio_best: &[&'a AudioFormat]) -> ContainerPlan<'a> {
    let first = |test: fn(&AudioFormat) -> bool| audio_best.iter().copied().find(|a| test(a));
    let aac = first(AudioFormat::aac);
    let mp4_audio = aac.or_else(|| first(AudioFormat::opus));
    let webm_audio = first(|a| a.opus() || a.vorbis());
    let webm_video = video != Codec::H264;
    let has_audio = !audio_best.is_empty();
    let plan = |container, audio, problem| ContainerPlan { container, audio, problem };
    match wanted {
        Container::Mkv => plan(Container::Mkv, audio_best.first().copied(), None),
        Container::Mp4 => {
            let problem = if video == Codec::Vp8 {
                Some(Problem::Mp4Vp8)
            } else if has_audio && mp4_audio.is_none() {
                Some(Problem::Mp4Audio)
            } else {
                None
            };
            plan(Container::Mp4, mp4_audio, problem)
        }
        Container::Webm => {
            let problem = if !webm_video {
                Some(Problem::WebmH264)
            } else if has_audio && webm_audio.is_none() {
                Some(Problem::WebmAudio)
            } else {
                None
            };
            plan(Container::Webm, webm_audio, problem)
        }
        Container::Auto => match (video, aac, webm_audio) {
            (Codec::H264, Some(aac), _) => plan(Container::Mp4, Some(aac), None),
            (_, _, Some(webm)) if webm_video => plan(Container::Webm, Some(webm), None),
            _ => plan(Container::Mkv, audio_best.first().copied(), None),
        },
    }
}

/// What [plan] downloads: locked format ids and the container.
#[derive(Debug, Serialize)]
pub struct Selection {
    #[serde(rename = "audioOnly", skip_serializing_if = "std::ops::Not::not")]
    pub audio_only: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub codec: Option<Codec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub video: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audio: Option<String>,
    pub container: Container,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<i64>,
}

/// The selection for the dialog's options, or why there is none.
#[derive(Debug, Default, Serialize)]
pub struct Plan {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub selection: Option<Selection>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub problem: Option<Problem>,
}

/// Builds the selection for [codec] (none: the automatic one), [height]
/// and [container]; for [audio_only] the best m4a track, else the best
/// track.
pub fn plan(formats: &Formats, codec: Option<Codec>, height: Option<u32>, container: Container, audio_only: bool) -> Plan {
    let audio = formats.audio_best();
    if audio_only {
        let track = audio.iter().find(|a| a.ext == "m4a").or(audio.first());
        return Plan {
            selection: track.map(|t| Selection { audio_only: true, codec: None, height: None, video: None, audio: Some(t.id.clone()), container: Container::Mkv, size: t.size }),
            problem: None,
        };
    }
    let Some(video) = formats.pick_video(codec, height) else {
        return Plan::default();
    };
    let chosen = plan_container(container, video.codec, &audio);
    if let Some(problem) = chosen.problem {
        return Plan { selection: None, problem: Some(problem) };
    }
    let size = video.size.map(|s| s + chosen.audio.and_then(|a| a.size).unwrap_or(0));
    Plan {
        selection: Some(Selection {
            audio_only: false,
            codec: Some(video.codec),
            height: Some(video.height),
            video: Some(video.id.clone()),
            audio: chosen.audio.map(|a| a.id.clone()),
            container: chosen.container,
            size,
        }),
        problem: None,
    }
}

/// What the dialog asks: the formats and its options.
#[derive(Deserialize)]
struct Ask {
    #[serde(flatten)]
    formats: Formats,
    /// The playback codec order, for automatic picks.
    #[serde(default)]
    preference: Vec<Codec>,
    #[serde(default)]
    codec: Option<Codec>,
    #[serde(default)]
    height: Option<u32>,
    #[serde(default)]
    container: Container,
    #[serde(default, rename = "audioOnly")]
    audio_only: bool,
}

/// Everything the dialog shows for its options.
#[derive(Serialize)]
struct Answer<'a> {
    codecs: Vec<Codec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    automatic: Option<Codec>,
    heights: Vec<u32>,
    /// The picked video stream's id.
    #[serde(skip_serializing_if = "Option::is_none")]
    video: Option<&'a str>,
    /// Audio ids, best first.
    #[serde(rename = "audioBest")]
    audio_best: Vec<&'a str>,
    plan: Plan,
}

/// The download formats of yt-dlp's JSON [info]: `{video, audio}`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_download_formats(info: *const u8, length: usize) -> *mut c_char {
    let info = serde_json::from_str::<Value>(unsafe { text(info, length) }).unwrap_or(Value::Null);
    give_json(&Formats::parse(&info))
}

/// Answers the download dialog: for JSON `{video, audio, preference, codec,
/// height, container, audioOnly}`, the codecs, the automatic codec, the
/// heights, the picked stream, the audio tracks best first and the plan.
/// Null when the JSON does not read.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_download_choose(json: *const u8, length: usize) -> *mut c_char {
    let Ok(ask) = serde_json::from_str::<Ask>(unsafe { text(json, length) }) else {
        return std::ptr::null_mut();
    };
    let formats = &ask.formats;
    let codec = ask.codec.or_else(|| formats.automatic(&ask.preference));
    give_json(&Answer {
        codecs: formats.codecs(),
        automatic: formats.automatic(&ask.preference),
        heights: formats.heights(codec),
        video: formats.pick_video(codec, ask.height).map(|v| v.id.as_str()),
        audio_best: formats.audio_best().into_iter().map(|a| a.id.as_str()).collect(),
        plan: plan(formats, codec, ask.height, ask.container, ask.audio_only),
    })
}

/// The container for JSON `{container, codec, audio}` (audio best first):
/// `{container, audio, problem}`. Null when the JSON does not read.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_download_container(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        #[serde(default)]
        container: Container,
        codec: Codec,
        #[serde(default)]
        audio: Vec<AudioFormat>,
    }
    let Ok(ask) = serde_json::from_str::<Ask>(unsafe { text(json, length) }) else {
        return std::ptr::null_mut();
    };
    let audio: Vec<&AudioFormat> = ask.audio.iter().collect();
    give_json(&plan_container(ask.container, ask.codec, &audio))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn v(id: &str, codec: &str, height: u32, ext: &str, fps: f64, tbr: f64, size: Option<i64>) -> Value {
        let mut f = json!({"format_id": id, "vcodec": codec, "acodec": "none", "height": height, "fps": fps, "ext": ext, "tbr": tbr, "url": format!("http://x/{id}"), "protocol": "https"});
        if let Some(size) = size {
            f["filesize"] = json!(size);
        }
        f
    }

    fn a(id: &str, codec: &str, ext: &str, abr: f64, size: Option<i64>) -> Value {
        let mut f = json!({"format_id": id, "vcodec": "none", "acodec": codec, "ext": ext, "abr": abr, "url": format!("http://x/{id}"), "protocol": "https"});
        if let Some(size) = size {
            f["filesize_approx"] = json!(size);
        }
        f
    }

    fn info() -> Value {
        json!({"formats": [
            {"format_id": "sb0", "ext": "mhtml", "vcodec": "none", "acodec": "none", "url": "http://x/sb", "protocol": "mhtml"},
            {"format_id": "nourl", "vcodec": "avc1.4d401f", "acodec": "none", "height": 720, "ext": "mp4"},
            {"format_id": "18", "vcodec": "avc1.42001E", "acodec": "mp4a.40.2", "height": 360, "ext": "mp4", "url": "http://x/18", "protocol": "https"},
            v("401", "av01.0.12M.08", 2160, "mp4", 30.0, 9000.0, Some(900000000)),
            v("400", "av01.0.08M.08", 1440, "mp4", 30.0, 5000.0, None),
            v("313", "vp09.00.51.08", 2160, "webm", 30.0, 8000.0, Some(800000000)),
            v("271", "vp9", 1440, "webm", 30.0, 5000.0, None),
            v("248", "vp09.00.40.08", 1080, "webm", 30.0, 2500.0, Some(600000000)),
            v("303", "vp09.00.40.08", 1080, "webm", 60.0, 3500.0, Some(700000000)),
            v("137", "avc1.640028", 1080, "mp4", 30.0, 4000.0, Some(650000000)),
            v("136", "avc1.4d401f", 720, "mp4", 30.0, 2000.0, None),
            a("140", "mp4a.40.2", "m4a", 129.5, Some(10000000)),
            a("251", "opus", "webm", 130.0, Some(11000000)),
            a("251-drc", "opus", "webm", 130.0, None),
            a("139", "mp4a.40.5", "m4a", 48.0, None),
        ]})
    }

    fn ids<'a>(list: impl IntoIterator<Item = &'a str>) -> Vec<&'a str> {
        list.into_iter().collect()
    }

    #[test]
    fn parses_video_and_audio_streams() {
        let f = Formats::parse(&info());
        assert_eq!(ids(f.video.iter().map(|v| v.id.as_str())), ["401", "400", "313", "271", "248", "303", "137", "136"]);
        assert_eq!(ids(f.audio.iter().map(|a| a.id.as_str())), ["140", "251", "139"]);
        assert_eq!(f.video[0].size, Some(900000000));
        assert_eq!(f.audio[0].abr, Some(129.5));
        assert!(Formats::parse(&json!({})).video.is_empty());
        assert!(Formats::parse(&json!({"formats": "x"})).audio.is_empty());
        assert_eq!(f.codecs(), [Codec::Vp9, Codec::Av1, Codec::H264]);
    }

    #[test]
    fn picks_heights_and_streams() {
        let f = Formats::parse(&info());
        assert_eq!(f.heights(None), [2160, 1440, 1080, 720]);
        assert_eq!(f.heights(Some(Codec::Av1)), [2160, 1440]);
        let pick = |codec, height| f.pick_video(codec, height).map(|v| v.id.as_str());
        assert_eq!(pick(Some(Codec::Vp9), None), Some("313"));
        assert_eq!(pick(Some(Codec::Vp9), Some(1200)), Some("303"));
        assert_eq!(pick(Some(Codec::H264), Some(4320)), Some("137"));
        assert_eq!(pick(Some(Codec::H264), Some(480)), Some("136"));
        assert_eq!(pick(Some(Codec::Vp8), None), None);
        assert_eq!(pick(None, None), Some("401"));
        let hdr = Formats::parse(&json!({"formats": [
            {"format_id": "a", "vcodec": "vp09.02.51.10", "acodec": "none", "height": 1080, "ext": "webm", "tbr": 9000, "url": "u", "dynamic_range": "HDR10"},
            {"format_id": "b", "vcodec": "vp09.00.40.08", "acodec": "none", "height": 1080, "ext": "webm", "url": "u", "dynamic_range": "SDR"},
        ]}));
        assert_eq!(hdr.pick_video(None, None).map(|v| v.id.as_str()), Some("b"));
        assert_eq!(f.automatic(&[Codec::H264, Codec::Vp9]), Some(Codec::H264));
        assert_eq!(f.automatic(&[Codec::Vp8]), None);
    }

    #[test]
    fn orders_audio_by_language_then_bitrate() {
        let f = Formats::parse(&json!({"formats": [
            {"format_id": "251-de", "vcodec": "none", "acodec": "opus", "ext": "webm", "abr": 130, "url": "u", "language_preference": -1},
            {"format_id": "251-en", "vcodec": "none", "acodec": "opus", "ext": "webm", "abr": 130, "url": "u", "language_preference": 10},
            {"format_id": "250-en", "vcodec": "none", "acodec": "opus", "ext": "webm", "abr": 70, "url": "u", "language_preference": 10},
            {"format_id": "251-drc", "vcodec": "none", "acodec": "opus", "ext": "webm", "abr": 200, "url": "u", "format_note": "Medium, DRC"},
        ]}));
        assert_eq!(ids(f.audio_best().into_iter().map(|a| a.id.as_str())), ["251-en", "250-en", "251-de"]);
    }

    #[test]
    fn plans_containers() {
        let f = Formats::parse(&info());
        let audio = f.audio_best();
        let chosen = |wanted, codec| {
            let p = plan_container(wanted, codec, &audio);
            (p.container, p.audio.map(|a| a.id.clone()), p.problem)
        };
        assert_eq!(chosen(Container::Auto, Codec::H264), (Container::Mp4, Some("140".into()), None));
        assert_eq!(chosen(Container::Auto, Codec::Vp9), (Container::Webm, Some("251".into()), None));
        assert_eq!(chosen(Container::Mp4, Codec::Vp8).2, Some(Problem::Mp4Vp8));
        assert_eq!(chosen(Container::Webm, Codec::H264).2, Some(Problem::WebmH264));
        let aac: Vec<&AudioFormat> = audio.iter().copied().filter(|a| a.aac()).collect();
        assert_eq!(plan_container(Container::Webm, Codec::Vp9, &aac).problem, Some(Problem::WebmAudio));
        assert_eq!(plan_container(Container::Auto, Codec::Vp8, &aac).container, Container::Mkv);
    }

    #[test]
    fn plans_downloads() {
        let f = Formats::parse(&info());
        let s = plan(&f, Some(Codec::Vp9), Some(1080), Container::Auto, false).selection.unwrap();
        assert_eq!((s.video.as_deref(), s.audio.as_deref(), s.container, s.size), (Some("303"), Some("251"), Container::Webm, Some(711000000)));
        let p = plan(&f, Some(Codec::H264), None, Container::Webm, false);
        assert!(p.selection.is_none());
        assert_eq!(p.problem, Some(Problem::WebmH264));
        let s = plan(&f, None, None, Container::Auto, true).selection.unwrap();
        assert_eq!((s.audio_only, s.audio.as_deref(), s.video), (true, Some("140"), None));
    }
}
