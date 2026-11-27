//! Catholic Chinese wording for translations of Catholic videos: the names
//! and terms a translation service writes the Protestant way (和合本: 上帝,
//! 圣灵, 彼得, 摩西) put the way the Catholic Church in Chinese writes them
//! (思高本: 天主, 圣神, 伯多禄, 梅瑟).
//!
//! The rules come from church_words/terms.json and Lumtub's own
//! church_words/extra.json (see church_words/make.py), one table each for
//! simplified characters, traditional ones as Taiwan writes them, and
//! Hong Kong's (亞孟, 修和聖事 where Taiwan has 阿們, 和好聖事). Each rule
//! may name characters that must not stand before or after its word, so
//! that 神 becomes 天主 but 神父, 精神 and 神迹 stay.
//!
//! Some mistakes show only beside the original: 圣父 is God the Father,
//! unless the original said Santo Padre, the Pope. [Sourced] rules
//! (church_words/sourced.json) change such words only when the original
//! has the words that call for it, and no more often than it has them.
//!
//! Text is read once from left to right. At each character, the longest
//! word starting there whose neighbours allow it is replaced, else a
//! shorter one, else the character is kept. Characters that start no word
//! are passed over through a bitmap, so text without any of the words costs
//! one lookup per character and is never copied. Work is linear in the
//! text's length times the longest word (a few characters).

use std::sync::LazyLock;

/// The characters of the Basic Multilingual Plane, one bit each.
const PLANE: usize = 0x1_0000;

struct Rule {
    to: Box<str>,
    not_before: Box<[char]>,
    not_after: Box<[char]>,
}

impl Rule {
    fn allows(&self, before: Option<char>, after: Option<char>) -> bool {
        !before.is_some_and(|c| self.not_before.binary_search(&c).is_ok())
            && !after.is_some_and(|c| self.not_after.binary_search(&c).is_ok())
    }
}

#[derive(Default)]
struct Node {
    /// (character, node), sorted by character.
    next: Vec<(char, u32)>,
    rule: Option<u32>,
}

pub struct Table {
    nodes: Vec<Node>,
    rules: Vec<Rule>,
    /// Bit c is set when a word starts with character c.
    starts: Box<[u64]>,
    longest: usize,
}

impl Table {
    /// A table from lines of `from\tto\tnot before\tnot after`; a later
    /// line for the same word replaces an earlier one.
    pub fn parse(tsv: &str) -> Table {
        let mut table = Table {
            nodes: vec![Node::default()],
            rules: Vec::new(),
            starts: vec![0; PLANE / 64].into_boxed_slice(),
            longest: 0,
        };
        for line in tsv.lines() {
            let mut fields = line.split('\t');
            let (Some(from), Some(to)) = (fields.next(), fields.next()) else {
                continue;
            };
            if from.is_empty() {
                continue;
            }
            let set = |s: Option<&str>| {
                let mut chars: Vec<char> = s.unwrap_or("").chars().collect();
                chars.sort_unstable();
                chars.dedup();
                chars.into_boxed_slice()
            };
            let rule = Rule {
                to: to.into(),
                not_before: set(fields.next()),
                not_after: set(fields.next()),
            };
            table.insert(from, rule);
        }
        for node in &mut table.nodes {
            node.next.sort_unstable_by_key(|&(c, _)| c);
        }
        table
    }

    fn insert(&mut self, from: &str, rule: Rule) {
        let mut at = 0usize;
        let mut length = 0;
        for c in from.chars() {
            length += 1;
            let found = self.nodes[at]
                .next
                .iter()
                .find(|&&(d, _)| d == c)
                .map(|&(_, n)| n);
            at = match found {
                Some(n) => n as usize,
                None => {
                    let n = self.nodes.len();
                    self.nodes.push(Node::default());
                    self.nodes[at].next.push((c, n as u32));
                    n
                }
            };
        }
        let first = from
            .chars()
            .next()
            .expect("empty words are skipped in parse") as usize;
        if first < PLANE {
            self.starts[first / 64] |= 1 << (first % 64);
        }
        self.longest = self.longest.max(length);
        match self.nodes[at].rule {
            Some(r) => self.rules[r as usize] = rule,
            None => {
                self.nodes[at].rule = Some(self.rules.len() as u32);
                self.rules.push(rule);
            }
        }
    }

