//! Records a live stream to disk: its picture and its sound, each from
//! YouTube's numbered fragments (see [crate::relay_live]) into a file of its
//! own, both from the same fragment on. Such a file is the first fragment
//! whole and then what follows the headers of every later one, so it has
//! no index; [Unindexed] gives it one when the two are joined
//! ([crate::join]).

use std::collections::HashMap;
use std::ffi::c_char;
use std::fs::File;
use std::io::{BufWriter, Read, Seek, SeekFrom, Write};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use serde::Deserialize;

use crate::cast_webm::{self, children, element};
use crate::relay::{Fetch, Target, Web};
use crate::relay_live::{End, follow, newest};
use crate::taste::{give, text};

/// How long a refused address may wait for the app to bring a new one.
const RENEW_WAIT: Duration = Duration::from_secs(120);

/// One stream being recorded.
struct Stream {
    url: Mutex<String>,
    bytes: AtomicU64,
    /// Waiting for a new address.
    refused: AtomicBool,
}

struct Recording {
    stop: Arc<AtomicBool>,
    streams: [Arc<Stream>; 2],
    threads: Vec<JoinHandle<Result<(), String>>>,
    started: Instant,
    ended: Arc<Mutex<Option<String>>>,
    log: Arc<Log>,
}

/// Lines for the app's log, taken with each state.
#[derive(Default)]
struct Log(Mutex<Vec<String>>);

impl Log {
    fn add(&self, line: String) {
        let mut lines = self.0.lock().unwrap();
        if lines.len() < 200 {
            lines.push(line);
        }
    }
}

fn recordings() -> &'static Mutex<HashMap<u64, Recording>> {
    static ALL: OnceLock<Mutex<HashMap<u64, Recording>>> = OnceLock::new();
    ALL.get_or_init(Default::default)
}

/// Records `stream` into `path` from fragment `first`, the newest being
/// `head` (`at`), until `stop` or the live ends. A refused address waits for a new
/// one ([RENEW_WAIT]).
fn record(fetch: &dyn Fetch, mut target: Target, stream: &Stream, path: &str, at: (u64, u64), stop: &AtomicBool, log: &Log) -> Result<(), String> {
    let (first, head) = at;
    let file = File::create(path).map_err(|e| format!("{path}: {e}"))?;
    let mut out = BufWriter::with_capacity(1 << 20, file);
    let mut failed = None;
    let (mut from, mut newest_known, mut whole) = (first, head, true);
    loop {
        let mut wrote = 0u64;
        let put = |bytes: &[u8]| {
            if let Err(e) = out.write_all(bytes).and_then(|_| out.flush()) {
                failed = Some(e.to_string());
                return false;
            }
            wrote += 1;
            stream.bytes.fetch_add(bytes.len() as u64, Ordering::Relaxed);
            true
        };
        let end = follow(&target, fetch, from, newest_known, whole, &|| stop.load(Ordering::Relaxed), put, &|line| log.add(line));
        if wrote > 0 {
            whole = false;
        }
        if let Some(e) = failed.take() {
            return Err(e);
        }
        let End::Refused(sq, status) = end else { return Ok(()) };
        log.add(format!("Recording: fragment {sq} refused (HTTP {status}); waiting for a new address"));
        stream.refused.store(true, Ordering::SeqCst);
        let old = target.url.clone();
        let since = Instant::now();
        loop {
            if stop.load(Ordering::Relaxed) {
                return Ok(());
            }
            let url = stream.url.lock().unwrap().clone();
            if url != old {
                target.url = url;
                break;
            }
            if since.elapsed() > RENEW_WAIT {
                return Err(format!("the address expired (HTTP {status})"));
            }
            std::thread::sleep(Duration::from_millis(500));
        }
        stream.refused.store(false, Ordering::SeqCst);
        (from, newest_known) = (sq, sq);
    }
}

#[derive(Deserialize)]
struct Start {
    video: Target,
    audio: Target,
    /// The files' path without their ending: the picture goes to
    /// `stem.live-video.part`, the sound to `stem.live-audio.part`.
    stem: String,
}

/// The two files a recording of `stem` writes, picture first.
pub fn files_of(stem: &str) -> [String; 2] {
    [format!("{stem}.live-video.part"), format!("{stem}.live-audio.part")]
}

