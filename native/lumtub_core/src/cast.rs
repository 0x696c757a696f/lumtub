//! Serves a YouTube video to a TV on the local network with its picture and
//! sound joined into one stream, without decoding anything. YouTube sends
//! its better pictures and its sound as separate fragmented MP4 files, and
//! a TV takes one address; the index (`sidx`) at the head of each file says
//! where every fragment starts, so the two are read fragment by fragment
//! and written out as one fragmented MP4 (for Chromecast) or as an MPEG
//! transport stream (for DLNA renderers, which take it most reliably).
//!
//! The stream starts at the keyframe at or before the asked position;
//! seeking registers the video again from the new position. Bytes are read
//! from YouTube in chunks the way the loopback relay reads them. Only
//! registered sessions are served, under random tokens.

use crate::relay::{Fetch, Stop, Target, Web, drain, read_request, request};
use serde::Deserialize;
use std::collections::{HashMap, VecDeque};
use std::io::{BufReader, ErrorKind, Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::os::raw::c_char;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

/// Sessions kept; older ones stop being served.
const KEEP: usize = 4;
/// Connections served at once.
const MAX_CONNECTIONS: usize = 8;
/// The most bytes read to find a file's index.
const HEAD_LIMIT: u64 = 8 << 20;
/// The largest fragment read into memory.
const FRAGMENT_LIMIT: u64 = 64 << 20;
const LOG_KEEP: usize = 100;

#[derive(Deserialize, Clone, Copy, PartialEq, Debug)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Mp4,
    Ts,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Ask {
    pub video: Target,
    pub audio: Target,
    #[serde(default)]
    pub start_ms: u64,
    pub kind: Kind,
}

/// One file's place in the stream: what its header says and where its
/// fragments are.
#[derive(Debug, Clone, PartialEq)]
pub struct Track {
    /// The whole `trak` box.
    trak: Vec<u8>,
    /// The whole `mvhd` box of its file.
    mvhd: Vec<u8>,
    timescale: u32,
    video: bool,
    codec: Codec,
    defaults: Defaults,
    /// The first entry of the edit list, in [timescale]: how far the
    /// presentation starts into the media.
    shift: u64,
    segments: Vec<Segment>,
}

#[derive(Debug, Clone, PartialEq)]
enum Codec {
    Avc { length: usize, sps: Vec<Vec<u8>>, pps: Vec<Vec<u8>> },
    Aac { profile: u8, frequency: u8, channels: u8 },
    Other,
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
struct Defaults {
    duration: u32,
    size: u32,
    flags: u32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct Segment {
    offset: u64,
    size: u64,
    /// Start, in seconds.
    start: f64,
}

/// A run of samples read from one segment.
struct Fragment {
    data: Vec<u8>,
    samples: Vec<Sample>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct Sample {
    at: usize,
    size: usize,
    /// Decode time, in the track's timescale.
    time: u64,
    duration: u32,
    offset: i32,
    sync: bool,
}

// ---- boxes ----

fn be16(b: &[u8], at: usize) -> Option<u16> {
    Some(u16::from_be_bytes(b.get(at..at + 2)?.try_into().ok()?))
}

fn be32(b: &[u8], at: usize) -> Option<u32> {
    Some(u32::from_be_bytes(b.get(at..at + 4)?.try_into().ok()?))
}

fn be64(b: &[u8], at: usize) -> Option<u64> {
    Some(u64::from_be_bytes(b.get(at..at + 8)?.try_into().ok()?))
}

/// A box inside a byte slice: its type, where it starts, where its payload
/// starts and where it ends. `end` may lie past the slice when the box was
/// not read whole.
#[derive(Debug, Clone, Copy)]
struct Atom {
    kind: [u8; 4],
    start: usize,
    body: usize,
    end: usize,
}

/// The boxes laid one after another in `data[from..to]`.
fn atoms(data: &[u8], from: usize, to: usize) -> Vec<Atom> {
    let mut found = Vec::new();
    let mut at = from;
    while at + 8 <= to {
        let Some(size) = be32(data, at) else { break };
        let kind: [u8; 4] = data[at + 4..at + 8].try_into().unwrap_or_default();
        let (body, size) = match size {
            1 => match be64(data, at + 8) {
                Some(large) => (at + 16, usize::try_from(large).unwrap_or(usize::MAX)),
                None => break,
            },
            0 => (at + 8, to - at),
            n => (at + 8, n as usize),
        };
        if size < body - at {
            break;
        }
        let end = at.saturating_add(size);
        found.push(Atom { kind, start: at, body, end });
        if end > to {
            break;
        }
        at = end;
    }
    found
}

fn child(data: &[u8], parent: Atom, kind: &[u8; 4]) -> Option<Atom> {
    atoms(data, parent.body, parent.end.min(data.len())).into_iter().find(|a| &a.kind == kind && a.end <= data.len())
}

fn path(data: &[u8], parent: Atom, kinds: &[&[u8; 4]]) -> Option<Atom> {
    kinds.iter().try_fold(parent, |atom, kind| child(data, atom, kind))
}

fn whole(data: &[u8], atom: Atom) -> Vec<u8> {
    data[atom.start..atom.end].to_vec()
}

// ---- reading a file's head ----

#[derive(Debug, PartialEq)]
pub enum Head {
    Track(Box<Track>),
    /// The head goes on past what was read; read this many bytes.
    More(u64),
    Unusable(&'static str),
}

/// What the first bytes of a YouTube DASH file say: its track and the index
/// of its fragments.
pub fn read_head(data: &[u8]) -> Head {
    let mut moov = None;
    for atom in atoms(data, 0, data.len()) {
        if atom.end > data.len() {
            return Head::More(atom.end as u64);
        }
        match &atom.kind {
            b"moov" => moov = Some(atom),
            b"sidx" => {
                let Some(moov) = moov else { return Head::Unusable("no moov before the index") };
                return match track(data, moov, atom) {
                    Ok(track) => Head::Track(Box::new(track)),
                    Err(why) => Head::Unusable(why),
                };
            }
            b"moof" | b"mdat" => return Head::Unusable("no index"),
            _ => {}
        }
    }
    let read = data.len() as u64;
    Head::More(if read < 64 << 10 { 64 << 10 } else { read * 2 })
}

fn track(data: &[u8], moov: Atom, sidx: Atom) -> Result<Track, &'static str> {
    let trak = child(data, moov, b"trak").ok_or("no trak")?;
    let mvhd = child(data, moov, b"mvhd").ok_or("no mvhd")?;
    let mdhd = path(data, trak, &[b"mdia", b"mdhd"]).ok_or("no mdhd")?;
    let timescale = match data[mdhd.body] {
        1 => be32(data, mdhd.body + 20),
        _ => be32(data, mdhd.body + 12),
    }
    .filter(|&t| t > 0)
    .ok_or("no timescale")?;
    let hdlr = path(data, trak, &[b"mdia", b"hdlr"]).ok_or("no hdlr")?;
    let video = match data.get(hdlr.body + 8..hdlr.body + 12) {
        Some(b"vide") => true,
        Some(b"soun") => false,
        _ => return Err("neither picture nor sound"),
    };
    let stsd = path(data, trak, &[b"mdia", b"minf", b"stbl", b"stsd"]).ok_or("no stsd")?;
    let codec = codec(data, stsd);
    let defaults = path(data, moov, &[b"mvex", b"trex"])
        .and_then(|trex| {
            Some(Defaults { duration: be32(data, trex.body + 12)?, size: be32(data, trex.body + 16)?, flags: be32(data, trex.body + 20)? })
        })
        .unwrap_or_default();
    let shift = path(data, trak, &[b"edts", b"elst"])
        .and_then(|elst| {
            let count = be32(data, elst.body + 4)?;
            if count == 0 {
                return None;
            }
            let time = match data[elst.body] {
                1 => be64(data, elst.body + 16)? as i64,
                _ => be32(data, elst.body + 12)? as i32 as i64,
            };
            u64::try_from(time).ok()
        })
        .unwrap_or(0);
    let segments = index(data, sidx).ok_or("unreadable index")?;
    if segments.is_empty() {
        return Err("empty index");
    }
    Ok(Track { trak: whole(data, trak), mvhd: whole(data, mvhd), timescale, video, codec, defaults, shift, segments })
}

fn codec(data: &[u8], stsd: Atom) -> Codec {
    let entries = atoms(data, stsd.body + 8, stsd.end.min(data.len()));
    let Some(entry) = entries.first().filter(|e| e.end <= data.len()) else { return Codec::Other };
    match &entry.kind {
        b"avc1" | b"avc3" => {
            let Some(avcc) = atoms(data, entry.body + 78, entry.end).into_iter().find(|a| &a.kind == b"avcC" && a.end <= data.len()) else {
                return Codec::Other;
            };
            avc_config(&data[avcc.body..avcc.end]).unwrap_or(Codec::Other)
        }
        b"mp4a" => {
            let Some(esds) = atoms(data, entry.body + 28, entry.end).into_iter().find(|a| &a.kind == b"esds" && a.end <= data.len()) else {
                return Codec::Other;
            };
            aac_config(&data[esds.body + 4..esds.end]).unwrap_or(Codec::Other)
        }
        _ => Codec::Other,
    }
}

fn avc_config(b: &[u8]) -> Option<Codec> {
    let length = (b.get(4)? & 3) as usize + 1;
    let mut at = 5;
    let sets = |count: usize, at: &mut usize| -> Option<Vec<Vec<u8>>> {
        let mut found = Vec::new();
        for _ in 0..count {
            let n = be16(b, *at)? as usize;
            found.push(b.get(*at + 2..*at + 2 + n)?.to_vec());
            *at += 2 + n;
        }
        Some(found)
    };
    let sps_count = (*b.get(at)? & 0x1f) as usize;
    at += 1;
    let sps = sets(sps_count, &mut at)?;
    let pps_count = *b.get(at)? as usize;
    at += 1;
    let pps = sets(pps_count, &mut at)?;
    Some(Codec::Avc { length, sps, pps })
}

/// The tag and payload of the MPEG-4 descriptor at `at`.
fn descriptor(b: &[u8], at: usize) -> Option<(u8, usize, usize)> {
    let tag = *b.get(at)?;
    let mut length = 0usize;
    let mut i = at + 1;
    for _ in 0..4 {
        let byte = *b.get(i)?;
        i += 1;
        length = (length << 7) | (byte & 0x7f) as usize;
        if byte & 0x80 == 0 {
            break;
        }
    }
    Some((tag, i, (i + length).min(b.len())))
}

fn aac_config(b: &[u8]) -> Option<Codec> {
    let (tag, body, end) = descriptor(b, 0)?;
    if tag != 3 {
        return None;
    }
    let flags = *b.get(body + 2)?;
    let mut at = body + 3;
    if flags & 0x80 != 0 {
        at += 2;
    }
    if flags & 0x40 != 0 {
        at += 1 + *b.get(at)? as usize;
    }
    if flags & 0x20 != 0 {
        at += 2;
    }
    let (tag, body, config_end) = descriptor(b, at)?;
    if tag != 4 || config_end > end {
        return None;
    }
    let (tag, info, info_end) = descriptor(b, body + 13)?;
    if tag != 5 || info_end > config_end || info_end < info + 2 {
        return None;
    }
    let bits = u16::from_be_bytes([b[info], b[info + 1]]);
    let object = (bits >> 11) as u8;
    let frequency = ((bits >> 7) & 0xf) as u8;
    let channels = ((bits >> 3) & 0xf) as u8;
    // ADTS carries profiles 1 to 4 (AAC LC is 2) and indexed frequencies.
    if !(1..=4).contains(&object) || frequency >= 13 || channels == 0 || channels > 7 {
        return None;
    }
    Some(Codec::Aac { profile: object - 1, frequency, channels })
}

fn index(data: &[u8], sidx: Atom) -> Option<Vec<Segment>> {
    let b = &data[sidx.body..sidx.end];
    let version = *b.first()?;
    let timescale = be32(b, 8).filter(|&t| t > 0)? as f64;
    let (earliest, first, mut at) = match version {
        0 => (be32(b, 12)? as u64, be32(b, 16)? as u64, 20),
        _ => (be64(b, 12)?, be64(b, 20)?, 28),
    };
    let count = be16(b, at + 2)? as usize;
    at += 4;
    let mut offset = sidx.end as u64 + first;
    let mut time = earliest;
    let mut segments = Vec::with_capacity(count);
    for _ in 0..count {
        let reference = be32(b, at)?;
        let duration = be32(b, at + 4)?;
        // A reference to another index: YouTube's files have none.
        if reference & 0x8000_0000 != 0 {
            return None;
        }
        let size = (reference & 0x7fff_ffff) as u64;
        segments.push(Segment { offset, size, start: time as f64 / timescale });
        offset += size;
        time += duration as u64;
        at += 12;
    }
    Some(segments)
}

// ---- fragments ----

/// The samples of every `moof` in one segment's bytes. `base` is the
/// segment's offset in its file, for a `tfhd` that gives an absolute one.
fn fragment(data: Vec<u8>, base: u64, defaults: Defaults) -> Result<Fragment, &'static str> {
    let mut samples = Vec::new();
    for moof in atoms(&data, 0, data.len()).into_iter().filter(|a| &a.kind == b"moof") {
        if moof.end > data.len() {
            return Err("fragment cut short");
        }
        for traf in atoms(&data, moof.body, moof.end).into_iter().filter(|a| &a.kind == b"traf") {
            read_traf(&data, moof, traf, base, defaults, &mut samples)?;
        }
    }
    for s in &samples {
        if s.at.checked_add(s.size).is_none_or(|end| end > data.len()) {
            return Err("sample outside the fragment");
        }
    }
    Ok(Fragment { data, samples })
}

fn read_traf(data: &[u8], moof: Atom, traf: Atom, base: u64, defaults: Defaults, samples: &mut Vec<Sample>) -> Result<(), &'static str> {
    let tfhd = child(data, traf, b"tfhd").ok_or("no tfhd")?;
    let flags = be32(data, tfhd.body).ok_or("short tfhd")? & 0xff_ffff;
    let mut at = tfhd.body + 8;
    let mut start = moof.start as u64;
    if flags & 0x01 != 0 {
        start = be64(data, at).ok_or("short tfhd")?.checked_sub(base).ok_or("base before the segment")?;
        at += 8;
    }
    if flags & 0x02 != 0 {
        at += 4;
    }
    let mut d = defaults;
    if flags & 0x08 != 0 {
        d.duration = be32(data, at).ok_or("short tfhd")?;
        at += 4;
    }
    if flags & 0x10 != 0 {
        d.size = be32(data, at).ok_or("short tfhd")?;
        at += 4;
    }
    if flags & 0x20 != 0 {
        d.flags = be32(data, at).ok_or("short tfhd")?;
    }
    let mut time = match child(data, traf, b"tfdt") {
        Some(tfdt) => match data[tfdt.body] {
            1 => be64(data, tfdt.body + 4),
            _ => be32(data, tfdt.body + 4).map(u64::from),
        }
        .ok_or("short tfdt")?,
        None => samples.last().map_or(0, |s| s.time + s.duration as u64),
    };
    let mut next = start;
    for trun in atoms(data, traf.body, traf.end).into_iter().filter(|a| &a.kind == b"trun") {
        let b = &data[trun.body..trun.end.min(data.len())];
        let version = b[0];
        let flags = be32(b, 0).ok_or("short trun")? & 0xff_ffff;
        let count = be32(b, 4).ok_or("short trun")? as usize;
        let mut at = 8;
        if flags & 0x01 != 0 {
            let offset = be32(b, at).ok_or("short trun")? as i32 as i64;
            next = u64::try_from(start as i64 + offset).map_err(|_| "negative data offset")?;
            at += 4;
        }
        let mut first_flags = None;
        if flags & 0x04 != 0 {
            first_flags = Some(be32(b, at).ok_or("short trun")?);
            at += 4;
        }
        for i in 0..count {
            let mut field = |on: u32| -> Result<Option<u32>, &'static str> {
                if flags & on == 0 {
                    return Ok(None);
                }
                let v = be32(b, at).ok_or("short trun")?;
                at += 4;
                Ok(Some(v))
            };
            let duration = field(0x100)?.unwrap_or(d.duration);
            let size = field(0x200)?.unwrap_or(d.size) as usize;
            let mut sample_flags = field(0x400)?.unwrap_or(d.flags);
            if i == 0 && let Some(f) = first_flags {
                sample_flags = f;
            }
            let offset = field(0x800)?.map_or(0, |v| if version == 0 { v.min(i32::MAX as u32) as i32 } else { v as i32 });
            samples.push(Sample { at: usize::try_from(next).map_err(|_| "offset too large")?, size, time, duration, offset, sync: sample_flags & 0x0001_0000 == 0 });
            next += size as u64;
            time += duration as u64;
        }
    }
    Ok(())
}

// ---- reading from YouTube ----

/// Bytes of one file read in order from a position, in chunks.
struct Reader<'a> {
    fetch: &'a dyn Fetch,
    target: &'a Target,
    position: u64,
    body: Option<(crate::relay::Body, u64)>,
}

