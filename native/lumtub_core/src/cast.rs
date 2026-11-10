//! Serves a YouTube video to a TV on the local network with its picture and
//! sound joined into one stream, without decoding anything. YouTube sends
//! its better pictures and its sound as separate fragmented MP4 files, and
//! a TV takes one address; the index (`sidx`) at the head of each file says
//! where every fragment starts, so the two are read fragment by fragment
//! and written out as one fragmented MP4 (for Chromecast), an MPEG
//! transport stream (for DLNA renderers, which take it most reliably), an
//! HLS playlist of transport stream segments (for Apple's players) or
//! Matroska (any picture, with a subtitle track).
//!
//! The stream starts at the keyframe at or before the asked position;
//! seeking registers the video again from the new position. Bytes are read
//! from YouTube in chunks the way the loopback relay reads them. Only
//! registered sessions are served, under random tokens.

use crate::{cast_mkv, cast_webm};
use crate::relay::{Fetch, Stop, Target, Web, drain, read_request, request};
use serde::Deserialize;
use std::collections::{HashMap, VecDeque};
use std::io::{BufReader, ErrorKind, Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
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
    /// An HLS playlist of transport stream segments, for Apple's players,
    /// which play a transport stream only that way.
    Hls,
    /// Matroska, which carries any of the pictures and a subtitle track.
    Mkv,
}

/// The subtitle lines to send inside the stream: start and end in
/// milliseconds from the start of the video, and the text.
#[derive(Deserialize, Default)]
pub struct Subtitles {
    #[serde(default)]
    pub language: String,
    /// What a player lists the track as, such as `English (auto-generated)`.
    #[serde(default)]
    pub name: String,
    pub cues: Vec<(u64, u64, String)>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Ask {
    pub video: Target,
    pub audio: Target,
    #[serde(default)]
    pub start_ms: u64,
    pub kind: Kind,
    /// The video's length, for the last segment of an HLS playlist.
    #[serde(default)]
    pub duration_ms: u64,
    /// Lines for HLS (a WebVTT rendition) and MKV (a text track).
    #[serde(default)]
    pub subtitles: Option<Subtitles>,
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
    /// For a WebM file: its track number and frame duration in ticks.
    webm: Option<(u64, u32)>,
}

#[derive(Debug, Clone, PartialEq)]
enum Codec {
    Avc { length: usize, sps: Vec<Vec<u8>>, pps: Vec<Vec<u8>> },
    Aac { profile: u8, frequency: u8, channels: u8 },
    Opus(cast_webm::Opus),
    /// Dolby Digital (AC-3) or Dolby Digital Plus (E-AC-3).
    Dolby { plus: bool, rate: u32, channels: u8 },
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
    Ok(Track { trak: whole(data, trak), mvhd: whole(data, mvhd), timescale, video, codec, defaults, shift, segments, webm: None })
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
        b"ac-3" | b"ec-3" => {
            let plus = &entry.kind == b"ec-3";
            let rate = be32(data, entry.body + 24).map_or(48_000, |r| r >> 16);
            let mut channels = be16(data, entry.body + 16).unwrap_or(2) as u8;
            let config = if plus { b"dec3" } else { b"dac3" };
            if let Some(c) = atoms(data, entry.body + 28, entry.end).into_iter().find(|a| &a.kind == config && a.end <= data.len()) {
                // acmod and lfeon of the (first) independent stream.
                let at = if plus { c.body + 3 } else { c.body + 1 };
                if let Some(&b) = data.get(at).filter(|_| at < c.end) {
                    let (acmod, lfe) = if plus { ((b >> 1) & 7, b & 1) } else { ((b >> 3) & 7, (b >> 2) & 1) };
                    channels = [2, 1, 2, 3, 3, 4, 4, 5][acmod as usize] + lfe;
                }
            }
            Codec::Dolby { plus, rate, channels }
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

// ---- WebM pictures ----

/// A WebM picture track as the MP4 writer takes it: a `trak` with a `vp09`
/// sample entry, and its clusters as segments; an Opus sound track has an
/// `Opus` one.
fn webm_track(head: &cast_webm::Head, total: u64) -> Track {
    let segments = head
        .clusters
        .iter()
        .enumerate()
        .map(|(i, &(offset, start))| Segment { offset, size: head.clusters.get(i + 1).map_or(total, |n| n.0) - offset, start })
        .collect();
    if let Some(opus) = &head.opus {
        return Track {
            trak: opus_trak(opus, head.timescale),
            mvhd: Vec::new(),
            timescale: head.timescale,
            video: false,
            codec: Codec::Opus(opus.clone()),
            defaults: Defaults::default(),
            shift: 0,
            segments,
            webm: Some((head.number, head.frame)),
        };
    }
    let trak = trak_box(head.timescale, Media::Picture(head.width, head.height), |o| {
        put_box(o, b"vp09", |o| {
            o.extend_from_slice(&[0, 0, 0, 0, 0, 0, 0, 1]);
            o.extend_from_slice(&[0; 16]);
            o.extend_from_slice(&head.width.to_be_bytes());
            o.extend_from_slice(&head.height.to_be_bytes());
            o.extend_from_slice(&0x0048_0000u32.to_be_bytes());
            o.extend_from_slice(&0x0048_0000u32.to_be_bytes());
            o.extend_from_slice(&[0, 0, 0, 0, 0, 1]);
            o.extend_from_slice(&[0; 32]);
            o.extend_from_slice(&[0, 0x18, 0xff, 0xff]);
            o.extend_from_slice(&head.vpcc);
        });
    });
    let mut mvhd = Vec::new();
    put_box(&mut mvhd, b"mvhd", |o| {
        o.extend_from_slice(&[0; 12]);
        o.extend_from_slice(&1000u32.to_be_bytes());
        o.extend_from_slice(&[0; 4]);
        o.extend_from_slice(&0x0001_0000u32.to_be_bytes());
        o.extend_from_slice(&[0x01, 0x00, 0, 0]);
        o.extend_from_slice(&[0; 8]);
        for v in [0x0001_0000u32, 0, 0, 0, 0x0001_0000, 0, 0, 0, 0x4000_0000] {
            o.extend_from_slice(&v.to_be_bytes());
        }
        o.extend_from_slice(&[0; 24]);
        o.extend_from_slice(&2u32.to_be_bytes());
    });
    Track {
        trak,
        mvhd,
        timescale: head.timescale,
        video: true,
        codec: Codec::Other,
        defaults: Defaults::default(),
        shift: 0,
        segments,
        webm: Some((head.number, head.frame)),
    }
}

/// What a track made here holds.
#[derive(Clone, Copy)]
enum Media<'a> {
    Picture(u16, u16),
    Sound,
    /// Timed text in this language (BCP 47).
    Text(&'a str),
}

/// A `trak` with one sample entry, written by `entry`. The sample tables
/// are empty, as the samples come in fragments.
fn trak_box(timescale: u32, media: Media, entry: impl FnOnce(&mut Vec<u8>)) -> Vec<u8> {
    let mut trak = Vec::new();
    put_box(&mut trak, b"trak", |o| {
        put_box(o, b"tkhd", |o| {
            o.extend_from_slice(&3u32.to_be_bytes());
            o.extend_from_slice(&[0; 8]);
            o.extend_from_slice(&1u32.to_be_bytes());
            o.extend_from_slice(&[0; 4 + 4 + 8 + 2]);
            // Subtitle tracks share an alternate group: one shows at a time.
            o.extend_from_slice(&(if matches!(media, Media::Text(_)) { 2u16 } else { 0 }).to_be_bytes());
            o.extend_from_slice(&(if matches!(media, Media::Sound) { 0x0100u16 } else { 0 }).to_be_bytes());
            o.extend_from_slice(&[0; 2]);
            for v in [0x0001_0000u32, 0, 0, 0, 0x0001_0000, 0, 0, 0, 0x4000_0000] {
                o.extend_from_slice(&v.to_be_bytes());
            }
            let (width, height) = if let Media::Picture(w, h) = media { (w, h) } else { (0, 0) };
            o.extend_from_slice(&((width as u32) << 16).to_be_bytes());
            o.extend_from_slice(&((height as u32) << 16).to_be_bytes());
        });
        put_box(o, b"mdia", |o| {
            put_box(o, b"mdhd", |o| {
                o.extend_from_slice(&[0; 12]);
                o.extend_from_slice(&timescale.to_be_bytes());
                o.extend_from_slice(&[0, 0, 0, 0]);
                let language = if let Media::Text(l) = media { crate::embed::iso639_2t(l) } else { "und" };
                let packed = language.bytes().fold(0u16, |v, c| (v << 5) | (c.wrapping_sub(0x60) as u16 & 0x1f));
                o.extend_from_slice(&packed.to_be_bytes());
                o.extend_from_slice(&[0, 0]);
            });
            let (handler, name): (&[u8; 4], &[u8]) = match media {
                Media::Picture(..) => (b"vide", b"VideoHandler\0"),
                Media::Sound => (b"soun", b"SoundHandler\0"),
                Media::Text(_) => (b"sbtl", b"SubtitleHandler\0"),
            };
            put_box(o, b"hdlr", |o| {
                o.extend_from_slice(&[0; 8]);
                o.extend_from_slice(handler);
                o.extend_from_slice(&[0; 12]);
                o.extend_from_slice(name);
            });
            if let Media::Text(language) = media
                && !language.is_empty()
            {
                put_box(o, b"elng", |o| {
                    o.extend_from_slice(&[0; 4]);
                    o.extend_from_slice(language.as_bytes());
                    o.push(0);
                });
            }
            put_box(o, b"minf", |o| {
                match media {
                    Media::Picture(..) => put_box(o, b"vmhd", |o| o.extend_from_slice(&[0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0])),
                    Media::Sound => put_box(o, b"smhd", |o| o.extend_from_slice(&[0; 8])),
                    Media::Text(_) => put_box(o, b"nmhd", |o| o.extend_from_slice(&[0; 4])),
                }
                put_box(o, b"dinf", |o| {
                    put_box(o, b"dref", |o| {
                        o.extend_from_slice(&[0, 0, 0, 0, 0, 0, 0, 1]);
                        put_box(o, b"url ", |o| o.extend_from_slice(&[0, 0, 0, 1]));
                    });
                });
                put_box(o, b"stbl", |o| {
                    put_box(o, b"stsd", |o| {
                        o.extend_from_slice(&[0, 0, 0, 0, 0, 0, 0, 1]);
                        entry(o);
                    });
                    for kind in [b"stts", b"stsc", b"stco"] {
                        put_box(o, kind, |o| o.extend_from_slice(&[0; 8]));
                    }
                    put_box(o, b"stsz", |o| o.extend_from_slice(&[0; 12]));
                });
            });
        });
    });
    trak
}

/// A timed text (`tx3g`) track's `trak`, at 1000 ticks a second: white
/// text centred at the bottom.
fn text_trak(language: &str) -> Vec<u8> {
    trak_box(1000, Media::Text(language), |o| {
        put_box(o, b"tx3g", |o| {
            o.extend_from_slice(&[0, 0, 0, 0, 0, 0, 0, 1]);
            o.extend_from_slice(&0u32.to_be_bytes());
            o.extend_from_slice(&[1, 0xff]);
            o.extend_from_slice(&[0, 0, 0, 0]);
            o.extend_from_slice(&[0; 8]);
            o.extend_from_slice(&[0, 0, 0, 0, 0, 1, 0, 18, 0xff, 0xff, 0xff, 0xff]);
            put_box(o, b"ftab", |o| {
                o.extend_from_slice(&1u16.to_be_bytes());
                o.extend_from_slice(&1u16.to_be_bytes());
                o.push(5);
                o.extend_from_slice(b"Serif");
            });
        });
    })
}

/// The text track's one fragment: each cue a sample, and the gaps between
/// cues empty samples, so it covers the whole video from 0.
fn text_fragment(cues: &[(u64, u64, String)]) -> Fragment {
    let mut data = Vec::new();
    let mut samples = Vec::new();
    let mut at = 0u64;
    let mut sample = |data: &mut Vec<u8>, text: &str, time: u64, duration: u64| {
        let start = data.len();
        let text = &text.as_bytes()[..text.len().min(u16::MAX as usize)];
        data.extend_from_slice(&(text.len() as u16).to_be_bytes());
        data.extend_from_slice(text);
        samples.push(Sample { at: start, size: data.len() - start, time, duration: duration.min(u32::MAX as u64) as u32, offset: 0, sync: true });
    };
    for (i, (start, end, text)) in cues.iter().enumerate() {
        let start = (*start).max(at);
        let end = cues.get(i + 1).map_or(*end, |next| (*end).min(next.0)).max(start + 1);
        if start > at {
            sample(&mut data, "", at, start - at);
        }
        sample(&mut data, text, start, end - start);
        at = end;
    }
    // An empty one after the last, so players that time a line by the
    // next sample clear it.
    if !cues.is_empty() {
        sample(&mut data, "", at, 1);
    }
    Fragment { data, samples }
}

/// `udta` with the title and cover as iTunes-style metadata, which players
/// and file managers read.
fn mp4_metadata(title: Option<&str>, cover: Option<&[u8]>) -> Vec<u8> {
    let mut out = Vec::new();
    if title.is_none() && cover.is_none() {
        return out;
    }
    put_box(&mut out, b"udta", |o| {
        put_box(o, b"meta", |o| {
            o.extend_from_slice(&[0; 4]);
            put_box(o, b"hdlr", |o| {
                o.extend_from_slice(&[0; 8]);
                o.extend_from_slice(b"mdirappl");
                o.extend_from_slice(&[0; 9]);
            });
            put_box(o, b"ilst", |o| {
                let item = |o: &mut Vec<u8>, kind: &[u8; 4], type_: u32, value: &[u8]| {
                    put_box(o, kind, |o| {
                        put_box(o, b"data", |o| {
                            o.extend_from_slice(&type_.to_be_bytes());
                            o.extend_from_slice(&[0; 4]);
                            o.extend_from_slice(value);
                        });
                    });
                };
                if let Some(title) = title {
                    item(o, b"\xa9nam", 1, title.as_bytes());
                }
                if let Some(cover) = cover {
                    item(o, b"covr", if crate::embed::is_png(cover) { 14 } else { 13 }, cover);
                }
            });
        });
    });
    out
}

/// An Opus sound track's `trak`, its `OpusHead` turned into `dOps`
/// (big-endian, without the magic and version).
fn opus_trak(opus: &cast_webm::Opus, timescale: u32) -> Vec<u8> {
    let head = &opus.private;
    let le16 = |at: usize| head.get(at..at + 2).map_or(0, |b| u16::from_le_bytes([b[0], b[1]]));
    let le32 = |at: usize| head.get(at..at + 4).map_or(0, |b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]));
    trak_box(timescale, Media::Sound, |o| {
        put_box(o, b"Opus", |o| {
            o.extend_from_slice(&[0, 0, 0, 0, 0, 0, 0, 1]);
            o.extend_from_slice(&[0; 8]);
            o.extend_from_slice(&(opus.channels as u16).to_be_bytes());
            o.extend_from_slice(&16u16.to_be_bytes());
            o.extend_from_slice(&[0; 4]);
            o.extend_from_slice(&(48000u32 << 16).to_be_bytes());
            put_box(o, b"dOps", |o| {
                o.push(0);
                o.push(head.get(9).copied().unwrap_or(opus.channels));
                o.extend_from_slice(&le16(10).to_be_bytes());
                o.extend_from_slice(&le32(12).to_be_bytes());
                o.extend_from_slice(&le16(16).to_be_bytes());
                o.extend_from_slice(head.get(18..).unwrap_or(&[0]));
            });
        });
    })
}

/// One WebM cluster's frames as samples; each lasts until the next, the
/// last as long as the file says a frame lasts (or as the one before it).
fn webm_fragment(data: Vec<u8>, number: u64, frame: u32) -> Result<Fragment, &'static str> {
    let frames = cast_webm::frames(&data, number)?;
    let mut samples: Vec<Sample> = Vec::with_capacity(frames.len());
    for (i, f) in frames.iter().enumerate() {
        let duration = match frames.get(i + 1) {
            Some(next) if next.time > f.time => (next.time - f.time) as u32,
            _ => samples.last().map_or(frame, |s| s.duration).max(1),
        };
        samples.push(Sample { at: f.at, size: f.size, time: f.time, duration, offset: 0, sync: f.key });
    }
    Ok(Fragment { data, samples })
}