    fn may_start(&self, c: char) -> bool {
        let c = c as usize;
        c < PLANE && self.starts[c / 64] & (1 << (c % 64)) != 0
    }

    fn child(&self, node: usize, c: char) -> Option<usize> {
        let next = &self.nodes[node].next;
        next.binary_search_by_key(&c, |&(d, _)| d)
            .ok()
            .map(|i| next[i].1 as usize)
    }

    /// The rule for the word starting at `chars[at]`, and its length in
    /// characters: the longest one its neighbours allow.
    fn word_at(&self, chars: &[char], at: usize) -> Option<(usize, &Rule)> {
        let mut found = [(0usize, 0u32); 32];
        let mut count = 0;
        let mut node = 0;
        for (i, &c) in chars[at..].iter().enumerate().take(self.longest) {
            let Some(n) = self.child(node, c) else { break };
            node = n;
            if let Some(r) = self.nodes[n].rule
                && count < found.len()
            {
                found[count] = (i + 1, r);
                count += 1;
            }
        }
        let before = at.checked_sub(1).map(|i| chars[i]);
        found[..count].iter().rev().find_map(|&(length, r)| {
            let rule = &self.rules[r as usize];
            rule.allows(before, chars.get(at + length).copied())
                .then_some((length, rule))
        })
    }

    /// [text] with the words replaced, or None when nothing changed.
    pub fn convert(&self, text: &str) -> Option<String> {
        self.convert_around(text, &[])
    }

    /// [convert], leaving alone the characters `locked` covers: (start,
    /// end) ranges in characters, in order, not overlapping.
    pub fn convert_around(&self, text: &str, locked: &[(usize, usize)]) -> Option<String> {
        let first = text.chars().position(|c| self.may_start(c))?;
        let chars: Vec<char> = text.chars().collect();
        let mut out = String::new();
        let mut changed = false;
        let mut at = first;
        let mut kept = 0;
        let mut lock = 0;
        while at < chars.len() {
            while lock < locked.len() && locked[lock].1 <= at {
                lock += 1;
            }
            if let Some(&(start, end)) = locked.get(lock)
                && start <= at
            {
                at = end;
                continue;
            }
            // A word may not reach into the next locked range.
            let room = locked.get(lock).map_or(chars.len(), |&(start, _)| start);
            if self.may_start(chars[at])
                && let Some((length, rule)) = self.word_at(&chars[..room], at)
            {
                let word = &chars[at..at + length];
                if !word.iter().copied().eq(rule.to.chars()) {
                    if !changed {
                        out.reserve(text.len() + text.len() / 4);
                        changed = true;
                    }
                    out.extend(&chars[kept..at]);
                    out.push_str(&rule.to);
                    kept = at + length;
                }
                at += length;
            } else {
                at += 1;
            }
        }
        if !changed {
            return None;
        }
        out.extend(&chars[kept..]);
        Some(out)
    }
}

/// Phrases found in text, each with the rules it stands for: a small trie
/// read once over the text, like [Table].
#[derive(Default)]
struct Phrases {
    nodes: Vec<PhraseNode>,
    longest: usize,
}

#[derive(Default)]
struct PhraseNode {
    next: Vec<(char, u32)>,
    /// The rules a phrase ending here belongs to.
    ends: Vec<u32>,
}

impl Phrases {
    fn add(&mut self, phrase: &str, rule: u32) {
        if self.nodes.is_empty() {
            self.nodes.push(PhraseNode::default());
        }
        let mut at = 0usize;
        let mut length = 0;
        for c in phrase.chars() {
            length += 1;
            let found = self.nodes[at]
                .next
                .iter()
                .find(|&&(d, _)| d == c)
                .map(|&(_, n)| n as usize);
            at = found.unwrap_or_else(|| {
                let n = self.nodes.len();
                self.nodes.push(PhraseNode::default());
                self.nodes[at].next.push((c, n as u32));
                n
            });
        }
        if !self.nodes[at].ends.contains(&rule) {
            self.nodes[at].ends.push(rule);
        }
        self.longest = self.longest.max(length);
    }

    fn finish(&mut self) {
        for node in &mut self.nodes {
            node.next.sort_unstable_by_key(|&(c, _)| c);
        }
    }

