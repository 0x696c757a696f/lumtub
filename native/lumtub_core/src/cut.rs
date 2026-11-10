//! Cuts a downloaded sound file into parts of about a given length, for
//! speech recognition services that take only so much at once, without
//! ffmpeg: whole clusters (WebM) or fragments (MP4) are copied into each
//! part after the file's own head, their times moved to start at zero.

use std::ffi::c_char;
use std::fs::File;
use std::io::{BufWriter, Read, Seek, SeekFrom, Write};

use serde::Deserialize;

use crate::cast_webm::{element, CLUSTER};
use crate::taste::{give, text};

const EBML: u32 = 0x1A45_DFA3;
const SEGMENT: u32 = 0x1853_8067;
const INFO: u32 = 0x1549_A966;
const TRACKS: u32 = 0x1654_AE6B;
const TIMECODE_SCALE: u32 = 0x2A_D7B1;
const DURATION: u32 = 0x4489;
const TIMESTAMP: u32 = 0xE7;

/// One part written: its file and where it starts in the whole, in seconds.
#[derive(Debug, PartialEq)]
pub struct Part {
    pub path: String,
    pub start: f64,
}

/// A piece of the file that can start a part: its bytes and its start in
/// the file's own time units.
struct Piece {
    from: u64,
    to: u64,
    time: u64,
}

fn read_at(file: &mut File, at: u64, length: usize) -> Result<Vec<u8>, String> {
    file.seek(SeekFrom::Start(at)).map_err(|e| e.to_string())?;
    let mut bytes = Vec::with_capacity(length);
    file.take(length as u64).read_to_end(&mut bytes).map_err(|e| e.to_string())?;
    Ok(bytes)
}

fn copy(file: &mut File, from: u64, to: u64, out: &mut impl Write) -> Result<(), String> {
    file.seek(SeekFrom::Start(from)).map_err(|e| e.to_string())?;
    let copied = std::io::copy(&mut file.take(to - from), out).map_err(|e| e.to_string())?;
    if copied != to - from {
        return Err("the file ends early".into());
    }
    Ok(())
}

/// Cuts `input` into parts of about `every` seconds named `stem` plus a
/// number and the input's extension.
pub fn cut(input: &str, stem: &str, every: f64) -> Result<Vec<Part>, String> {
    let mut file = File::open(input).map_err(|e| format!("{input}: {e}"))?;
    let total = file.metadata().map_err(|e| e.to_string())?.len();
    let start = read_at(&mut file, 0, 8)?;
    let extension = input.rsplit_once('.').map_or("", |(_, e)| e);
    if start.len() >= 4 && u32::from_be_bytes([start[0], start[1], start[2], start[3]]) == EBML {
        webm(&mut file, total, stem, extension, every)
    } else if start.len() >= 8 && &start[4..8] == b"ftyp" {
        mp4(&mut file, total, stem, extension, every)
    } else {
        Err("neither WebM nor MP4".into())
    }
}

/// The pieces grouped into parts of about `every` time units, the first
/// piece of each part starting one.
fn groups(pieces: &[Piece], every: f64) -> Vec<std::ops::Range<usize>> {
    let mut groups = Vec::new();
    let mut first = 0;
    let mut next = every;
    for (i, piece) in pieces.iter().enumerate().skip(1) {
        if piece.time as f64 >= next {
            groups.push(first..i);
            first = i;
            next = piece.time as f64 + every;
        }
    }
    if first < pieces.len() {
        groups.push(first..pieces.len());
    }
    groups
}

