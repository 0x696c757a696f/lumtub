//! HLS through the relay: a live stream's playlists and every address in
//! them (other playlists, segments, keys) are fetched by the core, with
//! its TLS (证书来源, 抗量子加密), its proxy and its DNS, instead of by
//! libmpv's own HTTPS. A playlist is served with each address in it
//! replaced by a loopback address of the relay; libmpv asks for the
//! playlist again as the stream grows, and every time it is fetched anew.

use crate::relay::{Fetch, Target};
use std::io::{Read, Write};
use std::net::TcpStream;

/// What a relay address serves in HLS.
#[derive(serde::Deserialize, Clone, Copy, PartialEq, Eq, Debug, Default)]
#[serde(rename_all = "lowercase")]
pub enum Hls {
    /// Not HLS: a stream read in chunks, or a live pair.
    #[default]
    No,
    /// A playlist, served with its addresses through the relay.
    Playlist,
    /// A segment, a key or anything else a playlist names, served as is.
    #[serde(skip)]
    Part,
}

/// The longest playlist read; YouTube's are a few kilobytes.
const MAX_PLAYLIST: u64 = 4 << 20;

/// Answers one GET for [target], an HLS playlist or part. [register] gives
/// the loopback address that serves another [Target].
pub fn serve(
    writer: &mut TcpStream,
    target: &Target,
    fetch: &dyn Fetch,
    register: &dyn Fn(Target) -> Option<String>,
    log: &dyn Fn(String),
) {
    let (status, mut body) = match fetch.get(target, &target.url) {
        Ok(reply) => reply,
        Err(e) => {
            log(format!("HLS relay could not fetch: {e}"));
            let _ = writer.write_all(
                b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            );
            return;
        }
    };
    if !(200..300).contains(&status) {
        log(format!("HLS relay: YouTube answered {status}"));
        let _ = write!(
            writer,
            "HTTP/1.1 {status} Upstream Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        );
        return;
    }
    if target.hls == Hls::Playlist {
        let mut bytes = Vec::new();
        if (&mut body)
            .take(MAX_PLAYLIST)
            .read_to_end(&mut bytes)
            .is_err()
        {
            let _ = writer.write_all(
                b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            );
            return;
        }
        let text = rewrite(
            &String::from_utf8_lossy(&bytes),
            &target.url,
            &|url, hls| {
                register(Target {
                    url: url.to_string(),
                    size: 0,
                    user_agent: target.user_agent.clone(),
                    mime: None,
                    proxy: target.proxy.clone(),
                    chunk: target.chunk,
                    live: None,
                    hls,
                })
            },
        );
        let _ = write!(
            writer,
            "HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\nContent-Length: {}\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n",
            text.len()
        );
        let _ = writer.write_all(text.as_bytes());
        return;
    }
    // A part's length is not known ahead; the reply ends where the
    // connection does.
    let mime = target.mime.as_deref().unwrap_or("application/octet-stream");
    if write!(
        writer,
        "HTTP/1.1 200 OK\r\nContent-Type: {mime}\r\nConnection: close\r\n\r\n"
    )
    .is_err()
    {
        return;
    }
    if let Err(e) = std::io::copy(&mut body, writer) {
        log(format!("HLS relay stopped a segment: {e}"));
    }
}

/// [playlist], read from [base], with every address in it replaced by
/// what [register] gives for it; one it gives none for stays as it was.
pub fn rewrite(
    playlist: &str,
    base: &str,
    register: &dyn Fn(&str, Hls) -> Option<String>,
) -> String {
    let base = reqwest::Url::parse(base).ok();
    let resolve = |reference: &str| -> Option<String> {
        let url = match &base {
            Some(base) => base.join(reference).ok()?,
            None => reqwest::Url::parse(reference).ok()?,
        };
        matches!(url.scheme(), "http" | "https").then(|| url.to_string())
    };
    let mut out = String::with_capacity(playlist.len() * 2);
    // The next address is a playlist: it follows #EXT-X-STREAM-INF.
    let mut variant = false;
    for line in playlist.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            out.push_str(line);
        } else if let Some(tag) = trimmed.strip_prefix('#') {
            if tag.starts_with("EXT-X-STREAM-INF") {
                variant = true;
            }
            out.push_str(&rewrite_uri_attribute(trimmed, &|reference| {
                let url = resolve(reference)?;
                let kind = if tag.starts_with("EXT-X-MEDIA") || tag.starts_with("EXT-X-I-FRAME") {
                    Hls::Playlist
                } else {
                    Hls::Part
                };
                register(&url, kind)
            }));
        } else {
            let kind = if variant || looks_like_playlist(trimmed) {
                Hls::Playlist
            } else {
                Hls::Part
            };
            variant = false;
            match resolve(trimmed).and_then(|url| register(&url, kind)) {
                Some(address) => out.push_str(&address),
                None => out.push_str(line),
            }
        }
        out.push('\n');
    }
    out
}