    fn child(&self, node: usize, c: char) -> Option<usize> {
        let next = &self.nodes.get(node)?.next;
        next.binary_search_by_key(&c, |&(d, _)| d)
            .ok()
            .map(|i| next[i].1 as usize)
    }

    /// Every phrase in `chars` standing as a whole word: calls `found`
    /// with each one's rules. Phrases may overlap.
    fn each_word(&self, chars: &[char], mut found: impl FnMut(&[u32])) {
        let letter = |i: usize| chars.get(i).is_some_and(|c| c.is_alphanumeric());
        for at in 0..chars.len() {
            if at > 0 && letter(at - 1) {
                continue;
            }
            let mut node = 0;
            for (i, &c) in chars[at..].iter().enumerate().take(self.longest) {
                let Some(n) = self.child(node, c) else { break };
                node = n;
                if !self.nodes[n].ends.is_empty() && !letter(at + i + 1) {
                    found(&self.nodes[n].ends);
                }
            }
        }
    }

    /// The longest phrase starting at `chars[at]` whose rule `wanted`
    /// allows: its length and rule.
    fn longest_at(
        &self,
        chars: &[char],
        at: usize,
        wanted: impl Fn(u32) -> bool,
    ) -> Option<(usize, u32)> {
        let mut best = None;
        let mut node = 0;
        for (i, &c) in chars[at..].iter().enumerate().take(self.longest) {
            let Some(n) = self.child(node, c) else { break };
            node = n;
            if let Some(&rule) = self.nodes[n].ends.iter().find(|&&r| wanted(r)) {
                best = Some((i + 1, rule));
            }
        }
        best
    }
}

/// Rules that look at the original: each turns its Chinese words into one
/// word when the original says what calls for it.
pub struct Sourced {
    /// The original's words, lower case; [unless] those that rule a rule out.
    calls: Phrases,
    unless: Phrases,
    /// The Chinese words a service writes, and what each rule makes them.
    words: Phrases,
    to: Vec<Box<str>>,
}

impl Sourced {
    /// Rules from lines of `original words\tunless\tChinese words\tto`,
    /// the words of a field split by `|`.
    pub fn parse(tsv: &str) -> Sourced {
        let mut sourced = Sourced {
            calls: Phrases::default(),
            unless: Phrases::default(),
            words: Phrases::default(),
            to: Vec::new(),
        };
        for line in tsv.lines() {
            let fields: Vec<&str> = line.split('\t').collect();
            let [calls, unless, words, to] = fields[..] else {
                continue;
            };
            let rule = sourced.to.len() as u32;
            let words_of = |field: &str| {
                field
                    .split('|')
                    .filter(|w| !w.is_empty())
                    .map(str::to_owned)
                    .collect::<Vec<_>>()
            };
            for w in words_of(calls) {
                sourced.calls.add(&w, rule);
            }
            for w in words_of(unless) {
                sourced.unless.add(&w, rule);
            }
            for w in words_of(words) {
                sourced.words.add(&w, rule);
            }
            sourced.to.push(to.into());
        }
        sourced.calls.finish();
        sourced.unless.finish();
        sourced.words.finish();
        sourced
    }

    /// [text] (the translation of [original]) with the words the original
    /// calls for, and where those words are now (character ranges); None
    /// when nothing changed. One pass over each.
    pub fn convert(&self, text: &str, original: &str) -> Option<(String, Vec<(usize, usize)>)> {
        if original.is_empty() || self.to.is_empty() {
            return None;
        }
        let original: Vec<char> = original.to_lowercase().chars().collect();
        let mut called = vec![0usize; self.to.len()];
        self.calls.each_word(&original, |rules| {
            for &r in rules {
                called[r as usize] += 1;
            }
        });
        if called.iter().all(|&n| n == 0) {
            return None;
        }
        self.unless.each_word(&original, |rules| {
            for &r in rules {
                called[r as usize] = 0;
            }
        });
        let chars: Vec<char> = text.chars().collect();
        // Where each called rule's words are, longest first.
        let mut places = Vec::new();
        let mut used = vec![0usize; self.to.len()];
        let mut at = 0;
        while at < chars.len() {
            match self
                .words
                .longest_at(&chars, at, |r| called[r as usize] > 0)
            {
                Some((length, rule)) => {
                    places.push((at, length, rule));
                    used[rule as usize] += 1;
                    at += length;
                }
                None => at += 1,
            }
        }
        // A rule whose words come more often than the original calls for
        // them leaves them all: some may mean what they say.
        let mut out = String::with_capacity(text.len() + 16);
        let mut locked = Vec::new();
        let mut written = 0;
        let mut kept = 0;
        for (at, length, rule) in places {
            let r = rule as usize;
            if used[r] > called[r] {
                continue;
            }
            out.extend(&chars[kept..at]);
            written += at - kept;
            let to = &self.to[r];
            let count = to.chars().count();
            locked.push((written, written + count));
            out.push_str(to);
            written += count;
            kept = at + length;
        }
        if locked.is_empty() {
            return None;
        }
        out.extend(&chars[kept..]);
        Some((out, locked))
    }
}