fn webm(file: &mut File, total: u64, stem: &str, extension: &str, every: f64) -> Result<Vec<Part>, String> {
    let at = |file: &mut File, at: u64| -> Result<(crate::cast_webm::Element, Vec<u8>), String> {
        let bytes = read_at(file, at, 12)?;
        let e = element(&bytes, 0).ok_or("damaged WebM")?;
        Ok((e, bytes))
    };
    let (ebml, _) = at(file, 0)?;
    let head_end = ebml.end as u64;
    let (segment, _) = at(file, head_end)?;
    if segment.id != SEGMENT {
        return Err("no segment".into());
    }
    let segment_end = if segment.end == usize::MAX { total } else { (head_end + segment.end as u64).min(total) };
    let (mut info, mut tracks, mut scale) = (None, None, 1_000_000u64);
    let mut pieces = Vec::new();
    let mut position = head_end + segment.data as u64;
    while position < segment_end {
        let (e, _) = at(file, position)?;
        if e.end == usize::MAX {
            return Err("element of unknown size".into());
        }
        let end = position + e.end as u64;
        match e.id {
            INFO => {
                let bytes = read_at(file, position, e.end)?;
                let mut kept = Vec::new();
                let mut inner = e.data;
                while inner < bytes.len() {
                    let Some(c) = element(&bytes, inner).filter(|c| c.end <= bytes.len()) else { break };
                    if c.id == TIMECODE_SCALE {
                        scale = bytes[c.data..c.end].iter().fold(0u64, |v, &x| (v << 8) | x as u64);
                    }
                    if c.id != DURATION {
                        kept.extend_from_slice(&bytes[inner..c.end]);
                    }
                    inner = c.end;
                }
                info = Some(kept);
            }
            TRACKS => tracks = Some(read_at(file, position, e.end)?),
            CLUSTER => {
                let header = read_at(file, position, e.data + 12)?;
                let stamp = element(&header, e.data).filter(|t| t.id == TIMESTAMP && t.end <= header.len()).ok_or("cluster without a timestamp")?;
                let time = header[stamp.data..stamp.end].iter().fold(0u64, |v, &x| (v << 8) | x as u64);
                pieces.push(Piece { from: position, to: end.min(total), time });
            }
            _ => {}
        }
        position = end;
    }
    let (info, tracks) = (info.ok_or("no info")?, tracks.ok_or("no tracks")?);
    if pieces.is_empty() || scale == 0 {
        return Err("no sound".into());
    }
    let ticks = 1e9 / scale as f64;
    let mut parts = Vec::new();
    for (n, group) in groups(&pieces, every * ticks).into_iter().enumerate() {
        let base = pieces[group.start].time;
        let path = format!("{stem}{n:03}.{extension}");
        let mut out = BufWriter::new(File::create(&path).map_err(|e| e.to_string())?);
        let write = |out: &mut BufWriter<File>, bytes: &[u8]| out.write_all(bytes).map_err(|e| e.to_string());
        copy(file, 0, head_end, &mut out)?;
        write(&mut out, &[0x18, 0x53, 0x80, 0x67, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])?;
        write(&mut out, &[0x15, 0x49, 0xA9, 0x66])?;
        write(&mut out, &size8(info.len() as u64))?;
        write(&mut out, &info)?;
        write(&mut out, &tracks)?;
        for piece in &pieces[group] {
            let (cluster, _) = at(file, piece.from)?;
            let header = read_at(file, piece.from, cluster.data + 12)?;
            let stamp = element(&header, cluster.data).ok_or("cluster without a timestamp")?;
            let mut moved = header[..stamp.end].to_vec();
            let width = stamp.end - stamp.data;
            let value = piece.time - base;
            if width < 8 && value >> (8 * width) != 0 {
                return Err("timestamp too wide".into());
            }
            for i in 0..width {
                moved[stamp.data + i] = (value >> (8 * (width - 1 - i))) as u8;
            }
            write(&mut out, &moved)?;
            copy(file, piece.from + stamp.end as u64, piece.to, &mut out)?;
        }
        out.flush().map_err(|e| e.to_string())?;
        parts.push(Part { path, start: base as f64 / ticks });
    }
    Ok(parts)
}

/// An EBML size in eight bytes.
fn size8(size: u64) -> [u8; 8] {
    let mut out = size.to_be_bytes();
    out[0] = 0x01;
    out
}

