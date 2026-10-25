//! The home feed's recommendations: what the history says about taste, and
//! the ranking of suggested videos by it. Worked out on this computer only.
//!
//! Dart sends JSON in and gets JSON or plain numbers back; see
//! lib/recommendations.dart for the side that calls this.

#![allow(clippy::missing_safety_doc)]

use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::ffi::{CString, c_char};

/// Keys in the order they were first added, so ties come out the same way
/// every time.
#[derive(Default)]
struct Ordered {
    keys: Vec<String>,
    values: Vec<f64>,
    index: HashMap<String, usize>,
}

impl Ordered {
    fn add(&mut self, key: &str, by: f64) {
        match self.index.get(key) {
            Some(&i) => self.values[i] += by,
            None => {
                self.index.insert(key.to_owned(), self.keys.len());
                self.keys.push(key.to_owned());
                self.values.push(by);
            }
        }
    }

    fn get(&self, key: &str) -> Option<f64> {
        self.index.get(key).map(|&i| self.values[i])
    }

    fn max(&self) -> f64 {
        self.values.iter().copied().fold(0.0, f64::max)
    }

    /// Up to [count] keys, the highest first, only those above [floor].
    fn top(&self, count: usize, floor: f64) -> Vec<&str> {
        let mut order: Vec<usize> = (0..self.keys.len()).filter(|&i| self.values[i] > floor).collect();
        order.sort_by(|&a, &b| self.values[b].total_cmp(&self.values[a]));
        order.into_iter().take(count).map(|i| self.keys[i].as_str()).collect()
    }
}

#[derive(Deserialize)]
struct Watched {
    /// The channel key.
    k: String,
    /// The title.
    t: String,
    /// How much of it was watched, when known.
    f: Option<f64>,
    /// Left within the first seconds.
    #[serde(default)]
    skip: bool,
}

#[derive(Deserialize)]
struct Kept {
    k: String,
    t: String,
}

#[derive(Deserialize)]
struct History {
    #[serde(default)]
    history: Vec<Watched>,
    #[serde(default)]
    favorites: Vec<Kept>,
    #[serde(default)]
    followed: Vec<String>,
    /// Newest first.
    #[serde(default)]
    searches: Vec<String>,
    #[serde(default = "default_decay")]
    decay: f64,
}

fn default_decay() -> f64 {
    0.93
}

/// How much each channel is watched (skipped videos count against it) and
/// which words matter, weighted TF-IDF style so words in every title count
/// for little.
pub struct Taste {
    channels: Ordered,
    /// Word to interest, already multiplied by the word's IDF.
    words: Ordered,
    idf: HashMap<String, f64>,
    default_idf: f64,
    words_norm: f64,
    max_channel: f64,
    max_word: f64,
}

impl Taste {
    fn from(data: History) -> Taste {
        let mut channels = Ordered::default();
        let mut documents: Vec<(Vec<String>, f64)> = Vec::new();
        for (i, item) in data.history.iter().enumerate() {
            let recency = data.decay.powf(i as f64);
            if item.skip {
                // A sign against, not for.
                channels.add(&item.k, -0.5 * recency);
                continue;
            }
            let weight = recency * (0.3 + 0.7 * item.f.unwrap_or(0.5));
            channels.add(&item.k, weight);
            documents.push((title_words(&item.t), weight));
        }
        for item in &data.favorites {
            channels.add(&item.k, 1.0);
            documents.push((title_words(&item.t), 1.0));
        }
        for (i, query) in data.searches.iter().take(20).enumerate() {
            documents.push((title_words(query), 0.6 * 0.9f64.powf(i as f64)));
        }
        for id in &data.followed {
            channels.add(id, 1.5);
        }
        let count = documents.len() as f64;
        let mut df: HashMap<&str, u32> = HashMap::new();
        for (words, _) in &documents {
            for word in words {
                *df.entry(word).or_default() += 1;
            }
        }
        let idf_of = |seen: u32| ((count + 1.0) / (seen as f64 + 1.0)).ln() + 1.0;
        let idf: HashMap<String, f64> = df.iter().map(|(word, &seen)| ((*word).to_owned(), idf_of(seen))).collect();
        let mut words = Ordered::default();
        for (title_words, weight) in &documents {
            for word in title_words {
                words.add(word, weight * idf[word]);
            }
        }
        let words_norm = words.values.iter().map(|v| v * v).sum::<f64>().sqrt();
        let max_channel = channels.max();
        let max_word = words.max();
        Taste { channels, words, idf, default_idf: idf_of(0), words_norm, max_channel, max_word }
    }

