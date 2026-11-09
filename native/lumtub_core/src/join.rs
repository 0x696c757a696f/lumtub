//! Joins a downloaded picture and sound into one file, without ffmpeg,
//! for Android, which cannot start a downloaded ffmpeg: the cast stream
//! writer ([crate::cast::Session]) reads the two files instead of
//! YouTube's addresses. The picture may be H.264 or AV1 in MP4, or VP9 in
//! WebM; the sound AAC in MP4.

use std::ffi::c_char;
use std::fs::File;
use std::io::{BufWriter, Read, Seek, SeekFrom, Write};
use std::sync::Arc;

use serde::Deserialize;

use crate::cast::{Ask, Kind, Session};
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

/// Writes `video` and `audio` joined into `out`, a fragmented MP4. `out`
/// is written beside as `out.part` and renamed when whole.
pub fn join(video: &str, audio: &str, out: &str) -> Result<(), String> {
    let fetch: Arc<dyn Fetch> = Arc::new(Files);
    let ask = Ask { video: target(video)?, audio: target(audio)?, start_ms: 0, kind: Kind::Mp4, duration_ms: 0, subtitles: None };
    let session = Session::new(ask, &fetch)?;
    let part = format!("{out}.part");
    let result = (|| {
        let mut file = BufWriter::new(File::create(&part).map_err(|e| e.to_string())?);
        session.stream(&fetch, &mut file).map_err(|e| if e.is_empty() { "could not write the file".to_string() } else { e })?;
        file.flush().map_err(|e| e.to_string())?;
        drop(file);
        std::fs::rename(&part, out).map_err(|e| e.to_string())
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&part);
    }
    result
}

/// Joins JSON `{video, audio, out}`; null when done, else why not.
/// It reads and writes the whole video, so call it off the UI thread.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_join(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Request {
        video: String,
        audio: String,
        out: String,
    }
    match serde_json::from_str::<Request>(unsafe { text(json, length) }) {
        Ok(r) => match join(&r.video, &r.audio, &r.out) {
            Ok(()) => std::ptr::null_mut(),
            Err(e) => give(e),
        },
        Err(e) => give(e.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Joins the sample files of cast's test (LUMTUB_CAST_SAMPLES) from disk.
    #[test]
    fn joins_files_on_disk() {
        let Ok(dir) = std::env::var("LUMTUB_CAST_SAMPLES") else { return };
        let (video, audio) = (format!("{dir}/v.mp4"), format!("{dir}/a.mp4"));
        if !std::path::Path::new(&video).exists() {
            return;
        }
        for (picture, out) in [(video.as_str(), "joined.mp4"), (&*format!("{dir}/vp9.webm"), "joined-vp9.mp4")] {
            if !std::path::Path::new(picture).exists() {
                continue;
            }
            let out = format!("{dir}/{out}");
            join(picture, &audio, &out).expect("join");
            assert!(std::fs::metadata(&out).unwrap().len() > 100_000);
            assert!(!std::path::Path::new(&format!("{out}.part")).exists());
        }
        assert!(join(&audio, &audio, &format!("{dir}/wrong.mp4")).is_err());
        assert!(!std::path::Path::new(&format!("{dir}/wrong.mp4.part")).exists());
    }
}