/// A box header at `at`: its kind, where its body starts and where it ends.
fn mp4_box(file: &mut File, at: u64, total: u64) -> Result<([u8; 4], u64, u64), String> {
    let h = read_at(file, at, 16)?;
    if h.len() < 8 {
        return Err("damaged MP4".into());
    }
    let size = u32::from_be_bytes([h[0], h[1], h[2], h[3]]) as u64;
    let kind = [h[4], h[5], h[6], h[7]];
    let (body, end) = match size {
        0 => (at + 8, total),
        1 if h.len() >= 16 => (at + 16, at + u64::from_be_bytes(h[8..16].try_into().unwrap())),
        n if n >= 8 => (at + 8, at + n),
        _ => return Err("damaged MP4".into()),
    };
    if end > total {
        return Err("the file ends early".into());
    }
    Ok((kind, body, end))
}

/// The `tfdt` of each track in `moof`: where its decode time is and how
/// wide.
fn decode_times(moof: &[u8]) -> Vec<(usize, usize)> {
    let mut found = Vec::new();
    let boxes = |from: usize, to: usize| {
        let mut list = Vec::new();
        let mut at = from;
        while at + 8 <= to {
            let size = u32::from_be_bytes(moof[at..at + 4].try_into().unwrap()) as usize;
            if size < 8 || at + size > to {
                break;
            }
            list.push((&moof[at + 4..at + 8], at + 8, at + size));
            at += size;
        }
        list
    };
    for (kind, body, end) in boxes(8, moof.len()) {
        if kind != b"traf" {
            continue;
        }
        for (kind, body, end) in boxes(body, end) {
            if kind == b"tfdt" && body + 4 <= end {
                let width = if moof[body] == 1 { 8 } else { 4 };
                if body + 4 + width <= end {
                    found.push((body + 4, width));
                }
            }
        }
    }
    found
}

fn be(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0u64, |v, &x| (v << 8) | x as u64)
}

fn mp4(file: &mut File, total: u64, stem: &str, extension: &str, every: f64) -> Result<Vec<Part>, String> {
    let (mut head, mut timescale) = (Vec::new(), 0u32);
    let mut pieces = Vec::new();
    let mut at = 0;
    let mut pending: Option<(u64, u64)> = None;
    while at < total {
        let (kind, _, end) = mp4_box(file, at, total)?;
        match &kind {
            b"ftyp" => head.push((at, end)),
            b"moov" => {
                head.push((at, end));
                let moov = read_at(file, at, (end - at) as usize)?;
                let mdhd = moov.windows(4).position(|w| w == b"mdhd").ok_or("no mdhd")?;
                let version = moov[mdhd + 4];
                let field = mdhd + 4 + if version == 1 { 20 } else { 12 };
                timescale = u32::from_be_bytes(moov.get(field..field + 4).ok_or("damaged mdhd")?.try_into().unwrap());
            }
            b"moof" => {
                let moof = read_at(file, at, (end - at) as usize)?;
                let time = decode_times(&moof).first().map(|&(p, w)| be(&moof[p..p + w])).ok_or("fragment without a decode time")?;
                pending = Some((at, time));
            }
            b"mdat" => {
                if let Some((from, time)) = pending.take() {
                    pieces.push(Piece { from, to: end, time });
                }
            }
            _ => {}
        }
        at = end;
    }
    if timescale == 0 || head.len() < 2 {
        return Err("no head".into());
    }
    if pieces.is_empty() {
        return Err("not fragmented".into());
    }
    let mut parts = Vec::new();
    for (n, group) in groups(&pieces, every * timescale as f64).into_iter().enumerate() {
        let base = pieces[group.start].time;
        let path = format!("{stem}{n:03}.{extension}");
        let mut out = BufWriter::new(File::create(&path).map_err(|e| e.to_string())?);
        for &(from, to) in &head {
            copy(file, from, to, &mut out)?;
        }
        for piece in &pieces[group] {
            let (_, _, moof_end) = mp4_box(file, piece.from, total)?;
            let mut moof = read_at(file, piece.from, (moof_end - piece.from) as usize)?;
            for (p, w) in decode_times(&moof) {
                let value = be(&moof[p..p + w]).saturating_sub(base);
                for i in 0..w {
                    moof[p + i] = (value >> (8 * (w - 1 - i))) as u8;
                }
            }
            out.write_all(&moof).map_err(|e| e.to_string())?;
            copy(file, moof_end, piece.to, &mut out)?;
        }
        out.flush().map_err(|e| e.to_string())?;
        parts.push(Part { path, start: base as f64 / timescale as f64 });
    }
    Ok(parts)
}