// ---- reading from YouTube ----

/// A stream's address, which the app replaces when YouTube lets it expire.
pub struct Address {
    url: Mutex<String>,
    /// Set when YouTube refused the address; cleared by a new one.
    expired: AtomicBool,
    /// Whether the app can bring a new one: not while a session is being
    /// registered, as nothing asks for it then.
    renewable: bool,
}

impl Address {
    fn new(url: String) -> Arc<Address> {
        Arc::new(Address { url: Mutex::new(url), expired: AtomicBool::new(false), renewable: true })
    }

    fn fixed(url: String) -> Arc<Address> {
        Arc::new(Address { url: Mutex::new(url), expired: AtomicBool::new(false), renewable: false })
    }

    fn get(&self) -> String {
        self.url.lock().unwrap().clone()
    }
}

/// How long a refused address waits for the app to bring a new one.
const RENEW_WAIT: Duration = Duration::from_secs(60);

/// A chunk's reply being opened on another thread.
type Opening = std::thread::JoinHandle<Result<crate::relay::Body, Stop>>;

/// Bytes of one file read in order from a position, in chunks; the next
/// chunk is asked for while the current one is read.
struct Reader {
    fetch: Arc<dyn Fetch>,
    target: Target,
    address: Arc<Address>,
    stop: Arc<AtomicBool>,
    position: u64,
    body: Option<(crate::relay::Body, u64)>,
    ahead: Option<(u64, u64, Opening)>,
}

impl Reader {
    fn new(fetch: Arc<dyn Fetch>, target: &Target, address: Arc<Address>, stop: Arc<AtomicBool>, position: u64) -> Self {
        Reader { fetch, target: target.clone(), address, stop, position, body: None, ahead: None }
    }

    fn last_of(&self, from: u64) -> u64 {
        (from + self.target.chunk.max(1) - 1).min(self.target.size.saturating_sub(1))
    }

