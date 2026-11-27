//! Learning words: when each vocabulary word comes back for review (the
//! FSRS 4.5 scheduler with its published default weights), and what a
//! video's subtitles hold for a learner given the words they know.

use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};
use std::ffi::c_char;

use crate::taste::{give, text};

const W: [f64; 17] = [
    0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316, 1.0651, 0.0234, 1.616, 0.1544, 1.0824, 1.9813,
    0.0953, 0.2975, 2.2042, 0.2407, 2.9466,
];
const DECAY: f64 = -0.5;
const FACTOR: f64 = 19.0 / 81.0;
const RETENTION: f64 = 0.9;
const MAX_DAYS: f64 = 36500.0;
const DAY_MS: i64 = 86_400_000;

/// No video has more lines than this; anything past it is ignored.
const MAX_LINES: usize = 100_000;

/// A forgotten word comes back this soon, within the same session.
pub const RELEARN_MS: i64 = 10 * 60 * 1000;

/// Where a word stands: how many days it is likely to be remembered, how
/// hard it is (1 to 10), and when it was last reviewed.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct State {
    pub stability: f64,
    pub difficulty: f64,
    pub reps: u32,
    pub lapses: u32,
    pub last_ms: i64,
    pub due_ms: i64,
}

/// The chance of still knowing a word [days] after its last review.
pub fn retrievability(days: f64, stability: f64) -> f64 {
    (1.0 + FACTOR * days / stability).powf(DECAY)
}

/// Days until the chance of knowing the word falls to 90 %.
pub fn interval(stability: f64) -> f64 {
    (stability / FACTOR * (RETENTION.powf(1.0 / DECAY) - 1.0))
        .round()
        .clamp(1.0, MAX_DAYS)
}

fn initial_difficulty(grade: u8) -> f64 {
    (W[4] - (f64::from(grade) - 3.0) * W[5]).clamp(1.0, 10.0)
}

fn due(stability: f64, grade: u8, now_ms: i64) -> i64 {
    if grade == 1 {
        now_ms + RELEARN_MS
    } else {
        now_ms + interval(stability) as i64 * DAY_MS
    }
}

/// The state after reviewing [state] (None for a word never reviewed)
/// with [grade]: 1 forgot, 2 hard, 3 remembered, 4 easy.
pub fn next(state: Option<State>, grade: u8, now_ms: i64) -> State {
    let grade = grade.clamp(1, 4);
    let g = f64::from(grade);
    let Some(state) = state else {
        let stability = W[usize::from(grade) - 1];
        return State {
            stability,
            difficulty: initial_difficulty(grade),
            reps: 1,
            lapses: u32::from(grade == 1),
            last_ms: now_ms,
            due_ms: due(stability, grade, now_ms),
        };
    };
    let days = ((now_ms - state.last_ms).max(0) / 3_600_000) as f64 / 24.0;
    let r = retrievability(days, state.stability);
    let d0 = state.difficulty - W[6] * (g - 3.0);
    let difficulty = (W[7] * initial_difficulty(4) + (1.0 - W[7]) * d0).clamp(1.0, 10.0);
    let stability = if grade == 1 {
        state.stability.min(
            W[11]
                * difficulty.powf(-W[12])
                * ((state.stability + 1.0).powf(W[13]) - 1.0)
                * (W[14] * (1.0 - r)).exp(),
        )
    } else {
        let hard = if grade == 2 { W[15] } else { 1.0 };
        let easy = if grade == 4 { W[16] } else { 1.0 };
        state.stability
            * (W[8].exp()
                * (11.0 - difficulty)
                * state.stability.powf(-W[9])
                * ((W[10] * (1.0 - r)).exp() - 1.0)
                * hard
                * easy
                + 1.0)
    };
    State {
        stability,
        difficulty,
        reps: state.reps + 1,
        lapses: state.lapses + u32::from(grade == 1),
        last_ms: now_ms,
        due_ms: due(stability, grade, now_ms),
    }
}

