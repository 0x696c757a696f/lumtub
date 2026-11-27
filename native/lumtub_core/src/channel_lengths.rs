//! Sorting a channel tab by length (按时长排序): YouTube has no such order, so the app reads
//! the tab newest first and the videos are ordered here. What was read is
//! kept in the cache folder, one file per channel tab, so the next time
//! only the uploads since then are read: the newest-first listing stops at
//! the first videos it already knows.
//!
//! Each file is bounded ([MAX_FILE] bytes, [MAX_ITEMS] videos, items of at
//! most [MAX_ITEM] bytes) and the folder keeps the [MAX_FILES] channel tabs
//! used last. A file is named only from a checked channel id and a tab from
//! a fixed list, so no name reaches outside the folder; it is written to a
//! temporary file first and renamed over the old one, so a crash leaves
//! either the old file or the new one.
//!
//! Merging is linear (one hash set of ids), ordering O(n log n) on a key
//! worked out once per video; the order is stable, so videos of the same
//! length stay newest first.

use serde::{Deserialize, Serialize};
use serde_json::value::RawValue;
use std::collections::HashSet;
use std::fs;
use std::io::{Read, Write};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};

use crate::taste::{give_json, text};

/// Videos kept for one channel tab.
pub const MAX_ITEMS: usize = 20_000;
/// The most one video's saved entry may take.
pub const MAX_ITEM: usize = 8 * 1024;
/// The most one file may take; a bigger one is not read.
pub const MAX_FILE: u64 = 32 * 1024 * 1024;
/// Channel tabs kept; the ones used longest ago go first.
pub const MAX_FILES: usize = 300;

const TABS: [&str; 2] = ["videos", "live"];

#[derive(Serialize, Deserialize)]
struct Saved {
    v: u32,
    /// Seconds since 1970 when the tab was last read.
    saved: u64,
    /// Whether the tab was read to its end at least once, so a video
    /// missing from it was taken down.
    #[serde(default)]
    whole: bool,
    items: Vec<Box<RawValue>>,
}

/// The part of a saved entry the order needs.
#[derive(Deserialize)]
struct Facts {
    id: String,
    #[serde(default)]
    duration: Option<f64>,
}

/// An entry with its id and length read once.
struct Entry {
    raw: Box<RawValue>,
    id: String,
    seconds: Option<u64>,
}

impl Entry {
    fn of(raw: Box<RawValue>) -> Option<Entry> {
        if raw.get().len() > MAX_ITEM {
            return None;
        }
        let facts: Facts = serde_json::from_str(raw.get()).ok()?;
        if !video_id(&facts.id) {
            return None;
        }
        let seconds = facts
            .duration
            .filter(|d| d.is_finite() && *d >= 0.0)
            .map(|d| d as u64);
        Some(Entry {
            raw,
            id: facts.id,
            seconds,
        })
    }
}

