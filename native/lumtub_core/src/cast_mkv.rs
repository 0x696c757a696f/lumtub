//! Writes the joined cast stream as Matroska: a segment of unknown length
//! that grows cluster by cluster, so a TV can play it as it arrives. MKV
//! carries any of YouTube's pictures (H.264, VP9, AV1) and text subtitle
//! tracks, which TVs that play MKV show without asking for another file.
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

/// What goes into the head besides picture and sound: subtitle tracks
/// (language and name, numbered from [TEXT]), a title and a cover.
#[derive(Default, Clone, Copy)]
pub struct Extra<'a> {
    /// Language, name, and for an ASS track its header.
    pub texts: &'a [(&'a str, &'a str, Option<&'a str>)],
    pub title: Option<&'a str>,
    pub cover: Option<&'a [u8]>,
}

pub const VIDEO: u64 = 1;
pub const AUDIO: u64 = 2;
pub const TEXT: u64 = 3;

const CLUSTER: u32 = 0x1f43_b675;
const CUES: u32 = 0x1c53_bb6b;

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
pub fn head(
    video: &TrackInfo,
    audio: &TrackInfo,
    extra: Extra,
    duration: f64,
    file: bool,
    matroska: bool,
) -> Head {
    let webm = !matroska && webm_holds(video, audio, extra);
    let mut out = Vec::new();
    master(&mut out, 0x1a45_dfa3, |o| {
        uint(o, 0x4286, 1);
        uint(o, 0x42f7, 1);
        uint(o, 0x42f2, 4);
        uint(o, 0x42f3, 8);
        element(o, 0x4282, if webm { b"webm" } else { b"matroska" });
        uint(o, 0x4287, 4);
        uint(o, 0x4285, 2);
    });
    id(&mut out, 0x1853_8067);
    out.extend_from_slice(&[0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
    let segment = out.len();
    let mut cues_at = None;
    if file {
        // SeekHead { Seek { SeekID Cues, SeekPosition (8 bytes) } }
        id(&mut out, 0x114d_9b74);
        size(&mut out, 21);
        id(&mut out, 0x4dbb);
        size(&mut out, 18);
        element(&mut out, 0x53ab, &CUES.to_be_bytes());
        id(&mut out, 0x53ac);
        size(&mut out, 8);
        cues_at = Some(out.len());
        out.extend_from_slice(&[0; 8]);
    }
    let mut info = Vec::new();
    uint(&mut info, 0x2ad7b1, 1_000_000);
    let mut duration_at = None;
    if duration > 0.0 || file {
        id(&mut info, 0x4489);
        size(&mut info, 8);
        duration_at = Some(info.len());
        info.extend_from_slice(&duration.to_be_bytes());
    }
    if let Some(title) = extra.title.filter(|t| !t.is_empty()) {
        element(&mut info, 0x7ba9, title.as_bytes());
    }
    element(&mut info, 0x4d80, b"Lumtub");
    element(&mut info, 0x5741, b"Lumtub");
    id(&mut out, 0x1549_a966);
    size(&mut out, info.len() as u64);
    let duration_at = duration_at.filter(|_| file).map(|at| out.len() + at);
    out.extend_from_slice(&info);
    master(&mut out, 0x1654_ae6b, |o| {
        for (number, info) in [(VIDEO, video), (AUDIO, audio)] {
            master(o, 0xae, |o| {
                uint(o, 0xd7, number);
                uint(o, 0x73c5, number);
                uint(o, 0x83, if info.video.is_some() { 1 } else { 2 });
                uint(o, 0x9c, 0);
                element(o, 0x86, info.codec.as_bytes());
                element(o, 0x0022_b59c, b"und");
                if let Some(private) = &info.private {
                    element(o, 0x63a2, private);
                }
                if info.delay > 0 {
                    uint(o, 0x56aa, info.delay);
                }
                if info.preroll > 0 {
                    uint(o, 0x56bb, info.preroll);
                }
                if let Some((width, height)) = info.video {
                    master(o, 0xe0, |o| {
                        uint(o, 0xb0, width as u64);
                        uint(o, 0xba, height as u64);
                    });
                }
                if let Some((rate, channels)) = info.audio {
                    master(o, 0xe1, |o| {
                        float(o, 0xb5, rate);
                        uint(o, 0x9f, channels as u64);
                    });
                }
            });
        }
        for (i, &(language, name, ass)) in extra.texts.iter().enumerate() {
            master(o, 0xae, |o| {
                uint(o, 0xd7, TEXT + i as u64);
                uint(o, 0x73c5, TEXT + i as u64);
                uint(o, 0x83, 0x11);
                uint(o, 0x9c, 0);
                uint(o, 0x88, u64::from(i == 0));
                match ass {
                    Some(header) => {
                        element(o, 0x86, b"S_TEXT/ASS");
                        element(o, 0x63a2, header.as_bytes());
                    }
                    None => element(o, 0x86, b"S_TEXT/UTF8"),
                }
                if !name.is_empty() {
                    element(o, 0x536e, name.as_bytes());
                }
                element(o, 0x0022_b59c, crate::embed::iso639_2(language).as_bytes());
                if !language.is_empty() {
                    element(o, 0x0022_b59d, language.as_bytes());
                }
            });
        }
    });
    if let Some(cover) = extra.cover {
        // Attachments { AttachedFile { name, type, data, id } }, named so
        // players show it as the cover.
        let png = crate::embed::is_png(cover);
        master(&mut out, 0x1941_a469, |o| {
            master(o, 0x61a7, |o| {
                element(o, 0x466e, if png { b"cover.png" } else { b"cover.jpg" });
                element(o, 0x4660, if png { b"image/png" } else { b"image/jpeg" });
                element(o, 0x465c, cover);
                uint(o, 0x46ae, 1);
            });
        });
    }
    Head {
        bytes: out,
        segment,
        duration_at,
        cues_at,
    }
}

/// Whether WebM may hold these: VP9 or AV1 with Opus, and nothing else.
pub fn webm_holds(video: &TrackInfo, audio: &TrackInfo, extra: Extra) -> bool {
    matches!(video.codec, "V_VP9" | "V_AV1")
        && audio.codec == "A_OPUS"
        && extra.texts.is_empty()
        && extra.cover.is_none()
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
        Clusters {
            position: (head.bytes.len() - head.segment) as u64,
            ..Clusters::default()
        }
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
        element(&mut self.body, 0xa3, &block);
    }

    /// Adds a subtitle of track `track` shown from `time` ms for `duration` ms.
    pub fn text(&mut self, out: &mut Vec<u8>, track: u64, time: i64, duration: u64, text: &str) {
        self.open(out, time, false);
        let relative = (time - self.start.unwrap_or(time)) as i16;
        master(&mut self.body, 0xa0, |o| {
            let mut block = Vec::with_capacity(text.len() + 4);
            size(&mut block, track);
            block.extend_from_slice(&relative.to_be_bytes());
            block.push(0);
            block.extend_from_slice(text.as_bytes());
            element(o, 0xa1, &block);
            uint(o, 0x9b, duration);
        });
    }

    fn open(&mut self, out: &mut Vec<u8>, time: i64, key: bool) {
        let fresh = match self.start {
            None => true,
            Some(start) => {
                (key && time - start >= 1000) || time - start > 30_000 || time < start - 30_000
            }
        };
        if fresh {
            self.flush(out);
            if key || self.points.is_empty() {
                self.points.push((time.max(0), self.position));
            }
            self.start = Some(time);
            uint(&mut self.body, 0xe7, time.max(0) as u64);
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
                master(o, 0xbb, |o| {
                    uint(o, 0xb3, time as u64);
                    master(o, 0xb7, |o| {
                        uint(o, 0xf7, VIDEO);
                        uint(o, 0xf1, position);
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
        assert_eq!(out, [0x85, 0xfe, 0x40, 0x7f, 0x41, 0x2c]);
    }
}
