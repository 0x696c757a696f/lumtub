//! Writes the joined cast stream as Matroska: a segment of unknown length
//! that grows cluster by cluster, so a TV can play it as it arrives. MKV
//! carries any of YouTube's pictures (H.264, VP9, AV1) and a text subtitle
//! track, which TVs that play MKV show without asking for another file.
//! A saved file also gets its length and a `Cues` index at the end, which
//! the writer fills in once the whole stream is written.

/// One track as Matroska describes it.
pub struct TrackInfo {
    pub codec: &'static str,
    pub private: Option<Vec<u8>>,
    /// The picture's size, or the sound's sample rate and channels.
    pub video: Option<(u16, u16)>,
    pub audio: Option<(f64, u8)>,
    /// Opus's CodecDelay and SeekPreRoll, in nanoseconds.
    pub delay: u64,
    pub preroll: u64,
}

/// The bytes before the first cluster, and where a saved file's numbers
/// go once the stream is whole.
pub struct Head {
    pub bytes: Vec<u8>,
    /// Where the segment's data starts; its size takes the 8 bytes before.
    pub segment: usize,
    /// For a file: where the length (an 8-byte float, in ms) and the
    /// position of `Cues` (an 8-byte integer) are.
    pub duration_at: Option<usize>,
    pub cues_at: Option<usize>,
}

pub const VIDEO: u64 = 1;
pub const AUDIO: u64 = 2;
pub const TEXT: u64 = 3;

const CLUSTER: u32 = 0x1F43_B675;
const CUES: u32 = 0x1C53_BB6B;

fn id(out: &mut Vec<u8>, id: u32) {
    let bytes = id.to_be_bytes();
    let skip = bytes.iter().position(|&b| b != 0).unwrap_or(3);
    out.extend_from_slice(&bytes[skip..]);
}

fn size(out: &mut Vec<u8>, n: u64) {
    let mut length = 1;
    while length < 8 && n >= (1u64 << (7 * length)) - 1 {
        length += 1;
    }
    let marked = n | (1u64 << (7 * length));
    out.extend_from_slice(&marked.to_be_bytes()[8 - length..]);
}

fn element(out: &mut Vec<u8>, kind: u32, body: &[u8]) {
    id(out, kind);
    size(out, body.len() as u64);
    out.extend_from_slice(body);
}

fn master(out: &mut Vec<u8>, kind: u32, fill: impl FnOnce(&mut Vec<u8>)) {
    let mut body = Vec::new();
    fill(&mut body);
    element(out, kind, &body);
}

fn uint(out: &mut Vec<u8>, kind: u32, v: u64) {
    let bytes = v.to_be_bytes();
    let skip = bytes.iter().position(|&b| b != 0).unwrap_or(7);
    element(out, kind, &bytes[skip..]);
}

fn float(out: &mut Vec<u8>, kind: u32, v: f64) {
    element(out, kind, &v.to_be_bytes());
}