impl<'a> Reader<'a> {
    fn new(fetch: &'a dyn Fetch, target: &'a Target, position: u64) -> Self {
        Reader { fetch, target, position, body: None }
    }

    /// Exactly `n` bytes from the current position.
    fn take(&mut self, n: u64) -> Result<Vec<u8>, String> {
        let mut out = vec![0u8; usize::try_from(n).map_err(|_| "too large")?];
        let mut filled = 0;
        let mut retries = 0;
        while filled < out.len() {
            if self.body.is_none() {
                let last = (self.position + self.target.chunk.max(1) - 1).min(self.target.size.saturating_sub(1));
                if last < self.position {
                    return Err(format!("read past the end at byte {}", self.position));
                }
                let body = request(self.fetch, self.target, self.position, last).map_err(|s: Stop| s.why())?;
                self.body = Some((drain(body, last + 1 - self.position), last));
            }
            let (body, last) = self.body.as_mut().unwrap();
            let last = *last;
            match body.read(&mut out[filled..]) {
                Ok(0) => {
                    self.body = None;
                    if self.position <= last {
                        retries += 1;
                        if retries > 2 {
                            return Err(format!("YouTube broke off at byte {}", self.position));
                        }
                    }
                }
                Ok(read) => {
                    filled += read;
                    self.position += read as u64;
                    retries = 0;
                    if self.position > last {
                        self.body = None;
                    }
                }
                Err(e) if e.kind() == ErrorKind::Interrupted => {}
                Err(e) => {
                    self.body = None;
                    retries += 1;
                    if retries > 2 {
                        return Err(e.to_string());
                    }
                }
            }
        }
        Ok(out)
    }

