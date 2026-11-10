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
use std::sync::Arc;

use serde::Deserialize;

use crate::cast::{Ask, Kind, Session};
use crate::cast_webm;
use crate::relay::{Fetch, Target};
use crate::taste::{give, text};

/// Local files read like YouTube's streams: the address is the path and
/// the byte range comes after `&range=`.
struct Files;

impl Fetch for Files {
    fn get(&self, _: &Target, url: &str) -> Result<(u16, Box<dyn Read + Send>), String> {
        let (path, range) = url.rsplit_once("&range=").ok_or("no range")?;
        let (from, to) = range.split_once('-').ok_or("bad range")?;
        let (from, to): (u64, u64) = (from.parse().map_err(|_| "bad range")?, to.parse().map_err(|_| "bad range")?);
        let mut file = File::open(path).map_err(|e| e.to_string())?;
        file.seek(SeekFrom::Start(from)).map_err(|e| e.to_string())?;
        Ok((206, Box::new(file.take((to + 1).saturating_sub(from)))))
    }
}

fn target(path: &str) -> Result<Target, String> {
    let size = std::fs::metadata(path).map_err(|e| format!("{path}: {e}"))?.len();
    Ok(Target { url: path.to_string(), size, user_agent: None, mime: None, proxy: None, chunk: 8 << 20, live: None })
}

/// Whether the file at `path` is WebM (or other Matroska).
fn is_webm(path: &str) -> Result<bool, String> {
    let mut start = [0u8; 4];
    let read = File::open(path).and_then(|mut f| f.read(&mut start)).map_err(|e| format!("{path}: {e}"))?;
    Ok(cast_webm::is_webm(&start[..read]))
}

/// Writes `video` and `audio` joined into `stem` plus the extension of
/// `container` (`mp4`, `webm` or `mkv`; any other word picks what fits),
/// and returns that path. The file is written beside as `.part` and
/// renamed when whole.
pub fn join(video: &str, audio: &str, stem: &str, container: &str) -> Result<String, String> {
    let fetch: Arc<dyn Fetch> = Arc::new(Files);
    let kind = match container {
        "mp4" => Kind::Mp4,
        "webm" | "mkv" => Kind::Mkv,
        _ if is_webm(audio)? => Kind::Mkv,
        _ => Kind::Mp4,
    };
    let ask = Ask { video: target(video)?, audio: target(audio)?, start_ms: 0, kind, duration_ms: 0, subtitles: None };
    let mut session = Session::new(ask, &fetch)?;
    if container == "mkv" {
        session = session.plain_matroska();
    }
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
    result.map(|_| out)
}

/// Joins JSON `{video, audio, out, container?}`, `out` without its extension; answers
/// `{"path": …}` when done, else `{"error": …}`. It reads and writes the
/// whole video, so call it off the UI thread.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_join(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Request {
        video: String,
        audio: String,
        out: String,
        #[serde(default)]
        container: String,
    }
    let answer = serde_json::from_str::<Request>(unsafe { text(json, length) }).map_err(|e| e.to_string()).and_then(|r| join(&r.video, &r.audio, &r.out, &r.container));
    give(match answer {
        Ok(path) => serde_json::json!({ "path": path }).to_string(),
        Err(error) => serde_json::json!({ "error": error }).to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

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
            let out = join(&format!("{dir}/{picture}"), &format!("{dir}/{sound}"), &stem, "auto").expect("join");
            assert_eq!(out, format!("{stem}.{extension}"));
            assert!(std::fs::metadata(&out).unwrap().len() > 100_000);
            assert!(!std::path::Path::new(&format!("{out}.part")).exists());
            for asked in ["mp4", "mkv"] {
                let out = join(&format!("{dir}/{picture}"), &format!("{dir}/{sound}"), &format!("{stem}-as"), asked).expect("join as asked");
                assert_eq!(out, format!("{stem}-as.{asked}"));
            }
            let webm = join(&format!("{dir}/{picture}"), &format!("{dir}/{sound}"), &format!("{stem}-as"), "webm");
            assert_eq!(webm.is_ok(), extension == "webm", "{picture} {sound} as WebM");
        }
        let audio = format!("{dir}/a.mp4");
        assert!(join(&audio, &audio, &format!("{dir}/wrong"), "auto").is_err());
        assert!(!std::path::Path::new(&format!("{dir}/wrong.mp4.part")).exists());
    }
}
