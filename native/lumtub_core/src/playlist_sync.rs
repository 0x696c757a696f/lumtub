//! Puts a YouTube playlist into the order the user dragged its copy into,
//! moving as few videos as possible.
//!
//! YouTube moves a playlist entry by its `setVideoId` (one per entry, unlike
//! the video id, which can repeat), placing it after another entry or, for
//! the first place, before one. The entries already in the wanted order
//! that can stay put are a longest increasing subsequence of their current
//! places; only the others are moved. That is O(n log n) to work out and
//! the fewest moves any plan needs.

use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::ffi::c_char;

/// One entry of the playlist on YouTube, in its current order.
#[derive(Deserialize, Clone, Debug, PartialEq)]
pub struct Entry {
    pub video: String,
    pub set: String,
}

#[derive(Deserialize)]
struct Ask {
    current: Vec<Entry>,
    wanted: Vec<String>,
}

/// One move, as `browse/edit_playlist` takes it.
#[derive(Debug, PartialEq, Clone)]
pub enum Move {
    /// Puts entry `set` right after entry `after`.
    After { set: String, after: String },
    /// Puts entry `set` right before entry `before`.
    Before { set: String, before: String },
}

impl Move {
    pub fn action(&self) -> Value {
        match self {
            Move::After { set, after } => json!({
                "action": "ACTION_MOVE_VIDEO_AFTER",
                "setVideoId": set,
                "movedSetVideoIdPredecessor": after,
            }),
            Move::Before { set, before } => json!({
                "action": "ACTION_MOVE_VIDEO_BEFORE",
                "setVideoId": set,
                "movedSetVideoIdSuccessor": before,
            }),
        }
    }
}

/// Indices into `seq` of one longest strictly increasing subsequence.
/// Patience sorting: O(n log n) time, O(n) space.
fn longest_increasing(seq: &[usize]) -> Vec<usize> {
    // tails[k]: index in seq of the smallest tail of an increasing run of
    // length k + 1; back[i]: the index before i in the run that ends at i.
    let mut tails: Vec<usize> = Vec::new();
    let mut back: Vec<Option<usize>> = vec![None; seq.len()];
    for (i, &value) in seq.iter().enumerate() {
        let at = tails.partition_point(|&t| seq[t] < value);
        if at > 0 {
            back[i] = Some(tails[at - 1]);
        }
        if at == tails.len() {
            tails.push(i);
        } else {
            tails[at] = i;
        }
    }
    let mut run = Vec::with_capacity(tails.len());
    let mut next = tails.last().copied();
    while let Some(i) = next {
        run.push(i);
        next = back[i];
    }
    run.reverse();
    run
}

/// The moves that turn `current` into the order of `wanted` (video ids).
/// Entries `wanted` does not name keep their places relative to each other
/// at the end; ids `wanted` names that are not in `current` are skipped,
/// and a video in the playlist twice is matched entry by entry.
pub fn moves(current: &[Entry], wanted: &[String]) -> Vec<Move> {
    let mut places: HashMap<&str, Vec<usize>> = HashMap::with_capacity(current.len());
    for (i, entry) in current.iter().enumerate().rev() {
        places.entry(entry.video.as_str()).or_default().push(i);
    }
    // The current place of each wanted entry, in the wanted order.
    let mut order: Vec<usize> = Vec::with_capacity(wanted.len());
    for video in wanted {
        if let Some(i) = places.get_mut(video.as_str()).and_then(Vec::pop) {
            order.push(i);
        }
    }
    let mut stays = vec![false; order.len()];
    for k in longest_increasing(&order) {
        stays[k] = true;
    }
    let mut plan = Vec::new();
    for (k, &i) in order.iter().enumerate() {
        if stays[k] {
            continue;
        }
        let set = current[i].set.clone();
        if k > 0 {
            plan.push(Move::After {
                set,
                after: current[order[k - 1]].set.clone(),
            });
        } else {
            // The first entry goes before the first one that stays, which is
            // ahead of every other entry by the time the moves are done.
            // Nothing stays only with a single entry, which needs no move.
            if let Some(first) = stays.iter().position(|&s| s) {
                plan.push(Move::Before {
                    set,
                    before: current[order[first]].set.clone(),
                });
            }
        }
    }
    plan
}

/// The `actions` lists for `browse/edit_playlist` that put the playlist in
/// order, at most `per_request` moves in each, so a long playlist is sent
/// in a few requests rather than one per video.
pub fn requests(current: &[Entry], wanted: &[String], per_request: usize) -> Vec<Value> {
    let actions: Vec<Value> = moves(current, wanted).iter().map(Move::action).collect();
    actions
        .chunks(per_request.max(1))
        .map(|chunk| Value::Array(chunk.to_vec()))
        .collect()
}

