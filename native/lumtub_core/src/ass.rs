//! Styled subtitles for a downloaded file: an ASS file the app wrote from
//! its subtitle settings, carried as an ASS track in Matroska, and as much
//! of its look as `tx3g` holds (font, size, color, bold) in MP4.

/// What a style of the ASS file looks like.
#[derive(Clone, Debug, PartialEq)]
pub struct Look {
    pub font: String,
    /// In the file's units, with `PlayResY` lines from top to bottom.
    pub size: f64,
    /// RGBA.
    pub color: u32,
    pub bold: bool,
}

/// An ASS file read for a track.
#[derive(Clone, Debug, Default)]
pub struct Styled {
    /// Everything before the first event: Matroska's CodecPrivate.
    pub header: String,
    /// Each event as Matroska stores it: `ReadOrder,Layer,Style,Name,
    /// MarginL,MarginR,MarginV,Effect,Text`, with its start and end in ms.
    pub events: Vec<(u64, u64, String)>,
    /// `Default`, and `Second` for a bilingual track's other language.
    pub main: Option<Look>,
    pub second: Option<Look>,
    pub play_res_y: f64,
}

/// `h:mm:ss.cc` in ms.
fn time(text: &str) -> Option<u64> {
    let mut parts = text.trim().split(':');
    let (h, m, s) = (parts.next()?, parts.next()?, parts.next()?);
    let (s, cs) = s.split_once('.').unwrap_or((s, "0"));
    let cs: u64 = format!("{cs:0<2}")[..2].parse().ok()?;
    Some(
        ((h.parse::<u64>().ok()? * 60 + m.parse::<u64>().ok()?) * 60 + s.parse::<u64>().ok()?)
            * 1000
            + cs * 10,
    )
}

/// `&HAABBGGRR` as RGBA.
fn color(text: &str) -> Option<u32> {
    let hex = text
        .trim()
        .trim_start_matches("&H")
        .trim_start_matches("&h")
        .trim_end_matches('&');
    let abgr = u32::from_str_radix(hex, 16).ok()?;
    let (a, b, g, r) = (
        abgr >> 24,
        (abgr >> 16) & 0xFF,
        (abgr >> 8) & 0xFF,
        abgr & 0xFF,
    );
    Some(r << 24 | g << 16 | b << 8 | (255 - a))
}

/// The ASS file in `source`, or None when it holds no events.
pub fn parse(source: &str) -> Option<Styled> {
    let source = source.replace("\r\n", "\n");
    let mut out = Styled {
        play_res_y: 288.0,
        ..Styled::default()
    };
    let mut header_end = None;
    let mut format: Vec<String> = Vec::new();
    let mut offset = 0;
    for line in source.split('\n') {
        let start = offset;
        offset += line.len() + 1;
        if let Some(value) = line.strip_prefix("PlayResY:") {
            out.play_res_y = value.trim().parse().unwrap_or(288.0);
        } else if let Some(value) = line.strip_prefix("Format:") {
            format = value
                .split(',')
                .map(|f| f.trim().to_ascii_lowercase())
                .collect();
        } else if let Some(value) = line.strip_prefix("Style:") {
            let fields: Vec<&str> = value.split(',').map(str::trim).collect();
            let field = |name: &str| {
                format
                    .iter()
                    .position(|f| f == name)
                    .and_then(|i| fields.get(i).copied())
            };
            let look = Look {
                font: field("fontname").unwrap_or("").to_string(),
                size: field("fontsize")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(18.0),
                color: field("primarycolour")
                    .and_then(color)
                    .unwrap_or(0xFFFF_FFFF),
                bold: field("bold").is_some_and(|b| b != "0"),
            };
            match field("name") {
                Some("Default") => out.main = Some(look),
                Some("Second") => out.second = Some(look),
                _ => {}
            }
        } else if let Some(value) = line.strip_prefix("Dialogue:") {
            header_end.get_or_insert(start);
            let fields: Vec<&str> = value.trim_start().splitn(10, ',').collect();
            if fields.len() < 10 {
                continue;
            }
            let (Some(from), Some(to)) = (time(fields[1]), time(fields[2])) else {
                continue;
            };
            if to <= from {
                continue;
            }
            let rest = [
                fields[0], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8],
                fields[9],
            ]
            .join(",");
            out.events.push((from, to, rest));
        }
    }
    out.header = source[..header_end?].to_string();
    out.events.sort_by_key(|e| e.0);
    for (i, event) in out.events.iter_mut().enumerate() {
        event.2 = format!("{i},{}", event.2);
    }
    (!out.events.is_empty()).then_some(out)
}