fn looks_like_playlist(reference: &str) -> bool {
    let path = reference.split(['?', '#']).next().unwrap_or_default();
    path.ends_with(".m3u8") || path.ends_with(".m3u")
}

/// [line] with the value of its `URI="…"` attribute replaced, when
/// [replace] gives one.
fn rewrite_uri_attribute(line: &str, replace: &dyn Fn(&str) -> Option<String>) -> String {
    let Some(at) = line.find("URI=\"") else {
        return line.to_string();
    };
    let start = at + 5;
    let Some(length) = line[start..].find('"') else {
        return line.to_string();
    };
    let reference = &line[start..start + length];
    match replace(reference) {
        Some(address) => format!("{}{}{}", &line[..start], address, &line[start + length..]),
        None => line.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    #[test]
    fn rewrites_every_address() {
        let master = "#EXTM3U\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\",URI=\"audio/index.m3u8\"\n#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS=\"avc1\"\nhttps://manifest.googlevideo.com/api/manifest/hls_playlist/id/x/playlist/index\n\n#EXT-X-STREAM-INF:BANDWIDTH=2\nlow/index.m3u8?a=1\n";
        let seen = Mutex::new(Vec::new());
        let text = rewrite(
            master,
            "https://manifest.googlevideo.com/api/manifest/hls_variant/id/x/file/index.m3u8",
            &|url, kind| {
                seen.lock().unwrap().push((url.to_string(), kind));
                Some(format!("http://127.0.0.1:1/{}", seen.lock().unwrap().len()))
            },
        );
        let seen = seen.into_inner().unwrap();
        assert_eq!(
            seen,
            vec![
                (
                    "https://manifest.googlevideo.com/api/manifest/hls_variant/id/x/file/audio/index.m3u8".to_string(),
                    Hls::Playlist
                ),
                (
                    "https://manifest.googlevideo.com/api/manifest/hls_playlist/id/x/playlist/index".to_string(),
                    Hls::Playlist
                ),
                (
                    "https://manifest.googlevideo.com/api/manifest/hls_variant/id/x/file/low/index.m3u8?a=1".to_string(),
                    Hls::Playlist
                ),
            ]
        );
        assert_eq!(
            text,
            "#EXTM3U\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\",URI=\"http://127.0.0.1:1/1\"\n#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS=\"avc1\"\nhttp://127.0.0.1:1/2\n\n#EXT-X-STREAM-INF:BANDWIDTH=2\nhttp://127.0.0.1:1/3\n"
        );

        let media = "#EXTM3U\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:100\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://k.example/key\"\n#EXTINF:5.0,\nhttps://rr1---sn-x.googlevideo.com/videoplayback/id/x/sq/100/file/seg.ts\n#EXTINF:5.0,\nskd://not-http\n";
        let kinds = Mutex::new(Vec::new());
        let text = rewrite(media, "https://m.example/p/index.m3u8", &|url, kind| {
            kinds.lock().unwrap().push((url.to_string(), kind));
            Some("L".into())
        });
        assert_eq!(
            kinds.into_inner().unwrap(),
            vec![
                ("https://m.example/p/init.mp4".to_string(), Hls::Part),
                ("https://k.example/key".to_string(), Hls::Part),
                (
                    "https://rr1---sn-x.googlevideo.com/videoplayback/id/x/sq/100/file/seg.ts"
                        .to_string(),
                    Hls::Part
                ),
            ]
        );
        assert!(text.contains("#EXT-X-MAP:URI=\"L\"\n"), "{text}");
        assert!(
            text.contains("#EXT-X-KEY:METHOD=AES-128,URI=\"L\"\n"),
            "{text}"
        );
        assert!(text.contains("#EXTINF:5.0,\nL\n"), "{text}");
        assert!(text.contains("skd://not-http"), "{text}");
        assert!(text.contains("#EXT-X-MEDIA-SEQUENCE:100\n"), "{text}");
    }
}