/// A state read back from a file: anything out of range is no state,
/// so a damaged file never divides by zero.
fn state_of(value: &Value) -> Option<State> {
    let stability = value
        .get("s")?
        .as_f64()
        .filter(|s| s.is_finite() && *s > 0.0)?
        .min(MAX_DAYS * 10.0);
    let difficulty = value
        .get("d")?
        .as_f64()
        .filter(|d| d.is_finite())?
        .clamp(1.0, 10.0);
    Some(State {
        stability,
        difficulty,
        reps: value.get("reps").and_then(Value::as_u64).unwrap_or(0) as u32,
        lapses: value.get("lapses").and_then(Value::as_u64).unwrap_or(0) as u32,
        last_ms: value.get("last").and_then(Value::as_i64)?,
        due_ms: value.get("due").and_then(Value::as_i64).unwrap_or(0),
    })
}

fn json_of(state: State) -> Value {
    json!({
        "s": (state.stability * 10_000.0).round() / 10_000.0,
        "d": (state.difficulty * 10_000.0).round() / 10_000.0,
        "reps": state.reps,
        "lapses": state.lapses,
        "last": state.last_ms,
        "due": state.due_ms,
    })
}

/// What a video's lines hold for a learner who knows [known]: the share
/// of its words (counted each time they are said) known already, its
/// distinct words, the unknown ones said most often, and the lines with
/// exactly one unknown word among at least three. A word in [half] (a
/// Chinese or Japanese word whose every character the learner knows from
/// other words) counts as half understood: its meaning can often be
/// guessed, but not always.
pub fn coverage(
    lines: &[Vec<String>],
    known: &HashSet<&str>,
    half: &HashSet<&str>,
    most: usize,
) -> Value {
    let mut said = 0usize;
    let mut understood = 0.0f64;
    let mut counts: HashMap<&str, usize> = HashMap::new();
    let mut first: HashMap<&str, usize> = HashMap::new();
    let mut one_new = Vec::new();
    for (i, line) in lines.iter().enumerate() {
        let mut unknown: HashSet<&str> = HashSet::new();
        for word in line {
            said += 1;
            if known.contains(word.as_str()) {
                understood += 1.0;
            } else {
                if half.contains(word.as_str()) {
                    understood += 0.5;
                }
                unknown.insert(word);
                *counts.entry(word).or_default() += 1;
                first.entry(word).or_insert(i);
            }
        }
        if line.len() >= 3 && unknown.len() == 1 {
            one_new.push(i);
        }
    }
    let distinct: HashSet<&str> = lines.iter().flatten().map(String::as_str).collect();
    let unknown_words = distinct.iter().filter(|w| !known.contains(**w)).count();
    // The [most] said most often, in linear time: select them, then sort
    // only those few.
    let mut often: Vec<(&str, usize, usize)> =
        counts.into_iter().map(|(w, n)| (w, n, first[w])).collect();
    let order =
        |a: &(&str, usize, usize), b: &(&str, usize, usize)| b.1.cmp(&a.1).then(a.2.cmp(&b.2));
    if often.len() > most && most > 0 {
        often.select_nth_unstable_by(most - 1, order);
        often.truncate(most);
    }
    often.sort_unstable_by(order);
    json!({
        "said": said,
        "known": if said == 0 { 0.0 } else { understood / said as f64 },
        "words": distinct.len(),
        "unknownWords": unknown_words,
        "often": often.iter().take(most).map(|(w, n, _)| json!([w, n])).collect::<Vec<_>>(),
        "oneNew": one_new,
    })
}

/// [next] for Dart, from `{state?, grade, now}` (times in ms since the
/// epoch); with `grades: true`, the state after each of the four grades.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_review_next(json: *const u8, length: usize) -> *mut c_char {
    // SAFETY: The caller passes `json` pointing at `length` readable bytes, per this function's `#
    // Safety`.
    let input: Value = serde_json::from_str(unsafe { text(json, length) }).unwrap_or(Value::Null);
    let state = input.get("state").and_then(state_of);
    let now = input.get("now").and_then(Value::as_i64).unwrap_or(0);
    if input
        .get("grades")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        return give(
            Value::Array((1..=4).map(|g| json_of(next(state, g, now))).collect()).to_string(),
        );
    }
    let grade = input.get("grade").and_then(Value::as_u64).unwrap_or(3) as u8;
    give(json_of(next(state, grade, now)).to_string())
}