    fn seek(&mut self, position: u64) {
        if position != self.position {
            self.body = None;
            self.position = position;
        }
    }
}

/// Reads the head of `target` until its index is there.
pub fn fetch_head(fetch: &dyn Fetch, target: &Target) -> Result<Track, String> {
    let mut want = (64u64 << 10).min(target.size);
    loop {
        let data = Reader::new(fetch, target, 0).take(want)?;
        match read_head(&data) {
            Head::Track(track) => return Ok(*track),
            Head::Unusable(why) => return Err(why.into()),
            Head::More(more) => {
                let more = more.min(target.size);
                if more <= want || more > HEAD_LIMIT {
                    return Err("the index is not at the head of the file".into());
                }
                want = more;
            }
        }
    }
}

/// One track's fragments, in order from a segment.
struct Source<'a> {
    track: &'a Track,
    reader: Reader<'a>,
    next: usize,
}

impl<'a> Source<'a> {
    fn new(fetch: &'a dyn Fetch, target: &'a Target, track: &'a Track, first: usize) -> Self {
        let offset = track.segments.get(first).map_or(0, |s| s.offset);
        Source { track, reader: Reader::new(fetch, target, offset), next: first }
    }

    fn fragment(&mut self) -> Result<Option<Fragment>, String> {
        let Some(&segment) = self.track.segments.get(self.next) else { return Ok(None) };
        if segment.size > FRAGMENT_LIMIT {
            return Err("fragment too large".into());
        }
        self.reader.seek(segment.offset);
        let data = self.reader.take(segment.size)?;
        self.next += 1;
        fragment(data, segment.offset, self.track.defaults).map(Some).map_err(String::from)
    }
}

