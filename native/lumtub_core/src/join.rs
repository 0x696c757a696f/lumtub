//! Joins a downloaded picture and sound into one file, without ffmpeg:
//! the cast stream writer ([crate::cast::Session]) reads the two files
//! instead of YouTube's addresses. The picture may be H.264 or AV1 in MP4,
//! or VP9 in WebM; the sound AAC or Dolby (AC-3, E-AC-3) in MP4, or Opus
//! in WebM. Left to choose, AAC and Dolby make an MP4 and Opus a WebM (an
//! MKV beside H.264); asked, any of them goes into MP4 or MKV, and Opus
//! with VP9 or AV1 into WebM.

use std::ffi::c_char;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::collections::HashMap;
use std::sync::Arc;

use serde::Deserialize;

use crate::cast::{Ask, Kind, Session};
use crate::cast_webm;
use crate::record::Unindexed;
use crate::relay::{Fetch, Target};
use crate::taste::{give, text};

/// Local files read like YouTube's streams: the address is the path and
/// the byte range comes after `&range=`. A recorded live stream is read
/// with the index it lacks ([crate::record]).
#[derive(Default)]
struct Files(HashMap<String, Unindexed>);

impl Fetch for Files {
    fn get(&self, _: &Target, url: &str) -> Result<(u16, Box<dyn Read + Send>), String> {
        let (path, range) = url.rsplit_once("&range=").ok_or("no range")?;
        let (from, to) = range.split_once('-').ok_or("bad range")?;
        let (from, to): (u64, u64) = (from.parse().map_err(|_| "bad range")?, to.parse().map_err(|_| "bad range")?);
        if let Some(seen) = self.0.get(path) {
            return Ok((206, seen.read(path, from, to)?));
        }
        let mut file = File::open(path).map_err(|e| e.to_string())?;
        file.seek(SeekFrom::Start(from)).map_err(|e| e.to_string())?;
        Ok((206, Box::new(file.take((to + 1).saturating_sub(from)))))
    }
}

impl Files {
    fn target(&mut self, path: &str) -> Result<Target, String> {
        let size = match crate::record::unindexed(path)? {
            Some(seen) => {
                let size = seen.len();
                self.0.insert(path.to_string(), seen);
                size
            }
            None => std::fs::metadata(path).map_err(|e| format!("{path}: {e}"))?.len(),
        };
        Ok(Target { url: path.to_string(), size, user_agent: None, mime: None, proxy: None, chunk: 8 << 20, live: None })
    }
}

/// Whether the file at `path` is WebM (or other Matroska).
fn is_webm(path: &str) -> Result<bool, String> {
    let mut start = [0u8; 4];
    let read = File::open(path).and_then(|mut f| f.read(&mut start)).map_err(|e| format!("{path}: {e}"))?;
    Ok(cast_webm::is_webm(&start[..read]))
}

/// A subtitle file (WebVTT or SRT) to carry as a track.
#[derive(Deserialize, Default, Clone)]
pub struct Text {
    pub path: String,
    #[serde(default)]
    pub language: String,
    #[serde(default)]
    pub name: String,
}

/// What a joined file carries besides picture and sound.
#[derive(Deserialize, Default)]
pub struct Extra {
    #[serde(default)]
    pub subtitles: Vec<Text>,
    #[serde(default)]
    pub title: Option<String>,
    /// A JPEG or PNG file.
    #[serde(default)]
    pub cover: Option<String>,
    /// Stretches to leave out, in seconds (SponsorBlock's segments).
    #[serde(default)]
    pub cut: Vec<(f64, f64)>,
}

/// A joined file and what it leaves out, in ms from its start.
pub struct Joined {
    pub path: String,
    pub cut: Vec<(i64, i64)>,
}

impl Extra {
    /// The subtitle files read, a file that cannot be read or holds no
    /// lines left out, and the cover read.
    fn read(&self) -> crate::embed::Extras {
        let texts = self
            .subtitles
            .iter()
            .filter_map(|t| {
                let source = std::fs::read(&t.path).ok()?;
                let cues: Vec<(u64, u64, String)> = crate::subtitles::cues(&String::from_utf8_lossy(&source)).into_iter().map(|c| (c.start, c.end, c.text)).collect();
                (!cues.is_empty()).then(|| crate::cast::Subtitles { language: t.language.clone(), name: t.name.clone(), cues })
            })
            .collect();
        let cover = self.cover.as_ref().and_then(|p| std::fs::read(p).ok()).filter(|b| b.starts_with(&[0xFF, 0xD8]) || crate::embed::is_png(b));
        crate::embed::Extras { texts, title: self.title.clone().filter(|t| !t.is_empty()), cover }
    }
}

