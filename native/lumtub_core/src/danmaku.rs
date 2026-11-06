//! Chat messages flying across the picture (弹幕), laid out here and drawn
//! by mpv's libass through `osd-overlay`, so Flutter repaints nothing.
//!
//! Each message gets a lane when it is added, the way niconico and
//! Bilibili lay theirs out: a lane takes a new message only once the one
//! before it has fully come in and cannot be caught up before it leaves.
//! A message no lane can take is dropped rather than drawn over another.
//! [Danmaku::frame] then writes the messages on screen at a moment as ASS
//! events with absolute positions, for an overlay [WIDTH] × [HEIGHT].
//!
//! A message with emoji is drawn by the app as a picture instead, since
//! libass draws neither pictures nor colour glyphs: it comes with its
//! measured width and a picture id, and the frame names where that picture
//! goes on a line of its own, `!id x y`, which no ASS event starts with.

use std::ffi::c_char;

use serde::Deserialize;

use crate::taste::{give, text};

pub const WIDTH: f64 = 1920.0;
pub const HEIGHT: f64 = 1080.0;

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// Text height at [HEIGHT].
    pub font_size: f64,
    /// How long a message takes to cross the picture.
    pub duration_ms: f64,
    /// The share of the picture's height lanes may use, from the top.
    pub area: f64,
    /// 0 (invisible) to 1.
    pub opacity: f64,
    /// The font family, bold.
    pub font: String,
}