/// The segment holding `seconds`: the last that starts at or before it.
fn segment_at(track: &Track, seconds: f64) -> usize {
    track.segments.iter().rposition(|s| s.start <= seconds + 1e-6).unwrap_or(0)
}

// ---- writing ----

fn put_box(out: &mut Vec<u8>, kind: &[u8; 4], body: impl FnOnce(&mut Vec<u8>)) {
    let start = out.len();
    out.extend_from_slice(&[0, 0, 0, 0]);
    out.extend_from_slice(kind);
    body(out);
    let size = (out.len() - start) as u32;
    out[start..start + 4].copy_from_slice(&size.to_be_bytes());
}

/// `trak` with its `tkhd` track id set to `id`.
fn renumbered(trak: &[u8], id: u32) -> Vec<u8> {
    let mut trak = trak.to_vec();
    let outer = Atom { kind: *b"trak", start: 0, body: 8, end: trak.len() };
    if let Some(tkhd) = child(&trak, outer, b"tkhd") {
        let at = tkhd.body + if trak[tkhd.body] == 1 { 20 } else { 12 };
        if at + 4 <= tkhd.end {
            trak[at..at + 4].copy_from_slice(&id.to_be_bytes());
        }
    }
    trak
}

/// The start of a fragmented MP4 holding both tracks: picture as track 1,
/// sound as track 2.
fn mp4_head(video: &Track, audio: &Track) -> Vec<u8> {
    let mut out = Vec::new();
    put_box(&mut out, b"ftyp", |o| {
        o.extend_from_slice(b"isom");
        o.extend_from_slice(&0x200u32.to_be_bytes());
        for brand in [b"isom", b"iso5", b"iso6", b"mp41"] {
            o.extend_from_slice(brand);
        }
    });
    put_box(&mut out, b"moov", |o| {
        let mut mvhd = video.mvhd.clone();
        let n = mvhd.len();
        if n >= 12 {
            mvhd[n - 4..].copy_from_slice(&3u32.to_be_bytes());
        }
        o.extend_from_slice(&mvhd);
        o.extend_from_slice(&renumbered(&video.trak, 1));
        o.extend_from_slice(&renumbered(&audio.trak, 2));
        put_box(o, b"mvex", |o| {
            for id in [1u32, 2] {
                put_box(o, b"trex", |o| {
                    o.extend_from_slice(&[0, 0, 0, 0]);
                    o.extend_from_slice(&id.to_be_bytes());
                    o.extend_from_slice(&1u32.to_be_bytes());
                    o.extend_from_slice(&[0; 12]);
                });
            }
        });
    });
    out
}

/// One `moof` and `mdat` for `samples` of `fragment`, decode times moved
/// back by `rebase`.
fn mp4_fragment(out: &mut Vec<u8>, sequence: u32, track: u32, fragment: &Fragment, samples: &[Sample], rebase: u64) {
    let Some(first) = samples.first() else { return };
    let moof_start = out.len();
    let mut offset_at = 0;
    put_box(out, b"moof", |o| {
        put_box(o, b"mfhd", |o| {
            o.extend_from_slice(&[0, 0, 0, 0]);
            o.extend_from_slice(&sequence.to_be_bytes());
        });
        put_box(o, b"traf", |o| {
            put_box(o, b"tfhd", |o| {
                o.extend_from_slice(&0x0002_0000u32.to_be_bytes());
                o.extend_from_slice(&track.to_be_bytes());
            });
            put_box(o, b"tfdt", |o| {
                o.extend_from_slice(&0x0100_0000u32.to_be_bytes());
                o.extend_from_slice(&first.time.saturating_sub(rebase).to_be_bytes());
            });
            put_box(o, b"trun", |o| {
                o.extend_from_slice(&0x0100_0f01u32.to_be_bytes());
                o.extend_from_slice(&(samples.len() as u32).to_be_bytes());
                offset_at = o.len();
                o.extend_from_slice(&[0, 0, 0, 0]);
                for s in samples {
                    o.extend_from_slice(&s.duration.to_be_bytes());
                    o.extend_from_slice(&(s.size as u32).to_be_bytes());
                    let flags: u32 = if s.sync { 0x0200_0000 } else { 0x0101_0000 };
                    o.extend_from_slice(&flags.to_be_bytes());
                    o.extend_from_slice(&s.offset.to_be_bytes());
                }
            });
        });
    });
    let data_offset = (out.len() - moof_start + 8) as u32;
    out[offset_at..offset_at + 4].copy_from_slice(&data_offset.to_be_bytes());
    let total: usize = samples.iter().map(|s| s.size).sum();
    out.extend_from_slice(&((total + 8) as u32).to_be_bytes());
    out.extend_from_slice(b"mdat");
    for s in samples {
        out.extend_from_slice(&fragment.data[s.at..s.at + s.size]);
    }
}

/// MPEG transport stream packets for one picture and one sound track.
struct TsWriter {
    counters: HashMap<u16, u8>,
    packets: u64,
}

const PID_PMT: u16 = 0x1000;
const PID_VIDEO: u16 = 0x100;
const PID_AUDIO: u16 = 0x101;
/// Added to every timestamp, so the first ones are not near zero.
const TS_BASE: u64 = 2 * 90_000;

fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for &byte in data {
        crc ^= (byte as u32) << 24;
        for _ in 0..8 {
            crc = if crc & 0x8000_0000 != 0 { (crc << 1) ^ 0x04c1_1db7 } else { crc << 1 };
        }
    }
    crc
}

fn timestamp(out: &mut Vec<u8>, marker: u8, t: u64) {
    let t = t & 0x1_ffff_ffff;
    out.push((marker << 4) | (((t >> 30) as u8 & 0x07) << 1) | 1);
    out.extend_from_slice(&((((t >> 15) & 0x7fff) << 1 | 1) as u16).to_be_bytes());
    out.extend_from_slice(&((((t & 0x7fff) << 1) | 1) as u16).to_be_bytes());
}