/// Writes `video` and `audio` joined into `stem` plus the extension of
/// `container` (`mp4`, `webm` or `mkv`; any other word picks what fits),
/// with `extra` inside where the container takes it (WebM takes none),
/// and returns that path. The file is written beside as `.part` and
/// renamed when whole.
pub fn join(video: &str, audio: &str, stem: &str, container: &str, extra: &Extra) -> Result<Joined, String> {
    let mut files = Files::default();
    let (video_target, audio_target) = (files.target(video)?, files.target(audio)?);
    let fetch: Arc<dyn Fetch> = Arc::new(files);
    let kind = match container {
        "mp4" => Kind::Mp4,
        "webm" | "mkv" => Kind::Mkv,
        _ if is_webm(audio)? => Kind::Mkv,
        _ => Kind::Mp4,
    };
    let ask = Ask { video: video_target, audio: audio_target, start_ms: 0, kind, duration_ms: 0, subtitles: None };
    let mut session = Session::new(ask, &fetch)?;
    if container == "mkv" {
        session = session.plain_matroska();
    }
    if container != "webm" {
        session = session.with_extras(extra.read());
    }
    session = session.with_cut(extra.cut.clone());
    let cuts = session.cuts();
    let cut = cuts.stretches().to_vec();
    if container == "webm" && session.extension() != "webm" {
        return Err("WebM takes only VP9 or AV1 with Opus".into());
    }
    let out = format!("{stem}.{}", session.extension());
    let part = format!("{out}.part");
    let result = (|| {
        let mut file = File::create(&part).map_err(|e| e.to_string())?;
        session.save(&fetch, &mut file)?;
        file.sync_all().map_err(|e| e.to_string())?;
        drop(file);
        std::fs::rename(&part, &out).map_err(|e| e.to_string())
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&part);
    }
    result?;
    if !cuts.is_empty() {
        for text in &extra.subtitles {
            shift_file(&text.path, &cuts);
        }
    }
    Ok(Joined { path: out, cut })
}

/// Rewrites the subtitle file at `path` (kept beside the joined file) with
/// its lines moved past what `cuts` left out, as WebVTT or, for `.srt`, SRT.
fn shift_file(path: &str, cuts: &crate::cast::Cuts) {
    let Ok(source) = std::fs::read(path) else { return };
    let cues: Vec<(u64, u64, String)> = crate::subtitles::cues(&String::from_utf8_lossy(&source)).into_iter().map(|c| (c.start, c.end, c.text)).collect();
    if cues.is_empty() {
        return;
    }
    let srt = path.to_ascii_lowercase().ends_with(".srt");
    let time = |ms: u64| format!("{:02}:{:02}:{:02}{}{:03}", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, if srt { ',' } else { '.' }, ms % 1000);
    let mut out = if srt { String::new() } else { "WEBVTT\n\n".to_string() };
    for (i, (start, end, text)) in cuts.cues(&cues).into_iter().enumerate() {
        if srt {
            out.push_str(&format!("{}\n", i + 1));
        }
        out.push_str(&format!("{} --> {}\n{}\n\n", time(start), time(end), text.trim_end()));
    }
    let _ = std::fs::write(path, out);
}