/// Which Chinese a translation is in.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Region {
    Simplified,
    /// Traditional characters, with Taiwan's words.
    Taiwan,
    /// Traditional characters, with Hong Kong's words.
    HongKong,
}

/// The wording to write: a [Region]'s, for a Latin-rite or a Byzantine-rite
/// (Eastern Catholic) video, whose Great Lent is 大斋期, not 四旬期.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Variant {
    pub region: Region,
    pub byzantine: bool,
}

impl Variant {
    pub const SIMPLIFIED: Variant = Variant {
        region: Region::Simplified,
        byzantine: false,
    };
    pub const TAIWAN: Variant = Variant {
        region: Region::Taiwan,
        byzantine: false,
    };
    pub const HONG_KONG: Variant = Variant {
        region: Region::HongKong,
        byzantine: false,
    };

    /// From Dart's number: 0 simplified, 1 Taiwan, 2 Hong Kong, plus 4 for
    /// the Byzantine rite.
    pub fn of(code: u32) -> Variant {
        let region = match code & 3 {
            1 => Region::Taiwan,
            2 => Region::HongKong,
            _ => Region::Simplified,
        };
        Variant {
            region,
            byzantine: code & 4 != 0,
        }
    }

    fn table(self) -> &'static Table {
        macro_rules! table {
            ($file:literal) => {{
                static TABLE: LazyLock<Table> = LazyLock::new(|| {
                    Table::parse(include_str!(concat!("../church_words/", $file)))
                });
                &TABLE
            }};
        }
        match (self.region, self.byzantine) {
            (Region::Simplified, false) => table!("hans.tsv"),
            (Region::Simplified, true) => table!("hans-byzantine.tsv"),
            (Region::Taiwan, false) => table!("hant.tsv"),
            (Region::Taiwan, true) => table!("hant-byzantine.tsv"),
            (Region::HongKong, false) => table!("hk.tsv"),
            (Region::HongKong, true) => table!("hk-byzantine.tsv"),
        }
    }

    fn sourced(self) -> &'static Sourced {
        macro_rules! sourced {
            ($file:literal) => {{
                static SOURCED: LazyLock<Sourced> = LazyLock::new(|| {
                    Sourced::parse(include_str!(concat!("../church_words/", $file)))
                });
                &SOURCED
            }};
        }
        match self.region {
            Region::Simplified => sourced!("sourced-hans.tsv"),
            Region::Taiwan => sourced!("sourced-hant.tsv"),
            Region::HongKong => sourced!("sourced-hk.tsv"),
        }
    }
}

/// [text], a translation into Chinese in [variant] of [original] (empty
/// when unknown), in Catholic wording, or None when nothing changes. The
/// [Sourced] rules the original calls for come first and stay as they
/// write; then the words of the table.
pub fn church_words(text: &str, original: &str, variant: Variant) -> Option<String> {
    match variant.sourced().convert(text, original) {
        Some((sourced, locked)) => Some(
            variant
                .table()
                .convert_around(&sourced, &locked)
                .unwrap_or(sourced),
        ),
        None => variant.table().convert(text),
    }
}