impl Default for Settings {
    fn default() -> Self {
        Settings { font_size: 44.0, duration_ms: 12000.0, area: 0.5, opacity: 0.85, font: "Microsoft YaHei".into() }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct Message {
    pub start_ms: f64,
    pub text: String,
    /// Paid messages and stickers stand out in gold.
    #[serde(default)]
    pub paid: bool,
    /// Drawn by the app as this picture, [width] wide at [HEIGHT].
    #[serde(default)]
    pub picture: Option<u32>,
    #[serde(default)]
    pub width: Option<f64>,
}

#[derive(Debug, Clone)]
struct Placed {
    start: f64,
    width: f64,
    lane: usize,
    text: String,
    paid: bool,
    picture: Option<u32>,
}

pub struct Danmaku {
    settings: Settings,
    /// By start time.
    placed: Vec<Placed>,
    /// The last message placed in each lane.
    lanes: Vec<Option<(f64, f64)>>,
}

/// About how wide [text] is drawn at [size]: full width for CJK, kana,
/// hangul and emoji, a little over half for the rest.
pub fn text_width(text: &str, size: f64) -> f64 {
    text.chars()
        .map(|c| {
            let code = c as u32;
            let wide = (0x1100..=0x115F).contains(&code)
                || (0x2E80..=0xA4CF).contains(&code)
                || (0xAC00..=0xD7A3).contains(&code)
                || (0xF900..=0xFAFF).contains(&code)
                || (0xFE30..=0xFE4F).contains(&code)
                || (0xFF00..=0xFF60).contains(&code)
                || (0xFFE0..=0xFFE6).contains(&code)
                || code >= 0x1F300;
            if wide {
                size
            } else if c == ' ' {
                size * 0.3
            } else {
                size * 0.6
            }
        })
        .sum()
}

/// [text] as ASS shows it literally: braces would start override tags and
/// a backslash an escape, so both are swapped for look-alikes.
fn literal(text: &str) -> String {
    text.chars()
        .map(|c| match c {
            '{' => '｛',
            '}' => '｝',
            '\\' => '＼',
            '\n' | '\r' => ' ',
            c => c,
        })
        .collect()
}

impl Danmaku {
    pub fn new(settings: Settings) -> Self {
        let line = settings.font_size * 1.25;
        let count = ((HEIGHT * settings.area.clamp(0.1, 1.0)) / line).floor().max(1.0) as usize;
        Danmaku { settings, placed: Vec::new(), lanes: vec![None; count] }
    }

    fn speed(&self, width: f64) -> f64 {
        (WIDTH + width) / self.settings.duration_ms
    }

    /// Whether a message [width] wide starting at [start] may follow the one
    /// last placed in a lane, which started at [before] and is [before_width]
    /// wide: that one has fully come in, and leaves before this one, faster
    /// when longer, reaches the left edge.
    fn fits(&self, before: (f64, f64), start: f64, width: f64) -> bool {
        let (before_start, before_width) = before;
        let came_in = before_start + (before_width + self.settings.font_size * 0.5) / self.speed(before_width);
        let leaves = before_start + self.settings.duration_ms;
        let reaches_left = start + WIDTH / self.speed(width);
        start >= came_in && reaches_left >= leaves
    }

    /// Lays [message] out. False when every lane is busy and it is dropped.
    pub fn add(&mut self, message: Message) -> bool {
        let text = literal(message.text.trim());
        if text.is_empty() {
            return false;
        }
        let width = match (message.picture, message.width) {
            (Some(_), Some(width)) if width.is_finite() && width > 0.0 => width,
            _ => text_width(&text, self.settings.font_size),
        };
        let start = message.start_ms;
        let lane = (0..self.lanes.len()).find(|&i| self.lanes[i].is_none_or(|before| self.fits(before, start, width)));
        let Some(lane) = lane else { return false };
        self.lanes[lane] = Some((start, width));
        let at = self.placed.partition_point(|p| p.start <= start);
        self.placed.insert(at, Placed { start, width, lane, text, paid: message.paid, picture: message.picture });
        true
    }

    /// Forgets messages that left the picture before [now], for a chat that
    /// keeps growing.
    pub fn forget_before(&mut self, now: f64) {
        let gone = self.placed.partition_point(|p| p.start + self.settings.duration_ms < now);
        self.placed.drain(..gone);
    }

    /// The messages on screen at [now], one ASS event or picture per line;
    /// a picture's line is `!id x y`, its top left corner at [HEIGHT], the
    /// top of its lane.
    pub fn frame(&self, now: f64) -> String {
        let duration = self.settings.duration_ms;
        let first = self.placed.partition_point(|p| p.start + duration <= now);
        let opacity = self.settings.opacity.clamp(0.0, 1.0);
        let alpha = ((1.0 - opacity) * 255.0).round() as u8;
        // A thin, lighter outline like Bilibili's, so the text reads on a
        // bright picture without a heavy dark edge around it.
        let edge = ((1.0 - opacity * 0.6) * 255.0).round() as u8;
        let size = self.settings.font_size;
        let line = size * 1.25;
        let border = (size / 30.0).max(1.0);
        let mut out = String::new();
        // An override tag ends at '}' and '\\' starts the next one.
        let font: String = self.settings.font.chars().filter(|c| !matches!(c, '{' | '}' | '\\' | '\n' | '\r')).collect();
        for p in &self.placed[first..] {
            if p.start > now {
                break;
            }
            let x = WIDTH - (now - p.start) * self.speed(p.width);
            if let Some(id) = p.picture {
                out.push_str(&format!("!{id} {x:.1} {:.1}\n", p.lane as f64 * line));
                continue;
            }
            let y = p.lane as f64 * line + (line - size) / 2.0;
            let colour = if p.paid { "&H38C8FF&" } else { "&HFFFFFF&" };
            out.push_str(&format!(
                "{{\\an7\\pos({x:.1},{y:.1})\\fn{font}\\b1\\fs{size:.0}\\bord{border:.1}\\shad0\\blur0.6\\1c{colour}\\3c&H000000&\\1a&H{alpha:02X}&\\3a&H{edge:02X}&\\4a&HFF&\\q2}}{}\n",
                p.text
            ));
        }
        out
    }
}

/// A [Danmaku] for Dart, from [Settings] as JSON. Free it with
/// `lumtub_danmaku_free`.
///
/// # Safety
/// [settings] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_danmaku_new(settings: *const u8, length: usize) -> *mut Danmaku {
    let settings = serde_json::from_str(unsafe { text(settings, length) }).unwrap_or_default();
    Box::into_raw(Box::new(Danmaku::new(settings)))
}

/// Adds messages, `[{"start_ms": 0, "text": "…", "paid": false}, …]` in the
/// order they were sent, a picture's with `"picture": id, "width": w`, and
/// returns how many found a lane.
///
/// # Safety
/// [danmaku] must come from `lumtub_danmaku_new`; [messages] must point to
/// [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_danmaku_add(danmaku: *mut Danmaku, messages: *const u8, length: usize) -> u32 {
    let Some(danmaku) = (unsafe { danmaku.as_mut() }) else { return 0 };
    let messages: Vec<Message> = serde_json::from_str(unsafe { text(messages, length) }).unwrap_or_default();
    messages.into_iter().map(|m| danmaku.add(m) as u32).sum()
}

