//! A live stream's picture or sound above 1080p, served to libmpv as one
//! growing stream. YouTube offers those only as separate streams without a
//! manifest: each request with `sq=N` answers fragment N on its own (a few
//! seconds of WebM or MP4), and `x-head-seqnum` names the newest. The relay
//! asks the fragments in order, a few at once while they are behind the
//! newest, and writes them one after another; the timestamps inside carry
//! on from fragment to fragment, so libmpv reads them as one stream and
//! keeps picture and sound together. Each fragment repeats the headers,
//! which would end the stream for libmpv's demuxers, so after the first
//! only what follows them is written (see [continuation]).

use crate::relay::{Fetch, Target};
use std::collections::VecDeque;
use std::io::{Read, Write};
use std::time::{Duration, Instant};

/// Fragments behind the newest a stream starts at, so libmpv can fill its
/// cache before it reaches the edge. About 20 s, near YouTube's own player:
/// with 3 (about 6 s) every pause in a broadcaster's upload longer than
/// that stopped the picture (the user's log: no new fragment for a minute,
/// and stalls between).
pub const BEHIND: u64 = 10;
/// Fragments asked for at once while there are that many to catch up on.
const AT_ONCE: usize = 3;
/// How long a fragment may stay unavailable before the stream ends and the
/// app reconnects.
const GIVE_UP: Duration = Duration::from_secs(45);
/// Pause between asking for a fragment that is not out yet.
const RETRY: Duration = Duration::from_millis(500);
/// Pauses between asking again for the newest fragment while YouTube's
/// server answers 5xx or not at all: a live's server can be unavailable
/// for a while, and reopening only asks the same one. About 10 s in all,
/// within libmpv's 20 s wait for an answer.
const HEAD_WAITS: [Duration; 5] =
    [Duration::from_millis(500), Duration::from_secs(1), Duration::from_secs(2), Duration::from_secs(3), Duration::from_secs(4)];

/// One fragment's bytes and the newest fragment YouTube named with it.
struct Fragment {
    bytes: Vec<u8>,
    head: Option<u64>,
}

enum Miss {
    /// Not there yet, or a failure worth asking again for.
    Again(String),
    /// The address expired or was refused: the app has to resolve anew.
    Refused(u16),
}

/// What of a fragment after the first carries the stream on: from the first
/// WebM cluster, or from the first MP4 `moof`; all of it when neither is
/// found.
fn continuation(bytes: &[u8]) -> &[u8] {
    let at = if bytes.starts_with(&[0x1A, 0x45, 0xDF, 0xA3]) { webm_clusters(bytes) } else { mp4_fragments(bytes) };
    at.map_or(bytes, |at| &bytes[at..])
}

fn webm_clusters(b: &[u8]) -> Option<usize> {
    use crate::cast_webm::{element, CLUSTER, EBML, SEGMENT};
    let header = element(b, 0).filter(|e| e.id == EBML)?;
    let segment = element(b, header.end).filter(|e| e.id == SEGMENT)?;
    let mut at = segment.data;
    while at < b.len() {
        let e = element(b, at)?;
        if e.id == CLUSTER {
            return Some(at);
        }
        if e.end == usize::MAX {
            return None;
        }
        at = e.end;
    }
    None
}

fn mp4_fragments(b: &[u8]) -> Option<usize> {
    let mut at = 0usize;
    while at.checked_add(8)? <= b.len() {
        let size = u32::from_be_bytes(b[at..at + 4].try_into().ok()?) as u64;
        if &b[at + 4..at + 8] == b"moof" {
            return (at > 0).then_some(at);
        }
        let size = match size {
            0 => return None,
            1 => u64::from_be_bytes(b.get(at + 8..at + 16)?.try_into().ok()?),
            n => n,
        };
        if size < 8 {
            return None;
        }
        at = at.checked_add(usize::try_from(size).ok()?)?;
    }
    None
}

/// [url] without its `sq` parameter.
fn base(url: &str) -> String {
    let Some((path, query)) = url.split_once('?') else { return url.to_string() };
    let kept: Vec<&str> = query.split('&').filter(|pair| !pair.starts_with("sq=") && *pair != "sq").collect();
    if kept.is_empty() { path.to_string() } else { format!("{path}?{}", kept.join("&")) }
}