/// Cuts JSON `{input, stem, every}` (`every` in seconds); answers
/// `{"parts": [{"path", "start"}]}` or `{"error"}`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_cut_audio(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Request {
        input: String,
        stem: String,
        every: f64,
    }
    let answer = serde_json::from_str::<Request>(unsafe { text(json, length) }).map_err(|e| e.to_string()).and_then(|r| cut(&r.input, &r.stem, r.every));
    give(match answer {
        Ok(parts) => serde_json::json!({ "parts": parts.iter().map(|p| serde_json::json!({ "path": p.path, "start": p.start })).collect::<Vec<_>>() }).to_string(),
        Err(error) => serde_json::json!({ "error": error }).to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn groups_pieces_by_time() {
        let pieces: Vec<Piece> = [0u64, 4, 8, 12, 16, 20, 24].iter().map(|&time| Piece { from: 0, to: 0, time }).collect();
        assert_eq!(groups(&pieces, 10.0), vec![0..3, 3..6, 6..7]);
        assert_eq!(groups(&pieces, 100.0), vec![0..7]);
    }

    #[test]
    fn writes_eight_byte_sizes() {
        assert_eq!(size8(0x1234), [0x01, 0, 0, 0, 0, 0, 0x12, 0x34]);
    }

    fn ebml(id: &[u8], body: &[u8]) -> Vec<u8> {
        let mut out = id.to_vec();
        out.extend_from_slice(&size8(body.len() as u64));
        out.extend_from_slice(body);
        out
    }

    /// A WebM of one Opus-like track: a cluster every 2 s, each with one
    /// block whose byte is the cluster's number.
    fn webm_file(path: &str) {
        let mut segment = ebml(&[0x15, 0x49, 0xA9, 0x66], &[ebml(&[0x2A, 0xD7, 0xB1], &[0x0F, 0x42, 0x40]), ebml(&[0x44, 0x89], &20000f64.to_be_bytes())].concat());
        segment.extend(ebml(&[0x16, 0x54, 0xAE, 0x6B], &ebml(&[0xAE], &[ebml(&[0xD7], &[1]), ebml(&[0x83], &[2]), ebml(&[0x86], b"A_OPUS")].concat())));
        for n in 0..10u8 {
            let time = (n as u16 * 2000).to_be_bytes();
            segment.extend(ebml(&[0x1F, 0x43, 0xB6, 0x75], &[ebml(&[0xE7], &time), ebml(&[0xA3], &[0x81, 0, 0, 0x80, n])].concat()));
        }
        let mut file = ebml(&[0x1A, 0x45, 0xDF, 0xA3], &ebml(&[0x42, 0x82], b"webm"));
        file.extend(ebml(&[0x18, 0x53, 0x80, 0x67], &segment));
        std::fs::write(path, file).unwrap();
    }

    fn mp4_box(kind: &[u8; 4], body: &[u8]) -> Vec<u8> {
        let mut out = ((body.len() + 8) as u32).to_be_bytes().to_vec();
        out.extend_from_slice(kind);
        out.extend_from_slice(body);
        out
    }

    /// A fragmented MP4 at 1000 ticks a second: a fragment every 2 s whose
    /// one sample is the fragment's number.
    fn mp4_file(path: &str) {
        let mut mdhd = vec![0u8; 12];
        mdhd.extend_from_slice(&1000u32.to_be_bytes());
        mdhd.extend_from_slice(&[0; 8]);
        let mut file = mp4_box(b"ftyp", b"iso6\0\0\0\0");
        file.extend(mp4_box(b"moov", &mp4_box(b"trak", &mp4_box(b"mdia", &mp4_box(b"mdhd", &mdhd)))));
        file.extend(mp4_box(b"sidx", &[0; 12]));
        for n in 0..10u8 {
            let mut tfdt = vec![1, 0, 0, 0];
            tfdt.extend_from_slice(&(n as u64 * 2000).to_be_bytes());
            file.extend(mp4_box(b"moof", &[mp4_box(b"mfhd", &[0; 8]), mp4_box(b"traf", &mp4_box(b"tfdt", &tfdt))].concat()));
            file.extend(mp4_box(b"mdat", &[n]));
        }
        std::fs::write(path, file).unwrap();
    }

    #[test]
    fn cuts_webm_and_mp4_at_whole_pieces_from_zero() {
        let dir = std::env::temp_dir().join(format!("lumtub-cut-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let dir = dir.to_str().unwrap().to_string();
        webm_file(&format!("{dir}/a.webm"));
        mp4_file(&format!("{dir}/a.m4a"));
        for name in ["a.webm", "a.m4a"] {
            let parts = cut(&format!("{dir}/{name}"), &format!("{dir}/{name}-"), 5.0).expect(name);
            assert_eq!(parts.iter().map(|p| p.start).collect::<Vec<_>>(), [0.0, 6.0, 12.0, 18.0], "{name}");
            assert!(parts[1].path.ends_with(&format!("{name}-001.{}", name.rsplit('.').next().unwrap())));
            for (i, part) in parts.iter().enumerate() {
                let bytes = std::fs::read(&part.path).unwrap();
                if name.ends_with("webm") {
                    // Info lost its Duration; the first cluster starts at 0.
                    assert!(!bytes.windows(2).any(|w| w == [0x44, 0x89]));
                    let cluster = bytes.windows(4).position(|w| w == [0x1F, 0x43, 0xB6, 0x75]).unwrap();
                    let stamp = element(&bytes, cluster + 12).unwrap();
                    assert_eq!(&bytes[stamp.data..stamp.end], &[0, 0]);
                } else {
                    assert!(!bytes.windows(4).any(|w| w == b"sidx"));
                    let tfdt = bytes.windows(4).position(|w| w == b"tfdt").unwrap();
                    assert_eq!(&bytes[tfdt + 8..tfdt + 16], &0u64.to_be_bytes());
                }
                // Each part's last block or sample is the one before the next part's first.
                let last = *bytes.last().unwrap();
                assert_eq!(last as usize, [2, 5, 8, 9][i]);
            }
        }
        let _ = std::fs::remove_dir_all(&dir);
        assert!(cut("/nonexistent/a.webm", "x", 5.0).is_err());
    }

    /// Cuts the sample sound files (LUMTUB_CAST_SAMPLES: o.webm, a.mp4).
    #[test]
    fn cuts_files_on_disk() {
        let Ok(dir) = std::env::var("LUMTUB_CAST_SAMPLES") else { return };
        for name in ["o.webm", "a.mp4"] {
            let input = format!("{dir}/{name}");
            if !std::path::Path::new(&input).exists() {
                continue;
            }
            let stem = format!("{dir}/cut-{}-", name.replace('.', "_"));
            let parts = cut(&input, &stem, 5.0).expect("cut");
            assert!(parts.len() >= 3, "{name}: {parts:?}");
            assert_eq!(parts[0].start, 0.0);
            assert!(parts.windows(2).all(|w| w[1].start > w[0].start));
        }
    }
}