/// An event's text without override tags, and the character from which
/// the `Second` style (`{\rSecond}`) applies.
pub fn plain(event: &str) -> (String, Option<usize>) {
    let text = event.splitn(9, ',').nth(8).unwrap_or("");
    let mut out = String::new();
    let mut second = None;
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '{' => {
                let mut tag = String::new();
                for d in chars.by_ref() {
                    if d == '}' {
                        break;
                    }
                    tag.push(d);
                }
                if tag.contains("\\rSecond") {
                    second = Some(out.chars().count());
                }
            }
            '\\' if matches!(chars.peek(), Some('N' | 'n')) => {
                chars.next();
                out.push('\n');
            }
            '\\' if chars.peek() == Some(&'h') => {
                chars.next();
                out.push('\u{a0}');
            }
            _ => out.push(c),
        }
    }
    (out, second)
}

/// The tx3g font size for `look`: ffmpeg and VLC draw tx3g on a canvas
/// 288 lines tall.
pub fn tx3g_size(look: &Look, play_res_y: f64) -> u8 {
    (look.size * 288.0 / play_res_y.max(1.0))
        .round()
        .clamp(6.0, 255.0) as u8
}

/// A `styl` box giving characters `from..to` of a sample `look`.
pub fn styl(from: usize, to: usize, look: &Look, play_res_y: f64) -> Vec<u8> {
    let mut out = Vec::with_capacity(24);
    out.extend_from_slice(&22u32.to_be_bytes());
    out.extend_from_slice(b"styl");
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&(from.min(u16::MAX as usize) as u16).to_be_bytes());
    out.extend_from_slice(&(to.min(u16::MAX as usize) as u16).to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out.push(u8::from(look.bold));
    out.push(tx3g_size(look, play_res_y));
    out.extend_from_slice(&look.color.to_be_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const FILE: &str = "[Script Info]\nScriptType: v4.00+\nPlayResX: 1280\nPlayResY: 720\n\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\nStyle: Default,Microsoft YaHei,40.00,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,2.00,0,2,25,25,30,1\nStyle: Second,Segoe UI,30.00,&H1A00E7FF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2.00,0,2,25,25,30,1\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:03.50,0:00:05.00,Default,,0,0,0,,世界\\N{\\rSecond}world, again\nDialogue: 0,0:00:01.00,0:00:02.25,Default,,0,0,0,,你好\n";

    #[test]
    fn reads_styles_and_events_in_time_order() {
        let styled = parse(FILE).unwrap();
        assert!(styled.header.ends_with("Effect, Text\n"));
        assert!(styled.header.starts_with("[Script Info]"));
        assert_eq!(
            styled.events[0],
            (1000, 2250, "0,0,Default,,0,0,0,,你好".to_string())
        );
        assert_eq!(styled.events[1].0, 3500);
        assert_eq!(
            styled.events[1].2,
            "1,0,Default,,0,0,0,,世界\\N{\\rSecond}world, again"
        );
        let main = styled.main.unwrap();
        assert_eq!(
            (main.font.as_str(), main.size, main.color, main.bold),
            ("Microsoft YaHei", 40.0, 0xFFFF_FFFF, true)
        );
        let second = styled.second.unwrap();
        assert_eq!((second.color, second.bold), (0xFFE7_00E5, false));
        assert_eq!(tx3g_size(&second, styled.play_res_y), 12);
    }

    #[test]
    fn plain_text_marks_where_the_second_language_starts() {
        assert_eq!(
            plain("1,0,Default,,0,0,0,,世界\\N{\\rSecond}world, again"),
            ("世界\nworld, again".to_string(), Some(3))
        );
        assert_eq!(
            plain("0,0,Default,,0,0,0,,{\\rSecond}only"),
            ("only".to_string(), Some(0))
        );
        assert_eq!(
            plain("0,0,Default,,0,0,0,,a\\hb"),
            ("a\u{a0}b".to_string(), None)
        );
    }

    #[test]
    fn nothing_without_events() {
        assert!(parse("[Script Info]\n").is_none());
    }
}
