//! Catholic Chinese wording for translations of Catholic videos: the names
//! and terms a translation service writes the Protestant way (和合本: 上帝,
//! 圣灵, 彼得, 摩西) put the way the Catholic Church in Chinese writes them
//! (思高本: 天主, 圣神, 伯多禄, 梅瑟).
//!
//! The rules come from church_words/terms.json and Lumtub's own
//! church_words/extra.json (see church_words/make.py),
//! one table in simplified and one in traditional characters. Each rule may
//! name characters that must not stand before or after its word, so that
//! 神 becomes 天主 but 神父, 精神 and 神迹 stay.
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
        let first = from.chars().next().unwrap() as usize;
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
        let first = text.chars().position(|c| self.may_start(c))?;
        let chars: Vec<char> = text.chars().collect();
        let mut out = String::new();
        let mut changed = false;
        let mut at = first;
        let mut kept = 0;
        while at < chars.len() {
            if self.may_start(chars[at])
                && let Some((length, rule)) = self.word_at(&chars, at)
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

static SIMPLIFIED: LazyLock<Table> =
    LazyLock::new(|| Table::parse(include_str!("../church_words/hans.tsv")));
static TRADITIONAL: LazyLock<Table> =
    LazyLock::new(|| Table::parse(include_str!("../church_words/hant.tsv")));

/// [text] (Chinese, [traditional] or simplified) in Catholic wording, or
/// None when it has nothing to change.
pub fn church_words(text: &str, traditional: bool) -> Option<String> {
    if traditional {
        &TRADITIONAL
    } else {
        &SIMPLIFIED
    }
    .convert(text)
}

/// [church_words] for Dart: null when nothing changed. Free the text with
/// `lumtub_string_free`.
///
/// # Safety
/// [text] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_church_words(
    traditional: bool,
    text: *const u8,
    length: usize,
) -> *mut std::ffi::c_char {
    match church_words(unsafe { crate::taste::text(text, length) }, traditional) {
        Some(out) => crate::taste::give(out.replace('\0', "")),
        None => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn simplified(text: &str) -> String {
        church_words(text, false).unwrap_or_else(|| text.to_owned())
    }

    fn traditional(text: &str) -> String {
        church_words(text, true).unwrap_or_else(|| text.to_owned())
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
                church_words(text, false),
                if text == "🙂神" {
                    Some("🙂天主".into())
                } else {
                    None
                },
                "{text}"
            );
        }
        // A word written as the Catholic Church writes it is not changed.
        assert_eq!(church_words("天主的默西亚", false), None);
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
}