/// The ASS events and pictures on screen at [now_ms]; forgets the ones gone when
/// [forget] is true. Free the text with `lumtub_string_free`.
///
/// # Safety
/// [danmaku] must come from `lumtub_danmaku_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_danmaku_frame(danmaku: *mut Danmaku, now_ms: f64, forget: bool) -> *mut c_char {
    let Some(danmaku) = (unsafe { danmaku.as_mut() }) else { return give(String::new()) };
    if forget {
        danmaku.forget_before(now_ms);
    }
    give(danmaku.frame(now_ms))
}

/// # Safety
/// [danmaku] must come from `lumtub_danmaku_new` and not be used after.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_danmaku_free(danmaku: *mut Danmaku) {
    if !danmaku.is_null() {
        drop(unsafe { Box::from_raw(danmaku) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn message(start_ms: f64, text: &str) -> Message {
        Message { start_ms, text: text.into(), paid: false, picture: None, width: None }
    }

    #[test]
    fn a_message_crosses_from_the_right_edge_to_past_the_left() {
        let mut d = Danmaku::new(Settings::default());
        assert!(d.add(message(1000.0, "hello")));
        assert_eq!(d.frame(999.0), "");
        assert!(d.frame(1000.0).contains("\\pos(1920.0,"));
        let width = text_width("hello", 44.0);
        let end = d.frame(12999.0);
        let x: f64 = end.split("\\pos(").nth(1).unwrap().split(',').next().unwrap().parse().unwrap();
        assert!(x < -width + 1.0, "{x}");
        assert_eq!(d.frame(13000.0), "");
    }

    #[test]
    fn messages_at_once_take_lanes_down_the_picture() {
        let mut d = Danmaku::new(Settings::default());
        for i in 0..3 {
            assert!(d.add(message(0.0, &format!("m{i}"))));
        }
        let frame = d.frame(10.0);
        let ys: Vec<f64> = frame.lines().map(|l| l.split(',').nth(1).unwrap().split(')').next().unwrap().parse().unwrap()).collect();
        assert_eq!(ys.len(), 3);
        assert!(ys[0] < ys[1] && ys[1] < ys[2]);
    }

    #[test]
    fn a_lane_is_reused_once_the_message_before_has_come_in() {
        let mut d = Danmaku::new(Settings { area: 0.05, ..Settings::default() });
        assert!(d.add(message(0.0, "first")));
        assert!(!d.add(message(10.0, "too soon")));
        assert!(d.add(message(3000.0, "later")));
    }

    #[test]
    fn a_full_picture_drops_messages_instead_of_overlapping() {
        let mut d = Danmaku::new(Settings::default());
        let lanes = d.lanes.len();
        let placed = (0..lanes + 5).filter(|i| d.add(message(0.0, &format!("m{i}")))).count();
        assert_eq!(placed, lanes);
    }

    #[test]
    fn override_characters_are_shown_as_text() {
        let mut d = Danmaku::new(Settings::default());
        d.add(message(0.0, "{\\b1}hi\\N"));
        let frame = d.frame(0.0);
        assert!(frame.ends_with("｛＼b1｝hi＼N\n"), "{frame}");
    }

    #[test]
    fn forgetting_keeps_what_is_still_on_screen() {
        let mut d = Danmaku::new(Settings::default());
        d.add(message(0.0, "old"));
        d.add(message(5000.0, "new"));
        d.forget_before(13000.0);
        assert_eq!(d.placed.len(), 1);
        assert!(d.frame(13000.0).contains("new"));
    }

    #[test]
    fn a_picture_is_placed_with_its_own_width_and_named_on_its_own_line() {
        let mut d = Danmaku::new(Settings::default());
        assert!(d.add(Message { start_ms: 0.0, text: ":wave: hi".into(), paid: false, picture: Some(7), width: Some(300.0) }));
        assert!(d.add(message(0.0, "plain")));
        assert_eq!(d.placed[0].width, 300.0);
        let frame = d.frame(1200.0);
        let mut lines = frame.lines();
        let x = WIDTH - 1200.0 * (WIDTH + 300.0) / 12000.0;
        assert_eq!(lines.next().unwrap(), format!("!7 {x:.1} 0.0"));
        assert!(lines.next().unwrap().starts_with("{\\an7"));
    }
}