impl TsWriter {
    fn new() -> Self {
        TsWriter { counters: HashMap::new(), packets: 0 }
    }

    fn counter(&mut self, pid: u16) -> u8 {
        let c = self.counters.entry(pid).or_insert(0);
        let now = *c;
        *c = (*c + 1) & 0x0f;
        now
    }

    /// `payload` split into packets of `pid`; the first carries `pcr` and the
    /// random access flag when given.
    fn packetize(&mut self, out: &mut Vec<u8>, pid: u16, payload: &[u8], pcr: Option<u64>, random: bool) {
        let mut at = 0;
        let mut first = true;
        while at < payload.len() || first {
            let mut adaptation = Vec::new();
            if first && (pcr.is_some() || random) {
                let mut flags = 0u8;
                if random {
                    flags |= 0x40;
                }
                if pcr.is_some() {
                    flags |= 0x10;
                }
                adaptation.push(flags);
                if let Some(pcr) = pcr {
                    let base = pcr & 0x1_ffff_ffff;
                    adaptation.extend_from_slice(&((base >> 1) as u32).to_be_bytes());
                    adaptation.push((((base & 1) as u8) << 7) | 0x7e);
                    adaptation.push(0);
                }
            }
            let room = 184 - if adaptation.is_empty() { 0 } else { adaptation.len() + 1 };
            let left = payload.len() - at;
            let mut take = left.min(room);
            // Fill the last packet with stuffing in its adaptation field.
            if left < room {
                if adaptation.is_empty() {
                    // One length byte, then a flags byte if there is room for it.
                    let pad = 184 - left;
                    if pad == 1 {
                        adaptation = Vec::new();
                        take = left;
                        out.extend_from_slice(&self.header(pid, first, true));
                        out.push(0);
                        out.extend_from_slice(&payload[at..at + take]);
                        at += take;
                        first = false;
                        self.packets += 1;
                        continue;
                    }
                    adaptation.push(0);
                    adaptation.resize(pad - 1, 0xff);
                } else {
                    let pad = room - left;
                    adaptation.resize(adaptation.len() + pad, 0xff);
                }
                take = left;
            }
            out.extend_from_slice(&self.header(pid, first, !adaptation.is_empty()));
            if !adaptation.is_empty() {
                out.push(adaptation.len() as u8);
                out.extend_from_slice(&adaptation);
            }
            out.extend_from_slice(&payload[at..at + take]);
            at += take;
            first = false;
            self.packets += 1;
        }
    }

    fn header(&mut self, pid: u16, start: bool, adaptation: bool) -> [u8; 4] {
        let counter = self.counter(pid);
        [0x47, (if start { 0x40 } else { 0 }) | ((pid >> 8) as u8 & 0x1f), pid as u8, (if adaptation { 0x30 } else { 0x10 }) | counter]
    }

    fn section(&mut self, out: &mut Vec<u8>, pid: u16, table: u8, id: u16, body: &[u8]) {
        let mut section = vec![table];
        let length = (body.len() + 5 + 4) as u16;
        section.extend_from_slice(&(0xb000 | length).to_be_bytes());
        section.extend_from_slice(&id.to_be_bytes());
        section.extend_from_slice(&[0xc1, 0, 0]);
        section.extend_from_slice(body);
        let crc = crc32(&section);
        section.extend_from_slice(&crc.to_be_bytes());
        let mut payload = vec![0u8];
        payload.extend_from_slice(&section);
        payload.resize(184, 0xff);
        let counter = self.counter(pid);
        out.extend_from_slice(&[0x47, 0x40 | ((pid >> 8) as u8 & 0x1f), pid as u8, 0x10 | counter]);
        out.extend_from_slice(&payload);
        self.packets += 1;
    }

    fn tables(&mut self, out: &mut Vec<u8>) {
        let mut pat = Vec::new();
        pat.extend_from_slice(&1u16.to_be_bytes());
        pat.extend_from_slice(&(0xe000 | PID_PMT).to_be_bytes());
        self.section(out, 0, 0x00, 1, &pat);
        let mut pmt = Vec::new();
        pmt.extend_from_slice(&(0xe000 | PID_VIDEO).to_be_bytes());
        pmt.extend_from_slice(&0xf000u16.to_be_bytes());
        for (kind, pid) in [(0x1b, PID_VIDEO), (0x0f, PID_AUDIO)] {
            pmt.push(kind);
            pmt.extend_from_slice(&(0xe000 | pid).to_be_bytes());
            pmt.extend_from_slice(&0xf000u16.to_be_bytes());
        }
        self.section(out, PID_PMT, 0x02, 1, &pmt);
    }

    fn video(&mut self, out: &mut Vec<u8>, codec: &Codec, data: &[u8], sync: bool, dts: u64, pts: u64) {
        let Codec::Avc { length, sps, pps } = codec else { return };
        let mut es = vec![0, 0, 0, 1, 0x09, 0xf0];
        let mut nals = Vec::new();
        let mut at = 0;
        while at + length <= data.len() {
            let n = data[at..at + length].iter().fold(0usize, |n, &b| (n << 8) | b as usize);
            at += length;
            let Some(nal) = data.get(at..at + n) else { break };
            at += n;
            nals.push(nal);
        }
        let has_sets = nals.iter().any(|n| n.first().is_some_and(|b| b & 0x1f == 7));
        for nal in nals {
            let kind = nal.first().map_or(0, |b| b & 0x1f);
            if kind == 9 {
                continue;
            }
            if kind == 5 && !has_sets {
                for set in sps.iter().chain(pps) {
                    es.extend_from_slice(&[0, 0, 0, 1]);
                    es.extend_from_slice(set);
                }
            }
            es.extend_from_slice(&[0, 0, 0, 1]);
            es.extend_from_slice(nal);
        }
        let mut pes = vec![0, 0, 1, 0xe0, 0, 0, 0x80];
        if pts != dts {
            pes.extend_from_slice(&[0xc0, 10]);
            timestamp(&mut pes, 3, pts);
            timestamp(&mut pes, 1, dts);
        } else {
            pes.extend_from_slice(&[0x80, 5]);
            timestamp(&mut pes, 2, pts);
        }
        pes.extend_from_slice(&es);
        if sync {
            self.tables(out);
        }
        self.packetize(out, PID_VIDEO, &pes, Some(dts.saturating_sub(9000)), sync);
    }

