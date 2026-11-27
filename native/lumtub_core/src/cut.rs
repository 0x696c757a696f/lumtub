//! Cuts a downloaded sound file into parts of about a given length, for
//! speech recognition services that take only so much at once, without
//! ffmpeg: whole clusters (WebM) or fragments (MP4) are copied into each
//! part after the file's own head, their times moved to start at zero.

use std::ffi::c_char;
use std::fs::File;
use std::io::{BufWriter, Read, Seek, SeekFrom, Write};

use serde::Deserialize;

use crate::cast_webm::{CLUSTER, element};
use crate::taste::{give, text};

const EBML: u32 = 0x1a45_dfa3;
const SEGMENT: u32 = 0x1853_8067;
const INFO: u32 = 0x1549_a966;
const TRACKS: u32 = 0x1654_ae6b;
const TIMECODE_SCALE: u32 = 0x2a_d7b1;
const DURATION: u32 = 0x4489;
const TIMESTAMP: u32 = 0xe7;

/// The most read whole of a WebM's EBML head, Info or Tracks.
const MAX_WEBM_HEAD: u64 = 1 << 20;
/// The most read whole of an MP4's `moov` and of one `moof`.
const MAX_MOOV: u64 = 64 << 20;
const MAX_MOOF: u64 = 16 << 20;

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

fn read_at(file: &mut impl ReadSeek, at: u64, length: usize) -> Result<Vec<u8>, String> {
    file.seek(SeekFrom::Start(at)).map_err(|e| e.to_string())?;
    let mut bytes = Vec::with_capacity(length.min(1 << 16));
    file.take(length as u64)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    Ok(bytes)
}

fn copy(file: &mut impl ReadSeek, from: u64, to: u64, out: &mut impl Write) -> Result<(), String> {
    if to < from {
        return Err("damaged file".into());
    }
    file.seek(SeekFrom::Start(from))
        .map_err(|e| e.to_string())?;
    let copied = std::io::copy(&mut file.take(to - from), out).map_err(|e| e.to_string())?;
    if copied != to - from {
        return Err("the file ends early".into());
    }
    Ok(())
}

/// What the cutter reads from: a file, or bytes in memory.
pub trait ReadSeek: Read + Seek {}
impl<T: Read + Seek> ReadSeek for T {}

/// Cuts `input` into parts of about `every` seconds named `stem` plus a
/// number and the input's extension.
pub fn cut(input: &str, stem: &str, every: f64) -> Result<Vec<Part>, String> {
    let mut file = File::open(input).map_err(|e| format!("{input}: {e}"))?;
    let total = file.metadata().map_err(|e| e.to_string())?.len();
    let extension = input.rsplit_once('.').map_or("", |(_, e)| e);
    let mut paths = Vec::new();
    let starts = cut_from(&mut file, total, every, |n| {
        let path = format!("{stem}{n:03}.{extension}");
        let out = File::create(&path).map_err(|e| e.to_string())?;
        paths.push(path);
        Ok(BufWriter::new(out))
    })?;
    Ok(paths
        .into_iter()
        .zip(starts)
        .map(|(path, start)| Part { path, start })
        .collect())
}