/// [church_words] for Dart, with [Variant::of]'s number: null when nothing
/// changed. Free the text with `lumtub_string_free`.
///
/// # Safety
/// [text] and [original] must point to [length] and [original_length]
/// bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_church_words(
    variant: u32,
    text: *const u8,
    length: usize,
    original: *const u8,
    original_length: usize,
) -> *mut std::ffi::c_char {
    // SAFETY: the caller passes `length` bytes at `text`, as `# Safety` asks.
    let text = unsafe { crate::taste::text(text, length) };
    // SAFETY: the caller passes `original_length` bytes at `original`, as
    // `# Safety` asks.
    let original = unsafe { crate::taste::text(original, original_length) };
    match church_words(text, original, Variant::of(variant)) {
        Some(out) => crate::taste::give(out.replace('\0', "")),
        None => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn in_variant(text: &str, original: &str, variant: Variant) -> String {
        church_words(text, original, variant).unwrap_or_else(|| text.to_owned())
    }

    fn simplified(text: &str) -> String {
        in_variant(text, "", Variant::SIMPLIFIED)
    }

    fn traditional(text: &str) -> String {
        in_variant(text, "", Variant::TAIWAN)
    }

    fn hong_kong(text: &str) -> String {
        in_variant(text, "", Variant::HONG_KONG)
    }

    fn beside(text: &str, original: &str) -> String {
        in_variant(text, original, Variant::SIMPLIFIED)
    }

    #[test]
    fn passes_the_shared_cases() {
        #[derive(serde::Deserialize)]
        struct Case {
            dir: String,
            #[serde(rename = "in")]
            input: String,
            out: String,
        }
        #[derive(serde::Deserialize)]
        struct Cases {
            cases: Vec<Case>,
        }
        let cases: Cases =
            serde_json::from_str(include_str!("../church_words/cases.json")).unwrap();
        let mut tried = 0;
        for case in cases.cases.iter().filter(|c| c.dir == "p2c") {
            assert_eq!(simplified(&case.input), case.out, "{}", case.input);
            tried += 1;
        }
        assert!(tried > 20);
        for line in include_str!("../church_words/cases-hant.tsv").lines() {
            let (input, out) = line.split_once('\t').unwrap();
            assert_eq!(traditional(input), out, "{input}");
        }
    }

    #[test]
    fn writes_traditional_text_the_catholic_way() {
        assert_eq!(traditional("西門彼得對約翰說"), "西滿伯多祿對若望說");
        assert_eq!(
            traditional("上帝的彌賽亞，聖靈降臨"),
            "天主的默西亞，聖神降臨"
        );
        assert_eq!(traditional("他行了神蹟，神父來了"), "他行了神蹟，神父來了");
        assert_eq!(traditional("摩西在西奈山"), "梅瑟在西乃山");
        assert_eq!(traditional("就不能進入神的國"), "就不能進入天主的國");
        assert_eq!(traditional("那位牧師在主持彌撒"), "那位神父在主持彌撒");
    }

    #[test]
    fn leaves_text_without_the_words_alone() {
        for text in ["", "hello", "今天天气很好", "他是一个好人。", "🙂神"] {
            assert_eq!(
                church_words(text, "", Variant::SIMPLIFIED),
                if text == "🙂神" {
                    Some("🙂天主".into())
                } else {
                    None
                },
                "{text}"
            );
        }
        // A word written as the Catholic Church writes it is not changed.
        assert_eq!(church_words("天主的默西亚", "", Variant::SIMPLIFIED), None);
        assert_eq!(simplified("牧师在做弥撒"), "神父在做弥撒");
    }

    #[test]
    fn needs_one_pass_over_long_text() {
        let line = "西门彼得对约翰说，上帝的弥赛亚来了。今天的天气很好，我们去散步吧。";
        let text = line.repeat(20_000);
        let start = std::time::Instant::now();
        let out = simplified(&text);
        assert!(out.starts_with("西满伯多禄对若望说，天主的默西亚来了。"));
        // About 700,000 characters; a debug build takes well under this.
        assert!(
            start.elapsed() < std::time::Duration::from_secs(5),
            "{:?}",
            start.elapsed()
        );
    }

    #[test]
    fn writes_hong_kong_and_taiwan_their_own_way() {
        assert_eq!(traditional("阿門，哈利路亞"), "阿們，阿肋路亞");
        assert_eq!(hong_kong("阿門，哈利路亞"), "亞孟，亞肋路亞");
        assert_eq!(
            hong_kong("他去辦和好聖事，又去了法蒂瑪"),
            "他去辦修和聖事，又去了花地瑪"
        );
        assert_eq!(
            traditional("他去辦和好聖事，又去了法蒂瑪"),
            "他去辦和好聖事，又去了法蒂瑪"
        );
        // Both write 思高本 names alike.
        assert_eq!(hong_kong("西門彼得對約翰說"), "西滿伯多祿對若望說");
        assert_eq!(
            simplified("阿门。圣灵降临节和降临节"),
            "阿们。圣神降临节和将临期"
        );
    }

    #[test]
    fn knows_feasts_devotions_and_saints_in_every_language() {
        assert_eq!(
            beside("皮奥父亲的遗体", "Il corpo di Padre Pio"),
            "碧岳神父的遗体"
        );
        assert_eq!(
            beside("孩子们的第一次交流", "La prima comunione dei bambini"),
            "孩子们的初领圣体"
        );
        assert_eq!(beside("耶稣的神圣心脏", "Herz-Jesu-Freitag"), "耶稣圣心");
        assert_eq!(
            beside("净化之火中的灵魂", "Die Seelen im Fegefeuer"),
            "炼狱中的灵魂"
        );
        assert_eq!(beside("圣母假设", "L'Assomption de Marie"), "圣母蒙召升天");
        assert_eq!(
            in_variant("聖母無原罪始胎", "Immaculate Conception", Variant::TAIWAN),
            "聖母始胎無染原罪"
        );
        assert_eq!(
            beside("露西亚修女和约瑟夫·拉辛格", "Irmã Lúcia e Joseph Ratzinger"),
            "路济亚修女和若瑟·拉青格"
        );
        assert_eq!(beside("拉辛格枢机", "Kardinal Ratzinger"), "拉青格枢机");
        assert_eq!(
            beside(
                "大天使迈克尔、加布里埃尔和拉斐尔",
                "Archangels St. Michael, St. Gabriel and St. Raphael"
            ),
            "总领天使弥额尔、加俾额尔和辣法耳"
        );
        assert_eq!(
            beside("拉斐尔的壁画", "Gli affreschi di Raffaello"),
            "拉斐尔的壁画"
        );
        assert_eq!(simplified("天使拉斐尔陪伴多俾亚"), "天使辣法耳陪伴多俾亚");
        // An English assumption is only an assumption.
        assert_eq!(
            beside("这个假设是错的", "This assumption is wrong"),
            "这个假设是错的"
        );
        // Already right stays right.
        assert_eq!(
            beside("基督圣体圣血节游行", "Corpus Christi procession"),
            "基督圣体圣血节游行"
        );
        assert_eq!(
            beside("基督圣体游行", "Fronleichnamsprozession"),
            "基督圣体游行"
        );
        assert_eq!(
            beside("基督圣体游行", "Corpus Domini, processione"),
            "基督圣体圣血节游行"
        );
        assert_eq!(
            beside("牧师说", "Der evangelische Pfarrer sagt"),
            simplified("牧师说")
        );
    }

    #[test]
    fn changes_what_the_original_calls_for_and_no_more() {
        assert_eq!(
            beside("圣父抵达罗马", "Il Santo Padre arriva a Roma"),
            "教宗抵达罗马"
        );
        // Said once, written twice: one of them may be God the Father.
        assert_eq!(
            beside("圣父向圣父祈祷", "Il Santo Padre prega"),
            "圣父向圣父祈祷"
        );
        // Without the original's words, 圣父 is God the Father.
        assert_eq!(
            beside("我们向圣父祈祷", "Preghiamo il Padre"),
            "我们向圣父祈祷"
        );
        assert_eq!(
            beside("麦当娜，请为我们祈祷", "Madonna, prega per noi"),
            "圣母，请为我们祈祷"
        );
        assert_eq!(
            beside("麦当娜开了演唱会", "Il concerto di Lady Gaga"),
            "麦当娜开了演唱会"
        );
        assert_eq!(
            beside("今天的展会", "Die heilige Messe heute"),
            "今天的弥撒"
        );
        assert_eq!(beside("今天的展会", "Die Messestadt heute"), "今天的展会");
        assert_eq!(beside("治疗来了", "Llegó el cura"), "神父来了");
        assert_eq!(beside("治疗很有效", "La cura es eficaz"), "治疗很有效");
        assert_eq!(beside("我们的女士", "Notre-Dame de Lourdes"), "圣母");
        assert_eq!(
            beside("巴黎圣母院着火了", "Notre-Dame de Paris brûle"),
            "巴黎圣母院着火了"
        );
        assert_eq!(
            beside("万圣节是十一月一日", "All Saints' Day is November 1"),
            "诸圣节是十一月一日"
        );
        assert_eq!(
            beside("万圣节要穿装扮", "Halloween costumes"),
            "万圣节要穿装扮"
        );
        assert_eq!(
            beside("教区牧师在讲道", "Il parroco predica"),
            "本堂神父在讲道"
        );
        assert_eq!(beside("玛丽亚姐妹说", "Suor Maria dice"), "玛丽亚修女说");
        assert_eq!(beside("我的姐妹说", "Mia sorella dice"), "我的姐妹说");
        assert_eq!(church_words("圣父", "", Variant::SIMPLIFIED), None);
        assert_eq!(
            church_words("聖父抵達羅馬", "Il Santo Padre arriva", Variant::HONG_KONG),
            Some("教宗抵達羅馬".into())
        );
    }

    #[test]
    fn leaves_what_must_not_change() {
        for text in [
            "顾客是上帝",
            "彼得大帝建立了圣彼得堡",
            "圣奥斯定的忏悔录",
            "犹大旷野",
            "犹大支派",
            "他有精神，眼神很好，研究神学",
            "无神论者",
            "外邦人的众神和假神",
            "战火的洗礼",
            "亚伯拉罕·林肯",
            "神父来了",
        ] {
            assert_eq!(simplified(text), text, "{text}");
        }
    }

    #[test]
    fn keeps_the_byzantine_rite_its_own() {
        let byzantine = Variant {
            region: Region::Simplified,
            byzantine: true,
        };
        // Great Lent stays 大斋期 in a Byzantine video, by its original or not.
        assert_eq!(
            in_variant("大斋期开始了", "Great Lent begins", byzantine),
            "大斋期开始了"
        );
        assert_eq!(
            in_variant("四旬期开始了", "Great Lent begins", Variant::SIMPLIFIED),
            "大斋期开始了"
        );
        assert_eq!(in_variant("大斋期开始了", "", byzantine), "大斋期开始了");
        assert_eq!(simplified("大斋期开始了"), "四旬期开始了");
        assert_eq!(
            in_variant("弥撒结束后", "After the Divine Liturgy", byzantine),
            "神圣礼仪结束后"
        );
        assert_eq!(in_variant("坚振圣事", "Chrismation", byzantine), "傅油圣事");
        assert_eq!(
            in_variant("大主教说", "The Major Archbishop said", byzantine),
            "大总主教说"
        );
        assert_eq!(simplified("大主教说"), "总主教说");
        assert_eq!(in_variant("诞神女", "Theotokos", byzantine), "天主之母");
        assert_eq!(in_variant("回指", "The Anaphora", byzantine), "献礼经");
    }

    #[test]
    fn writes_the_church_s_words_for_sacraments() {
        assert_eq!(simplified("领圣餐以后去坚信礼"), "领圣体以后去坚振圣事");
        assert_eq!(beside("他去忏悔了", "He went to confession"), "他去告解了");
        assert_eq!(
            beside("圣奥斯定的忏悔录", "The Confessions of Saint Augustine"),
            "圣奥斯定的忏悔录"
        );
        assert_eq!(beside("教区的质量", "The parish Mass"), "堂区的弥撒");
        // Diocese and parish both said: 教区 may be the diocese, kept.
        assert_eq!(
            beside("教区和教区", "The diocese and the parish"),
            "教区和教区"
        );
        assert_eq!(traditional("婚姻聖禮"), "婚姻聖事");
        assert_eq!(hong_kong("婚姻聖禮"), "婚配聖事");
        assert_eq!(hong_kong("神聖慈悲主日"), "救主慈悲主日");
        assert_eq!(traditional("神聖慈悲主日"), "天主慈悲主日");
    }
}