    fn audio(&mut self, out: &mut Vec<u8>, codec: &Codec, data: &[u8], pts: u64) {
        let Codec::Aac { profile, frequency, channels } = *codec else { return };
        let length = data.len() + 7;
        if length > 0x1fff {
            return;
        }
        let adts = [
            0xff,
            0xf1,
            (profile << 6) | (frequency << 2) | (channels >> 2),
            ((channels & 3) << 6) | ((length >> 11) as u8 & 0x03),
            (length >> 3) as u8,
            (((length & 7) as u8) << 5) | 0x1f,
            0xfc,
        ];
        let size = 3 + 5 + adts.len() + data.len();
        let mut pes = vec![0, 0, 1, 0xc0];
        pes.extend_from_slice(&(size as u16).to_be_bytes());
        pes.extend_from_slice(&[0x80, 0x80, 5]);
        timestamp(&mut pes, 2, pts);
        pes.extend_from_slice(&adts);
        pes.extend_from_slice(data);
        self.packetize(out, PID_AUDIO, &pes, None, false);
    }
}

fn ticks90(ticks: u64, timescale: u32) -> u64 {
    (ticks as u128 * 90_000 / timescale as u128) as u64
}

// ---- the stream ----

/// What a session streams: both tracks' heads and where to start.
pub struct Session {
    video_target: Target,
    audio_target: Target,
    video: Track,
    audio: Track,
    start: f64,
    kind: Kind,
    /// Raised by each request, so an older one for the same session stops.
    generation: AtomicU64,
}

impl Session {
    pub fn new(ask: Ask, fetch: &dyn Fetch) -> Result<Session, String> {
        let (video, audio) = std::thread::scope(|scope| {
            let video = scope.spawn(|| fetch_head(fetch, &ask.video));
            let audio = fetch_head(fetch, &ask.audio);
            (video.join().unwrap_or_else(|_| Err("failed".into())), audio)
        });
        let (video, audio) = (video.map_err(|e| format!("picture: {e}"))?, audio.map_err(|e| format!("sound: {e}"))?);
        if !video.video || audio.video {
            return Err("tracks swapped".into());
        }
        if ask.kind == Kind::Ts && (!matches!(video.codec, Codec::Avc { .. }) || !matches!(audio.codec, Codec::Aac { .. })) {
            return Err("only H.264 with AAC goes into a transport stream".into());
        }
        Ok(Session { video_target: ask.video, audio_target: ask.audio, video, audio, start: ask.start_ms as f64 / 1000.0, kind: ask.kind, generation: AtomicU64::new(0) })
    }

    /// Where the stream really starts, in seconds: the keyframe at or
    /// before the asked position.
    pub fn starts_at(&self) -> f64 {
        self.video.segments[segment_at(&self.video, self.start)].start
    }

    pub fn mime(&self) -> &'static str {
        match self.kind {
            Kind::Mp4 => "video/mp4",
            Kind::Ts => "video/mpeg",
        }
    }

    /// Writes the stream into `into` until it ends, the client goes away or
    /// a newer request for this session starts.
    pub fn stream(&self, fetch: &dyn Fetch, into: &mut dyn Write) -> Result<(), String> {
        let generation = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
        let current = || self.generation.load(Ordering::SeqCst) == generation;
        let first_video = segment_at(&self.video, self.start);
        let mut video = Source::new(fetch, &self.video_target, &self.video, first_video);
        let mut v = video.fragment()?;
        // The picture starts at its first keyframe; the sound at the same time.
        if let Some(f) = v.as_mut() {
            let keyframe = f.samples.iter().position(|s| s.sync).unwrap_or(0);
            f.samples.drain(..keyframe);
        }
        let Some(origin) = v.as_ref().and_then(|f| f.samples.first()).map(|s| s.time) else { return Err("no picture".into()) };
        let seconds = origin as f64 / self.video.timescale as f64;
        let audio_origin = (seconds * self.audio.timescale as f64).round() as u64;
        let mut audio = Source::new(fetch, &self.audio_target, &self.audio, segment_at(&self.audio, seconds));
        let mut a = audio.fragment()?;
        while let Some(f) = a.as_mut() {
            f.samples.retain(|s| s.time >= audio_origin);
            if !f.samples.is_empty() {
                break;
            }
            a = audio.fragment()?;
        }
        let rebase = [origin, audio_origin];
        let mut out = Vec::with_capacity(1 << 20);
        match self.kind {
            Kind::Mp4 => {
                out.extend_from_slice(&mp4_head(&self.video, &self.audio));
                let mut sequence = 1u32;
                let timescales = [self.video.timescale, self.audio.timescale];
                loop {
                    if !current() {
                        return Ok(());
                    }
                    let start = |f: &Option<Fragment>, i: usize| {
                        f.as_ref().and_then(|f| f.samples.first()).map(|s| s.time.saturating_sub(rebase[i]) as f64 / timescales[i] as f64)
                    };
                    let pick = match (start(&v, 0), start(&a, 1)) {
                        (None, None) => break,
                        (Some(_), None) => 0,
                        (None, Some(_)) => 1,
                        (Some(x), Some(y)) => usize::from(y < x),
                    };
                    let (slot, source) = if pick == 0 { (&mut v, &mut video) } else { (&mut a, &mut audio) };
                    if let Some(f) = slot.as_ref() {
                        mp4_fragment(&mut out, sequence, pick as u32 + 1, f, &f.samples, rebase[pick]);
                        sequence += 1;
                    }
                    into.write_all(&out).map_err(|_| String::new())?;
                    out.clear();
                    *slot = next_fragment(source)?;
                }
            }
            Kind::Ts => {
                let mut ts = TsWriter::new();
                ts.tables(&mut out);
                let shift = [ticks90(self.video.shift, self.video.timescale), ticks90(self.audio.shift, self.audio.timescale)];
                let mut at = [0usize, 0usize];
                loop {
                    if !current() {
                        return Ok(());
                    }
                    let time = |f: &Option<Fragment>, i: usize, at: usize, timescale: u32| {
                        f.as_ref().and_then(|f| f.samples.get(at)).map(|s| ticks90(s.time.saturating_sub(rebase[i]), timescale))
                    };
                    let pick = match (time(&v, 0, at[0], self.video.timescale), time(&a, 1, at[1], self.audio.timescale)) {
                        (None, None) => break,
                        (Some(_), None) => 0,
                        (None, Some(_)) => 1,
                        (Some(x), Some(y)) => usize::from(y < x),
                    };
                    if pick == 0 {
                        let f = v.as_ref().unwrap();
                        let s = f.samples[at[0]];
                        let dts = (TS_BASE + ticks90(s.time.saturating_sub(rebase[0]), self.video.timescale)).saturating_sub(shift[0]);
                        let composition = ticks90(s.offset.max(0) as u64, self.video.timescale);
                        ts.video(&mut out, &self.video.codec, &f.data[s.at..s.at + s.size], s.sync, dts, dts + composition);
                        at[0] += 1;
                    } else {
                        let f = a.as_ref().unwrap();
                        let s = f.samples[at[1]];
                        let pts = (TS_BASE + ticks90(s.time.saturating_sub(rebase[1]), self.audio.timescale)).saturating_sub(shift[1]);
                        ts.audio(&mut out, &self.audio.codec, &f.data[s.at..s.at + s.size], pts);
                        at[1] += 1;
                    }
                    if out.len() >= 64 << 10 {
                        into.write_all(&out).map_err(|_| String::new())?;
                        out.clear();
                    }
                    if v.as_ref().is_some_and(|f| at[0] >= f.samples.len()) {
                        v = next_fragment(&mut video)?;
                        at[0] = 0;
                    }
                    if a.as_ref().is_some_and(|f| at[1] >= f.samples.len()) {
                        a = next_fragment(&mut audio)?;
                        at[1] = 0;
                    }
                }
                into.write_all(&out).map_err(|_| String::new())?;
            }
        }
        Ok(())
    }
}