    /// Bytes `from` to `last`, read to their end on another thread.
    fn open(&self, from: u64, last: u64) -> Opening {
        let (fetch, mut target) = (self.fetch.clone(), self.target.clone());
        target.url = self.address.get();
        std::thread::spawn(move || request(fetch.as_ref(), &target, from, last).map(|body| drain(body, last + 1 - from)))
    }

    /// The reply for the chunk at the current position: the one asked for
    /// ahead when it is that one. A refused address waits for a new one.
    fn next_body(&mut self) -> Result<(), String> {
        let from = self.position;
        let last = self.last_of(from);
        if last < from {
            return Err(format!("read past the end at byte {from}"));
        }
        let mut waited = Duration::ZERO;
        loop {
            let (pending, early) = match self.ahead.take() {
                Some((f, l, handle)) if f == from && l == last => (handle, true),
                _ => (self.open(from, last), false),
            };
            let tried = self.address.get();
            match pending.join().unwrap_or_else(|_| Err(Stop::Upstream("failed".into()))) {
                Ok(body) => {
                    self.body = Some((body, last));
                    if last + 1 < self.target.size {
                        let next = last + 1;
                        let next_last = self.last_of(next);
                        self.ahead = Some((next, next_last, self.open(next, next_last)));
                    }
                    return Ok(());
                }
                Err(Stop::Refused(status @ (403 | 410), _)) if !self.address.renewable => {
                    return Err(format!("YouTube answered {status}"));
                }
                Err(Stop::Refused(status @ (403 | 410), _)) => {
                    self.address.expired.store(true, Ordering::SeqCst);
                    while self.address.get() == tried {
                        if waited >= RENEW_WAIT || self.stop.load(Ordering::Relaxed) {
                            return Err(format!("YouTube answered {status} and no new address came"));
                        }
                        std::thread::sleep(Duration::from_millis(500));
                        waited += Duration::from_millis(500);
                    }
                }
                // A reply asked for ahead may have failed long ago; ask now.
                Err(Stop::Upstream(_)) if early => {}
                Err(stop) => return Err(stop.why()),
            }
        }
    }