fn video_id(id: &str) -> bool {
    id.len() == 11
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// A channel id as YouTube gives them (UC… or a handle's id), nothing
/// that could name another folder.
fn channel_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// The file of [channel]'s [tab] in [dir], or None for a name that does not
/// pass.
fn file_of(dir: &Path, channel: &str, tab: &str) -> Option<PathBuf> {
    if !channel_id(channel) || !TABS.contains(&tab) {
        return None;
    }
    Some(dir.join(format!("{tab}-{channel}.json")))
}

fn read(path: &Path) -> Option<Saved> {
    let file = fs::File::open(path).ok()?;
    let meta = file.metadata().ok()?;
    if !meta.is_file() || meta.len() > MAX_FILE {
        return None;
    }
    let mut body = String::new();
    file.take(MAX_FILE).read_to_string(&mut body).ok()?;
    let saved: Saved = serde_json::from_str(&body).ok()?;
    (saved.v == 1).then_some(saved)
}

fn write(dir: &Path, path: &Path, saved: &Saved) -> std::io::Result<()> {
    fs::create_dir_all(dir)?;
    let body = serde_json::to_vec(saved)?;
    if body.len() as u64 > MAX_FILE {
        return Err(std::io::Error::other("too big"));
    }
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("tab");
    let temp = dir.join(format!(".{name}.{}.tmp", std::process::id()));
    {
        let mut file = fs::File::create(&temp)?;
        file.write_all(&body)?;
        file.sync_all()?;
    }
    fs::rename(&temp, path).inspect_err(|_| {
        let _ = fs::remove_file(&temp);
    })
}

/// Leaves the [MAX_FILES] tab files used last; [keep] is never removed.
fn prune(dir: &Path, keep: &Path) {
    let Ok(read) = fs::read_dir(dir) else { return };
    let mut files: Vec<(std::time::SystemTime, PathBuf)> = read
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_ok_and(|t| t.is_file()))
        .filter(|e| {
            e.file_name().to_str().is_some_and(|n| {
                n.ends_with(".json") && TABS.iter().any(|t| n.starts_with(&format!("{t}-")))
            })
        })
        .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
        .collect();
    if files.len() <= MAX_FILES {
        return;
    }
    files.sort_unstable_by_key(|f| std::cmp::Reverse(f.0));
    for (_, path) in files.into_iter().skip(MAX_FILES) {
        if path != keep {
            let _ = fs::remove_file(path);
        }
    }
}

/// [fresh] (newest first, as just read) followed by the saved entries not
/// in it. When [whole], the read went through the whole tab, so saved
/// entries it did not meet were taken down and are left out.
fn merge(fresh: Vec<Entry>, saved: Vec<Entry>, whole: bool) -> Vec<Entry> {
    let mut seen: HashSet<String> =
        HashSet::with_capacity(fresh.len() + if whole { 0 } else { saved.len() });
    let mut out = Vec::with_capacity(fresh.len() + if whole { 0 } else { saved.len() });
    for entry in fresh {
        if seen.insert(entry.id.clone()) {
            out.push(entry);
        }
    }
    if !whole {
        for entry in saved {
            if seen.insert(entry.id.clone()) {
                out.push(entry);
            }
        }
    }
    out.truncate(MAX_ITEMS);
    out
}

#[derive(Deserialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "snake_case")]
pub enum Order {
    Longest,
    Shortest,
}

/// The positions of [seconds] in [order]: a video of unknown length last
/// either way, ties in their given order.
pub fn order(seconds: &[Option<u64>], order: Order) -> Vec<usize> {
    let mut keys: Vec<(u8, u64, usize)> = seconds
        .iter()
        .enumerate()
        .map(|(i, s)| match (s, order) {
            (None, _) => (1, 0, i),
            (Some(s), Order::Longest) => (0, u64::MAX - s, i),
            (Some(s), Order::Shortest) => (0, *s, i),
        })
        .collect();
    // The index in the key keeps it stable without a stable sort's buffer.
    keys.sort_unstable();
    keys.into_iter().map(|(_, _, i)| i).collect()
}

/// One request from the app. A plain struct, not a tagged enum: serde
/// buffers a tagged enum's fields, which [RawValue] cannot be read from.
#[derive(Deserialize)]
struct Ask {
    /// `known`: the saved ids of a tab, newest first, and when it was read.
    /// `update`: merges [fresh] with what was saved, saves it, and gives it
    /// back in [order]. `order`: orders [fresh] without saving, when there
    /// is no cache folder.
    op: String,
    #[serde(default)]
    dir: String,
    #[serde(default)]
    channel: String,
    #[serde(default)]
    tab: String,
    #[serde(default)]
    now: u64,
    /// The read went through the whole tab.
    #[serde(default)]
    whole: bool,
    #[serde(default)]
    fresh: Vec<Box<RawValue>>,
    #[serde(default)]
    order: Option<Order>,
}