    /// -1 to 1: how much the channel [key] is watched, below 0 when mostly
    /// skipped.
    pub fn affinity(&self, key: &str) -> f64 {
        let value = self.channels.get(key).unwrap_or(0.0);
        if value < 0.0 {
            return value.max(-1.0);
        }
        if self.max_channel <= 0.0 { 0.0 } else { value / self.max_channel }
    }

    /// 0 to 1: the cosine between [title] and the history's words.
    pub fn title_match(&self, title: &str) -> f64 {
        if self.words_norm == 0.0 {
            return 0.0;
        }
        let mut dot = 0.0;
        let mut norm = 0.0;
        for word in title_words(title) {
            let idf = self.idf.get(&word).copied().unwrap_or(self.default_idf);
            dot += self.words.get(&word).unwrap_or(0.0) * idf;
            norm += idf * idf;
        }
        if norm == 0.0 {
            return 0.0;
        }
        // Short titles against a long history give small cosines; scaled up
        // so a clear match reaches about 1.
        (3.0 * dot / (self.words_norm * f64::sqrt(norm))).min(1.0)
    }

    /// The history's interest [title] belongs to most: its word that weighs
    /// most in the history, if any weighs enough.
    pub fn interest(&self, title: &str) -> Option<String> {
        let mut best = None;
        let mut best_weight = 0.0;
        for word in title_words(title) {
            let weight = self.words.get(&word).unwrap_or(0.0);
            if weight > best_weight {
                best_weight = weight;
                best = Some(word);
            }
        }
        if self.max_word > 0.0 && best_weight >= 0.2 * self.max_word { best } else { None }
    }

    /// The channels watched most, most first.
    pub fn top_channels(&self, count: usize) -> Vec<&str> {
        self.channels.top(count, 0.0)
    }

    /// The words the history is most about, most first.
    pub fn top_words(&self, count: usize) -> Vec<&str> {
        self.words.top(count, f64::NEG_INFINITY)
    }

    fn knows(&self, key: &str) -> bool {
        self.channels.index.contains_key(key)
    }
}

const STOP_WORDS: &[&str] = &[
    "the", "and", "for", "with", "you", "your", "this", "that", "from", "are", "was", "how", "what", "why", "who",
    "official", "video", "videos", "full", "new", "live", "episode", "part", "feat", "ft", "vs", "amp", "mv", "hd",
    "4k", "1080p", "shorts", "channel",
];

fn cjk(c: char) -> bool {
    matches!(c, '\u{3040}'..='\u{30ff}' | '\u{3400}'..='\u{9fff}' | '\u{ac00}'..='\u{d7af}')
}

/// Latin words of three letters or more, and pairs of neighbouring Chinese,
/// Japanese or Korean characters, which stand in for words. Each once, in
/// the order they appear, Latin words first.
pub fn title_words(title: &str) -> Vec<String> {
    let mut result: Vec<String> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    let mut push = |word: String| {
        if seen.insert(word.clone()) {
            result.push(word);
        }
    };
    let lower: Vec<char> = title.to_lowercase().chars().collect();
    let mut i = 0;
    while i < lower.len() {
        if lower[i].is_ascii_lowercase() {
            let end = (i..lower.len()).find(|&j| !(lower[j].is_ascii_lowercase() || lower[j].is_ascii_digit())).unwrap_or(lower.len());
            if end - i >= 3 {
                let word: String = lower[i..end].iter().collect();
                if !STOP_WORDS.contains(&word.as_str()) {
                    push(word);
                }
                i = end;
                continue;
            }
        }
        i += 1;
    }
    let chars: Vec<char> = title.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if !cjk(chars[i]) {
            i += 1;
            continue;
        }
        let end = (i..chars.len()).find(|&j| !cjk(chars[j])).unwrap_or(chars.len());
        for pair in chars[i..end].windows(2) {
            push(pair.iter().collect());
        }
        i = end;
    }
    result
}