fn fetch_fragment(fetch: &dyn Fetch, target: &Target, base: &str, sq: u64) -> Result<Fragment, Miss> {
    // Appended as text: rebuilding the query could re-encode signed values.
    let url = format!("{base}&sq={sq}");
    match fetch.get_live(target, &url) {
        Ok((200, head, mut body)) => {
            let mut bytes = Vec::new();
            match body.read_to_end(&mut bytes) {
                Ok(_) if !bytes.is_empty() => Ok(Fragment { bytes, head }),
                Ok(_) => Err(Miss::Again(format!("fragment {sq} was empty"))),
                Err(e) => Err(Miss::Again(format!("fragment {sq} broke off: {e}"))),
            }
        }
        Ok((status @ (401 | 403 | 410), _, _)) => Err(Miss::Refused(status)),
        Ok((status, _, _)) => Err(Miss::Again(format!("fragment {sq} answered {status}"))),
        Err(e) => Err(Miss::Again(format!("fragment {sq}: {e}"))),
    }
}

/// Answers one GET of a live [target]: the newest fragment is looked up,
/// [start_at] turns it into the first fragment served (shared with the
/// other stream of the pair), and fragments follow until libmpv hangs up
/// or YouTube stops answering.
pub(crate) fn stream(writer: &mut impl Write, target: &Target, fetch: &dyn Fetch, start_at: impl FnOnce(u64) -> u64, log: impl Fn(String)) {
    let base = base(&target.url);
    let mut waits = HEAD_WAITS.iter();
    let newest = loop {
        let answer = fetch.get_live(target, &base);
        let passing = matches!(answer, Ok((500..=599, _, _)) | Err(_));
        match waits.next() {
            Some(wait) if passing => {
                let why = match &answer {
                    Ok((status, _, _)) => format!("HTTP {status}"),
                    Err(e) => e.clone(),
                };
                log(format!("Live stream gave no newest fragment ({why}); asking again in {} ms", wait.as_millis()));
                std::thread::sleep(*wait);
            }
            _ => break answer,
        }
    };
    let head = match newest {
        Ok((200, Some(head), _)) => head,
        Ok((status, head, _)) => {
            log(format!("Live stream gave no newest fragment (HTTP {status}, head {head:?})"));
            let code = if status == 200 { 502 } else { status };
            let _ = write!(writer, "HTTP/1.1 {code} Upstream Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            return;
        }
        Err(e) => {
            log(format!("Live stream could not be reached: {e}"));
            let _ = write!(writer, "HTTP/1.1 502 Upstream Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            return;
        }
    };
    let first = start_at(head);
    let mime = target.mime.as_deref().unwrap_or("application/octet-stream");
    // No length: the stream grows until either side stops.
    if write!(writer, "HTTP/1.1 200 OK\r\nContent-Type: {mime}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n").is_err() {
        return;
    }
    std::thread::scope(|scope| {
        let base = base.as_str();
        let mut newest = head;
        let mut asked = first;
        let mut pending = VecDeque::new();
        let mut missing_since: Option<Instant> = None;
        let mut first = true;
        loop {
            // Several at once only for fragments already out; the next one
            // past the newest is asked alone and again until it appears.
            while pending.len() < AT_ONCE && (asked <= newest || pending.is_empty()) {
                let sq = asked;
                pending.push_back((sq, scope.spawn(move || fetch_fragment(fetch, target, base, sq))));
                asked += 1;
            }
            let Some((sq, handle)) = pending.pop_front() else { return };
            match handle.join() {
                Ok(Ok(fragment)) => {
                    missing_since = None;
                    if let Some(head) = fragment.head {
                        newest = newest.max(head);
                    }
                    let bytes = if first { &fragment.bytes[..] } else { continuation(&fragment.bytes) };
                    first = false;
                    if writer.write_all(bytes).and_then(|_| writer.flush()).is_err() {
                        // libmpv hung up; the fragments still being fetched
                        // finish on their own and are dropped.
                        return;
                    }
                }
                Ok(Err(Miss::Refused(status))) => {
                    log(format!("Live fragment {sq} refused (HTTP {status}); the address has to be renewed"));
                    return;
                }
                Ok(Err(Miss::Again(why))) => {
                    let since = *missing_since.get_or_insert_with(Instant::now);
                    if since.elapsed() > GIVE_UP {
                        log(format!("Live stream stopped: {why} for {} s", GIVE_UP.as_secs()));
                        return;
                    }
                    // Ask for it again first; the ones after it wait.
                    std::thread::sleep(RETRY);
                    pending.push_front((sq, scope.spawn(move || fetch_fragment(fetch, target, base, sq))));
                }
                Err(_) => return,
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Cursor, ErrorKind};
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicU64, Ordering};

    /// A live stream whose newest fragment moves on by one every [tick]
    /// requests; fragment N reads `<N>;`.
    struct Live {
        first_head: u64,
        asked: AtomicU64,
        tick: u64,
        refuse_from: Option<u64>,
        calls: Mutex<Vec<String>>,
    }

    impl Live {
        fn new(head: u64) -> Live {
            Live { first_head: head, asked: AtomicU64::new(0), tick: 2, refuse_from: None, calls: Mutex::new(vec![]) }
        }
        fn head(&self) -> u64 {
            self.first_head + self.asked.load(Ordering::SeqCst) / self.tick
        }
    }

    impl Fetch for Live {
        fn get(&self, target: &Target, url: &str) -> Result<(u16, Box<dyn Read + Send>), String> {
            self.get_live(target, url).map(|(s, _, b)| (s, b))
        }
        fn get_live(&self, _: &Target, url: &str) -> Result<(u16, Option<u64>, Box<dyn Read + Send>), String> {
            self.calls.lock().unwrap().push(url.to_string());
            self.asked.fetch_add(1, Ordering::SeqCst);
            let head = self.head();
            let Some(sq) = url.split("&sq=").nth(1) else {
                return Ok((200, Some(head), Box::new(Cursor::new(b"newest".to_vec()))));
            };
            let sq: u64 = sq.parse().unwrap();
            if self.refuse_from.is_some_and(|from| sq >= from) {
                return Ok((403, None, Box::new(Cursor::new(vec![]))));
            }
            if sq > head {
                return Ok((404, Some(head), Box::new(Cursor::new(vec![]))));
            }
            Ok((200, Some(head), Box::new(Cursor::new(format!("{sq};").into_bytes()))))
        }
    }

    fn target() -> Target {
        Target {
            url: "https://example.com/videoplayback?mime=video%2Fwebm&live=1&sq=7".into(),
            size: 0,
            user_agent: None,
            mime: Some("video/webm".into()),
            proxy: None,
            chunk: crate::relay::CHUNK,
            live: Some("pair".into()),
        }
    }

    /// Takes what is written until [limit] bytes, then hangs up like libmpv.
    struct Client {
        bytes: Vec<u8>,
        limit: usize,
    }

    impl Write for Client {
        fn write(&mut self, data: &[u8]) -> std::io::Result<usize> {
            if self.bytes.len() >= self.limit {
                return Err(std::io::Error::new(ErrorKind::BrokenPipe, "gone"));
            }
            self.bytes.extend_from_slice(data);
            Ok(data.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    fn body(client: &Client) -> String {
        let text = String::from_utf8_lossy(&client.bytes).into_owned();
        text.split_once("\r\n\r\n").unwrap().1.to_string()
    }

    #[test]
    fn serves_fragments_in_order_from_behind_the_newest_and_waits_for_new_ones() {
        let live = Live::new(100);
        let mut client = Client { bytes: vec![], limit: 160 };
        let mut started = None;
        stream(&mut client, &target(), &live, |head| { started = Some(head); head - BEHIND }, |_| {});
        assert_eq!(started, Some(100));
        let text = String::from_utf8_lossy(&client.bytes).into_owned();
        assert!(text.starts_with("HTTP/1.1 200 OK\r\nContent-Type: video/webm\r\n"));
        assert!(!text.contains("Content-Length"));
        let served: Vec<u64> = body(&client).split(';').filter(|s| !s.is_empty()).map(|s| s.parse().unwrap()).collect();
        assert!(served.len() > 10, "{served:?}");
        let expected: Vec<u64> = (100 - BEHIND..100 - BEHIND + served.len() as u64).collect();
        assert_eq!(served, expected);
        // The old sq of the address is replaced, never sent twice.
        assert!(live.calls.lock().unwrap().iter().all(|url| url.matches("sq=").count() <= 1 && !url.contains("sq=7")));
    }

    #[test]
    fn both_streams_of_a_pair_start_at_the_same_fragment() {
        let shared = Mutex::new(None::<u64>);
        let start = |head: u64| *shared.lock().unwrap().get_or_insert(head - BEHIND);
        let video = Live::new(50);
        let mut first = Client { bytes: vec![], limit: 120 };
        stream(&mut first, &target(), &video, start, |_| {});
        let audio = Live::new(52);
        let mut second = Client { bytes: vec![], limit: 120 };
        stream(&mut second, &target(), &audio, start, |_| {});
        assert!(body(&first).starts_with(&format!("{};", 50 - BEHIND)));
        assert!(body(&second).starts_with(&format!("{};", 50 - BEHIND)));
    }

    #[test]
    fn a_refused_fragment_ends_the_stream() {
        let mut live = Live::new(20);
        live.refuse_from = Some(20 - BEHIND + 2);
        let mut client = Client { bytes: vec![], limit: usize::MAX };
        let lines = Mutex::new(vec![]);
        stream(&mut client, &target(), &live, |head| head - BEHIND, |line| lines.lock().unwrap().push(line));
        assert_eq!(body(&client), format!("{};{};", 20 - BEHIND, 21 - BEHIND));
        assert!(lines.lock().unwrap().iter().any(|l| l.contains("403")));
    }

    #[test]
    fn no_newest_fragment_is_an_error_status() {
        struct Dead;
        impl Fetch for Dead {
            fn get(&self, _: &Target, _: &str) -> Result<(u16, Box<dyn Read + Send>), String> {
                Ok((403, Box::new(Cursor::new(vec![]))))
            }
        }
        let mut client = Client { bytes: vec![], limit: usize::MAX };
        stream(&mut client, &target(), &Dead, |h| h, |_| {});
        assert!(String::from_utf8_lossy(&client.bytes).starts_with("HTTP/1.1 403"));
    }

    #[test]
    fn asks_again_while_the_server_is_unavailable() {
        struct Busy {
            live: Live,
            busy: AtomicU64,
        }
        impl Fetch for Busy {
            fn get(&self, target: &Target, url: &str) -> Result<(u16, Box<dyn Read + Send>), String> {
                self.get_live(target, url).map(|(s, _, b)| (s, b))
            }
            fn get_live(&self, target: &Target, url: &str) -> Result<(u16, Option<u64>, Box<dyn Read + Send>), String> {
                if self.busy.fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1)).is_ok() {
                    return Ok((503, None, Box::new(Cursor::new(vec![]))));
                }
                self.live.get_live(target, url)
            }
        }
        let busy = Busy { live: Live::new(20), busy: AtomicU64::new(2) };
        let lines = Mutex::new(vec![]);
        let mut client = Client { bytes: vec![], limit: 120 };
        stream(&mut client, &target(), &busy, |head| head - BEHIND, |line| lines.lock().unwrap().push(line));
        assert!(body(&client).starts_with(&format!("{};", 20 - BEHIND)), "{}", body(&client));
        assert_eq!(lines.lock().unwrap().len(), 2);
    }

    #[test]
    fn later_fragments_lose_their_headers() {
        // EBML header, Segment of unknown size, Info, Cluster.
        let webm = [vec![0x1A, 0x45, 0xDF, 0xA3, 0x81, 0x00], vec![0x18, 0x53, 0x80, 0x67, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], vec![0x15, 0x49, 0xA9, 0x66, 0x82, 0, 0], vec![0x1F, 0x43, 0xB6, 0x75, 0x81, 0x07]].concat();
        assert_eq!(continuation(&webm), &[0x1F, 0x43, 0xB6, 0x75, 0x81, 0x07]);
        let mut mp4 = vec![];
        for (kind, body) in [(b"ftyp", 4usize), (b"moov", 8), (b"moof", 2), (b"mdat", 3)] {
            mp4.extend_from_slice(&((8 + body) as u32).to_be_bytes());
            mp4.extend_from_slice(kind);
            mp4.extend(std::iter::repeat_n(0u8, body));
        }
        assert_eq!(&continuation(&mp4)[4..8], b"moof");
        assert_eq!(continuation(&mp4).len(), 10 + 11);
        assert_eq!(continuation(b"7;"), b"7;");
    }

    #[test]
    fn base_drops_only_sq() {
        assert_eq!(base("https://x/v?a=1&sq=5&b=2"), "https://x/v?a=1&b=2");
        assert_eq!(base("https://x/v?sq=5"), "https://x/v");
        assert_eq!(base("https://x/v?sqx=5"), "https://x/v?sqx=5");
    }
}