fn start(ask: Start, fetch: Arc<dyn Fetch>) -> Result<u64, String> {
    let log = Arc::new(Log::default());
    let head = newest(&ask.video, fetch.as_ref(), &|line| log.add(line))?;
    // One fragment back, so both streams surely have their first.
    let first = head.saturating_sub(1);
    let stop = Arc::new(AtomicBool::new(false));
    let ended = Arc::new(Mutex::new(None));
    let files = files_of(&ask.stem);
    let mut streams = Vec::new();
    let mut threads = Vec::new();
    for (target, path) in [ask.video, ask.audio].into_iter().zip(files) {
        let stream = Arc::new(Stream { url: Mutex::new(target.url.clone()), bytes: AtomicU64::new(0), refused: AtomicBool::new(false) });
        let (fetch, stop, ended, stream_, log) = (fetch.clone(), stop.clone(), ended.clone(), stream.clone(), log.clone());
        threads.push(std::thread::spawn(move || {
            let result = record(fetch.as_ref(), target, &stream_, &path, (first, head), &stop, &log);
            // One stream over ends the other: a file needs both.
            stop.store(true, Ordering::SeqCst);
            let mut ended = ended.lock().unwrap();
            if ended.is_none() {
                *ended = Some(result.as_ref().err().cloned().unwrap_or_default());
            }
            result
        }));
        streams.push(stream);
    }
    static NEXT: AtomicU64 = AtomicU64::new(1);
    let id = NEXT.fetch_add(1, Ordering::SeqCst);
    let streams: [Arc<Stream>; 2] = [streams.remove(0), streams.remove(0)];
    recordings().lock().unwrap().insert(id, Recording { stop, streams, threads, started: Instant::now(), ended, log });
    Ok(id)
}

/// Starts recording JSON `{video: {url, user_agent?, proxy?}, audio: {…},
/// stem}`, both live addresses of numbered fragments; answers `{"id": …}`
/// or `{"error": …}`.
///
/// # Safety
/// [json] points at [length] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_record_start(json: *const u8, length: usize) -> *mut c_char {
    let answer = serde_json::from_str::<Start>(unsafe { text(json, length) }).map_err(|e| e.to_string()).and_then(|ask| start(ask, Arc::new(Web::default())));
    give(match answer {
        Ok(id) => serde_json::json!({ "id": id }).to_string(),
        Err(error) => serde_json::json!({ "error": error }).to_string(),
    })
}

/// How recording `id` goes: `{"bytes", "seconds", "running", "renew"}`
/// (`renew`: an address expired and waits for [lumtub_record_renew]), and
/// `error` when it stopped on one; `{}` for no such recording.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_record_state(id: u64) -> *mut c_char {
    let all = recordings().lock().unwrap();
    let Some(r) = all.get(&id) else { return give("{}".into()) };
    let ended = r.ended.lock().unwrap().clone();
    let mut state = serde_json::json!({
        "bytes": r.streams.iter().map(|s| s.bytes.load(Ordering::Relaxed)).sum::<u64>(),
        "seconds": r.started.elapsed().as_secs_f64(),
        "running": ended.is_none(),
        "renew": r.streams.iter().any(|s| s.refused.load(Ordering::SeqCst)),
        "log": std::mem::take(&mut *r.log.0.lock().unwrap()),
    });
    if let Some(error) = ended.filter(|e| !e.is_empty()) {
        state["error"] = error.into();
    }
    give(state.to_string())
}

/// Gives recording JSON `{id, video, audio}` new addresses for its streams.
///
/// # Safety
/// [json] points at [length] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_record_renew(json: *const u8, length: usize) -> bool {
    #[derive(Deserialize)]
    struct Renew {
        id: u64,
        video: String,
        audio: String,
    }
    let Ok(ask) = serde_json::from_str::<Renew>(unsafe { text(json, length) }) else { return false };
    let all = recordings().lock().unwrap();
    let Some(r) = all.get(&ask.id) else { return false };
    *r.streams[0].url.lock().unwrap() = ask.video;
    *r.streams[1].url.lock().unwrap() = ask.audio;
    true
}