/// How much each signal counts when ranking.
#[derive(Deserialize)]
struct Weights {
    channel: f64,
    title: f64,
    fresh: f64,
    views: f64,
    #[serde(default)]
    novelty: f64,
}

#[derive(Deserialize)]
struct Suggested {
    id: String,
    /// The channel key.
    k: String,
    t: String,
    /// Its source's weight times its seed's.
    s: f64,
    /// Taken off for kinds the settings want less of, and for channels
    /// marked 不感兴趣.
    #[serde(default)]
    p: f64,
    /// Hours since it was published.
    a: Option<f64>,
    /// Views.
    v: Option<f64>,
    /// Length in seconds.
    d: Option<f64>,
}

#[derive(Deserialize)]
struct Ranking {
    candidates: Vec<Suggested>,
    weights: Weights,
    count: usize,
    #[serde(default)]
    seed: i64,
}

/// 0 to 1, the same for the same [seed] and [id]: the chance mixed into a
/// video's score.
fn jitter(seed: i64, id: &str) -> f64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in id.bytes() {
        hash = (hash ^ byte as u64).wrapping_mul(0x100000001b3);
    }
    let mut x = hash ^ (seed as u64).wrapping_mul(0x9e3779b97f4a7c15);
    x = (x ^ (x >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94d049bb133111eb);
    x ^= x >> 31;
    (x >> 11) as f64 / (1u64 << 53) as f64
}

/// Orders the candidates, like a video site's feed: near what was watched,
/// from channels watched often, fresh and popular. Near the top no channel
/// and no interest repeats much, and a little chance is mixed in so the feed
/// does not narrow. Returns (the candidate whose video it is, the candidate
/// whose reason it shows) for each pick.
fn rank(taste: &Taste, ranking: &Ranking) -> Vec<(usize, usize)> {
    let weights = &ranking.weights;
    struct Entry {
        item: usize,
        reason: usize,
        score: f64,
    }
    let mut entries: Vec<Entry> = Vec::new();
    let mut by_id: HashMap<&str, usize> = HashMap::new();
    for (i, c) in ranking.candidates.iter().enumerate() {
        let mut score = c.s - c.p;
        let affinity = taste.affinity(&c.k);
        score += weights.channel * affinity;
        if !taste.knows(&c.k) {
            score += weights.novelty;
        }
        // A channel mostly skipped stays down whatever the lane.
        if affinity < 0.0 && weights.channel == 0.0 {
            score += 0.8 * affinity;
        }
        score += weights.title * taste.title_match(&c.t);
        if let Some(hours) = c.a {
            score += weights.fresh * (-hours / (24.0 * 7.0)).exp();
        }
        if let Some(views) = c.v.filter(|&v| v > 0.0) {
            score += weights.views * (views.log10() / 7.0).min(1.0);
        }
        // Shorts and very long videos fit a home page less.
        match c.d {
            Some(d) if d < 60.0 => score -= 0.3,
            Some(d) if d > 3.0 * 3600.0 => score -= 0.2,
            _ => {}
        }
        match by_id.get(c.id.as_str()) {
            None => {
                by_id.insert(&c.id, entries.len());
                entries.push(Entry { item: i, reason: i, score });
            }
            Some(&at) => {
                // Suggested from more than one place: a stronger sign. The
                // stronger source gives the reason.
                let known = &mut entries[at];
                if score > known.score {
                    known.reason = i;
                }
                known.score = known.score.max(score) + 0.3;
            }
        }
    }
    struct Pooled {
        item: usize,
        reason: usize,
        score: f64,
        channel: usize,
        interest: Option<usize>,
    }
    let mut channel_ids: HashMap<&str, usize> = HashMap::new();
    let mut interest_ids: HashMap<String, usize> = HashMap::new();
    let mut pool: Vec<Pooled> = entries
        .iter()
        .map(|e| {
            let c = &ranking.candidates[e.item];
            let next = channel_ids.len();
            let channel = *channel_ids.entry(&c.k).or_insert(next);
            let interest = taste.interest(&c.t).map(|word| {
                let next = interest_ids.len();
                *interest_ids.entry(word).or_insert(next)
            });
            Pooled { item: e.item, reason: e.reason, score: e.score + jitter(ranking.seed, &c.id) * 0.35, channel, interest }
        })
        .collect();
    let mut per_channel = vec![0u32; channel_ids.len()];
    let mut per_interest = vec![0u32; interest_ids.len()];
    let mut picked = Vec::new();
    while picked.len() < ranking.count && !pool.is_empty() {
        let mut best = 0;
        let mut best_score = f64::NEG_INFINITY;
        for (i, entry) in pool.iter().enumerate() {
            let score = entry.score
                - 0.45 * per_channel[entry.channel] as f64
                - entry.interest.map_or(0.0, |w| 0.2 * per_interest[w] as f64);
            if score > best_score {
                best_score = score;
                best = i;
            }
        }
        let chosen = pool.remove(best);
        per_channel[chosen.channel] += 1;
        if let Some(w) = chosen.interest {
            per_interest[w] += 1;
        }
        picked.push((chosen.item, chosen.reason));
    }
    picked
}