#[derive(Serialize, Default)]
struct Known {
    saved: u64,
    ids: Vec<String>,
}

fn known(dir: &str, channel: &str, tab: &str) -> Known {
    let Some(path) = file_of(Path::new(dir), channel, tab) else {
        return Known::default();
    };
    let Some(saved) = read(&path) else {
        return Known::default();
    };
    let ids = saved
        .items
        .into_iter()
        .filter_map(Entry::of)
        .map(|e| e.id)
        .collect();
    Known {
        saved: saved.saved,
        ids,
    }
}

fn ordered(entries: Vec<Entry>, by: Order) -> Vec<Box<RawValue>> {
    let seconds: Vec<Option<u64>> = entries.iter().map(|e| e.seconds).collect();
    let mut slots: Vec<Option<Entry>> = entries.into_iter().map(Some).collect();
    order(&seconds, by)
        .into_iter()
        .filter_map(|i| slots[i].take())
        .map(|e| e.raw)
        .collect()
}

fn update(
    dir: &str,
    channel: &str,
    tab: &str,
    now: u64,
    whole: bool,
    fresh: Vec<Box<RawValue>>,
    by: Order,
) -> Vec<Box<RawValue>> {
    let fresh: Vec<Entry> = fresh.into_iter().filter_map(Entry::of).collect();
    let dir = Path::new(dir);
    let Some(path) = file_of(dir, channel, tab) else {
        return ordered(fresh, by);
    };
    let before = read(&path);
    let was_whole = before.as_ref().is_some_and(|s| s.whole);
    let saved: Vec<Entry> = before
        .map(|s| s.items.into_iter().filter_map(Entry::of).collect())
        .unwrap_or_default();
    let merged = merge(fresh, saved, whole);
    let file = Saved {
        v: 1,
        saved: now,
        whole: whole || was_whole,
        items: merged.iter().map(|e| e.raw.clone()).collect(),
    };
    if write(dir, &path, &file).is_ok() {
        prune(dir, &path);
    }
    ordered(merged, by)
}

/// Each entry as the line it was saved as, for the app's listing.
fn lines(items: Vec<Box<RawValue>>) -> Vec<String> {
    items.into_iter().map(|raw| raw.get().to_owned()).collect()
}