/// [coverage] for Dart, from `{lines: [[word key, …], …], known: [key, …], half: [key, …], most}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_word_coverage(json: *const u8, length: usize) -> *mut c_char {
    // SAFETY: The caller passes `json` pointing at `length` readable bytes, per this function's `#
    // Safety`.
    let input: Value = serde_json::from_str(unsafe { text(json, length) }).unwrap_or(Value::Null);
    let lines: Vec<Vec<String>> = input
        .get("lines")
        .and_then(Value::as_array)
        .map(|lines| {
            lines
                .iter()
                .take(MAX_LINES)
                .map(|line| {
                    line.as_array()
                        .map(|w| {
                            w.iter()
                                .filter_map(|w| w.as_str().map(str::to_owned))
                                .collect()
                        })
                        .unwrap_or_default()
                })
                .collect()
        })
        .unwrap_or_default();
    let known: HashSet<&str> = input
        .get("known")
        .and_then(Value::as_array)
        .map(|k| k.iter().filter_map(Value::as_str).collect())
        .unwrap_or_default();
    let half: HashSet<&str> = input
        .get("half")
        .and_then(Value::as_array)
        .map(|k| k.iter().filter_map(Value::as_str).collect())
        .unwrap_or_default();
    let most = input
        .get("most")
        .and_then(Value::as_u64)
        .unwrap_or(10)
        .min(200) as usize;
    give(coverage(&lines, &known, &half, most).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: i64 = 1_795_000_000_000;

    #[test]
    fn new_words() {
        let again = next(None, 1, NOW);
        let good = next(None, 3, NOW);
        let easy = next(None, 4, NOW);
        assert_eq!(again.due_ms - NOW, RELEARN_MS);
        assert_eq!((good.due_ms - NOW) / DAY_MS, 3);
        assert_eq!((easy.due_ms - NOW) / DAY_MS, 15);
        assert!(again.difficulty > good.difficulty);
    }

    #[test]
    fn intervals_grow_then_shrink_after_a_lapse() {
        let mut state = next(None, 3, NOW);
        let mut gap = state.due_ms - NOW;
        for _ in 0..4 {
            let at = state.due_ms;
            state = next(Some(state), 3, at);
            assert!(state.due_ms - at > gap);
            gap = state.due_ms - at;
        }
        let lapsed = next(Some(state), 1, state.due_ms);
        assert!(lapsed.stability < state.stability);
        assert_eq!(lapsed.lapses, 1);
        assert_eq!(lapsed.due_ms - state.due_ms, RELEARN_MS);
    }

    #[test]
    fn grades_in_order() {
        let first = next(None, 3, NOW);
        let [hard, good, easy] = [2, 3, 4].map(|g| next(Some(first), g, first.due_ms).stability);
        assert!(hard < good && good < easy);
    }

    #[test]
    fn coverage_of_lines() {
        let line = |words: &[&str]| words.iter().map(|w| (*w).to_owned()).collect::<Vec<_>>();
        let lines = vec![
            line(&["我", "喜欢", "学习"]),
            line(&["我", "喜欢", "吃饭"]),
            line(&["学习", "学习"]),
        ];
        let known: HashSet<&str> = ["我", "喜欢"].into_iter().collect();
        let answer = coverage(&lines, &known, &HashSet::new(), 5);
        assert_eq!(answer["said"], 8);
        assert_eq!(answer["known"], 0.5);
        // 吃饭 guessed from known characters: half of its one saying.
        let half: HashSet<&str> = ["吃饭"].into_iter().collect();
        assert_eq!(coverage(&lines, &known, &half, 5)["known"], 4.5 / 8.0);
        assert_eq!(answer["words"], 4);
        assert_eq!(answer["unknownWords"], 2);
        assert_eq!(answer["often"][0], json!(["学习", 3]));
        assert_eq!(answer["oneNew"], json!([0, 1]));
    }
}