pub(crate) unsafe fn text<'a>(ptr: *const u8, len: usize) -> &'a str {
    if ptr.is_null() || len == 0 {
        return "";
    }
    std::str::from_utf8(unsafe { std::slice::from_raw_parts(ptr, len) }).unwrap_or("")
}

pub(crate) fn give(value: String) -> *mut c_char {
    CString::new(value).map_or(std::ptr::null_mut(), CString::into_raw)
}

pub(crate) fn give_json<T: serde::Serialize>(value: &T) -> *mut c_char {
    serde_json::to_string(value).map_or(std::ptr::null_mut(), give)
}

/// Learns a taste from the history in [json]; null when it does not parse.
/// Free it with [lumtub_taste_free].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_taste_new(json: *const u8, len: usize) -> *mut Taste {
    match serde_json::from_str::<History>(unsafe { text(json, len) }) {
        Ok(data) => Box::into_raw(Box::new(Taste::from(data))),
        Err(_) => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_taste_free(taste: *mut Taste) {
    if !taste.is_null() {
        drop(unsafe { Box::from_raw(taste) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_taste_affinity(taste: *const Taste, key: *const u8, len: usize) -> f64 {
    unsafe { taste.as_ref() }.map_or(0.0, |t| t.affinity(unsafe { text(key, len) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_taste_match(taste: *const Taste, title: *const u8, len: usize) -> f64 {
    unsafe { taste.as_ref() }.map_or(0.0, |t| t.title_match(unsafe { text(title, len) }))
}

/// The interest of [title], or null for none. Free it with
/// [lumtub_string_free].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_taste_interest(taste: *const Taste, title: *const u8, len: usize) -> *mut c_char {
    unsafe { taste.as_ref() }
        .and_then(|t| t.interest(unsafe { text(title, len) }))
        .map_or(std::ptr::null_mut(), give)
}

/// A JSON list of the top [count] channels ([words] false) or words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_taste_top(taste: *const Taste, words: bool, count: u32) -> *mut c_char {
    match unsafe { taste.as_ref() } {
        Some(t) => give_json(&if words { t.top_words(count as usize) } else { t.top_channels(count as usize) }),
        None => std::ptr::null_mut(),
    }
}

/// [title]'s words as a JSON list.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_title_words(title: *const u8, len: usize) -> *mut c_char {
    give_json(&title_words(unsafe { text(title, len) }))
}

/// Ranks the candidates in [json] by [taste]: a JSON list of
/// [video candidate, reason candidate] index pairs, best first; null when
/// the JSON does not parse.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_recommend(taste: *const Taste, json: *const u8, len: usize) -> *mut c_char {
    let Some(taste) = (unsafe { taste.as_ref() }) else { return std::ptr::null_mut() };
    match serde_json::from_str::<Ranking>(unsafe { text(json, len) }) {
        Ok(ranking) => give_json(&rank(taste, &ranking)),
        Err(_) => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { CString::from_raw(value) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn watched(k: &str, t: &str) -> Watched {
        Watched { k: k.into(), t: t.into(), f: None, skip: false }
    }

    fn taste(history: Vec<Watched>) -> Taste {
        Taste::from(History { history, favorites: vec![], followed: vec![], searches: vec![], decay: 0.93 })
    }

    #[test]
    fn title_words_split_latin_and_cjk() {
        assert_eq!(title_words("Official MV 原神"), vec!["原神"]);
        assert_eq!(title_words("Lofi HIP hop 9abc ab x1y2 lofi"), vec!["lofi", "hip", "hop", "abc", "x1y2"]);
        assert_eq!(title_words("机械键盘"), vec!["机械", "械键", "键盘"]);
    }

    #[test]
    fn weighs_channels_and_words() {
        let t = taste(vec![
            watched("UCgame", "原神 新角色 实机演示"),
            watched("UCgame", "原神 剧情 解说"),
            watched("UClofi", "Lofi hip hop radio"),
        ]);
        assert_eq!(t.top_channels(1), vec!["UCgame"]);
        assert_eq!(t.affinity("UCgame"), 1.0);
        assert_eq!(t.affinity("UCother"), 0.0);
        assert!(t.title_match("原神 4.0 前瞻") > t.title_match("红烧肉做法"));
        assert_eq!(t.interest("原神 前瞻").as_deref(), Some("原神"));
    }

    #[test]
    fn words_in_every_title_count_less() {
        let t = taste(vec![watched("", "教程 机械键盘"), watched("", "教程 剪辑"), watched("", "教程 摄影")]);
        let weight = |word: &str| t.words.get(word).unwrap();
        assert!(weight("教程") / 3.0 < weight("键盘"));
    }

    #[test]
    fn skips_count_against_a_channel() {
        let t = taste(vec![Watched { k: "UCskip".into(), t: "x".into(), f: Some(0.05), skip: true }, watched("UCgood", "y")]);
        assert!(t.affinity("UCskip") < 0.0);
        assert_eq!(t.affinity("UCgood"), 1.0);
    }

    #[test]
    fn jitter_is_stable_and_spread() {
        assert_eq!(jitter(3, "abc"), jitter(3, "abc"));
        assert_ne!(jitter(3, "abc"), jitter(4, "abc"));
        let values: Vec<f64> = (0..1000).map(|i| jitter(7, &format!("v{i}"))).collect();
        assert!(values.iter().all(|v| (0.0..1.0).contains(v)));
        let mean = values.iter().sum::<f64>() / values.len() as f64;
        assert!((mean - 0.5).abs() < 0.05);
    }

    #[test]
    fn ranks_through_the_c_functions() {
        let history = r#"{"history":[{"k":"UCkeys","t":"机械键盘 评测"},{"k":"UCkeys","t":"机械键盘 评测"}]}"#;
        let ranking = r#"{"count":24,"seed":0,"weights":{"channel":0.8,"title":0.6,"fresh":0.5,"views":0.3},"candidates":[
            {"id":"cook","k":"UCcook","t":"家常菜","s":0.5},
            {"id":"keys","k":"UCkeys","t":"机械键盘 轴体 评测","s":1.0},
            {"id":"keys","k":"UCkeys","t":"机械键盘 轴体 评测","s":0.7}]}"#;
        unsafe {
            let t = lumtub_taste_new(history.as_ptr(), history.len());
            assert!(!t.is_null());
            let out = lumtub_recommend(t, ranking.as_ptr(), ranking.len());
            assert_eq!(std::ffi::CStr::from_ptr(out).to_str().unwrap(), "[[1,1],[0,0]]");
            lumtub_string_free(out);
            assert!(lumtub_recommend(t, b"{".as_ptr(), 1).is_null());
            lumtub_taste_free(t);
            assert!(lumtub_taste_new(b"[".as_ptr(), 1).is_null());
        }
    }
}