fn next_fragment(source: &mut Source) -> Result<Option<Fragment>, String> {
    loop {
        match source.fragment()? {
            Some(f) if f.samples.is_empty() => continue,
            other => return Ok(other),
        }
    }
}

// ---- the server ----

#[derive(Default)]
struct Shared {
    sessions: HashMap<String, Arc<Session>>,
    order: VecDeque<String>,
    log: VecDeque<String>,
}

pub struct Server {
    port: u16,
    shared: Arc<Mutex<Shared>>,
    fetch: Arc<dyn Fetch>,
}

fn log(shared: &Mutex<Shared>, line: String) {
    let mut shared = shared.lock().unwrap();
    if shared.log.len() >= LOG_KEEP {
        shared.log.pop_front();
    }
    shared.log.push_back(line);
}

fn token() -> Option<String> {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes).ok()?;
    Some(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

impl Server {
    /// Listens on every interface, on a random port.
    pub fn start(fetch: Arc<dyn Fetch>) -> std::io::Result<Server> {
        let listener = TcpListener::bind("0.0.0.0:0")?;
        let port = listener.local_addr()?.port();
        let shared = Arc::new(Mutex::new(Shared::default()));
        let server = Server { port, shared: shared.clone(), fetch: fetch.clone() };
        std::thread::Builder::new().name("cast".into()).spawn(move || {
            let open = Arc::new(AtomicUsize::new(0));
            for client in listener.incoming().flatten() {
                if open.load(Ordering::Relaxed) >= MAX_CONNECTIONS {
                    continue;
                }
                open.fetch_add(1, Ordering::Relaxed);
                let (shared, fetch, done) = (shared.clone(), fetch.clone(), open.clone());
                let spawned = std::thread::Builder::new().name("cast-client".into()).spawn(move || {
                    serve(client, &shared, fetch.as_ref());
                    done.fetch_sub(1, Ordering::Relaxed);
                });
                if spawned.is_err() {
                    open.fetch_sub(1, Ordering::Relaxed);
                }
            }
        })?;
        Ok(server)
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    /// Reads both files' heads and keeps the session; its path, such as
    /// `/<token>.ts`, and where it starts, or why it cannot be streamed.
    pub fn register(&self, ask: Ask) -> Result<(String, f64), String> {
        let kind = ask.kind;
        let session = Session::new(ask, self.fetch.as_ref())?;
        let start = session.starts_at();
        let token = token().ok_or("no randomness")?;
        let mut shared = self.shared.lock().unwrap();
        shared.sessions.insert(token.clone(), Arc::new(session));
        shared.order.push_back(token.clone());
        while shared.order.len() > KEEP {
            if let Some(old) = shared.order.pop_front() {
                shared.sessions.remove(&old);
            }
        }
        Ok((format!("/{token}.{}", if kind == Kind::Ts { "ts" } else { "mp4" }), start))
    }

    pub fn take_log(&self) -> Vec<String> {
        self.shared.lock().unwrap().log.drain(..).collect()
    }
}

fn serve(client: TcpStream, shared: &Mutex<Shared>, fetch: &dyn Fetch) {
    let _ = client.set_read_timeout(Some(Duration::from_secs(30)));
    let _ = client.set_write_timeout(Some(Duration::from_secs(60)));
    let peer = client.peer_addr().map(|a| a.ip().to_string()).unwrap_or_default();
    let Ok(mut writer) = client.try_clone() else { return };
    let mut reader = BufReader::new(client);
    let Some((method, path, _headers)) = read_request(&mut reader) else { return };
    let token = path.trim_start_matches('/').split(['.', '?']).next().unwrap_or("").to_string();
    let session = shared.lock().unwrap().sessions.get(&token).cloned();
    let Some(session) = session.filter(|_| method == "GET" || method == "HEAD") else {
        let _ = writer.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        return;
    };
    let mut head = format!("HTTP/1.1 200 OK\r\nContent-Type: {}\r\nCache-Control: no-cache\r\nConnection: close\r\n", session.mime());
    head.push_str("transferMode.dlna.org: Streaming\r\ncontentFeatures.dlna.org: DLNA.ORG_OP=00;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000\r\n\r\n");
    if writer.write_all(head.as_bytes()).is_err() || method == "HEAD" {
        return;
    }
    log(shared, format!("Casting to {peer} from {:.1} s", session.start));
    let mut out = std::io::BufWriter::with_capacity(256 << 10, &mut writer);
    match session.stream(fetch, &mut out) {
        Ok(()) => log(shared, format!("Cast stream to {peer} ended")),
        Err(e) if e.is_empty() => log(shared, format!("{peer} stopped reading the cast stream")),
        Err(e) => log(shared, format!("Cast stream to {peer} failed: {e}")),
    }
    let _ = out.flush();
    drop(out);
    let _ = writer.shutdown(Shutdown::Both);
}

static SERVER: OnceLock<Server> = OnceLock::new();

/// Starts the server once; its port, or 0 when it could not listen.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_cast_start() -> u16 {
    if let Some(server) = SERVER.get() {
        return server.port();
    }
    match Server::start(Arc::new(Web::default())) {
        Ok(server) => SERVER.get_or_init(|| server).port(),
        Err(_) => 0,
    }
}

/// Registers the [Ask] in [json]: `{"path": ..., "start": seconds}` or
/// `{"error": ...}`.
/// Blocks while both files' heads are read.
///
/// # Safety
/// [json] points at [len] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_cast_register(json: *const u8, len: usize) -> *mut c_char {
    let answer = match SERVER.get() {
        None => Err("not started".to_string()),
        Some(server) => match serde_json::from_str::<Ask>(unsafe { crate::taste::text(json, len) }) {
            Ok(ask) => server.register(ask),
            Err(e) => Err(e.to_string()),
        },
    };
    crate::taste::give_json(&match answer {
        Ok((path, start)) => serde_json::json!({ "path": path, "start": start }),
        Err(error) => serde_json::json!({ "error": error }),
    })
}