/// Stops recording `id` and waits until its files are written; answers
/// `{}` or `{"error": …}` from a stream that failed.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_record_stop(id: u64) -> *mut c_char {
    let Some(r) = recordings().lock().unwrap().remove(&id) else { return give("{}".into()) };
    r.stop.store(true, Ordering::SeqCst);
    let errors: Vec<String> = r.threads.into_iter().filter_map(|t| t.join().unwrap_or_else(|_| Err("the recording broke".into())).err()).collect();
    give(match errors.first() {
        Some(error) => serde_json::json!({ "error": error }).to_string(),
        None => "{}".into(),
    })
}

// ---- reading a recorded file ----

/// A recorded file seen with an index before its fragments: the first
/// fragment's head with an index made from the fragments (an MP4 `sidx`,
/// WebM `Cues`), then the file from its first fragment on.
pub struct Unindexed {
    pub head: Vec<u8>,
    /// Where the fragments start in the file.
    pub from: u64,
    pub size: u64,
}

impl Unindexed {
    /// The size of the file as seen.
    pub fn len(&self) -> u64 {
        self.head.len() as u64 + self.size - self.from
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Bytes `from..=to` of the file as seen.
    pub fn read(&self, path: &str, from: u64, to: u64) -> Result<Box<dyn Read + Send>, String> {
        let end = to + 1;
        let head = self.head.len() as u64;
        let first: Vec<u8> = if from < head { self.head[from as usize..end.min(head) as usize].to_vec() } else { Vec::new() };
        let mut file = File::open(path).map_err(|e| e.to_string())?;
        let at = from.max(head) - head + self.from;
        file.seek(SeekFrom::Start(at)).map_err(|e| e.to_string())?;
        Ok(Box::new(std::io::Cursor::new(first).chain(file.take(end.saturating_sub(from.max(head))))))
    }
}

/// The file at `path` with an index, when it is a recording; None for a
/// file with one of its own.
pub fn unindexed(path: &str) -> Result<Option<Unindexed>, String> {
    let mut file = File::open(path).map_err(|e| format!("{path}: {e}"))?;
    let size = file.metadata().map_err(|e| e.to_string())?.len();
    let mut start = vec![0u8; size.min(1 << 20) as usize];
    file.read_exact(&mut start).map_err(|e| e.to_string())?;
    if cast_webm::is_webm(&start) { webm(&mut file, &start, size) } else { mp4(&mut file, &start, size) }
}

fn be32(b: &[u8], at: usize) -> Option<u32> {
    Some(u32::from_be_bytes(b.get(at..at + 4)?.try_into().ok()?))
}

fn be64(b: &[u8], at: usize) -> Option<u64> {
    Some(u64::from_be_bytes(b.get(at..at + 8)?.try_into().ok()?))
}

/// Box `kind` among the boxes of `b[from..to]`: its body and end.
fn child(b: &[u8], from: usize, to: usize, kind: &[u8; 4]) -> Option<(usize, usize)> {
    let mut at = from;
    while at + 8 <= to {
        let size = be32(b, at)? as usize;
        if size < 8 || at + size > to {
            return None;
        }
        if &b[at + 4..at + 8] == kind {
            return Some((at + 8, at + size));
        }
        at += size;
    }
    None
}

fn mp4(file: &mut File, start: &[u8], size: u64) -> Result<Option<Unindexed>, String> {
    // The head: boxes before the first moof; a sidx there means an index.
    let mut at = 0usize;
    let (mut ftyp, mut moov) = (None, None);
    loop {
        let Some(box_size) = be32(start, at) else { return Err("no fragment in the first megabyte".into()) };
        let kind = start.get(at + 4..at + 8).ok_or("cut short")?;
        let end = at + box_size as usize;
        match kind {
            b"sidx" => return Ok(None),
            b"moof" => break,
            b"ftyp" => ftyp = start.get(at..end),
            b"moov" => moov = start.get(at..end),
            _ => {}
        }
        if box_size < 8 {
            return Err("unreadable box".into());
        }
        at = end;
    }
    let (Some(ftyp), Some(moov)) = (ftyp, moov) else { return Err("no ftyp or moov".into()) };
    let (mdia, mdia_end) = child(moov, 8, moov.len(), b"trak").and_then(|(t, e)| child(moov, t, e, b"mdia")).ok_or("no mdia")?;
    let (mdhd, _) = child(moov, mdia, mdia_end, b"mdhd").ok_or("no mdhd")?;
    let timescale = if moov[mdhd] == 1 { be32(moov, mdhd + 20) } else { be32(moov, mdhd + 12) }.filter(|&t| t > 0).ok_or("no timescale")?;
    // Every moof: where it starts and its tfdt.
    let from = at as u64;
    let mut fragments: Vec<(u64, u64)> = Vec::new();
    let mut offset = from;
    let mut header = [0u8; 16];
    while offset + 8 <= size {
        file.seek(SeekFrom::Start(offset)).map_err(|e| e.to_string())?;
        file.read_exact(&mut header[..8]).map_err(|e| e.to_string())?;
        let mut box_size = be32(&header, 0).unwrap_or(0) as u64;
        if box_size == 1 {
            file.read_exact(&mut header[8..16]).map_err(|e| e.to_string())?;
            box_size = be64(&header, 8).unwrap_or(0);
        }
        if box_size < 8 {
            break;
        }
        if &header[4..8] == b"moof" {
            let mut moof = vec![0u8; box_size as usize];
            file.seek(SeekFrom::Start(offset)).map_err(|e| e.to_string())?;
            if file.read_exact(&mut moof).is_err() {
                break;
            }
            let time = child(&moof, 8, moof.len(), b"traf").and_then(|(t, e)| child(&moof, t, e, b"tfdt")).and_then(|(d, _)| if moof[d] == 1 { be64(&moof, d + 4) } else { be32(&moof, d + 4).map(u64::from) });
            fragments.push((offset, time.ok_or("a fragment without its time")?));
        }
        if offset + box_size > size {
            // The last fragment was cut short when the recording stopped.
            break;
        }
        offset += box_size;
    }
    let whole_end = offset.min(size);
    if fragments.is_empty() {
        return Err("no whole fragment".into());
    }
    // sidx version 1: one reference per moof, up to the next one.
    let mut sidx = Vec::new();
    let count = fragments.len();
    let body = 8 + 4 + 4 + 4 + 8 + 8 + 2 + 2 + 12 * count;
    sidx.extend_from_slice(&(body as u32).to_be_bytes());
    sidx.extend_from_slice(b"sidx");
    sidx.extend_from_slice(&[1, 0, 0, 0]);
    sidx.extend_from_slice(&1u32.to_be_bytes());
    sidx.extend_from_slice(&timescale.to_be_bytes());
    sidx.extend_from_slice(&fragments[0].1.to_be_bytes());
    sidx.extend_from_slice(&0u64.to_be_bytes());
    sidx.extend_from_slice(&[0, 0]);
    sidx.extend_from_slice(&(count as u16).to_be_bytes());
    let mut last = 0u64;
    for i in 0..count {
        let (at, time) = fragments[i];
        let end = fragments.get(i + 1).map_or(whole_end, |f| f.0);
        let duration = fragments.get(i + 1).map_or(last, |f| f.1.saturating_sub(time));
        last = duration;
        let reference = u32::try_from(end - at).map_err(|_| "a fragment too large")?;
        sidx.extend_from_slice(&reference.to_be_bytes());
        sidx.extend_from_slice(&(duration as u32).to_be_bytes());
        sidx.extend_from_slice(&0x9000_0000u32.to_be_bytes());
    }
    if count > u16::MAX as usize {
        return Err("too many fragments".into());
    }
    let head = [ftyp, moov, &sidx].concat();
    Ok(Some(Unindexed { head, from, size: whole_end }))
}

const SEGMENT: u32 = 0x1853_8067;
const CLUSTER: u32 = 0x1F43_B675;
const INFO: u32 = 0x1549_A966;
const TRACKS: u32 = 0x1654_AE6B;
const CUES: u32 = 0x1C53_BB6B;
const TIMESTAMP: u32 = 0xE7;

/// An EBML element with an 8-byte size.
fn ebml(out: &mut Vec<u8>, id: u32, body: &[u8]) {
    let id = id.to_be_bytes();
    let skip = id.iter().position(|&b| b != 0).unwrap_or(3);
    out.extend_from_slice(&id[skip..]);
    let mut size = (body.len() as u64).to_be_bytes();
    size[0] = 0x01;
    out.extend_from_slice(&size);
    out.extend_from_slice(body);
}

fn webm(file: &mut File, start: &[u8], size: u64) -> Result<Option<Unindexed>, String> {
    let ebml_head = element(start, 0).ok_or("no EBML head")?;
    let segment = element(start, ebml_head.end).filter(|e| e.id == SEGMENT).ok_or("no segment")?;
    let (mut info, mut tracks, mut number) = (None, None, None);
    let mut at = segment.data;
    let from = loop {
        let e = element(start, at).ok_or("no cluster in the first megabyte")?;
        match e.id {
            CLUSTER => break at as u64,
            CUES => return Ok(None),
            INFO => info = start.get(at..e.end),
            TRACKS => {
                tracks = start.get(at..e.end);
                // The first track's number.
                let entry = element(start, e.data).ok_or("no track")?;
                number = children(start, entry.data, entry.end.min(start.len())).into_iter().find(|c| c.id == 0xD7).and_then(|c| start.get(c.data..c.end)).map(|b| b.iter().fold(0u64, |n, &x| n << 8 | x as u64));
            }
            _ => {}
        }
        if e.end == usize::MAX || e.end > start.len() {
            return Err("unreadable head".into());
        }
        at = e.end;
    };
    let (Some(info), Some(tracks), Some(number)) = (info, tracks, number) else { return Err("no info or tracks".into()) };
    // Every cluster: where it starts and its timestamp.
    let mut clusters: Vec<(u64, u64)> = Vec::new();
    let mut offset = from;
    let mut header = [0u8; 32];
    while offset < size {
        file.seek(SeekFrom::Start(offset)).map_err(|e| e.to_string())?;
        let read = file.read(&mut header).map_err(|e| e.to_string())?;
        let Some(e) = element(&header[..read], 0) else { break };
        if e.end == usize::MAX {
            return Err("a cluster of unknown size".into());
        }
        if offset + e.end as u64 > size {
            break;
        }
        if e.id == CLUSTER {
            let time = element(&header[..read], e.data).filter(|t| t.id == TIMESTAMP && t.end <= read).map(|t| header[t.data..t.end].iter().fold(0u64, |n, &x| n << 8 | x as u64)).ok_or("a cluster without its time")?;
            clusters.push((offset, time));
        }
        offset += e.end as u64;
    }
    if clusters.is_empty() {
        return Err("no whole cluster".into());
    }
    // Cues with 8-byte numbers, so their size does not hang on the offsets.
    let before = info.len() + tracks.len();
    let point_size = 1 + 8 + (1 + 8 + 8) + (1 + 8 + (1 + 8 + 8) + (1 + 8 + 8));
    let cues_size = 4 + 8 + point_size * clusters.len();
    let mut cues = Vec::with_capacity(cues_size);
    for &(at, time) in &clusters {
        let mut positions = Vec::new();
        ebml(&mut positions, 0xF7, &number.to_be_bytes());
        ebml(&mut positions, 0xF1, &((before + cues_size) as u64 + at - from).to_be_bytes());
        let mut point = Vec::new();
        ebml(&mut point, 0xB3, &time.to_be_bytes());
        ebml(&mut point, 0xB7, &positions);
        ebml(&mut cues, 0xBB, &point);
    }
    let mut head = start[..ebml_head.end].to_vec();
    head.extend_from_slice(&[0x18, 0x53, 0x80, 0x67, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
    head.extend_from_slice(info);
    head.extend_from_slice(tracks);
    let index = head.len();
    ebml(&mut head, CUES, &cues);
    debug_assert_eq!(head.len() - index, cues_size);
    Ok(Some(Unindexed { head, from, size: offset.min(size) }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    /// A live stream made of a sample file: fragment N is the file's head
    /// with its Nth `moof` and `mdat` (or WebM cluster), as YouTube sends
    /// them; the newest is one past the one asked.
    struct Sample {
        fragments: [Vec<Vec<u8>>; 2],
    }

    fn split(path: &str) -> Vec<Vec<u8>> {
        let b = std::fs::read(path).unwrap();
        let mut parts: Vec<(usize, usize)> = Vec::new();
        if cast_webm::is_webm(&b) {
            let segment = element(&b, element(&b, 0).unwrap().end).unwrap();
            let mut at = segment.data;
            while let Some(e) = element(&b, at) {
                if e.id == CLUSTER {
                    parts.push((at, e.end.min(b.len())));
                }
                if e.end >= b.len() {
                    break;
                }
                at = e.end;
            }
        } else {
            let mut at = 0;
            while at + 8 <= b.len() {
                let size = be32(&b, at).unwrap() as usize;
                if &b[at + 4..at + 8] == b"moof" {
                    parts.push((at, at + size));
                } else if &b[at + 4..at + 8] == b"mdat" {
                    parts.last_mut().unwrap().1 = at + size;
                }
                at += size;
            }
        }
        let head = &b[..parts[0].0];
        parts.iter().map(|&(from, to)| [head, &b[from..to]].concat()).collect()
    }

    impl Fetch for Sample {
        fn get(&self, target: &Target, url: &str) -> Result<(u16, Box<dyn Read + Send>), String> {
            self.get_live(target, url).map(|(s, _, b)| (s, b))
        }
        fn get_live(&self, _: &Target, url: &str) -> Result<(u16, Option<u64>, Box<dyn Read + Send>), String> {
            let which = usize::from(url.contains("audio"));
            let fragments = &self.fragments[which];
            let Some(sq) = url.split("&sq=").nth(1) else { return Ok((200, Some(1), Box::new(Cursor::new(Vec::new())))) };
            let sq: usize = sq.parse().unwrap();
            let newest = (sq as u64 + 1).min(fragments.len() as u64 - 1);
            match fragments.get(sq) {
                Some(f) => Ok((200, Some(newest), Box::new(Cursor::new(f.clone())))),
                None => Ok((404, Some(newest), Box::new(Cursor::new(Vec::new())))),
            }
        }
    }

    fn live(url: &str) -> Target {
        Target { url: url.into(), size: 0, user_agent: None, mime: None, proxy: None, chunk: 1 << 20, live: Some("pair".into()) }
    }

    /// Records the live samples (LUMTUB_CAST_SAMPLES: live-v.mp4, live-vp9.webm,
    /// live-a.mp4 with times from 3600 s) and joins what was recorded.
    #[test]
    fn records_and_joins_a_live_stream() {
        let Ok(dir) = std::env::var("LUMTUB_CAST_SAMPLES") else { return };
        for picture in ["live-v.mp4", "live-vp9.webm"] {
            if !std::path::Path::new(&format!("{dir}/{picture}")).exists() {
                return;
            }
            let fragments = [split(&format!("{dir}/{picture}")), split(&format!("{dir}/live-a.mp4"))];
            let expected: Vec<usize> = fragments.iter().map(|f| f[0].len() + f[1..].iter().map(|f| continuation_len(f)).sum::<usize>()).collect();
            let stem = format!("{dir}/recorded-{}", picture.replace('.', "_"));
            let ask = Start { video: live("https://live/videoplayback?live=1&video"), audio: live("https://live/videoplayback?live=1&audio"), stem: stem.clone() };
            let id = start(ask, Arc::new(Sample { fragments })).expect("start");
            let files = files_of(&stem);
            let size = |i: usize| std::fs::metadata(&files[i]).map_or(0, |m| m.len() as usize);
            let state = || -> serde_json::Value { serde_json::from_str(&unsafe { std::ffi::CString::from_raw(lumtub_record_state(id)) }.into_string().unwrap()).unwrap() };
            let since = Instant::now();
            // The count follows each write.
            while state()["bytes"].as_u64().unwrap() as usize != expected[0] + expected[1] && since.elapsed() < Duration::from_secs(20) {
                std::thread::sleep(Duration::from_millis(50));
            }
            let now = state();
            assert_eq!(now["running"], true);
            assert_eq!(now["bytes"].as_u64().unwrap() as usize, expected[0] + expected[1]);
            let stopped = unsafe { std::ffi::CString::from_raw(lumtub_record_stop(id)) }.into_string().unwrap();
            assert_eq!(stopped, "{}");
            assert_eq!((size(0), size(1)), (expected[0], expected[1]));
            let seen = unindexed(&files[0]).unwrap().expect("no index of its own");
            assert!(seen.len() > seen.size - seen.from);
            let joined = crate::join::join(&files[0], &files[1], &stem, "auto", &crate::join::Extra::default()).expect("join");
            assert!(std::fs::metadata(&joined.path).unwrap().len() as usize > expected[0] / 2, "{}", joined.path);
        }
    }

    fn continuation_len(fragment: &[u8]) -> usize {
        crate::relay_live::continuation_len(fragment)
    }
}