/// Cuts the `total` bytes of `file` into parts of about `every` seconds,
/// each written to what `create` gives for its number; answers where each
/// part starts, in seconds.
pub fn cut_from<W: Write>(
    file: &mut impl ReadSeek,
    total: u64,
    every: f64,
    mut create: impl FnMut(usize) -> Result<W, String>,
) -> Result<Vec<f64>, String> {
    let start = read_at(file, 0, 8)?;
    if start.len() >= 4 && u32::from_be_bytes([start[0], start[1], start[2], start[3]]) == EBML {
        webm(file, total, every, &mut create)
    } else if start.len() >= 8 && &start[4..8] == b"ftyp" {
        mp4(file, total, every, &mut create)
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

fn webm<R: ReadSeek, W: Write>(
    file: &mut R,
    total: u64,
    every: f64,
    create: &mut impl FnMut(usize) -> Result<W, String>,
) -> Result<Vec<f64>, String> {
    let at = |file: &mut R, at: u64| -> Result<(crate::cast_webm::Element, Vec<u8>), String> {
        let bytes = read_at(file, at, 12)?;
        let e = element(&bytes, 0).ok_or("damaged WebM")?;
        Ok((e, bytes))
    };
    let (ebml, _) = at(file, 0)?;
    let head_end = ebml.end as u64;
    if head_end > total.min(MAX_WEBM_HEAD) {
        return Err("damaged WebM".into());
    }
    let (segment, _) = at(file, head_end)?;
    if segment.id != SEGMENT {
        return Err("no segment".into());
    }
    let segment_end = if segment.end == usize::MAX {
        total
    } else {
        (head_end + segment.end as u64).min(total)
    };
    let (mut info, mut tracks, mut scale) = (None, None, 1_000_000u64);
    let mut pieces = Vec::new();
    let mut position = head_end + segment.data as u64;
    while position < segment_end {
        let (e, _) = at(file, position)?;
        if e.end == usize::MAX {
            return Err("element of unknown size".into());
        }
        let end = position + e.end as u64;
        if matches!(e.id, INFO | TRACKS) && (end > total || e.end as u64 > MAX_WEBM_HEAD) {
            return Err("damaged WebM".into());
        }
        match e.id {
            INFO => {
                let bytes = read_at(file, position, e.end)?;
                let mut kept = Vec::new();
                let mut inner = e.data;
                while inner < bytes.len() {
                    let Some(c) = element(&bytes, inner).filter(|c| c.end <= bytes.len()) else {
                        break;
                    };
                    if c.id == TIMECODE_SCALE {
                        scale = bytes[c.data..c.end]
                            .iter()
                            .fold(0u64, |v, &x| (v << 8) | x as u64);
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
                let stamp = element(&header, e.data)
                    .filter(|t| t.id == TIMESTAMP && t.end <= header.len())
                    .ok_or("cluster without a timestamp")?;
                if stamp.end - stamp.data > 8 || position + stamp.end as u64 > end.min(total) {
                    return Err("damaged WebM".into());
                }
                let time = header[stamp.data..stamp.end]
                    .iter()
                    .fold(0u64, |v, &x| (v << 8) | x as u64);
                pieces.push(Piece {
                    from: position,
                    to: end.min(total),
                    time,
                });
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
        let mut out = create(n)?;
        let write = |out: &mut W, bytes: &[u8]| out.write_all(bytes).map_err(|e| e.to_string());
        copy(file, 0, head_end, &mut out)?;
        write(
            &mut out,
            &[
                0x18, 0x53, 0x80, 0x67, 0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
            ],
        )?;
        write(&mut out, &[0x15, 0x49, 0xa9, 0x66])?;
        write(&mut out, &size8(info.len() as u64))?;
        write(&mut out, &info)?;
        write(&mut out, &tracks)?;
        for piece in &pieces[group] {
            let (cluster, _) = at(file, piece.from)?;
            let header = read_at(file, piece.from, cluster.data + 12)?;
            let stamp = element(&header, cluster.data)
                .filter(|t| t.end <= header.len() && t.end - t.data <= 8)
                .ok_or("cluster without a timestamp")?;
            let mut moved = header[..stamp.end].to_vec();
            let width = stamp.end - stamp.data;
            let value = piece.time.saturating_sub(base);
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
        parts.push(base as f64 / ticks);
    }
    Ok(parts)
}

/// An EBML size in eight bytes.
fn size8(size: u64) -> [u8; 8] {
    let mut out = size.to_be_bytes();
    out[0] = 0x01;
    out
}

/// A box header at `at`: its kind, where its body starts and where it ends,
/// always past `at`.
fn mp4_box(file: &mut impl ReadSeek, at: u64, total: u64) -> Result<([u8; 4], u64, u64), String> {
    let h = read_at(file, at, 16)?;
    if h.len() < 8 {
        return Err("damaged MP4".into());
    }
    let size = u32::from_be_bytes([h[0], h[1], h[2], h[3]]) as u64;
    let kind = [h[4], h[5], h[6], h[7]];
    let (header, size) = match size {
        0 => (8, total.saturating_sub(at)),
        1 if h.len() >= 16 => (16, u64::from_be_bytes(h[8..16].try_into().unwrap())),
        n => (8, n),
    };
    if size < header {
        return Err("damaged MP4".into());
    }
    let end = at.checked_add(size).ok_or("damaged MP4")?;
    if end > total {
        return Err("the file ends early".into());
    }
    Ok((kind, at + header, end))
}

/// A `moov` or `moof` read whole, unless larger than `most`.
fn read_box(file: &mut impl ReadSeek, at: u64, end: u64, most: u64) -> Result<Vec<u8>, String> {
    if end - at > most {
        return Err("damaged MP4".into());
    }
    read_at(file, at, (end - at) as usize)
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
            if size < 8 || size > to - at {
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

fn mp4<W: Write>(
    file: &mut impl ReadSeek,
    total: u64,
    every: f64,
    create: &mut impl FnMut(usize) -> Result<W, String>,
) -> Result<Vec<f64>, String> {
    let (mut head, mut timescale) = (Vec::new(), 0u32);
    let mut pieces = Vec::new();
    let mut at = 0;
    let mut pending: Option<(u64, u64)> = None;
    while at < total {
        let (kind, _, end) = mp4_box(file, at, total)?;
        match &kind {
            b"ftyp" if head.len() < 2 => head.push((at, end)),
            b"moov" if head.len() < 2 => {
                head.push((at, end));
                let moov = read_box(file, at, end, MAX_MOOV)?;
                let mdhd = moov
                    .windows(4)
                    .position(|w| w == b"mdhd")
                    .ok_or("no mdhd")?;
                let version = *moov.get(mdhd + 4).ok_or("damaged mdhd")?;
                let field = mdhd + 4 + if version == 1 { 20 } else { 12 };
                timescale = u32::from_be_bytes(
                    moov.get(field..field + 4)
                        .ok_or("damaged mdhd")?
                        .try_into()
                        .unwrap(),
                );
            }
            b"moof" => {
                let moof = read_box(file, at, end, MAX_MOOF)?;
                let time = decode_times(&moof)
                    .first()
                    .map(|&(p, w)| be(&moof[p..p + w]))
                    .ok_or("fragment without a decode time")?;
                pending = Some((at, time));
            }
            b"mdat" => {
                if let Some((from, time)) = pending.take() {
                    pieces.push(Piece {
                        from,
                        to: end,
                        time,
                    });
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
    for (n, group) in groups(&pieces, every * timescale as f64)
        .into_iter()
        .enumerate()
    {
        let base = pieces[group.start].time;
        let mut out = create(n)?;
        for &(from, to) in &head {
            copy(file, from, to, &mut out)?;
        }
        for piece in &pieces[group] {
            let (_, _, moof_end) = mp4_box(file, piece.from, total)?;
            let mut moof = read_box(file, piece.from, moof_end, MAX_MOOF)?;
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
        parts.push(base as f64 / timescale as f64);
    }
    Ok(parts)
}

/// Cuts JSON `{input, stem, every}` (`every` in seconds); answers
/// `{"parts": [{"path", "start"}]}` or `{"error"}`.
///
/// # Safety
/// [json] points at [length] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_cut_audio(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Request {
        input: String,
        stem: String,
        every: f64,
    }
    let answer = serde_json::from_str::<Request>(unsafe { text(json, length) })
        .map_err(|e| e.to_string())
        .and_then(|r| cut(&r.input, &r.stem, r.every));
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
        let pieces: Vec<Piece> = [0u64, 4, 8, 12, 16, 20, 24]
            .iter()
            .map(|&time| Piece {
                from: 0,
                to: 0,
                time,
            })
            .collect();
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
        let mut segment = ebml(
            &[0x15, 0x49, 0xa9, 0x66],
            &[
                ebml(&[0x2a, 0xd7, 0xb1], &[0x0f, 0x42, 0x40]),
                ebml(&[0x44, 0x89], &20000f64.to_be_bytes()),
            ]
            .concat(),
        );
        segment.extend(ebml(
            &[0x16, 0x54, 0xae, 0x6b],
            &ebml(
                &[0xae],
                &[
                    ebml(&[0xd7], &[1]),
                    ebml(&[0x83], &[2]),
                    ebml(&[0x86], b"A_OPUS"),
                ]
                .concat(),
            ),
        ));
        for n in 0..10u8 {
            let time = (n as u16 * 2000).to_be_bytes();
            segment.extend(ebml(
                &[0x1f, 0x43, 0xb6, 0x75],
                &[ebml(&[0xe7], &time), ebml(&[0xa3], &[0x81, 0, 0, 0x80, n])].concat(),
            ));
        }
        let mut file = ebml(&[0x1a, 0x45, 0xdf, 0xa3], &ebml(&[0x42, 0x82], b"webm"));
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
        file.extend(mp4_box(
            b"moov",
            &mp4_box(b"trak", &mp4_box(b"mdia", &mp4_box(b"mdhd", &mdhd))),
        ));
        file.extend(mp4_box(b"sidx", &[0; 12]));
        for n in 0..10u8 {
            let mut tfdt = vec![1, 0, 0, 0];
            tfdt.extend_from_slice(&(n as u64 * 2000).to_be_bytes());
            file.extend(mp4_box(
                b"moof",
                &[
                    mp4_box(b"mfhd", &[0; 8]),
                    mp4_box(b"traf", &mp4_box(b"tfdt", &tfdt)),
                ]
                .concat(),
            ));
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
            assert_eq!(
                parts.iter().map(|p| p.start).collect::<Vec<_>>(),
                [0.0, 6.0, 12.0, 18.0],
                "{name}"
            );
            assert!(
                parts[1]
                    .path
                    .ends_with(&format!("{name}-001.{}", name.rsplit('.').next().unwrap()))
            );
            for (i, part) in parts.iter().enumerate() {
                let bytes = std::fs::read(&part.path).unwrap();
                if name.ends_with("webm") {
                    // Info lost its Duration; the first cluster starts at 0.
                    assert!(!bytes.windows(2).any(|w| w == [0x44, 0x89]));
                    let cluster = bytes
                        .windows(4)
                        .position(|w| w == [0x1f, 0x43, 0xb6, 0x75])
                        .unwrap();
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

    fn cut_bytes(bytes: &[u8]) -> Result<Vec<f64>, String> {
        let mut input = std::io::Cursor::new(bytes);
        cut_from(&mut input, bytes.len() as u64, 5.0, |_| Ok(std::io::sink()))
    }

    #[test]
    fn refuses_boxes_and_elements_that_do_not_fit() {
        let mut file = mp4_box(b"ftyp", b"iso6\0\0\0\0");
        for largesize in [0u64, 1, 15, u64::MAX - 4, u64::MAX] {
            let mut bad = file.clone();
            bad.extend_from_slice(&1u32.to_be_bytes());
            bad.extend_from_slice(b"moof");
            bad.extend_from_slice(&largesize.to_be_bytes());
            bad.extend_from_slice(&[0; 32]);
            assert!(cut_bytes(&bad).is_err(), "{largesize}");
        }
        file.extend(mp4_box(b"moov", b"mdhd"));
        assert_eq!(cut_bytes(&file), Err("damaged mdhd".into()));
        // Info claiming far more than the file holds.
        let mut webm = ebml(&[0x1a, 0x45, 0xdf, 0xa3], &[]);
        webm.extend_from_slice(&[0x18, 0x53, 0x80, 0x67, 0x01, 0xff, 0xff, 0xff, 0xff]);
        webm.extend_from_slice(&[0xff, 0xff, 0xff]);
        webm.extend_from_slice(&[0x15, 0x49, 0xa9, 0x66, 0x01, 0x00, 0xff, 0xff]);
        webm.extend_from_slice(&[0xff, 0xff, 0xff, 0xfe]);
        assert_eq!(cut_bytes(&webm), Err("damaged WebM".into()));
    }

    /// Cuts the sample sound files (LUMTUB_CAST_SAMPLES: o.webm, a.mp4).
    #[test]
    fn cuts_files_on_disk() {
        let Ok(dir) = std::env::var("LUMTUB_CAST_SAMPLES") else {
            return;
        };
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