/// [requests] for the JSON `{"current": [{"video", "set"}], "wanted":
/// [ids], "per_request": n}`: a JSON list of action lists, or null when the
/// JSON does not parse.
///
/// # Safety
/// [json] must point to [len] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_playlist_moves(json: *const u8, len: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Full {
        #[serde(flatten)]
        ask: Ask,
        #[serde(default)]
        per_request: Option<usize>,
    }
    match serde_json::from_str::<Full>(unsafe { crate::taste::text(json, len) }) {
        Ok(full) => crate::taste::give_json(&Value::Array(requests(
            &full.ask.current,
            &full.ask.wanted,
            full.per_request.unwrap_or(100),
        ))),
        Err(_) => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entries(videos: &[&str]) -> Vec<Entry> {
        videos
            .iter()
            .enumerate()
            .map(|(i, v)| Entry {
                video: v.to_string(),
                set: format!("s{i}"),
            })
            .collect()
    }

    /// Plays [plan] on [list] as YouTube would.
    fn apply(list: &mut Vec<Entry>, plan: &[Move]) {
        for step in plan {
            let (set, target, after) = match step {
                Move::After { set, after } => (set, after, true),
                Move::Before { set, before } => (set, before, false),
            };
            let from = list.iter().position(|e| &e.set == set).unwrap();
            let entry = list.remove(from);
            let to = list.iter().position(|e| &e.set == target).unwrap();
            list.insert(if after { to + 1 } else { to }, entry);
        }
    }

    fn check(current: &[&str], wanted: &[&str]) -> usize {
        let mut list = entries(current);
        let wanted: Vec<String> = wanted.iter().map(|s| s.to_string()).collect();
        let plan = moves(&list, &wanted);
        apply(&mut list, &plan);
        let got: Vec<&str> = list.iter().map(|e| e.video.as_str()).collect();
        let named: Vec<&str> = got
            .iter()
            .copied()
            .filter(|v| wanted.iter().any(|w| w == v))
            .collect();
        let expected: Vec<&str> = wanted
            .iter()
            .map(String::as_str)
            .filter(|w| current.contains(w))
            .collect();
        assert_eq!(named, expected, "plan {plan:?}");
        plan.len()
    }

    #[test]
    fn same_order_needs_no_moves() {
        assert_eq!(check(&["a", "b", "c"], &["a", "b", "c"]), 0);
        assert_eq!(check(&[], &[]), 0);
        assert_eq!(check(&["a"], &["a"]), 0);
    }

    #[test]
    fn one_video_moved_is_one_move() {
        assert_eq!(
            check(&["a", "b", "c", "d", "e"], &["a", "c", "d", "e", "b"]),
            1
        );
        assert_eq!(
            check(&["a", "b", "c", "d", "e"], &["e", "a", "b", "c", "d"]),
            1
        );
        assert_eq!(
            check(&["a", "b", "c", "d", "e"], &["b", "a", "c", "d", "e"]),
            1
        );
    }

    #[test]
    fn reversing_moves_all_but_one() {
        assert_eq!(check(&["a", "b", "c", "d"], &["d", "c", "b", "a"]), 3);
    }

    #[test]
    fn missing_and_extra_entries_are_skipped() {
        check(&["a", "b", "c", "x"], &["c", "gone", "a", "b"]);
        check(&["a", "a", "b"], &["b", "a", "a"]);
    }

    #[test]
    fn random_orders_come_out_right_with_the_fewest_moves() {
        // A small linear congruential generator keeps the test repeatable
        // without a dependency.
        let mut seed: u64 = 42;
        let mut next = |n: usize| {
            seed = seed
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            ((seed >> 33) as usize) % n.max(1)
        };
        for size in [2usize, 3, 5, 10, 40, 200] {
            for _ in 0..40 {
                let names: Vec<String> = (0..size).map(|i| format!("v{i}")).collect();
                let current: Vec<&str> = names.iter().map(String::as_str).collect();
                let mut wanted = current.clone();
                for i in (1..wanted.len()).rev() {
                    wanted.swap(i, next(i + 1));
                }
                let made = check(&current, &wanted);
                let places: Vec<usize> = wanted
                    .iter()
                    .map(|w| current.iter().position(|c| c == w).unwrap())
                    .collect();
                assert_eq!(made, size - longest_increasing(&places).len());
            }
        }
    }

    #[test]
    fn long_playlists_are_split_into_few_requests() {
        let names: Vec<String> = (0..1000).map(|i| format!("v{i}")).collect();
        let current: Vec<Entry> = names
            .iter()
            .enumerate()
            .map(|(i, v)| Entry {
                video: v.clone(),
                set: format!("s{i}"),
            })
            .collect();
        let wanted: Vec<String> = names.iter().rev().cloned().collect();
        let sent = requests(&current, &wanted, 100);
        assert_eq!(sent.len(), 10);
        assert!(
            sent[0][0]["action"]
                .as_str()
                .unwrap()
                .starts_with("ACTION_MOVE_VIDEO_")
        );
        assert_eq!(
            sent.iter()
                .map(|r| r.as_array().unwrap().len())
                .sum::<usize>(),
            999
        );
    }

    #[test]
    fn fifty_thousand_entries_plan_quickly() {
        let n = 50_000;
        let current: Vec<Entry> = (0..n)
            .map(|i| Entry {
                video: format!("v{i}"),
                set: format!("s{i}"),
            })
            .collect();
        let wanted: Vec<String> = (0..n).map(|i| format!("v{}", (i * 7919) % n)).collect();
        let start = std::time::Instant::now();
        let plan = moves(&current, &wanted);
        assert!(start.elapsed().as_millis() < 2000, "{:?}", start.elapsed());
        assert!(!plan.is_empty());
    }
}
