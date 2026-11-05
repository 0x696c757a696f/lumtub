//! YouTube's VP9 pictures come as WebM; the cast server repackages them
//! into MP4 fragments as they are read. This reads a WebM head (its track
//! and the `Cues` index of its clusters) and one cluster's frames.

/// What the head of a WebM file says, in the cast server's terms.
#[derive(Debug, Clone, PartialEq)]
pub struct Head {
    pub number: u64,
    /// Ticks per second: one tick is the file's `TimecodeScale`.
    pub timescale: u32,
    pub width: u16,
    pub height: u16,
    /// The `vpcC` box describing the VP9 stream.
    pub vpcc: Vec<u8>,
    /// Frame duration in ticks, when the file says.
    pub frame: u32,
    /// Each cluster: its offset in the file and its start in seconds.
    pub clusters: Vec<(u64, f64)>,
}

#[derive(Debug, PartialEq)]
pub enum Read {
    Head(Box<Head>),
    More(u64),
    Unusable(&'static str),
}

/// A frame of one cluster: where its bytes are, its time in ticks and
/// whether it is a keyframe.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Frame {
    pub at: usize,
    pub size: usize,
    pub time: u64,
    pub key: bool,
}

pub(crate) const EBML: u32 = 0x1A45_DFA3;
pub(crate) const SEGMENT: u32 = 0x1853_8067;
const INFO: u32 = 0x1549_A966;
const TIMECODE_SCALE: u32 = 0x2A_D7B1;
const TRACKS: u32 = 0x1654_AE6B;
const TRACK_ENTRY: u32 = 0xAE;
const TRACK_NUMBER: u32 = 0xD7;
const TRACK_TYPE: u32 = 0x83;
const CODEC_ID: u32 = 0x86;
const CODEC_PRIVATE: u32 = 0x63A2;
const DEFAULT_DURATION: u32 = 0x23_E383;
const VIDEO: u32 = 0xE0;
const PIXEL_WIDTH: u32 = 0xB0;
const PIXEL_HEIGHT: u32 = 0xBA;
const COLOUR: u32 = 0x55B0;
const MATRIX: u32 = 0x55B1;
const BITS: u32 = 0x55B2;
const RANGE: u32 = 0x55B9;
const TRANSFER: u32 = 0x55BA;
const PRIMARIES: u32 = 0x55BB;
const CUES: u32 = 0x1C53_BB6B;
const CUE_POINT: u32 = 0xBB;
const CUE_TIME: u32 = 0xB3;
const CUE_POSITIONS: u32 = 0xB7;
const CUE_TRACK: u32 = 0xF7;
const CUE_CLUSTER: u32 = 0xF1;
pub(crate) const CLUSTER: u32 = 0x1F43_B675;
const TIMECODE: u32 = 0xE7;
const SIMPLE_BLOCK: u32 = 0xA3;
const BLOCK_GROUP: u32 = 0xA0;
const BLOCK: u32 = 0xA1;
const REFERENCE: u32 = 0xFB;

/// An element: its id, where its data starts and ends (`end` may lie past
/// the bytes read, or is `usize::MAX` for an unknown size).
#[derive(Debug, Clone, Copy)]
pub(crate) struct Element {
    pub(crate) id: u32,
    pub(crate) data: usize,
    pub(crate) end: usize,
}

fn vint(b: &[u8], at: usize, keep_marker: bool) -> Option<(u64, usize)> {
    let first = *b.get(at)?;
    if first == 0 {
        return None;
    }
    let length = first.leading_zeros() as usize + 1;
    let mut value = if keep_marker { first as u64 } else { (first as u64) & (0xffu64 >> length) };
    for i in 1..length {
        value = (value << 8) | *b.get(at + i)? as u64;
    }
    Some((value, length))
}

pub(crate) fn element(b: &[u8], at: usize) -> Option<Element> {
    let (id, n) = vint(b, at, true)?;
    if n > 4 {
        return None;
    }
    let (size, m) = vint(b, at + n, false)?;
    let data = at + n + m;
    let unknown = size == (1u64 << (7 * m)) - 1;
    let end = if unknown { usize::MAX } else { data.saturating_add(usize::try_from(size).ok()?) };
    Some(Element { id: id as u32, data, end })
}