/// One request of [Ask] as JSON; the answer is JSON, or null when the ask
/// does not parse.
///
/// # Safety
/// [json] points at [len] readable bytes of UTF-8, or is null; it is only
/// read during the call. The answer is freed with `lumtub_string_free`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_channel_lengths(json: *const u8, len: usize) -> *mut c_char {
    // SAFETY: the caller passes `len` readable bytes at `json`, or null, as
    // the `# Safety` section requires; `text` checks the UTF-8.
    let Ok(ask) = serde_json::from_str::<Ask>(unsafe { text(json, len) }) else {
        return std::ptr::null_mut();
    };
    match (ask.op.as_str(), ask.order) {
        ("known", _) => give_json(&known(&ask.dir, &ask.channel, &ask.tab)),
        ("update", Some(order)) => give_json(&lines(update(
            &ask.dir,
            &ask.channel,
            &ask.tab,
            ask.now,
            ask.whole,
            ask.fresh,
            order,
        ))),
        ("order", Some(order)) => give_json(&lines(ordered(
            ask.fresh.into_iter().filter_map(Entry::of).collect(),
            order,
        ))),
        _ => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(id: &str, seconds: Option<u64>) -> Box<RawValue> {
        let body = match seconds {
            Some(s) => format!(r#"{{"id":"{id}","title":"t","duration":{s}}}"#),
            None => format!(r#"{{"id":"{id}","title":"t"}}"#),
        };
        RawValue::from_string(body).unwrap()
    }

    fn id(n: usize) -> String {
        format!("v{n:010}")
    }

    fn ids(items: &[Box<RawValue>]) -> Vec<String> {
        items
            .iter()
            .map(|r| serde_json::from_str::<Facts>(r.get()).unwrap().id)
            .collect()
    }

    fn temp() -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "lumtub-lengths-{}-{}",
            std::process::id(),
            rand_suffix()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn rand_suffix() -> u128 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    }

    fn ask(json: &str) -> Option<String> {
        // SAFETY: `json` is a live `&str`, so its pointer and length are valid.
        let out = unsafe { lumtub_channel_lengths(json.as_ptr(), json.len()) };
        if out.is_null() {
            return None;
        }
        // SAFETY: `out` is a non-null, NUL-terminated string the export made.
        let text = unsafe { std::ffi::CStr::from_ptr(out) }
            .to_str()
            .unwrap()
            .to_owned();
        // SAFETY: `out` came from the export and is freed once, after its last use.
        unsafe { crate::taste::lumtub_string_free(out) };
        Some(text)
    }

    #[test]
    fn answers_asks_through_the_export() {
        let dir = temp();
        let d = serde_json::to_string(dir.to_str().unwrap()).unwrap();
        let update = format!(
            r#"{{"op":"update","dir":{d},"channel":"UCabc","tab":"videos","now":9,"whole":true,"order":"shortest","fresh":[{{"id":"{}","duration":50}},{{"id":"{}","duration":null}},{{"id":"{}","duration":5}}]}}"#,
            id(1),
            id(2),
            id(3)
        );
        let lines: Vec<String> = serde_json::from_str(&ask(&update).unwrap()).unwrap();
        assert_eq!(lines.len(), 3);
        assert!(
            lines[0].contains(&id(3)) && lines[1].contains(&id(1)) && lines[2].contains(&id(2))
        );
        let known = ask(&format!(
            r#"{{"op":"known","dir":{d},"channel":"UCabc","tab":"videos"}}"#
        ))
        .unwrap();
        assert_eq!(
            known,
            format!(
                r#"{{"saved":9,"ids":["{}","{}","{}"]}}"#,
                id(1),
                id(2),
                id(3)
            )
        );
        assert!(ask(r#"{"op":"update"}"#).is_none());
        assert!(ask("not json").is_none());
        let ordered = ask(&format!(r#"{{"op":"order","order":"longest","fresh":[{{"id":"{}","duration":1}},{{"id":"{}","duration":2}}]}}"#, id(1), id(2))).unwrap();
        assert!(ordered.find(&id(2)).unwrap() < ordered.find(&id(1)).unwrap());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn orders_by_length_unknown_last_and_stable() {
        let s = [Some(300), Some(30), None, Some(4000), Some(30), Some(600)];
        assert_eq!(order(&s, Order::Longest), vec![3, 5, 0, 1, 4, 2]);
        assert_eq!(order(&s, Order::Shortest), vec![1, 4, 0, 5, 3, 2]);
    }

    #[test]
    fn saves_and_reads_on_from_what_it_knows() {
        let dir = temp();
        let d = dir.to_str().unwrap();
        let first: Vec<_> = (0..5).map(|i| item(&id(i), Some(i as u64 * 10))).collect();
        let out = update(
            d,
            "UCabc",
            "videos",
            100,
            /* whole= */ true,
            first,
            Order::Longest,
        );
        assert_eq!(ids(&out), vec![id(4), id(3), id(2), id(1), id(0)]);
        let k = known(d, "UCabc", "videos");
        assert_eq!(k.saved, 100);
        assert_eq!(k.ids.len(), 5);
        // A new upload read on its own keeps the rest from the file.
        let out = update(
            d,
            "UCabc",
            "videos",
            200,
            /* whole= */ false,
            vec![item(&id(9), Some(25))],
            Order::Shortest,
        );
        assert_eq!(ids(&out), vec![id(0), id(1), id(2), id(9), id(3), id(4)]);
        assert_eq!(known(d, "UCabc", "videos").ids[0], id(9));
        // A whole read drops what was taken down.
        let out = update(
            d,
            "UCabc",
            "videos",
            300,
            /* whole= */ true,
            vec![item(&id(9), Some(25)), item(&id(1), Some(10))],
            Order::Longest,
        );
        assert_eq!(ids(&out), vec![id(9), id(1)]);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn refuses_names_that_leave_the_folder_and_bad_entries() {
        let dir = temp();
        let d = dir.to_str().unwrap();
        for channel in [
            "../x",
            "a/b",
            "a\\b",
            "",
            "..",
            "UC.x",
            "C:",
            &"x".repeat(65),
        ] {
            assert!(file_of(&dir, channel, "videos").is_none(), "{channel}");
        }
        assert!(file_of(&dir, "UCabc", "../videos").is_none());
        assert!(file_of(&dir, "UCabc", "shorts").is_none());
        // Still ordered, just not saved.
        let out = update(
            d,
            "../evil",
            "videos",
            1,
            /* whole= */ true,
            vec![item(&id(1), Some(1)), item(&id(2), Some(2))],
            Order::Longest,
        );
        assert_eq!(ids(&out), vec![id(2), id(1)]);
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 0);
        // Entries without a video id, or too big, are dropped.
        let big = RawValue::from_string(format!(
            r#"{{"id":"{}","title":"{}"}}"#,
            id(3),
            "x".repeat(MAX_ITEM)
        ))
        .unwrap();
        let bad = RawValue::from_string(r#"{"id":"../../etc","duration":5}"#.to_string()).unwrap();
        let odd = RawValue::from_string(r#"[1,2]"#.to_string()).unwrap();
        let out = update(
            d,
            "UCabc",
            "videos",
            1,
            /* whole= */ true,
            vec![big, bad, odd, item(&id(4), Some(0))],
            Order::Longest,
        );
        assert_eq!(ids(&out), vec![id(4)]);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_broken_file_reads_as_nothing() {
        let dir = temp();
        let d = dir.to_str().unwrap();
        fs::write(dir.join("videos-UCabc.json"), b"{not json").unwrap();
        assert!(known(d, "UCabc", "videos").ids.is_empty());
        let out = update(
            d,
            "UCabc",
            "videos",
            5,
            /* whole= */ false,
            vec![item(&id(1), Some(1))],
            Order::Longest,
        );
        assert_eq!(ids(&out), vec![id(1)]);
        assert_eq!(known(d, "UCabc", "videos").ids, vec![id(1)]);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn keeps_only_the_tabs_used_last() {
        let dir = temp();
        let d = dir.to_str().unwrap();
        for i in 0..MAX_FILES + 3 {
            fs::write(dir.join(format!("videos-UC{i}.json")), b"{}").unwrap();
        }
        fs::write(dir.join("unrelated.txt"), b"keep").unwrap();
        update(
            d,
            "UCnew",
            "live",
            1,
            /* whole= */ true,
            vec![item(&id(1), Some(1))],
            Order::Longest,
        );
        let left = fs::read_dir(&dir).unwrap().count();
        assert_eq!(left, MAX_FILES + 1, "300 tab files and the unrelated one");
        assert!(dir.join("live-UCnew.json").exists());
        assert!(dir.join("unrelated.txt").exists());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn merges_twenty_thousand_quickly() {
        let fresh: Vec<Entry> = (0..20_000)
            .map(|i| Entry::of(item(&id(i), Some((i * 7919 % 10_000) as u64))).unwrap())
            .collect();
        let saved: Vec<Entry> = (10_000..30_000)
            .map(|i| Entry::of(item(&id(i), Some(i as u64))).unwrap())
            .collect();
        let start = std::time::Instant::now();
        let merged = merge(fresh, saved, /* whole= */ false);
        let out = ordered(merged, Order::Longest);
        assert_eq!(out.len(), MAX_ITEMS);
        assert!(start.elapsed().as_millis() < 2_000);
    }
}