/// The server's log lines since the last call, as a JSON array.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_cast_log() -> *mut c_char {
    let lines = SERVER.get().map(Server::take_log).unwrap_or_default();
    crate::taste::give_json(&lines)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Serves a local file like googlevideo serves a stream.
    struct Files(HashMap<String, Vec<u8>>);

    impl Fetch for Files {
        fn get(&self, _: &Target, url: &str) -> Result<(u16, Box<dyn Read + Send>), String> {
            let (name, range) = url.split_once("?range=").or_else(|| url.split_once("&range=")).ok_or("no range")?;
            let name = name.trim_end_matches("?x");
            let data = self.0.get(name).ok_or("unknown")?;
            let (a, b) = range.split_once('-').ok_or("bad range")?;
            let (a, b): (usize, usize) = (a.parse().unwrap(), b.parse().unwrap());
            let b = b.min(data.len() - 1);
            Ok((206, Box::new(std::io::Cursor::new(data[a..=b].to_vec()))))
        }
    }

    fn target(name: &str, size: usize) -> Target {
        Target { url: format!("{name}?x"), size: size as u64, user_agent: None, mime: None, proxy: None, chunk: 1 << 20 }
    }

    fn sample(dir: &str, name: &str) -> Option<Vec<u8>> {
        std::fs::read(format!("{dir}/{name}")).ok()
    }

    #[test]
    fn reads_avc_and_aac_configs() {
        let avcc = [1, 0x64, 0, 0x1f, 0xff, 0xe1, 0, 3, 0x67, 1, 2, 1, 0, 2, 0x68, 9];
        assert_eq!(avc_config(&avcc), Some(Codec::Avc { length: 4, sps: vec![vec![0x67, 1, 2]], pps: vec![vec![0x68, 9]] }));
        // ES_Descriptor > DecoderConfig (mp4a, AAC) > AudioSpecificConfig LC 44.1 kHz stereo.
        let esds = [3, 25, 0, 1, 0, 4, 17, 0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 2, 0x12, 0x10, 6, 1, 2];
        assert_eq!(aac_config(&esds), Some(Codec::Aac { profile: 1, frequency: 4, channels: 2 }));
    }

    #[test]
    fn transport_packets_are_whole() {
        let mut ts = TsWriter::new();
        let mut out = Vec::new();
        ts.tables(&mut out);
        for n in [0usize, 1, 2, 170, 176, 177, 182, 183, 184, 185, 400, 1000] {
            ts.packetize(&mut out, PID_AUDIO, &vec![7u8; n], None, false);
            ts.packetize(&mut out, PID_VIDEO, &vec![7u8; n], Some(123_456), true);
        }
        assert_eq!(out.len() % 188, 0);
        assert!(out.chunks(188).all(|p| p[0] == 0x47));
        assert_eq!(crc32(b"123456789"), 0x0376_e6e7);
    }

    /// Joins files made like YouTube's when LUMTUB_CAST_SAMPLES names their
    /// folder, holding `v.mp4` and `a.mp4` from
    /// `ffmpeg -i in.mp4 -map 0:v -c copy -movflags +frag_keyframe+empty_moov+default_base_moof+global_sidx+dash -frag_duration 2000000 v.mp4`
    /// (and `-map 0:a` for `a.mp4`); the joined files are left there.
    #[test]
    fn joins_dash_files() {
        let Ok(dir) = std::env::var("LUMTUB_CAST_SAMPLES") else { return };
        let (Some(v), Some(a)) = (sample(&dir, "v.mp4"), sample(&dir, "a.mp4")) else { return };
        let files = Files(HashMap::from([("v.mp4".to_string(), v.clone()), ("a.mp4".to_string(), a.clone())]));
        for (kind, start, name) in [(Kind::Mp4, 0, "out.mp4"), (Kind::Ts, 0, "out.ts"), (Kind::Mp4, 9_500, "seek.mp4"), (Kind::Ts, 9_500, "seek.ts")] {
            let ask = Ask { video: target("v.mp4", v.len()), audio: target("a.mp4", a.len()), start_ms: start, kind };
            let session = Session::new(ask, &files).expect("session");
            let mut out = Vec::new();
            session.stream(&files, &mut out).expect("stream");
            std::fs::write(format!("{dir}/{name}"), &out).unwrap();
            assert!(out.len() > 100_000);
        }
        // The same stream through the server, as a TV reads it.
        let server = Server::start(Arc::new(Files(files.0.clone()))).expect("listen");
        let ask = Ask { video: target("v.mp4", v.len()), audio: target("a.mp4", a.len()), start_ms: 0, kind: Kind::Ts };
        let (path, start) = server.register(ask).expect("register");
        assert_eq!(start, 0.0);
        let mut client = TcpStream::connect(("127.0.0.1", server.port())).unwrap();
        write!(client, "GET {path} HTTP/1.1\r\nHost: x\r\n\r\n").unwrap();
        let mut answer = Vec::new();
        client.read_to_end(&mut answer).unwrap();
        let body = answer.windows(4).position(|w| w == b"\r\n\r\n").map(|at| &answer[at + 4..]).unwrap();
        assert!(answer.starts_with(b"HTTP/1.1 200 OK\r\nContent-Type: video/mpeg"));
        assert_eq!(body, std::fs::read(format!("{dir}/out.ts")).unwrap());
    }

    #[test]
    fn serves_a_session_over_http() {
        let mut v = Vec::new();
        put_box(&mut v, b"ftyp", |o| o.extend_from_slice(b"isom"));
        let files = Arc::new(Files(HashMap::from([("v.mp4".to_string(), v.clone())])));
        let server = Server::start(files.clone()).expect("listen");
        let ask = Ask { video: target("v.mp4", v.len()), audio: target("v.mp4", v.len()), start_ms: 0, kind: Kind::Mp4 };
        assert!(server.register(ask).unwrap_err().contains("picture"));
        let mut client = TcpStream::connect(("127.0.0.1", server.port())).unwrap();
        client.write_all(b"GET /0123456789abcdef.mp4 HTTP/1.1\r\nHost: x\r\n\r\n").unwrap();
        let mut answer = String::new();
        client.read_to_string(&mut answer).unwrap();
        assert!(answer.starts_with("HTTP/1.1 404"));
    }
}