/// The elements one after another in `b[from..to]`, stopping at one that
/// does not fit.
fn children(b: &[u8], from: usize, to: usize) -> Vec<Element> {
    let mut found = Vec::new();
    let mut at = from;
    while at < to {
        let Some(e) = element(b, at) else { break };
        found.push(e);
        if e.end > to {
            break;
        }
        at = e.end;
    }
    found
}

fn uint(b: &[u8], e: Element) -> Option<u64> {
    let bytes = b.get(e.data..e.end)?;
    (bytes.len() <= 8).then(|| bytes.iter().fold(0u64, |v, &x| (v << 8) | x as u64))
}

fn find(b: &[u8], parent: Element, id: u32) -> Option<Element> {
    children(b, parent.data, parent.end.min(b.len())).into_iter().find(|e| e.id == id && e.end <= b.len())
}

pub fn is_webm(b: &[u8]) -> bool {
    b.len() >= 4 && u32::from_be_bytes([b[0], b[1], b[2], b[3]]) == EBML
}

/// Reads the head of a WebM file of `total` bytes: its VP9 track and the
/// clusters its `Cues` index lists.
pub fn read_head(b: &[u8], total: u64) -> Read {
    let Some(ebml) = element(b, 0).filter(|e| e.id == EBML) else { return Read::Unusable("not WebM") };
    let Some(segment) = element(b, ebml.end).filter(|e| e.id == SEGMENT) else {
        return if ebml.end + 12 > b.len() { Read::More(ebml.end as u64 + 4096) } else { Read::Unusable("no segment") };
    };
    let (mut scale, mut track, mut cues) = (1_000_000u64, None, None);
    let mut at = segment.data;
    loop {
        let Some(e) = element(b, at) else { return Read::More((at as u64 + 4096).max(b.len() as u64 * 2)) };
        if e.id == CLUSTER {
            return Read::Unusable("no index before the clusters");
        }
        if matches!(e.id, INFO | TRACKS | CUES) && e.end > b.len() {
            return if e.end == usize::MAX { Read::Unusable("element of unknown size") } else { Read::More(e.end as u64) };
        }
        match e.id {
            INFO => scale = find(b, e, TIMECODE_SCALE).and_then(|s| uint(b, s)).unwrap_or(scale),
            TRACKS => track = Some(e),
            CUES => cues = Some(e),
            _ => {}
        }
        if let (Some(track), Some(cues)) = (track, cues) {
            return head(b, segment.data as u64, scale, track, cues, total);
        }
        if e.end == usize::MAX {
            return Read::Unusable("element of unknown size");
        }
        at = e.end;
    }
}

