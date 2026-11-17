//! A channel's public Atom feed (`/feeds/videos.xml?channel_id=`): its
//! latest uploads with their publish times. The format is small and
//! fixed, so a scanner over the entries is enough; every XML character
//! reference is decoded, named or numeric, and CDATA is read as text.

use serde::Serialize;
use std::os::raw::c_char;

use crate::taste::{give_json, text};

#[derive(Debug, Serialize, PartialEq)]
pub struct FeedVideo {
    pub id: String,
    pub title: String,
    pub author: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub views: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub published: Option<String>,
    /// Shorts link to /shorts/; nothing else in the feed tells them apart.
    pub short: bool,
}

/// The entries of [xml], in feed order. Entries without a valid video id
/// are left out.
pub fn parse(xml: &str) -> Vec<FeedVideo> {
    let mut videos = Vec::new();
    let mut rest = xml;
    while let Some(start) = rest.find("<entry>") {
        rest = &rest[start + "<entry>".len()..];
        let Some(end) = rest.find("</entry>") else {
            break;
        };
        let entry = &rest[..end];
        rest = &rest[end + "</entry>".len()..];
        let Some(id) = element(entry, "yt:videoId").map(|id| id.trim().to_string()) else {
            continue;
        };
        if id.len() != 11
            || !id
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
        {
            continue;
        }
        let author = entry
            .find("<author>")
            .and_then(|at| element(&entry[at..], "name"))
            .map(decode)
            .unwrap_or_default();
        videos.push(FeedVideo {
            id,
            title: element(entry, "title").map(decode).unwrap_or_default(),
            author,
            views: attribute(entry, "media:statistics", "views").and_then(|v| v.parse().ok()),
            published: element(entry, "published")
                .map(|p| p.trim().to_string())
                .filter(|p| !p.is_empty()),
            short: links(entry).any(|href| href.starts_with("https://www.youtube.com/shorts/")),
        });
    }
    videos
}

/// The raw content of the first `<name>…</name>` (with or without
/// attributes) in [xml].
fn element<'a>(xml: &'a str, name: &str) -> Option<&'a str> {
    let mut rest = xml;
    loop {
        let at = rest.find('<')?;
        rest = &rest[at + 1..];
        let Some(after) = rest.strip_prefix(name) else {
            continue;
        };
        match after.as_bytes().first() {
            Some(b'>') => {
                let body = &after[1..];
                return Some(&body[..body.find(&format!("</{name}>"))?]);
            }
            Some(b' ' | b'\t' | b'\n' | b'\r') => {
                let close = after.find('>')?;
                if after[..close].ends_with('/') {
                    return Some("");
                }
                let body = &after[close + 1..];
                return Some(&body[..body.find(&format!("</{name}>"))?]);
            }
            _ => {}
        }
    }
}

/// The value of [attribute] on the first `<name …>` tag in [xml].
fn attribute(xml: &str, name: &str, attribute: &str) -> Option<String> {
    tags(xml, name).next().and_then(|tag| value(tag, attribute))
}

/// The inside of each `<name …>` tag.
fn tags<'a>(xml: &'a str, name: &'a str) -> impl Iterator<Item = &'a str> + 'a {
    let open = format!("<{name} ");
    let mut rest = xml;
    std::iter::from_fn(move || {
        let at = rest.find(&open)?;
        let tag = &rest[at + open.len()..];
        let end = tag.find('>')?;
        rest = &tag[end..];
        Some(&tag[..end])
    })
}

fn links(entry: &str) -> impl Iterator<Item = String> + '_ {
    tags(entry, "link")
        .filter(|tag| value(tag, "rel").as_deref() == Some("alternate"))
        .filter_map(|tag| value(tag, "href"))
}

fn value(tag: &str, attribute: &str) -> Option<String> {
    let mut rest = tag;
    loop {
        let at = rest.find(attribute)?;
        let before = rest[..at].chars().last();
        let after = rest[at + attribute.len()..].trim_start();
        rest = &rest[at + attribute.len()..];
        if before.is_some_and(|c| !c.is_whitespace()) {
            continue;
        }
        let Some(after) = after.strip_prefix('=') else {
            continue;
        };
        let after = after.trim_start();
        let quote = after.chars().next().filter(|c| *c == '"' || *c == '\'')?;
        let body = &after[1..];
        return Some(decode(&body[..body.find(quote)?]));
    }
}