/// The EBML header, the start of a segment of unknown size, its info and
/// its tracks. `duration` is in milliseconds, 0 when not known. For a
/// `file`, room is left for its length and the position of its index.
/// It is called WebM when that holds it, unless `matroska`.
pub fn head(video: &TrackInfo, audio: &TrackInfo, subtitles: Option<&str>, duration: f64, file: bool, matroska: bool) -> Head {
    let webm = !matroska && matches!(video.codec, "V_VP9" | "V_AV1") && audio.codec == "A_OPUS" && subtitles.is_none();
    let mut out = Vec::new();
    master(&mut out, 0x1A45_DFA3, |o| {
        uint(o, 0x4286, 1);
        uint(o, 0x42F7, 1);
        uint(o, 0x42F2, 4);
        uint(o, 0x42F3, 8);
        element(o, 0x4282, if webm { b"webm" } else { b"matroska" });
        uint(o, 0x4287, 4);
        uint(o, 0x4285, 2);
    });
    id(&mut out, 0x1853_8067);
    out.extend_from_slice(&[0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
    let segment = out.len();
    let mut cues_at = None;
    if file {
        // SeekHead { Seek { SeekID Cues, SeekPosition (8 bytes) } }
        id(&mut out, 0x114D_9B74);
        size(&mut out, 21);
        id(&mut out, 0x4DBB);
        size(&mut out, 18);
        element(&mut out, 0x53AB, &CUES.to_be_bytes());
        id(&mut out, 0x53AC);
        size(&mut out, 8);
        cues_at = Some(out.len());
        out.extend_from_slice(&[0; 8]);
    }
    let mut info = Vec::new();
    uint(&mut info, 0x2AD7B1, 1_000_000);
    let mut duration_at = None;
    if duration > 0.0 || file {
        id(&mut info, 0x4489);
        size(&mut info, 8);
        duration_at = Some(info.len());
        info.extend_from_slice(&duration.to_be_bytes());
    }
    element(&mut info, 0x4D80, b"Lumtub");
    element(&mut info, 0x5741, b"Lumtub");
    id(&mut out, 0x1549_A966);
    size(&mut out, info.len() as u64);
    let duration_at = duration_at.filter(|_| file).map(|at| out.len() + at);
    out.extend_from_slice(&info);
    master(&mut out, 0x1654_AE6B, |o| {
        for (number, info) in [(VIDEO, video), (AUDIO, audio)] {
            master(o, 0xAE, |o| {
                uint(o, 0xD7, number);
                uint(o, 0x73C5, number);
                uint(o, 0x83, if info.video.is_some() { 1 } else { 2 });
                uint(o, 0x9C, 0);
                element(o, 0x86, info.codec.as_bytes());
                element(o, 0x22B5_9C, b"und");
                if let Some(private) = &info.private {
                    element(o, 0x63A2, private);
                }
                if info.delay > 0 {
                    uint(o, 0x56AA, info.delay);
                }
                if info.preroll > 0 {
                    uint(o, 0x56BB, info.preroll);
                }
                if let Some((width, height)) = info.video {
                    master(o, 0xE0, |o| {
                        uint(o, 0xB0, width as u64);
                        uint(o, 0xBA, height as u64);
                    });
                }
                if let Some((rate, channels)) = info.audio {
                    master(o, 0xE1, |o| {
                        float(o, 0xB5, rate);
                        uint(o, 0x9F, channels as u64);
                    });
                }
            });
        }
        if let Some(language) = subtitles {
            master(o, 0xAE, |o| {
                uint(o, 0xD7, TEXT);
                uint(o, 0x73C5, TEXT);
                uint(o, 0x83, 0x11);
                uint(o, 0x9C, 0);
                uint(o, 0x88, 1);
                element(o, 0x86, b"S_TEXT/UTF8");
                if !language.is_empty() {
                    element(o, 0x22B5_9D, language.as_bytes());
                }
            });
        }
    });
    Head { bytes: out, segment, duration_at, cues_at }
}

/// Gathers blocks into clusters; a cluster is written out whole, as its
/// size comes first.
#[derive(Default)]
pub struct Clusters {
    start: Option<i64>,
    body: Vec<u8>,
    /// Bytes written so far, counted from the segment's data.
    position: u64,
    /// Clusters that start at a picture keyframe: time and position.
    points: Vec<(i64, u64)>,
}

impl Clusters {
    /// Clusters that follow `head`.
    pub fn after(head: &Head) -> Clusters {
        Clusters { position: (head.bytes.len() - head.segment) as u64, ..Clusters::default() }
    }

    /// Adds a frame at `time` ms (its presentation time). A new cluster
    /// starts at a keyframe of the picture a second or more into this one,
    /// or before the block's time would leave a cluster's range.
    pub fn frame(&mut self, out: &mut Vec<u8>, track: u64, time: i64, key: bool, data: &[u8]) {
        self.open(out, time, track == VIDEO && key);
        let mut block = Vec::with_capacity(data.len() + 4);
        size(&mut block, track);
        block.extend_from_slice(&((time - self.start.unwrap_or(time)) as i16).to_be_bytes());
        block.push(if key { 0x80 } else { 0 });
        block.extend_from_slice(data);
        element(&mut self.body, 0xA3, &block);
    }

    /// Adds a subtitle shown from `time` ms for `duration` ms.
    pub fn text(&mut self, out: &mut Vec<u8>, time: i64, duration: u64, text: &str) {
        self.open(out, time, false);
        let relative = (time - self.start.unwrap_or(time)) as i16;
        master(&mut self.body, 0xA0, |o| {
            let mut block = Vec::with_capacity(text.len() + 4);
            size(&mut block, TEXT);
            block.extend_from_slice(&relative.to_be_bytes());
            block.push(0);
            block.extend_from_slice(text.as_bytes());
            element(o, 0xA1, &block);
            uint(o, 0x9B, duration);
        });
    }

    fn open(&mut self, out: &mut Vec<u8>, time: i64, key: bool) {
        let fresh = match self.start {
            None => true,
            Some(start) => (key && time - start >= 1000) || time - start > 30_000 || time < start - 30_000,
        };
        if fresh {
            self.flush(out);
            if key || self.points.is_empty() {
                self.points.push((time.max(0), self.position));
            }
            self.start = Some(time);
            uint(&mut self.body, 0xE7, time.max(0) as u64);
        }
    }

    /// Writes the cluster gathered so far.
    pub fn flush(&mut self, out: &mut Vec<u8>) {
        if self.body.is_empty() {
            return;
        }
        let before = out.len();
        element(out, CLUSTER, &self.body);
        self.position += (out.len() - before) as u64;
        self.body.clear();
        self.start = None;
    }

    /// Writes what has been gathered and the index of the clusters; where
    /// the index starts, counted from the segment's data.
    pub fn finish(&mut self, out: &mut Vec<u8>) -> u64 {
        self.flush(out);
        let at = self.position;
        let before = out.len();
        master(out, CUES, |o| {
            for &(time, position) in &self.points {
                master(o, 0xBB, |o| {
                    uint(o, 0xB3, time as u64);
                    master(o, 0xB7, |o| {
                        uint(o, 0xF7, VIDEO);
                        uint(o, 0xF1, position);
                    });
                });
            }
        });
        self.position += (out.len() - before) as u64;
        at
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes_take_the_fewest_bytes() {
        let mut out = Vec::new();
        size(&mut out, 5);
        size(&mut out, 126);
        size(&mut out, 127);
        size(&mut out, 300);
        assert_eq!(out, [0x85, 0xFE, 0x40, 0x7F, 0x41, 0x2C]);
    }
}