    /// Exactly `n` bytes from the current position.
    fn take(&mut self, n: u64) -> Result<Vec<u8>, String> {
        let mut out = vec![0u8; usize::try_from(n).map_err(|_| "too large")?];
        let mut filled = 0;
        let mut retries = 0;
        while filled < out.len() {
            if self.stop.load(Ordering::Relaxed) {
                return Err(String::new());
            }
            if self.body.is_none() {
                self.next_body()?;
            }
            let (body, last) = self.body.as_mut().unwrap();
            let last = *last;
            match body.read(&mut out[filled..]) {
                Ok(0) => {
                    self.body = None;
                    if self.position <= last {
                        // Asked again from the missing byte, not ahead.
                        self.ahead = None;
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
                    self.ahead = None;
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
pub fn fetch_head(fetch: &Arc<dyn Fetch>, target: &Target) -> Result<Track, String> {
    let mut want = (64u64 << 10).min(target.size);
    let address = Address::fixed(target.url.clone());
    loop {
        let mut reader = Reader::new(fetch.clone(), &Target { chunk: want.max(1), ..target.clone() }, address.clone(), Arc::new(AtomicBool::new(false)), 0);
        let data = reader.take(want)?;
        let head = if cast_webm::is_webm(&data) {
            match cast_webm::read_head(&data, target.size) {
                cast_webm::Read::Head(head) => Head::Track(Box::new(webm_track(&head, target.size))),
                cast_webm::Read::More(more) => Head::More(more),
                cast_webm::Read::Unusable(why) => Head::Unusable(why),
            }
        } else {
            read_head(&data)
        };
        match head {
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

/// Fragments read ahead of the stream, per track.
const AHEAD: usize = 2;

/// Reads `track`'s fragments from segment `first` on its own thread, up to
/// [AHEAD] ahead of the stream; empty fragments are skipped.
fn produce<'s>(scope: &'s std::thread::Scope<'s, '_>, track: &'s Track, mut reader: Reader, first: usize) -> std::sync::mpsc::Receiver<Result<Fragment, String>> {
    let (tx, rx) = std::sync::mpsc::sync_channel(AHEAD);
    scope.spawn(move || {
        let mut next = first;
        while let Some(&segment) = track.segments.get(next) {
            next += 1;
            let read = if segment.size > FRAGMENT_LIMIT {
                Err("fragment too large".to_string())
            } else {
                reader.seek(segment.offset);
                reader.take(segment.size).and_then(|data| match track.webm {
                    Some((number, frame)) => webm_fragment(data, number, frame).map_err(String::from),
                    None => fragment(data, segment.offset, track.defaults).map_err(String::from),
                })
            };
            match read {
                Ok(f) if f.samples.is_empty() => {}
                Ok(f) => {
                    if tx.send(Ok(f)).is_err() {
                        return;
                    }
                }
                Err(e) => {
                    let _ = tx.send(Err(e));
                    return;
                }
            }
        }
    });
    rx
}

fn next_fragment(fragments: &std::sync::mpsc::Receiver<Result<Fragment, String>>) -> Result<Option<Fragment>, String> {
    match fragments.recv() {
        Ok(read) => read.map(Some),
        Err(_) => Ok(None),
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

/// How Matroska names a track's codec, from its sample entry.
fn mkv_track(track: &Track) -> Result<cast_mkv::TrackInfo, String> {
    if let Codec::Opus(opus) = &track.codec {
        return Ok(cast_mkv::TrackInfo { codec: "A_OPUS", private: Some(opus.private.clone()), video: None, audio: Some((opus.rate, opus.channels)), delay: opus.delay, preroll: opus.preroll });
    }
    let data = &track.trak;
    let trak = atoms(data, 0, data.len()).into_iter().next().ok_or("no trak")?;
    let stsd = path(data, trak, &[b"mdia", b"minf", b"stbl", b"stsd"]).ok_or("no stsd")?;
    let entry = atoms(data, stsd.body + 8, stsd.end.min(data.len())).into_iter().next().filter(|e| e.end <= data.len()).ok_or("no sample entry")?;
    let config = |from: usize, kind: &[u8; 4]| atoms(data, from, entry.end).into_iter().find(|a| &a.kind == kind && a.end <= data.len()).map(|a| data[a.body..a.end].to_vec());
    if track.video {
        let size = (be16(data, entry.body + 24).unwrap_or(0), be16(data, entry.body + 26).unwrap_or(0));
        let (codec, private) = match &entry.kind {
            b"avc1" | b"avc3" => ("V_MPEG4/ISO/AVC", Some(config(entry.body + 78, b"avcC").ok_or("no avcC")?)),
            b"vp09" => ("V_VP9", None),
            b"av01" => ("V_AV1", Some(config(entry.body + 78, b"av1C").ok_or("no av1C")?)),
            _ => return Err("a picture MKV does not take here".into()),
        };
        return Ok(cast_mkv::TrackInfo { codec, private, video: Some(size), audio: None, delay: 0, preroll: 0 });
    }
    if let Codec::Dolby { plus, rate, channels } = track.codec {
        return Ok(cast_mkv::TrackInfo { codec: if plus { "A_EAC3" } else { "A_AC3" }, private: None, video: None, audio: Some((rate as f64, channels)), delay: 0, preroll: 0 });
    }
    let Codec::Aac { profile, frequency, channels } = track.codec else { return Err("sound other than AAC, Opus or Dolby".into()) };
    const RATES: [u32; 13] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350];
    let bits = ((profile as u16 + 1) << 11) | ((frequency as u16) << 7) | ((channels as u16) << 3);
    Ok(cast_mkv::TrackInfo { codec: "A_AAC", private: Some(bits.to_be_bytes().to_vec()), video: None, audio: Some((RATES[frequency as usize] as f64, channels)), delay: 0, preroll: 0 })
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
/// sound as track 2, and `texts` (language) as tracks 3 on, with `extra`
/// metadata.
fn mp4_head(video: &Track, audio: &Track, texts: &[&str], title: Option<&str>, cover: Option<&[u8]>) -> Vec<u8> {
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
            mvhd[n - 4..].copy_from_slice(&(3 + texts.len() as u32).to_be_bytes());
        }
        o.extend_from_slice(&mvhd);
        o.extend_from_slice(&renumbered(&video.trak, 1));
        o.extend_from_slice(&renumbered(&audio.trak, 2));
        for (i, language) in texts.iter().enumerate() {
            o.extend_from_slice(&renumbered(&text_trak(language), 3 + i as u32));
        }
        o.extend_from_slice(&mp4_metadata(title, cover));
        put_box(o, b"mvex", |o| {
            for id in 1..3 + texts.len() as u32 {
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

/// What a saved Matroska file's head still needs once it is whole.
struct Saved {
    segment: usize,
    duration_at: Option<usize>,
    cues_at: Option<usize>,
    duration: f64,
    cues: u64,
}

/// Stretches left out of a saved file, in ms from its start: each from a
/// picture keyframe to a later one, so nothing is encoded again.
#[derive(Default, Clone, Debug, PartialEq)]
pub struct Cuts(Vec<(i64, i64)>);

impl Cuts {
    /// The stretches `asked` (seconds) narrowed to `keyframes` (ms, in
    /// order): from the first keyframe at or after a stretch's start to the
    /// last at or before its end, so no more than asked is left out. A
    /// stretch with no two keyframes in it stays.
    pub fn snap(asked: &[(f64, f64)], keyframes: &[i64]) -> Cuts {
        let mut cuts: Vec<(i64, i64)> = asked
            .iter()
            .filter_map(|&(from, to)| {
                let (from, to) = ((from * 1000.0).round() as i64, (to * 1000.0).round() as i64);
                let start = *keyframes.iter().find(|&&k| k >= from)?;
                let end = *keyframes.iter().rev().find(|&&k| k <= to)?;
                (end > start).then_some((start, end))
            })
            .collect();
        cuts.sort();
        let mut merged: Vec<(i64, i64)> = Vec::new();
        for (start, end) in cuts {
            match merged.last_mut() {
                Some(last) if start <= last.1 => last.1 = last.1.max(end),
                _ => merged.push((start, end)),
            }
        }
        Cuts(merged)
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    pub fn stretches(&self) -> &[(i64, i64)] {
        &self.0
    }

    /// Whether `ms` falls in a stretch left out.
    fn inside(&self, ms: i64) -> bool {
        self.0.iter().any(|&(a, b)| a <= ms && ms < b)
    }

    /// How much is left out before `ms`.
    fn before(&self, ms: i64) -> i64 {
        self.0.iter().filter(|&&(_, b)| b <= ms).map(|&(a, b)| b - a).sum()
    }

    /// Where `ms` lands in the file once the stretches are out: a time in
    /// one lands where it starts.
    pub fn map(&self, ms: i64) -> i64 {
        let ms = self.0.iter().find(|&&(a, b)| a <= ms && ms < b).map_or(ms, |&(a, _)| a);
        ms - self.before(ms)
    }

    /// `cues` (ms) moved to where they land, those wholly left out dropped.
    pub fn cues(&self, cues: &[(u64, u64, String)]) -> Vec<(u64, u64, String)> {
        cues.iter()
            .filter_map(|(start, end, text)| {
                let (start, end) = (self.map(*start as i64), self.map(*end as i64));
                (end > start).then(|| (start as u64, end as u64, text.clone()))
            })
            .collect()
    }
}

/// What a session streams: both tracks' heads and where to start.
pub struct Session {
    video_target: Target,
    audio_target: Target,
    addresses: [Arc<Address>; 2],
    video: Track,
    audio: Track,
    start: f64,
    kind: Kind,
    duration: f64,
    subtitles: Option<Subtitles>,
    /// Matroska named so even when WebM would hold it.
    matroska: bool,
    /// What a saved file carries besides: subtitle tracks, title, cover.
    extras: crate::embed::Extras,
    /// Stretches (seconds) to leave out of a saved file.
    cut: Vec<(f64, f64)>,
    /// Raised by each request, so an older one for the same session stops.
    generation: AtomicU64,
    /// HLS segments made last, as players often ask for one twice.
    made: Mutex<VecDeque<(usize, Arc<Vec<u8>>)>>,
}

impl Session {
    pub fn new(ask: Ask, fetch: &Arc<dyn Fetch>) -> Result<Session, String> {
        let (video, audio) = std::thread::scope(|scope| {
            let video = scope.spawn(|| fetch_head(fetch, &ask.video));
            let audio = fetch_head(fetch, &ask.audio);
            (video.join().unwrap_or_else(|_| Err("failed".into())), audio)
        });
        let (video, audio) = (video.map_err(|e| format!("picture: {e}"))?, audio.map_err(|e| format!("sound: {e}"))?);
        if !video.video || audio.video {
            return Err("tracks swapped".into());
        }
        if matches!(ask.kind, Kind::Ts | Kind::Hls) && (!matches!(video.codec, Codec::Avc { .. }) || !matches!(audio.codec, Codec::Aac { .. })) {
            return Err("only H.264 with AAC goes into a transport stream".into());
        }
        if ask.kind == Kind::Mkv {
            mkv_track(&video)?;
            mkv_track(&audio)?;
        }
        let addresses = [Address::new(ask.video.url.clone()), Address::new(ask.audio.url.clone())];
        Ok(Session { video_target: ask.video, audio_target: ask.audio, addresses, video, audio, start: ask.start_ms as f64 / 1000.0, kind: ask.kind, duration: ask.duration_ms as f64 / 1000.0, subtitles: ask.subtitles.filter(|s| !s.cues.is_empty()), matroska: false, extras: crate::embed::Extras::default(), cut: Vec::new(), generation: AtomicU64::new(0), made: Mutex::new(VecDeque::new()) })
    }

    /// Names Matroska so, never WebM, for a file the user asked to be MKV.
    pub fn plain_matroska(mut self) -> Self {
        self.matroska = true;
        self
    }

    /// Carries `extras` in a saved file.
    pub fn with_extras(mut self, extras: crate::embed::Extras) -> Self {
        self.extras = extras;
        self
    }

    /// Leaves `stretches` (seconds) out of a saved file, as far as
    /// keyframes allow; [Session::cuts] says what that comes to.
    pub fn with_cut(mut self, stretches: Vec<(f64, f64)>) -> Self {
        self.cut = stretches;
        self
    }

    /// What a saved file leaves out, in ms from its start.
    pub fn cuts(&self) -> Cuts {
        if self.cut.is_empty() {
            return Cuts::default();
        }
        let first = segment_at(&self.video, self.start);
        let from = self.video.segments[first].start;
        let keyframes: Vec<i64> = self.video.segments[first..].iter().map(|s| ((s.start - from) * 1000.0).round() as i64).collect();
        Cuts::snap(&self.cut.iter().map(|&(a, b)| (a - from, b - from)).collect::<Vec<_>>(), &keyframes)
    }

    /// Every subtitle track a Matroska stream carries.
    fn texts(&self) -> Vec<&Subtitles> {
        self.subtitles.iter().chain(self.extras.texts.iter()).collect()
    }

    /// The file name extension a saved stream takes: `webm` when Matroska
    /// holds only what WebM allows.
    pub fn extension(&self) -> &'static str {
        match self.kind {
            Kind::Mp4 => "mp4",
            Kind::Ts => "ts",
            Kind::Hls => "m3u8",
            Kind::Mkv if !self.matroska && self.texts().is_empty() && self.extras.cover.is_none() && matches!(self.audio.codec, Codec::Opus(_)) && mkv_track(&self.video).is_ok_and(|v| matches!(v.codec, "V_VP9" | "V_AV1")) => "webm",
            Kind::Mkv => "mkv",
        }
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
            Kind::Hls => "application/vnd.apple.mpegurl",
            Kind::Mkv => "video/x-matroska",
        }
    }

    /// The picture's segments from the one holding the start: index, start
    /// and length in seconds.
    fn hls_segments(&self) -> Vec<(usize, f64, f64)> {
        let segments = &self.video.segments;
        let first = segment_at(&self.video, self.start);
        let last = segments.last().map_or(0.0, |s| s.start);
        let typical = if segments.len() > 1 { last / (segments.len() - 1) as f64 } else { 5.0 };
        let end = if self.duration > last { self.duration } else { last + typical };
        (first..segments.len())
            .map(|i| {
                let start = segments[i].start;
                let next = segments.get(i + 1).map_or(end, |s| s.start);
                (i, start, (next - start).max(0.001))
            })
            .collect()
    }

    /// The playlist asked for first: with subtitles, a master playlist
    /// naming the picture's playlist and a WebVTT rendition; else the
    /// picture's playlist itself.
    pub fn master(&self, token: &str) -> String {
        let Some(subtitles) = &self.subtitles else { return self.playlist(&format!("{token}/")) };
        let seconds = self.duration.max(1.0);
        let bandwidth = ((self.video_target.size + self.audio_target.size) as f64 * 8.0 / seconds).round() as u64;
        let language = subtitles.language.replace('"', "");
        let name = if language.is_empty() { "Subtitles".to_string() } else { language.clone() };
        let language = if language.is_empty() { String::new() } else { format!(",LANGUAGE=\"{language}\"") };
        format!(
            "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"{name}\"{language},DEFAULT=YES,AUTOSELECT=YES,FORCED=NO,URI=\"{token}/subtitles.m3u8\"\n#EXT-X-STREAM-INF:BANDWIDTH={},SUBTITLES=\"subs\"\n{token}/video.m3u8\n",
            bandwidth.max(1)
        )
    }

    /// The subtitles' playlist: one WebVTT file for the whole stream.
    pub fn subtitle_playlist(&self) -> String {
        let length: f64 = self.hls_segments().iter().map(|s| s.2).sum();
        format!("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-TARGETDURATION:{}\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:{length:.3},\nsubtitles.vtt\n#EXT-X-ENDLIST\n", length.ceil() as u64)
    }

    /// The subtitles as WebVTT, timed like the segments: a time from the
    /// start of the video is that far past the segments' base timestamp.
    pub fn vtt(&self) -> String {
        let mut out = format!("WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:{TS_BASE},LOCAL:00:00:00.000\n\n");
        let clock = |ms: u64| format!("{:02}:{:02}:{:02}.{:03}", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000);
        let from = (self.starts_at() * 1000.0) as u64;
        for (start, end, text) in self.subtitles.iter().flat_map(|s| s.cues.iter()) {
            let text = text.replace("-->", "->");
            let text = text.lines().filter(|l| !l.trim().is_empty()).collect::<Vec<_>>().join("\n");
            if *end > from && !text.is_empty() {
                out.push_str(&format!("{} --> {}\n{text}\n\n", clock(*start), clock(*end)));
            }
        }
        out
    }

    /// The picture's HLS playlist, its segments named `<prefix><index>.ts`:
    /// `<token>/` when it is the first playlist, nothing when it sits under
    /// the token beside the subtitles.
    pub fn playlist(&self, prefix: &str) -> String {
        let segments = self.hls_segments();
        let longest = segments.iter().map(|s| s.2).fold(1.0f64, f64::max).ceil() as u64;
        let mut out = format!("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-TARGETDURATION:{longest}\n#EXT-X-MEDIA-SEQUENCE:0\n");
        for (index, _, length) in segments {
            out.push_str(&format!("#EXTINF:{length:.3},\n{prefix}{index}.ts\n"));
        }
        out.push_str("#EXT-X-ENDLIST\n");
        out
    }

    /// The picture's fragment `index` and the sound that goes with it, as
    /// a transport stream timed from the start of the video, so segments
    /// follow on from each other.
    pub fn hls_segment(&self, fetch: &Arc<dyn Fetch>, index: usize) -> Result<Arc<Vec<u8>>, String> {
        if let Some((_, made)) = self.made.lock().unwrap().iter().find(|(i, _)| *i == index) {
            return Ok(made.clone());
        }
        let (_, start, length) = *self.hls_segments().iter().find(|s| s.0 == index).ok_or("no such segment")?;
        let end = if index + 1 < self.video.segments.len() { start + length } else { f64::MAX };
        let stop = Arc::new(AtomicBool::new(false));
        let read = |which: usize, track: &Track, target: &Target, i: usize| -> Result<Fragment, String> {
            let segment = track.segments[i];
            if segment.size > FRAGMENT_LIMIT {
                return Err("fragment too large".into());
            }
            let mut reader = Reader::new(fetch.clone(), target, self.addresses[which].clone(), stop.clone(), segment.offset);
            let data = reader.take(segment.size)?;
            match track.webm {
                Some((number, frame)) => webm_fragment(data, number, frame).map_err(String::from),
                None => fragment(data, segment.offset, track.defaults).map_err(String::from),
            }
        };
        let picture = read(0, &self.video, &self.video_target, index)?;
        let (ats, from, until) = (self.audio.timescale as f64, start, end);
        let mut sound = Vec::new();
        let mut i = segment_at(&self.audio, from);
        while let Some(segment) = self.audio.segments.get(i) {
            if segment.start >= until {
                break;
            }
            let f = read(1, &self.audio, &self.audio_target, i)?;
            let kept: Vec<Sample> = f.samples.iter().copied().filter(|s| {
                let at = s.time as f64 / ats;
                at >= from - 1e-6 && at < until - 1e-6
            }).collect();
            sound.push(Fragment { data: f.data, samples: kept });
            i += 1;
        }
        let shift = [ticks90(self.video.shift, self.video.timescale), ticks90(self.audio.shift, self.audio.timescale)];
        let mut out = Vec::with_capacity(picture.data.len() + (1 << 16));
        let mut ts = TsWriter::new();
        ts.tables(&mut out);
        let video_times: Vec<u64> = picture.samples.iter().map(|s| (TS_BASE + ticks90(s.time, self.video.timescale)).saturating_sub(shift[0])).collect();
        let audio: Vec<(&Fragment, Sample, u64)> = sound
            .iter()
            .flat_map(|f| f.samples.iter().map(move |s| (f, *s)))
            .map(|(f, s)| (f, s, (TS_BASE + ticks90(s.time, self.audio.timescale)).saturating_sub(shift[1])))
            .collect();
        let (mut v, mut a) = (0, 0);
        while v < picture.samples.len() || a < audio.len() {
            if v < picture.samples.len() && (a >= audio.len() || video_times[v] <= audio[a].2) {
                let s = picture.samples[v];
                let composition = ticks90(s.offset.max(0) as u64, self.video.timescale);
                ts.video(&mut out, &self.video.codec, &picture.data[s.at..s.at + s.size], s.sync, video_times[v], video_times[v] + composition);
                v += 1;
            } else {
                let (f, s, pts) = audio[a];
                ts.audio(&mut out, &self.audio.codec, &f.data[s.at..s.at + s.size], pts);
                a += 1;
            }
        }
        let made = Arc::new(out);
        let mut cache = self.made.lock().unwrap();
        cache.push_back((index, made.clone()));
        while cache.len() > 3 {
            cache.pop_front();
        }
        Ok(made)
    }

    /// Writes the stream into `into` until it ends, the client goes away or
    /// a newer request for this session starts.
    pub fn stream(&self, fetch: &Arc<dyn Fetch>, into: &mut dyn Write) -> Result<(), String> {
        let stop = Arc::new(AtomicBool::new(false));
        std::thread::scope(|scope| {
            let result = self.write(scope, fetch, &stop, into, false);
            stop.store(true, Ordering::Relaxed);
            result.map(|_| ())
        })
    }

    /// Writes the whole stream into `file`; a Matroska file then gets its
    /// size, length and index filled in, so it seeks like any other.
    pub fn save(&self, fetch: &Arc<dyn Fetch>, file: &mut std::fs::File) -> Result<(), String> {
        use std::io::{Seek, SeekFrom};
        let stop = Arc::new(AtomicBool::new(false));
        let saved = {
            let mut writer = std::io::BufWriter::with_capacity(1 << 20, &mut *file);
            let saved = std::thread::scope(|scope| {
                let result = self.write(scope, fetch, &stop, &mut writer, true);
                stop.store(true, Ordering::Relaxed);
                result
            });
            let saved = saved.map_err(|e| if e.is_empty() { "could not write the file".to_string() } else { e })?;
            writer.flush().map_err(|e| e.to_string())?;
            saved
        };
        let Some(saved) = saved else { return Ok(()) };
        let length = file.seek(SeekFrom::End(0)).map_err(|e| e.to_string())?;
        let mut size = (length - saved.segment as u64).to_be_bytes();
        size[0] = 0x01;
        let mut put = |at: usize, bytes: &[u8]| -> Result<(), String> {
            file.seek(SeekFrom::Start(at as u64)).map_err(|e| e.to_string())?;
            file.write_all(bytes).map_err(|e| e.to_string())
        };
        put(saved.segment - 8, &size)?;
        if let Some(at) = saved.duration_at {
            put(at, &saved.duration.to_be_bytes())?;
        }
        if let Some(at) = saved.cues_at {
            put(at, &saved.cues.to_be_bytes())?;
        }
        file.flush().map_err(|e| e.to_string())
    }

    /// Whether YouTube refused one of the addresses and the app has not
    /// brought a new one yet.
    pub fn expired(&self) -> bool {
        self.addresses.iter().any(|a| a.expired.load(Ordering::SeqCst))
    }

    /// Replaces the address `old` with `new`; whether it was one of these.
    pub fn renew(&self, old: &str, new: &str) -> bool {
        let mut renewed = false;
        for address in &self.addresses {
            let mut url = address.url.lock().unwrap();
            if *url == old {
                *url = new.to_string();
                address.expired.store(false, Ordering::SeqCst);
                renewed = true;
            }
        }
        renewed
    }

    /// Writes the stream; for a Matroska `file`, also its index at the end,
    /// and returns what goes back into its head.
    fn write<'s>(&'s self, scope: &'s std::thread::Scope<'s, '_>, fetch: &Arc<dyn Fetch>, stop: &Arc<AtomicBool>, into: &mut dyn Write, file: bool) -> Result<Option<Saved>, String> {
        let generation = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
        let current = || self.generation.load(Ordering::SeqCst) == generation;
        let first_video = segment_at(&self.video, self.start);
        let reader = |i: usize, target: &Target, track: &Track, first: usize| {
            let offset = track.segments.get(first).map_or(0, |s| s.offset);
            Reader::new(fetch.clone(), target, self.addresses[i].clone(), stop.clone(), offset)
        };
        let video = produce(scope, &self.video, reader(0, &self.video_target, &self.video, first_video), first_video);
        let mut v = next_fragment(&video)?;
        // The picture starts at its first keyframe; the sound at the same time.
        if let Some(f) = v.as_mut() {
            let keyframe = f.samples.iter().position(|s| s.sync).unwrap_or(0);
            f.samples.drain(..keyframe);
        }
        let Some(origin) = v.as_ref().and_then(|f| f.samples.first()).map(|s| s.time) else { return Err("no picture".into()) };
        let seconds = origin as f64 / self.video.timescale as f64;
        let audio_origin = (seconds * self.audio.timescale as f64).round() as u64;
        let first_audio = segment_at(&self.audio, seconds);
        let audio = produce(scope, &self.audio, reader(1, &self.audio_target, &self.audio, first_audio), first_audio);
        let mut a = next_fragment(&audio)?;
        while let Some(f) = a.as_mut() {
            f.samples.retain(|s| s.time >= audio_origin);
            if !f.samples.is_empty() {
                break;
            }
            a = next_fragment(&audio)?;
        }
        let rebase = [origin, audio_origin];
        let cuts = if file { self.cuts() } else { Cuts::default() };
        let mut out = Vec::with_capacity(1 << 20);
        match self.kind {
            Kind::Hls => return Err("an HLS session is read segment by segment".into()),
            Kind::Mkv => {
                let (picture, sound) = (mkv_track(&self.video)?, mkv_track(&self.audio)?);
                let from = seconds;
                let length = if self.duration > from { (self.duration - from) * 1000.0 } else { 0.0 };
                let texts = self.texts();
                let names: Vec<(&str, &str)> = texts.iter().map(|t| (t.language.as_str(), t.name.as_str())).collect();
                let extra = cast_mkv::Extra { texts: &names, title: self.extras.title.as_deref(), cover: self.extras.cover.as_deref() };
                let head = cast_mkv::head(&picture, &sound, extra, length, file, self.matroska);
                into.write_all(&head.bytes).map_err(|_| String::new())?;
                let mut end = 0i64;
                let from_ms = (from * 1000.0).round() as i64;
                let mut all: Vec<(u64, u64, &str, u64)> = texts
                    .iter()
                    .enumerate()
                    .flat_map(|(i, t)| t.cues.iter().map(move |c| (c.0, c.1, c.2.as_str(), cast_mkv::TEXT + i as u64)))
                    .filter(|c| c.1 as i64 > from_ms)
                    .collect();
                all.sort_by_key(|c| (c.0, c.3));
                let mut cues = all.into_iter().peekable();
                let mut clusters = cast_mkv::Clusters::after(&head);
                let timescales = [self.video.timescale, self.audio.timescale];
                let shifts = [self.video.shift as i64, self.audio.shift as i64];
                let ms = |ticks: i64, i: usize| ticks * 1000 / timescales[i] as i64;
                let mut at = [0usize, 0usize];
                loop {
                    if !current() {
                        return Ok(None);
                    }
                    let time = |f: &Option<Fragment>, i: usize, at: usize| f.as_ref().and_then(|f| f.samples.get(at)).map(|s| ms(s.time as i64 - rebase[i] as i64, i));
                    let pick = match (time(&v, 0, at[0]), time(&a, 1, at[1])) {
                        (None, None) => break,
                        (Some(_), None) => 0,
                        (None, Some(_)) => 1,
                        (Some(x), Some(y)) => usize::from(y < x),
                    };
                    let (f, s) = if pick == 0 { (v.as_ref().unwrap(), v.as_ref().unwrap().samples[at[0]]) } else { (a.as_ref().unwrap(), a.as_ref().unwrap().samples[at[1]]) };
                    let decoded = ms(s.time as i64 - rebase[pick] as i64, pick);
                    let left = cuts.before(decoded);
                    let shown = (ms(s.time as i64 - rebase[pick] as i64 + s.offset as i64 - shifts[pick], pick) - left).max(0);
                    while let Some(cue) = cues.next_if(|c| (c.0 as i64 - from_ms) <= decoded) {
                        let start = cuts.map((cue.0 as i64 - from_ms).max(0));
                        let end = cuts.map(cue.1 as i64 - from_ms);
                        if end > start {
                            clusters.text(&mut out, cue.3, start, (end - start) as u64, cue.2);
                        }
                    }
                    if !cuts.inside(decoded) {
                        clusters.frame(&mut out, if pick == 0 { cast_mkv::VIDEO } else { cast_mkv::AUDIO }, shown, pick == 1 || s.sync, &f.data[s.at..s.at + s.size]);
                        end = end.max(shown + ms(s.duration as i64, pick));
                    }
                    at[pick] += 1;
                    if out.len() >= 64 << 10 {
                        into.write_all(&out).map_err(|_| String::new())?;
                        out.clear();
                    }
                    if v.as_ref().is_some_and(|f| at[0] >= f.samples.len()) {
                        v = next_fragment(&video)?;
                        at[0] = 0;
                    }
                    if a.as_ref().is_some_and(|f| at[1] >= f.samples.len()) {
                        a = next_fragment(&audio)?;
                        at[1] = 0;
                    }
                }
                if !file {
                    clusters.flush(&mut out);
                    into.write_all(&out).map_err(|_| String::new())?;
                    return Ok(None);
                }
                let cues = clusters.finish(&mut out);
                into.write_all(&out).map_err(|_| String::new())?;
                return Ok(Some(Saved { segment: head.segment, duration_at: head.duration_at, cues_at: head.cues_at, duration: end as f64, cues }));
            }
            Kind::Mp4 => {
                let texts = self.texts();
                let languages: Vec<&str> = texts.iter().map(|t| t.language.as_str()).collect();
                out.extend_from_slice(&mp4_head(&self.video, &self.audio, &languages, self.extras.title.as_deref(), self.extras.cover.as_deref()));
                let mut sequence = 1u32;
                // Each subtitle track whole, first: a player reads it before
                // the picture and sound it goes with.
                if file {
                    for (i, text) in texts.iter().enumerate() {
                        let fragment = text_fragment(&if cuts.is_empty() { text.cues.clone() } else { cuts.cues(&text.cues) });
                        mp4_fragment(&mut out, sequence, 3 + i as u32, &fragment, &fragment.samples, 0);
                        sequence += 1;
                    }
                }
                let timescales = [self.video.timescale, self.audio.timescale];
                loop {
                    if !current() {
                        return Ok(None);
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
                    let (slot, source) = if pick == 0 { (&mut v, &video) } else { (&mut a, &audio) };
                    if let Some(f) = slot.as_ref() {
                        if cuts.is_empty() {
                            mp4_fragment(&mut out, sequence, pick as u32 + 1, f, &f.samples, rebase[pick]);
                            sequence += 1;
                        } else {
                            // Each run of samples kept, moved back by what was left out before it.
                            let timescale = timescales[pick] as i64;
                            let decoded = |s: &Sample| (s.time as i64 - rebase[pick] as i64) * 1000 / timescale;
                            let mut from = 0;
                            while from < f.samples.len() {
                                if cuts.inside(decoded(&f.samples[from])) {
                                    from += 1;
                                    continue;
                                }
                                let to = (from..f.samples.len()).find(|&i| cuts.inside(decoded(&f.samples[i]))).unwrap_or(f.samples.len());
                                let back = (cuts.before(decoded(&f.samples[from])) * timescale / 1000) as u64;
                                mp4_fragment(&mut out, sequence, pick as u32 + 1, f, &f.samples[from..to], rebase[pick] + back);
                                sequence += 1;
                                from = to;
                            }
                        }
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
                        return Ok(None);
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
                        v = next_fragment(&video)?;
                        at[0] = 0;
                    }
                    if a.as_ref().is_some_and(|f| at[1] >= f.samples.len()) {
                        a = next_fragment(&audio)?;
                        at[1] = 0;
                    }
                }
                into.write_all(&out).map_err(|_| String::new())?;
            }
        }
        Ok(None)
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
                    serve(client, &shared, &fetch);
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
        let session = Session::new(ask, &self.fetch)?;
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
        Ok((format!("/{token}.{}", match kind {
            Kind::Ts => "ts",
            Kind::Mp4 => "mp4",
            Kind::Hls => "m3u8",
            Kind::Mkv => "mkv",
        }), start))
    }

    /// Whether a session's address was refused and waits for a new one.
    pub fn expired(&self) -> bool {
        self.shared.lock().unwrap().sessions.values().any(|s| s.expired())
    }

    /// Gives every session streaming from `old` the address `new`; how
    /// many did.
    pub fn renew(&self, old: &str, new: &str) -> usize {
        self.shared.lock().unwrap().sessions.values().filter(|s| s.renew(old, new)).count()
    }

    pub fn take_log(&self) -> Vec<String> {
        self.shared.lock().unwrap().log.drain(..).collect()
    }
}

fn serve(client: TcpStream, shared: &Mutex<Shared>, fetch: &Arc<dyn Fetch>) {
    let _ = client.set_read_timeout(Some(Duration::from_secs(30)));
    let _ = client.set_write_timeout(Some(Duration::from_secs(60)));
    let peer = client.peer_addr().map(|a| a.ip().to_string()).unwrap_or_default();
    let Ok(mut writer) = client.try_clone() else { return };
    let mut reader = BufReader::new(client);
    let Some((method, path, headers)) = read_request(&mut reader) else {
        log(shared, format!("{peer} connected but sent no request"));
        return;
    };
    let token = path.trim_start_matches('/').split(['.', '?', '/']).next().unwrap_or("").to_string();
    let session = shared.lock().unwrap().sessions.get(&token).cloned();
    let asked = describe_request(&peer, &method, &path, &headers);
    let Some(session) = session.filter(|_| method == "GET" || method == "HEAD") else {
        log(shared, format!("{asked}: answered 404"));
        let _ = writer.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        return;
    };
    if session.kind == Kind::Hls {
        let segment = path.trim_start_matches('/').split_once('/').map(|(_, rest)| rest.split(['.', '?']).next().unwrap_or(""));
        let body = match segment {
            None => Ok((Arc::new(session.master(&token).into_bytes()), "application/vnd.apple.mpegurl")),
            Some("video") => Ok((Arc::new(session.playlist("").into_bytes()), "application/vnd.apple.mpegurl")),
            Some("subtitles") if path.contains(".vtt") => Ok((Arc::new(session.vtt().into_bytes()), "text/vtt; charset=utf-8")),
            Some("subtitles") => Ok((Arc::new(session.subtitle_playlist().into_bytes()), "application/vnd.apple.mpegurl")),
            Some(index) => match index.parse::<usize>() {
                Ok(index) => session.hls_segment(fetch, index).map(|b| (b, "video/mp2t")),
                Err(_) => Err("no such segment".to_string()),
            },
        };
        match body {
            Ok((body, mime)) => {
                let (status, part) = byte_range(headers.get("range"), body.len());
                log(shared, format!("{asked}: answered {status}"));
                let mut head = format!("HTTP/1.1 {status}\r\nContent-Type: {mime}\r\nContent-Length: {}\r\nAccept-Ranges: bytes\r\nConnection: close\r\n", part.len());
                if status == "206 Partial Content" {
                    head.push_str(&format!("Content-Range: bytes {}-{}/{}\r\n", part.start, part.end.max(1) - 1, body.len()));
                }
                head.push_str("\r\n");
                if writer.write_all(head.as_bytes()).is_ok() && method == "GET" {
                    let _ = writer.write_all(&body[part]);
                }
            }
            Err(e) => {
                log(shared, format!("{asked}: answered 502 ({e})"));
                let _ = writer.write_all(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            }
        }
        let _ = writer.flush();
        let _ = writer.shutdown(Shutdown::Both);
        return;
    }
    log(shared, format!("{asked}: answered 200"));
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

/// The status and the bytes of a `len`-byte body to send for a `Range`
/// header: one range, or the whole body.
fn byte_range(range: Option<&String>, len: usize) -> (&'static str, std::ops::Range<usize>) {
    let whole = ("200 OK", 0..len);
    let Some(spec) = range.and_then(|r| r.strip_prefix("bytes=")) else { return whole };
    let Some((a, b)) = spec.split_once('-') else { return whole };
    let (start, end) = match (a.trim().parse::<usize>().ok(), b.trim().parse::<usize>().ok()) {
        (Some(a), Some(b)) => (a, b.saturating_add(1).min(len)),
        (Some(a), None) => (a, len),
        (None, Some(n)) => (len.saturating_sub(n), len),
        (None, None) => return whole,
    };
    if start >= end {
        return whole;
    }
    ("206 Partial Content", start..end)
}

/// One request for the log: who asked what, and how, with no address.
fn describe_request(peer: &str, method: &str, path: &str, headers: &HashMap<String, String>) -> String {
    let kind = path.rsplit_once('.').map_or("", |(_, ext)| ext.split('?').next().unwrap_or(""));
    let mut line = format!("{peer} asked {method} for a .{kind} stream");
    if let Some(range) = headers.get("range") {
        line.push_str(&format!(", range {range}"));
    }
    if let Some(agent) = headers.get("user-agent") {
        line.push_str(&format!(", user agent {}", agent.chars().take(80).collect::<String>()));
    }
    line
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

/// Whether YouTube refused a cast stream's address and the app should
/// bring new ones with [lumtub_cast_renew].
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_cast_expired() -> bool {
    SERVER.get().is_some_and(Server::expired)
}

#[derive(Deserialize)]
struct Renewal {
    old: String,
    new: String,
}

/// Replaces stream addresses: [json] is a list of `{"old", "new"}`. The
/// number of addresses replaced.
///
/// # Safety
/// [json] points at [len] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_cast_renew(json: *const u8, len: usize) -> u32 {
    let (Some(server), Ok(renewals)) = (SERVER.get(), serde_json::from_str::<Vec<Renewal>>(unsafe { crate::taste::text(json, len) })) else { return 0 };
    renewals.iter().map(|r| server.renew(&r.old, &r.new) as u32).sum()
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

    #[test]
    fn cuts_snap_to_keyframes_inside_what_was_asked() {
        let keyframes = [0, 2000, 4000, 6000, 8000, 10_000];
        // 1.5 s to 7 s: from the keyframe at 2 s to the one at 6 s.
        let cuts = Cuts::snap(&[(1.5, 7.0)], &keyframes);
        assert_eq!(cuts.stretches(), &[(2000, 6000)]);
        // Too short to hold two keyframes: nothing left out.
        assert!(Cuts::snap(&[(2.5, 3.9)], &keyframes).is_empty());
        // Overlapping stretches merge.
        assert_eq!(Cuts::snap(&[(0.0, 4.0), (3.0, 8.5)], &keyframes).stretches(), &[(0, 8000)]);
        assert_eq!(cuts.map(1000), 1000);
        assert_eq!(cuts.map(3000), 2000);
        assert_eq!(cuts.map(7000), 3000);
        assert!(cuts.inside(2000) && !cuts.inside(6000));
        assert_eq!(cuts.cues(&[(500, 1500, "a".into()), (2500, 5000, "b".into()), (5500, 9000, "c".into())]), vec![(500, 1500, "a".into()), (2000, 5000, "c".into())]);
    }

    /// Serves local files like googlevideo serves streams: each reply cut
    /// after `cut` bytes when set, and an address holding `expired` refused.
    struct Files {
        data: HashMap<String, Vec<u8>>,
        cut: Option<usize>,
        expired: Option<&'static str>,
    }

    impl Fetch for Files {
        fn get(&self, _: &Target, url: &str) -> Result<(u16, Box<dyn Read + Send>), String> {
            if self.expired.is_some_and(|e| url.contains(e)) {
                return Ok((403, Box::new(std::io::empty())));
            }
            let (address, range) = url.split_once("&range=").ok_or("no range")?;
            let name = address.split('?').next().unwrap();
            let data = self.data.get(name).ok_or("unknown")?;
            let (a, b) = range.split_once('-').ok_or("bad range")?;
            let (a, b): (usize, usize) = (a.parse().unwrap(), b.parse().unwrap());
            let b = b.min(data.len() - 1);
            let end = self.cut.map_or(b + 1, |cut| (a + cut).min(b + 1));
            Ok((206, Box::new(std::io::Cursor::new(data[a..end].to_vec()))))
        }
    }

    fn files(data: HashMap<String, Vec<u8>>) -> Arc<dyn Fetch> {
        Arc::new(Files { data, cut: None, expired: None })
    }

    fn target(name: &str, size: usize) -> Target {
        Target { url: format!("{name}?x"), size: size as u64, user_agent: None, mime: None, proxy: None, chunk: 1 << 20, live: None }
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
        let both = HashMap::from([("v.mp4".to_string(), v.clone()), ("a.mp4".to_string(), a.clone())]);
        let files = files(both.clone());
        for (kind, start, name) in [(Kind::Mp4, 0, "out.mp4"), (Kind::Ts, 0, "out.ts"), (Kind::Mp4, 9_500, "seek.mp4"), (Kind::Ts, 9_500, "seek.ts")] {
            let ask = Ask { video: target("v.mp4", v.len()), audio: target("a.mp4", a.len()), start_ms: start, kind, duration_ms: 0, subtitles: None };
            let session = Session::new(ask, &files).expect("session");
            let mut out = Vec::new();
            session.stream(&files, &mut out).expect("stream");
            std::fs::write(format!("{dir}/{name}"), &out).unwrap();
            assert!(out.len() > 100_000);
        }
        // VP9 from WebM and AV1 from MP4, each with the AAC sound.
        for (picture, start, name) in [("vp9.webm", 0, "vp9.mp4"), ("vp9.webm", 7_000, "vp9-seek.mp4"), ("av1.mp4", 0, "av1-out.mp4")] {
            let Some(p) = sample(&dir, picture) else { continue };
            let files = super::tests::files(HashMap::from([(picture.to_string(), p.clone()), ("a.mp4".to_string(), a.clone())]));
            let ask = Ask { video: target(picture, p.len()), audio: target("a.mp4", a.len()), start_ms: start, kind: Kind::Mp4, duration_ms: 0, subtitles: None };
            let session = Session::new(ask, &files).expect("session");
            let mut out = Vec::new();
            session.stream(&files, &mut out).expect("stream");
            std::fs::write(format!("{dir}/{name}"), &out).unwrap();
            assert!(out.len() > 100_000);
            let ask = Ask { video: target(picture, p.len()), audio: target("a.mp4", a.len()), start_ms: 0, kind: Kind::Ts, duration_ms: 0, subtitles: None };
            assert!(Session::new(ask, &files).is_err());
        }
        // As Matroska with a subtitle track: H.264, VP9 from WebM and AV1.
        let lines = || Some(Subtitles { language: "en".into(), name: String::new(), cues: vec![(500, 2_500, "First line".into()), (8_000, 12_000, "Second\nline".into())] });
        for (picture, start, name) in [("v.mp4", 0, "out.mkv"), ("v.mp4", 9_500, "seek.mkv"), ("vp9.webm", 0, "vp9.mkv"), ("av1.mp4", 0, "av1.mkv")] {
            let Some(p) = sample(&dir, picture) else { continue };
            let files = super::tests::files(HashMap::from([(picture.to_string(), p.clone()), ("a.mp4".to_string(), a.clone())]));
            let ask = Ask { video: target(picture, p.len()), audio: target("a.mp4", a.len()), start_ms: start, kind: Kind::Mkv, duration_ms: 20_000, subtitles: lines() };
            let session = Session::new(ask, &files).expect("session");
            let mut out = Vec::new();
            session.stream(&files, &mut out).expect("stream");
            std::fs::write(format!("{dir}/{name}"), &out).unwrap();
            assert!(out.len() > 100_000 && out.starts_with(&[0x1A, 0x45, 0xDF, 0xA3]));
        }
        // Replies cut short every 300 kB, and an address refused until renewed.
        let reference = std::fs::read(format!("{dir}/out.mp4")).unwrap();
        let cutting: Arc<dyn Fetch> = Arc::new(Files { data: both.clone(), cut: Some(300_000), expired: None });
        let ask = Ask { video: target("v.mp4", v.len()), audio: target("a.mp4", a.len()), start_ms: 0, kind: Kind::Mp4, duration_ms: 0, subtitles: None };
        let session = Session::new(ask, &cutting).expect("session");
        let mut out = Vec::new();
        session.stream(&cutting, &mut out).expect("stream");
        assert_eq!(out, reference);
        let expiring: Arc<dyn Fetch> = Arc::new(Files { data: both.clone(), cut: None, expired: Some("old=1") });
        let ask = Ask { video: target("v.mp4", v.len()), audio: target("a.mp4", a.len()), start_ms: 0, kind: Kind::Mp4, duration_ms: 0, subtitles: None };
        let session = Arc::new(Session::new(ask, &files).expect("session"));
        session.renew("v.mp4?x", "v.mp4?old=1");
        let renewer = {
            let session = session.clone();
            std::thread::spawn(move || {
                while !session.expired() {
                    std::thread::sleep(Duration::from_millis(50));
                }
                assert!(session.renew("v.mp4?old=1", "v.mp4?new=1"));
            })
        };
        let mut out = Vec::new();
        session.stream(&expiring, &mut out).expect("stream");
        renewer.join().unwrap();
        assert!(!session.expired());
        assert_eq!(out, reference);
        // While a session is registered nothing can renew it, so a refused
        // address fails at once.
        let started = std::time::Instant::now();
        let ask = Ask { video: target("v.mp4?old=1", v.len()), audio: target("a.mp4", a.len()), start_ms: 0, kind: Kind::Mp4, duration_ms: 0, subtitles: None };
        let refused = Session::new(ask, &expiring).err().expect("refused");
        assert_eq!(refused, "picture: YouTube answered 403");
        assert!(started.elapsed() < Duration::from_secs(5));
        // The same stream through the server, as a TV reads it.
        let server = Server::start(files.clone()).expect("listen");
        let ask = Ask { video: target("v.mp4", v.len()), audio: target("a.mp4", a.len()), start_ms: 0, kind: Kind::Ts, duration_ms: 0, subtitles: None };
        let (path, start) = server.register(ask).expect("register");
        assert_eq!(start, 0.0);
        let mut client = TcpStream::connect(("127.0.0.1", server.port())).unwrap();
        write!(client, "GET {path} HTTP/1.1\r\nHost: x\r\n\r\n").unwrap();
        let mut answer = Vec::new();
        client.read_to_end(&mut answer).unwrap();
        let body = answer.windows(4).position(|w| w == b"\r\n\r\n").map(|at| &answer[at + 4..]).unwrap();
        assert!(answer.starts_with(b"HTTP/1.1 200 OK\r\nContent-Type: video/mpeg"));
        assert_eq!(body, std::fs::read(format!("{dir}/out.ts")).unwrap());
        // As an HLS playlist of segments, each read as a whole or in part.
        let get = |path: &str, range: &str| {
            let mut client = TcpStream::connect(("127.0.0.1", server.port())).unwrap();
            write!(client, "GET {path} HTTP/1.1\r\nHost: x\r\n{range}\r\n").unwrap();
            let mut answer = Vec::new();
            client.read_to_end(&mut answer).unwrap();
            let at = answer.windows(4).position(|w| w == b"\r\n\r\n").unwrap();
            (String::from_utf8_lossy(&answer[..at]).to_string(), answer[at + 4..].to_vec())
        };
        let ask = Ask { video: target("v.mp4", v.len()), audio: target("a.mp4", a.len()), start_ms: 0, kind: Kind::Hls, duration_ms: 20_000, subtitles: None };
        let (path, _) = server.register(ask).expect("register");
        assert!(path.ends_with(".m3u8"));
        let (head, playlist) = get(&path, "");
        assert!(head.contains("application/vnd.apple.mpegurl"), "{head}");
        let playlist = String::from_utf8(playlist).unwrap();
        std::fs::write(format!("{dir}/hls.m3u8"), &playlist).unwrap();
        let token = path.trim_start_matches('/').trim_end_matches(".m3u8");
        let names: Vec<&str> = playlist.lines().filter(|l| !l.starts_with('#')).collect();
        assert!(names.len() > 3 && playlist.ends_with("#EXT-X-ENDLIST\n"));
        let mut joined = Vec::new();
        for name in &names {
            let (head, body) = get(&format!("/{name}"), "");
            assert!(head.starts_with("HTTP/1.1 200 OK") && head.contains("video/mp2t") && head.contains(&format!("Content-Length: {}", body.len())), "{head}");
            assert!(body.len() % 188 == 0 && body[0] == 0x47);
            std::fs::create_dir_all(format!("{dir}/{token}")).unwrap();
            std::fs::write(format!("{dir}/{name}"), &body).unwrap();
            joined.extend_from_slice(&body);
        }
        let (head, part) = get(&format!("/{}", names[0]), "Range: bytes=0-1\r\n");
        assert!(head.starts_with("HTTP/1.1 206") && head.contains("Content-Range: bytes 0-1/"), "{head}");
        assert_eq!(part.len(), 2);
        std::fs::write(format!("{dir}/hls-joined.ts"), &joined).unwrap();
        // With subtitles, a master playlist names the picture's and theirs.
        let ask = Ask { video: target("v.mp4", v.len()), audio: target("a.mp4", a.len()), start_ms: 0, kind: Kind::Hls, duration_ms: 20_000, subtitles: lines() };
        let (path, _) = server.register(ask).expect("register");
        let token = path.trim_start_matches('/').trim_end_matches(".m3u8").to_string();
        let master = String::from_utf8(get(&path, "").1).unwrap();
        assert!(master.contains("TYPE=SUBTITLES") && master.contains(&format!("URI=\"{token}/subtitles.m3u8\"")) && master.contains(&format!("\n{token}/video.m3u8\n")), "{master}");
        let video = String::from_utf8(get(&format!("/{token}/video.m3u8"), "").1).unwrap();
        assert!(video.contains("\n0.ts\n"), "{video}");
        let (head, segment) = get(&format!("/{token}/0.ts"), "");
        assert!(head.contains("video/mp2t") && segment[0] == 0x47);
        let subtitles = String::from_utf8(get(&format!("/{token}/subtitles.m3u8"), "").1).unwrap();
        assert!(subtitles.contains("\nsubtitles.vtt\n"), "{subtitles}");
        let (head, vtt) = get(&format!("/{token}/subtitles.vtt"), "");
        let vtt = String::from_utf8(vtt).unwrap();
        assert!(head.contains("text/vtt"));
        assert_eq!(vtt, "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:180000,LOCAL:00:00:00.000\n\n00:00:00.500 --> 00:00:02.500\nFirst line\n\n00:00:08.000 --> 00:00:12.000\nSecond\nline\n\n");
        std::fs::create_dir_all(format!("{dir}/subs")).unwrap();
        std::fs::write(format!("{dir}/subs/master.m3u8"), master.replace(&format!("{token}/"), "")).unwrap();
        std::fs::write(format!("{dir}/subs/video.m3u8"), &video).unwrap();
        std::fs::write(format!("{dir}/subs/subtitles.m3u8"), &subtitles).unwrap();
        std::fs::write(format!("{dir}/subs/subtitles.vtt"), &vtt).unwrap();
        for name in video.lines().filter(|l| !l.starts_with('#')) {
            std::fs::write(format!("{dir}/subs/{name}"), get(&format!("/{token}/{name}"), "").1).unwrap();
        }
    }

    #[test]
    fn serves_a_session_over_http() {
        let mut v = Vec::new();
        put_box(&mut v, b"ftyp", |o| o.extend_from_slice(b"isom"));
        let server = Server::start(files(HashMap::from([("v.mp4".to_string(), v.clone())]))).expect("listen");
        let ask = Ask { video: target("v.mp4", v.len()), audio: target("v.mp4", v.len()), start_ms: 0, kind: Kind::Mp4, duration_ms: 0, subtitles: None };
        assert!(server.register(ask).unwrap_err().contains("picture"));
        let mut client = TcpStream::connect(("127.0.0.1", server.port())).unwrap();
        client.write_all(b"GET /0123456789abcdef.mp4 HTTP/1.1\r\nHost: x\r\n\r\n").unwrap();
        let mut answer = String::new();
        client.read_to_string(&mut answer).unwrap();
        assert!(answer.starts_with("HTTP/1.1 404"));
        let log = server.take_log();
        assert!(log.iter().any(|l| l.starts_with("127.0.0.1 asked GET for a .mp4 stream") && l.ends_with("answered 404")), "{log:?}");
    }
}