/// [raw] as text: CDATA kept as it is, character references decoded,
/// and the ends trimmed.
pub fn decode(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut rest = raw;
    while !rest.is_empty() {
        if let Some(cdata) = rest.strip_prefix("<![CDATA[") {
            let end = cdata.find("]]>").unwrap_or(cdata.len());
            out.push_str(&cdata[..end]);
            rest = cdata.get(end + 3..).unwrap_or("");
            continue;
        }
        let Some(amp) = rest.find(['&', '<']) else {
            out.push_str(rest);
            break;
        };
        out.push_str(&rest[..amp]);
        rest = &rest[amp..];
        if rest.starts_with('<') {
            if rest.starts_with("<![CDATA[") {
                continue;
            }
            out.push('<');
            rest = &rest[1..];
            continue;
        }
        let reference = rest[1..]
            .find(';')
            .filter(|end| *end <= 10)
            .map(|end| &rest[1..=end]);
        match reference.and_then(character) {
            Some(c) => {
                out.push(c);
                rest = &rest[reference.map_or(1, |r| r.len() + 2)..];
            }
            None => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.trim().to_string()
}

fn character(reference: &str) -> Option<char> {
    match reference {
        "lt" => Some('<'),
        "gt" => Some('>'),
        "amp" => Some('&'),
        "quot" => Some('"'),
        "apos" => Some('\''),
        _ => {
            let number = reference.strip_prefix('#')?;
            let code = match number.strip_prefix(['x', 'X']) {
                Some(hex) => u32::from_str_radix(hex, 16).ok()?,
                None => number.parse().ok()?,
            };
            char::from_u32(code).filter(|c| *c != '\0')
        }
    }
}

/// [parse] for Dart: the feed's XML in, `[{id, title, author, views?,
/// published?, short}]` out. Free it with `lumtub_string_free`.
///
/// # Safety
/// [xml] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_channel_feed(xml: *const u8, length: usize) -> *mut c_char {
    give_json(&parse(unsafe { text(xml, length) }))
}

#[cfg(test)]
mod tests {
    use super::*;

    const FEED: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
 <title>Channel</title>
 <author><name>Feed owner</name></author>
 <entry>
  <id>yt:video:abcdefghijk</id>
  <yt:videoId>abcdefghijk</yt:videoId>
  <title>Tom &amp; Jerry &#8217;s &#x4E2D;&#25991; &lt;b&gt;</title>
  <link rel="alternate" href="https://www.youtube.com/watch?v=abcdefghijk"/>
  <author><name>A &quot;B&quot;</name></author>
  <published>2026-11-01T10:00:00+00:00</published>
  <media:group><media:community><media:statistics views="1234"/></media:community></media:group>
 </entry>
 <entry>
  <yt:videoId>ABC-def_123</yt:videoId>
  <title><![CDATA[Short & sweet]]></title>
  <link rel="alternate" href="https://www.youtube.com/shorts/ABC-def_123"/>
  <published>2026-11-02T10:00:00+00:00</published>
 </entry>
 <entry><yt:videoId>bad</yt:videoId><title>x</title></entry>
</feed>"#;

    #[test]
    fn reads_entries() {
        let videos = parse(FEED);
        assert_eq!(videos.len(), 2);
        assert_eq!(videos[0].id, "abcdefghijk");
        assert_eq!(videos[0].title, "Tom & Jerry ’s 中文 <b>");
        assert_eq!(videos[0].author, "A \"B\"");
        assert_eq!(videos[0].views, Some(1234));
        assert_eq!(
            videos[0].published.as_deref(),
            Some("2026-11-01T10:00:00+00:00")
        );
        assert!(!videos[0].short);
        assert_eq!(videos[1].title, "Short & sweet");
        assert!(videos[1].short);
        assert_eq!(videos[1].views, None);
        assert_eq!(videos[1].author, "");
    }

    #[test]
    fn odd_text_is_kept() {
        assert_eq!(
            decode("a & b &unknown; &#0; &#xZZ;"),
            "a & b &unknown; &#0; &#xZZ;"
        );
        assert_eq!(decode("<![CDATA[unclosed"), "unclosed");
        assert!(parse("<entry><yt:videoId>abcdefghijk").is_empty());
        assert!(parse("").is_empty());
    }
}