fn head(b: &[u8], segment: u64, scale: u64, tracks: Element, cues: Element, total: u64) -> Read {
    if scale == 0 || 1_000_000_000 % scale != 0 {
        return Read::Unusable("unusual timecode scale");
    }
    let timescale = (1_000_000_000 / scale) as u32;
    let Some(entry) = children(b, tracks.data, tracks.end).into_iter().find(|e| e.id == TRACK_ENTRY && find(b, *e, TRACK_TYPE).and_then(|t| uint(b, t)) == Some(1)) else {
        return Read::Unusable("no picture track");
    };
    let codec = find(b, entry, CODEC_ID).and_then(|c| b.get(c.data..c.end));
    if codec != Some(b"V_VP9") {
        return Read::Unusable("not VP9");
    }
    let Some(number) = find(b, entry, TRACK_NUMBER).and_then(|n| uint(b, n)) else { return Read::Unusable("no track number") };
    let Some(video) = find(b, entry, VIDEO) else { return Read::Unusable("no picture size") };
    let dimension = |id| find(b, video, id).and_then(|e| uint(b, e)).and_then(|v| u16::try_from(v).ok());
    let (Some(width), Some(height)) = (dimension(PIXEL_WIDTH), dimension(PIXEL_HEIGHT)) else { return Read::Unusable("no picture size") };
    let colour = find(b, video, COLOUR);
    let field = |id, fallback: u64| colour.and_then(|c| find(b, c, id)).and_then(|e| uint(b, e)).unwrap_or(fallback);
    let mut bits = field(BITS, 8) as u8;
    // CodecPrivate: VP9 features as id, length, value.
    let (mut profile, mut level) = (None, None);
    if let Some(private) = find(b, entry, CODEC_PRIVATE).and_then(|p| b.get(p.data..p.end)) {
        let mut i = 0;
        while i + 2 <= private.len() {
            let (id, len) = (private[i], private[i + 1] as usize);
            let Some(&value) = private.get(i + 2).filter(|_| len == 1) else { break };
            match id {
                1 => profile = Some(value),
                2 => level = Some(value),
                3 => bits = value,
                _ => {}
            }
            i += 2 + len;
        }
    }
    let profile = profile.unwrap_or(if bits > 8 { 2 } else { 0 });
    let level = level.unwrap_or(match height {
        0..=1080 => 41,
        1081..=1440 => 50,
        1441..=2160 => 51,
        _ => 61,
    });
    let full = field(RANGE, 1) == 2;
    let (primaries, transfer, matrix) = (field(PRIMARIES, 1) as u8, field(TRANSFER, 1) as u8, field(MATRIX, 1) as u8);
    let mut vpcc = vec![1, 0, 0, 0, profile, level, (bits << 4) | (1 << 1) | u8::from(full), primaries, transfer, matrix, 0, 0];
    vpcc.splice(0..0, [0, 0, 0, 20, b'v', b'p', b'c', b'C']);
    let frame = find(b, entry, DEFAULT_DURATION).and_then(|d| uint(b, d)).map_or(0, |ns| (ns / scale) as u32);
    let mut points = Vec::new();
    for point in children(b, cues.data, cues.end).into_iter().filter(|e| e.id == CUE_POINT) {
        let Some(time) = find(b, point, CUE_TIME).and_then(|t| uint(b, t)) else { continue };
        for positions in children(b, point.data, point.end).into_iter().filter(|e| e.id == CUE_POSITIONS) {
            let track = find(b, positions, CUE_TRACK).and_then(|t| uint(b, t));
            if let (Some(n), Some(position)) = (track, find(b, positions, CUE_CLUSTER).and_then(|p| uint(b, p)))
                && n == number
            {
                points.push((segment + position, time as f64 / timescale as f64));
            }
        }
    }
    points.sort_by_key(|p| p.0);
    points.dedup_by_key(|p| p.0);
    points.retain(|p| p.0 < total);
    if points.is_empty() {
        return Read::Unusable("empty index");
    }
    Read::Head(Box::new(Head { number, timescale, width, height, vpcc, frame, clusters: points }))
}

/// The frames of `track` in one whole cluster, in file order.
pub fn frames(b: &[u8], track: u64) -> Result<Vec<Frame>, &'static str> {
    let cluster = element(b, 0).filter(|e| e.id == CLUSTER).ok_or("not a cluster")?;
    let end = cluster.end.min(b.len());
    let mut base = 0u64;
    let mut found = Vec::new();
    for e in children(b, cluster.data, end) {
        if e.end > end {
            break;
        }
        match e.id {
            TIMECODE => base = uint(b, e).ok_or("bad timecode")?,
            SIMPLE_BLOCK => block(b, e, track, base, None, &mut found)?,
            BLOCK_GROUP => {
                if let Some(inner) = find(b, e, BLOCK) {
                    let referenced = find(b, e, REFERENCE).is_some();
                    block(b, inner, track, base, Some(!referenced), &mut found)?;
                }
            }
            _ => {}
        }
    }
    Ok(found)
}

fn block(b: &[u8], e: Element, track: u64, base: u64, key: Option<bool>, found: &mut Vec<Frame>) -> Result<(), &'static str> {
    let (number, n) = vint(b, e.data, false).ok_or("bad block")?;
    if number != track {
        return Ok(());
    }
    let at = e.data + n;
    let relative = i16::from_be_bytes([*b.get(at).ok_or("bad block")?, *b.get(at + 1).ok_or("bad block")?]);
    let flags = *b.get(at + 2).ok_or("bad block")?;
    if flags & 0x06 != 0 {
        return Err("laced picture frames");
    }
    let start = at + 3;
    let time = (base as i64 + relative as i64).max(0) as u64;
    found.push(Frame { at: start, size: e.end - start, time, key: key.unwrap_or(flags & 0x80 != 0) });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_variable_integers() {
        assert_eq!(vint(&[0x81], 0, false), Some((1, 1)));
        assert_eq!(vint(&[0x40, 0x02], 0, false), Some((2, 2)));
        assert_eq!(vint(&[0x1A, 0x45, 0xDF, 0xA3], 0, true), Some((0x1A45_DFA3, 4)));
        assert_eq!(vint(&[0], 0, false), None);
        let unknown = element(&[0x1F, 0x43, 0xB6, 0x75, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], 0).unwrap();
        assert_eq!(unknown.end, usize::MAX);
    }
}