/// Joins JSON `{video, audio, out, container?, subtitles?: [{path,
/// language, name}], title?, cover?, cut?: [[from, to] s…]}`, `out`
/// without its extension; answers `{"path": …, "cut": [[from, to] ms…]}`
/// when done, else `{"error": …}`. It reads and writes the whole video, so
/// call it off the UI thread.
///
/// # Safety
/// [json] points at [length] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_join(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Request {
        video: String,
        audio: String,
        out: String,
        #[serde(default)]
        container: String,
        #[serde(flatten)]
        extra: Extra,
    }
    let answer = serde_json::from_str::<Request>(unsafe { text(json, length) }).map_err(|e| e.to_string()).and_then(|r| join(&r.video, &r.audio, &r.out, &r.container, &r.extra));
    give(match answer {
        Ok(joined) => serde_json::json!({ "path": joined.path, "cut": joined.cut }).to_string(),
        Err(error) => serde_json::json!({ "error": error }).to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Two subtitle files, a title and a cover picture in `dir`.
    fn extras(dir: &str) -> Extra {
        std::fs::write(format!("{dir}/en.vtt"), "WEBVTT\n\n00:00:00.500 --> 00:00:02.500\nFirst line\n\n00:00:08.000 --> 00:00:12.000\nSecond line\n").unwrap();
        std::fs::write(format!("{dir}/de.srt"), "1\n00:00:01,000 --> 00:00:03,000\nErste Zeile\n\n2\n00:00:09,000 --> 00:00:11,000\nZweite Zeile\n").unwrap();
        let mut jpeg = vec![0xFF, 0xD8, 0xFF, 0xE0];
        jpeg.extend_from_slice(&[0x42; 100]);
        std::fs::write(format!("{dir}/cover.jpg"), jpeg).unwrap();
        Extra {
            subtitles: vec![
                Text { path: format!("{dir}/en.vtt"), language: "en".into(), name: "English".into() },
                Text { path: format!("{dir}/de.srt"), language: "de".into(), name: "Deutsch".into() },
                Text { path: format!("{dir}/missing.vtt"), language: "fr".into(), name: String::new() },
            ],
            title: Some("A title".into()),
            cover: Some(format!("{dir}/cover.jpg")),
            cut: Vec::new(),
        }
    }

    #[test]
    fn moves_subtitle_files_past_cuts() {
        let dir = std::env::temp_dir().join(format!("lumtub-shift-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let cuts = crate::cast::Cuts::snap(&[(2.0, 6.0)], &[0, 2000, 4000, 6000, 8000]);
        let vtt = dir.join("a.en.vtt").to_string_lossy().into_owned();
        std::fs::write(&vtt, "WEBVTT\n\n00:00:01.000 --> 00:00:01.500\nBefore\n\n00:00:03.000 --> 00:00:04.000\nCut\n\n00:00:07.000 --> 00:00:08.000\nAfter\n").unwrap();
        shift_file(&vtt, &cuts);
        assert_eq!(std::fs::read_to_string(&vtt).unwrap(), "WEBVTT\n\n00:00:01.000 --> 00:00:01.500\nBefore\n\n00:00:03.000 --> 00:00:04.000\nAfter\n\n");
        let srt = dir.join("a.de.srt").to_string_lossy().into_owned();
        std::fs::write(&srt, "1\n00:00:07,250 --> 00:00:09,000\nNach\n").unwrap();
        shift_file(&srt, &cuts);
        assert_eq!(std::fs::read_to_string(&srt).unwrap(), "1\n00:00:03,250 --> 00:00:05,000\nNach\n\n");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Joins the sample files of cast's test (LUMTUB_CAST_SAMPLES) from disk:
    /// each picture with AAC, Dolby and Opus sound where there are samples.
    #[test]
    fn joins_files_on_disk() {
        let Ok(dir) = std::env::var("LUMTUB_CAST_SAMPLES") else { return };
        let exists = |name: &str| std::path::Path::new(&format!("{dir}/{name}")).exists();
        if !exists("v.mp4") {
            return;
        }
        let cases = [
            ("v.mp4", "a.mp4", "mp4"),
            ("vp9.webm", "a.mp4", "mp4"),
            ("av1.mp4", "a.mp4", "mp4"),
            ("v.mp4", "ec3.mp4", "mp4"),
            ("v.mp4", "ac3.mp4", "mp4"),
            ("v.mp4", "o.webm", "mkv"),
            ("vp9.webm", "o.webm", "webm"),
            ("av1.mp4", "o.webm", "webm"),
        ];
        for (picture, sound, extension) in cases {
            if !exists(picture) || !exists(sound) {
                continue;
            }
            let stem = format!("{dir}/joined-{}-{}", picture.replace('.', "_"), sound.replace('.', "_"));
            let out = join(&format!("{dir}/{picture}"), &format!("{dir}/{sound}"), &stem, "auto", &Extra::default()).expect("join").path;
            assert_eq!(out, format!("{stem}.{extension}"));
            assert!(std::fs::metadata(&out).unwrap().len() > 100_000);
            assert!(!std::path::Path::new(&format!("{out}.part")).exists());
            for asked in ["mp4", "mkv"] {
                let out = join(&format!("{dir}/{picture}"), &format!("{dir}/{sound}"), &format!("{stem}-as"), asked, &Extra::default()).expect("join as asked").path;
                assert_eq!(out, format!("{stem}-as.{asked}"));
            }
            let webm = join(&format!("{dir}/{picture}"), &format!("{dir}/{sound}"), &format!("{stem}-as"), "webm", &Extra::default());
            assert_eq!(webm.is_ok(), extension == "webm", "{picture} {sound} as WebM");
            let cut = Extra { cut: vec![(4.0, 13.0)], ..Extra::default() };
            let joined = join(&format!("{dir}/{picture}"), &format!("{dir}/{sound}"), &format!("{stem}-cut"), "auto", &cut).expect("join with a cut");
            assert!(!joined.cut.is_empty(), "{picture}: keyframes inside 4 s to 13 s");
            assert!(joined.cut.iter().all(|&(a, b)| a >= 4000 && b <= 13_000 && b > a));
            let extra = extras(&dir);
            for asked in ["mp4", "mkv", "auto"] {
                let out = join(&format!("{dir}/{picture}"), &format!("{dir}/{sound}"), &format!("{stem}-extra-{asked}"), asked, &extra).expect("join with extras").path;
                assert!(!out.ends_with(".webm"), "a WebM takes no subtitles: {out}");
                let bytes = std::fs::read(&out).unwrap();
                let has = |needle: &[u8]| bytes.windows(needle.len()).any(|w| w == needle);
                assert!(has(b"Second line") && has(b"Zweite Zeile") && has(b"A title"), "{out}");
                assert!(has(&[0xFF, 0xD8, 0xFF, 0xE0]), "cover in {out}");
            }
        }
        let audio = format!("{dir}/a.mp4");
        assert!(join(&audio, &audio, &format!("{dir}/wrong"), "auto", &Extra::default()).is_err());
        assert!(!std::path::Path::new(&format!("{dir}/wrong.mp4.part")).exists());
    }
}
