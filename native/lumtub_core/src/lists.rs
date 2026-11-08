//! Block lists kept as text under `lists/` (see lists/schema.md): parsed,
//! checked and compiled into the one `lists.json` the app reads.

use std::collections::HashSet;
use std::fmt;

use serde::Serialize;

/// What happens to a channel a list matches.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Action {
    Hide,
    Quiet,
    Demote,
    Label,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Confirmed,
    Unproven,
}

/// Every category with its tier: 0 for safety lists, which alone may be on
/// for a new install; 1 and 2 are offered on first run.
pub const CATEGORIES: [(&str, u8); 11] = [
    ("financial-scams", 0),
    ("malware-phishing", 0),
    ("medical-fraud", 0),
    ("ai-slop", 1),
    ("clickbait-reuploads", 1),
    ("religion", 1),
    ("state-media", 2),
    ("influence-operations", 2),
    ("new-age", 2),
    ("misinformation-farms", 2),
    ("deceptive-marketing", 2),
];

/// The tier of [category], if it is one.
pub fn tier(category: &str) -> Option<u8> {
    CATEGORIES.iter().find(|(c, _)| *c == category).map(|(_, t)| *t)
}

/// One channel of a list, with every way it is matched.
#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct Record {
    pub slug: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub ids: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub handles: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub names: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub prefixes: Vec<String>,
    #[serde(skip_serializing_if = "is_confirmed")]
    pub status: Option<Status>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub sources: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reviewed: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub legacy: Vec<String>,
}

fn is_confirmed(status: &Option<Status>) -> bool {
    !matches!(status, Some(Status::Unproven))
}

/// One list file.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct List {
    pub id: String,
    pub name: String,
    /// Translated names, by language tag.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub names: Vec<(String, String)>,
    pub categories: Vec<String>,
    pub action: Action,
    pub default_on: bool,
    /// Words a search names this list's subject by.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub topics: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub sources: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub legacy: Vec<String>,
    pub records: Vec<Record>,
}

/// A mistake in a list file, with its line.
#[derive(Debug, PartialEq, Eq)]
pub struct ListError {
    pub line: usize,
    pub message: String,
}

impl fmt::Display for ListError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "line {}: {}", self.line, self.message)
    }
}

fn slug_ok(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

/// Whether [text] is a YouTube channel id: UC and 22 characters of the
/// URL-safe base 64 alphabet.
pub fn channel_id_ok(text: &str) -> bool {
    text.len() == 24 && text.starts_with("UC") && text.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

/// [line] cut at each `|` that is not escaped, with `\|` and `\\` undone
/// and the spaces around each field dropped.
fn fields(line: &str) -> Result<Vec<String>, String> {
    let mut out = Vec::new();
    let mut field = String::new();
    let mut chars = line.chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' => match chars.next() {
                Some(next @ ('|' | '\\')) => field.push(next),
                Some(other) => return Err(format!("unknown escape \\{other}")),
                None => return Err("\\ at the end of the line".into()),
            },
            '|' => out.push(std::mem::take(&mut field).trim().to_string()),
            _ => field.push(c),
        }
    }
    out.push(field.trim().to_string());
    Ok(out)
}

/// Parses one list file. [file_id] is its name without `.txt`, which the
/// `id` header must repeat.
pub fn parse(text: &str, file_id: &str) -> Result<List, Vec<ListError>> {
    let mut errors = Vec::new();
    let mut err = |line: usize, message: String| errors.push(ListError { line, message });
    let text = text.strip_prefix('\u{feff}').map_or(text, |t| {
        err(1, "the file starts with a byte order mark".into());
        t
    });
    let mut id = None;
    let mut name = None;
    let mut names = Vec::new();
    let mut categories = Vec::new();
    let mut action = None;
    let mut default_on = None;
    let mut note = None;
    let mut topics = Vec::new();
    let mut sources = Vec::new();
    let mut legacy = Vec::new();
    let mut records: Vec<Record> = Vec::new();
    let mut slugs = HashSet::new();
    let mut seen = HashSet::new();
    for (index, raw) in text.split('\n').enumerate() {
        let line = index + 1;
        let raw = raw.strip_suffix('\r').unwrap_or(raw);
        if raw.trim().is_empty() || raw.trim_start().starts_with('#') {
            continue;
        }
        if raw.starts_with(' ') || raw.starts_with('\t') {
            let Some(record) = records.last_mut() else {
                err(line, "an indented attribute before any record".into());
                continue;
            };
            let Some((key, value)) = raw.trim().split_once(':') else {
                err(line, "an attribute needs key: value".into());
                continue;
            };
            let value = value.trim().to_string();
            match key.trim() {
                "status" => match value.as_str() {
                    "confirmed" => record.status = Some(Status::Confirmed),
                    "unproven" => record.status = Some(Status::Unproven),
                    _ => err(line, format!("status is confirmed or unproven, not {value}")),
                },
                "source" if value.starts_with("https://") || value.starts_with("http://") => record.sources.push(value),
                "source" => err(line, "a source is an http or https address".into()),
                "reviewed" if date_ok(&value) => record.reviewed = Some(value),
                "reviewed" => err(line, "reviewed is a date as YYYY-MM-DD".into()),
                "note" => record.note = Some(value),
                "legacy" => record.legacy.push(value),
                other => err(line, format!("unknown attribute {other}")),
            }
            continue;
        }
        if let Some(header) = raw.strip_prefix('!') {
            if !records.is_empty() {
                err(line, "a header line after the first record".into());
                continue;
            }
            let Some((key, value)) = header.split_once(':') else {
                err(line, "a header needs ! key: value".into());
                continue;
            };
            let (key, value) = (key.trim(), value.trim().to_string());
            match key {
                "id" => id = Some(value),
                "name" => name = Some(value),
                "category" => {
                    for c in value.split(',').map(str::trim) {
                        if tier(c).is_some() {
                            categories.push(c.to_string());
                        } else {
                            err(line, format!("unknown category {c}"));
                        }
                    }
                }
                "action" => match value.as_str() {
                    "hide" => action = Some(Action::Hide),
                    "quiet" => action = Some(Action::Quiet),
                    "demote" => action = Some(Action::Demote),
                    "label" => action = Some(Action::Label),
                    _ => err(line, format!("action is hide, quiet, demote or label, not {value}")),
                },
                "default" => match value.as_str() {
                    "on" => default_on = Some(true),
                    "off" => default_on = Some(false),
                    _ => err(line, format!("default is on or off, not {value}")),
                },
                "note" => note = Some(value),
                "topic" if !value.is_empty() => topics.push(value),
                "topic" => err(line, "an empty topic".into()),
                "source" if value.starts_with("https://") || value.starts_with("http://") => sources.push(value),
                "source" => err(line, "a source is an http or https address".into()),
                "legacy" => legacy.push(value),
                _ => match key.strip_prefix("name.") {
                    Some(lang) if !lang.is_empty() => names.push((lang.to_string(), value)),
                    _ => err(line, format!("unknown header {key}")),
                },
            }
            continue;
        }
        let Some(rest) = raw.strip_prefix(':') else {
            err(line, "a record starts with :slug".into());
            continue;
        };
        let parts = match fields(rest) {
            Ok(parts) => parts,
            Err(message) => {
                err(line, message);
                continue;
            }
        };
        let mut record = Record { slug: parts[0].clone(), ..Record::default() };
        if !slug_ok(&record.slug) {
            err(line, format!("the slug {:?} is not lowercase letters, digits and -", record.slug));
        } else if !slugs.insert(record.slug.clone()) {
            err(line, format!("the slug {} is used twice", record.slug));
        }
        for part in &parts[1..] {
            if part.is_empty() {
                err(line, "an empty condition".into());
            } else if let Some(handle) = part.strip_prefix('@') {
                if handle.is_empty() || handle.contains(char::is_whitespace) {
                    err(line, format!("the handle {part} is not one word"));
                } else {
                    record.handles.push(handle.to_lowercase());
                }
            } else if let Some(name) = part.strip_prefix('=') {
                if name.trim().is_empty() {
                    err(line, "= without a name".into());
                } else {
                    record.names.push(name.trim().to_string());
                }
            } else if let Some(prefix) = part.strip_prefix('^') {
                if prefix.trim().is_empty() {
                    err(line, "^ without a name".into());
                } else {
                    record.prefixes.push(prefix.trim().to_string());
                }
            } else if part.starts_with("UC") {
                if channel_id_ok(part) {
                    record.ids.push(part.clone());
                } else {
                    err(line, format!("{part} is not a channel id"));
                }
            } else {
                err(line, format!("{part} has no prefix: UC…, @, = or ^"));
            }
        }
        if parts.len() < 2 {
            err(line, format!("the record {} matches nothing", record.slug));
        }
        let conditions = record.ids.iter().map(|i| format!("id:{i}"))
            .chain(record.handles.iter().map(|h| format!("@{h}")))
            .chain(record.names.iter().map(|n| format!("={}", n.to_lowercase())))
            .chain(record.prefixes.iter().map(|p| format!("^{}", p.to_lowercase())));
        for condition in conditions {
            if !seen.insert(condition.clone()) {
                err(line, format!("{condition} is already in another record of this list"));
            }
        }
        records.push(record);
    }
    let (id, name, action, default_on) = (
        id.unwrap_or_else(|| {
            err(1, "the id header is missing".into());
            String::new()
        }),
        name.unwrap_or_else(|| {
            err(1, "the name header is missing".into());
            String::new()
        }),
        action.unwrap_or_else(|| {
            err(1, "the action header is missing".into());
            Action::Hide
        }),
        default_on.unwrap_or_else(|| {
            err(1, "the default header is missing".into());
            false
        }),
    );
    if !id.is_empty() && id != file_id {
        err(1, format!("the id {id} differs from the file name {file_id}"));
    }
    if !id.is_empty() && !slug_ok(&id) {
        err(1, format!("the id {id} is not lowercase letters, digits and -"));
    }
    if categories.is_empty() {
        err(1, "the category header is missing".into());
    }
    if records.is_empty() {
        err(1, "the list has no records".into());
    }
    let safety = !categories.is_empty() && categories.iter().all(|c| tier(c) == Some(0));
    if default_on && !safety {
        err(1, "only a list of safety categories alone may be on by default".into());
    }
    if safety && !topics.is_empty() {
        err(1, "a safety list has no topic: searches about scams must not bring the scams up".into());
    }
    if safety {
        for record in records.iter().filter(|r| r.status == Some(Status::Unproven)) {
            err(1, format!("the record {} is unproven, and a safety list takes confirmed records only", record.slug));
        }
    }
    for record in records.iter().filter(|r| r.status != Some(Status::Unproven) && r.sources.is_empty()) {
        if safety {
            err(1, format!("the record {} has no source, and every record of a safety list needs its own", record.slug));
        } else if sources.is_empty() {
            err(1, format!("the record {} is confirmed but neither it nor the list has a source", record.slug));
        }
    }
    if !errors.is_empty() {
        return Err(errors);
    }
    Ok(List { id, name, names, categories, action, default_on, topics, note, sources, legacy, records })
}

fn date_ok(text: &str) -> bool {
    let b = text.as_bytes();
    b.len() == 10 && b[4] == b'-' && b[7] == b'-' && b.iter().enumerate().all(|(i, c)| i == 4 || i == 7 || c.is_ascii_digit())
}

/// The compiled form of every list, as the app reads it.
#[derive(Serialize)]
pub struct Bundle<'a> {
    pub version: u64,
    pub built: &'a str,
    pub lists: &'a [List],
}

/// Reads every `<category>/<id>.txt` under [dir], with `retired.txt` at its
/// top. Each list must sit in the folder of one of its categories.
pub fn load_dir(dir: &std::path::Path) -> Result<(Vec<List>, HashSet<String>), Vec<String>> {
    let mut problems = Vec::new();
    let mut lists = Vec::new();
    let retired = match std::fs::read_to_string(dir.join("retired.txt")) {
        Ok(text) => text.lines().map(str::trim).filter(|l| !l.is_empty() && !l.starts_with('#')).map(String::from).collect(),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => HashSet::new(),
        Err(e) => return Err(vec![format!("retired.txt: {e}")]),
    };
    let mut folders: Vec<_> = match std::fs::read_dir(dir) {
        Ok(entries) => entries.filter_map(Result::ok).filter(|e| e.path().is_dir()).map(|e| e.path()).collect(),
        Err(e) => return Err(vec![format!("{}: {e}", dir.display())]),
    };
    folders.sort();
    for folder in folders {
        let category = folder.file_name().and_then(|n| n.to_str()).unwrap_or_default().to_string();
        if tier(&category).is_none() {
            problems.push(format!("{category}/ is not a category"));
            continue;
        }
        let mut files: Vec<_> = std::fs::read_dir(&folder).into_iter().flatten().filter_map(Result::ok).map(|e| e.path()).collect();
        files.sort();
        for file in files {
            let shown = format!("{category}/{}", file.file_name().and_then(|n| n.to_str()).unwrap_or_default());
            let Some(file_id) = file.file_name().and_then(|n| n.to_str()).and_then(|n| n.strip_suffix(".txt")) else {
                problems.push(format!("{shown}: only .txt files belong here"));
                continue;
            };
            let text = match std::fs::read(&file).map(String::from_utf8) {
                Ok(Ok(text)) => text,
                Ok(Err(_)) => {
                    problems.push(format!("{shown}: not UTF-8"));
                    continue;
                }
                Err(e) => {
                    problems.push(format!("{shown}: {e}"));
                    continue;
                }
            };
            match parse(&text, file_id) {
                Ok(list) if !list.categories.contains(&category) => {
                    problems.push(format!("{shown}: the list is not in the {category} category"));
                }
                Ok(list) => lists.push(list),
                Err(errors) => problems.extend(errors.iter().map(|e| format!("{shown}: {e}"))),
            }
        }
    }
    problems.extend(check_all(&lists, &retired));
    if problems.is_empty() { Ok((lists, retired)) } else { Err(problems) }
}

fn conditions(record: &Record) -> Vec<String> {
    let mut all: Vec<String> = record.ids.iter().cloned()
        .chain(record.handles.iter().map(|h| format!("@{h}")))
        .chain(record.names.iter().map(|n| format!("={n}")))
        .chain(record.prefixes.iter().map(|p| format!("^{p}")))
        .collect();
    all.sort();
    all
}

/// Record keys of [old] that [new] dropped without writing them to
/// [retired]: a check fails on these, since a saved choice could later
/// point at a different channel.
pub fn unretired(old: &[List], new: &[List], retired: &HashSet<String>) -> Vec<String> {
    let mut problems = Vec::new();
    for list in old {
        let now = new.iter().find(|n| n.id == list.id);
        for record in &list.records {
            let key = format!("{}/{}", list.id, record.slug);
            if !now.is_some_and(|n| n.records.iter().any(|r| r.slug == record.slug)) && !retired.contains(&key) {
                problems.push(format!("{key} was removed but is not in retired.txt"));
            }
        }
    }
    problems
}

/// What changed from [old] to [new], one line each, for review: lists and
/// records added or removed, and changes to conditions, actions, defaults,
/// status, sources, review dates and notes.
pub fn diff(old: &[List], new: &[List], retired: &HashSet<String>) -> Vec<String> {
    let mut lines = Vec::new();
    for list in old.iter().filter(|o| !new.iter().any(|n| n.id == o.id)) {
        lines.push(format!("- list {} ({} records)", list.id, list.records.len()));
    }
    for list in new {
        let Some(before) = old.iter().find(|o| o.id == list.id) else {
            lines.push(format!("+ list {} ({} records, {:?}, {})", list.id, list.records.len(), list.action, if list.default_on { "on" } else { "off" }));
            continue;
        };
        if before.action != list.action {
            lines.push(format!("~ list {} action {:?} -> {:?}", list.id, before.action, list.action));
        }
        if before.default_on != list.default_on {
            lines.push(format!("~ list {} default {} -> {}", list.id, before.default_on, list.default_on));
        }
        if before.categories != list.categories {
            lines.push(format!("~ list {} category {} -> {}", list.id, before.categories.join(","), list.categories.join(",")));
        }
        for record in before.records.iter().filter(|r| !list.records.iter().any(|n| n.slug == r.slug)) {
            let key = format!("{}/{}", list.id, record.slug);
            let note = if retired.contains(&key) { "" } else { " (not in retired.txt)" };
            lines.push(format!("- {key}{note}"));
        }
        for record in &list.records {
            let key = format!("{}/{}", list.id, record.slug);
            let now = conditions(record);
            match before.records.iter().find(|r| r.slug == record.slug) {
                None => lines.push(format!("+ {key}: {}", now.join(" | "))),
                Some(was) => {
                    let was = conditions(was);
                    let added: Vec<_> = now.iter().filter(|c| !was.contains(c)).cloned().collect();
                    let removed: Vec<_> = was.iter().filter(|c| !now.contains(c)).cloned().collect();
                    if !added.is_empty() || !removed.is_empty() {
                        lines.push(format!("~ {key}: +[{}] -[{}]", added.join(" | "), removed.join(" | ")));
                    }
                    let was = before.records.iter().find(|r| r.slug == record.slug).unwrap();
                    if was.status != record.status {
                        lines.push(format!("~ {key} status {:?} -> {:?}", was.status.unwrap_or(Status::Confirmed), record.status.unwrap_or(Status::Confirmed)));
                    }
                    for source in record.sources.iter().filter(|s| !was.sources.contains(s)) {
                        lines.push(format!("~ {key} + source {source}"));
                    }
                    for source in was.sources.iter().filter(|s| !record.sources.contains(s)) {
                        lines.push(format!("~ {key} - source {source}"));
                    }
                    if was.reviewed != record.reviewed {
                        lines.push(format!("~ {key} reviewed {} -> {}", was.reviewed.as_deref().unwrap_or("-"), record.reviewed.as_deref().unwrap_or("-")));
                    }
                    if was.note != record.note {
                        lines.push(format!("~ {key} note changed"));
                    }
                }
            }
        }
    }
    lines
}

/// Problems across lists: a list id used twice, or a record key that
/// [retired] says was removed and must not come back.
pub fn check_all(lists: &[List], retired: &HashSet<String>) -> Vec<String> {
    let mut problems = Vec::new();
    let mut ids = HashSet::new();
    for list in lists {
        if !ids.insert(&list.id) {
            problems.push(format!("the list id {} is used twice", list.id));
        }
        for record in &list.records {
            let key = format!("{}/{}", list.id, record.slug);
            if retired.contains(&key) {
                problems.push(format!("{key} was retired and cannot be used again"));
            }
        }
    }
    problems
}

#[cfg(test)]
mod tests {
    use super::*;

    const EXAMPLE: &str = "! id: falun-gong-media\n! name: Falun Gong media\n! name.zh-Hans: 法轮功媒体\n! category: religion\n! action: hide\n! default: off\n! topic: 法轮功\n! topic: Falun Gong\n! legacy: 法轮功\n\n# The paper\n:epoch-times | UCxxxxxxxxxxxxxxxxxxxxxx | @EpochTimes | =The Epoch Times | =大纪元 | =大紀元\n    source: https://example.org/a\n    reviewed: 2026-11-08\n    legacy: 法轮功/channel/大纪元\n:ntd | @NTDTelevision | ^新唐人 | ^NTD\n    status: unproven\n";

    #[test]
    fn reads_headers_records_and_attributes() {
        let list = parse(EXAMPLE, "falun-gong-media").unwrap();
        assert_eq!(list.name, "Falun Gong media");
        assert_eq!(list.names, vec![("zh-Hans".to_string(), "法轮功媒体".to_string())]);
        assert_eq!(list.categories, vec!["religion"]);
        assert_eq!(list.action, Action::Hide);
        assert!(!list.default_on);
        assert_eq!(list.topics, vec!["法轮功", "Falun Gong"]);
        assert_eq!(list.legacy, vec!["法轮功"]);
        let epoch = &list.records[0];
        assert_eq!(epoch.slug, "epoch-times");
        assert_eq!(epoch.ids, vec!["UCxxxxxxxxxxxxxxxxxxxxxx"]);
        assert_eq!(epoch.handles, vec!["epochtimes"]);
        assert_eq!(epoch.names, vec!["The Epoch Times", "大纪元", "大紀元"]);
        assert_eq!(epoch.sources, vec!["https://example.org/a"]);
        assert_eq!(epoch.reviewed.as_deref(), Some("2026-11-08"));
        assert_eq!(epoch.legacy, vec!["法轮功/channel/大纪元"]);
        let ntd = &list.records[1];
        assert_eq!(ntd.prefixes, vec!["新唐人", "NTD"]);
        assert_eq!(ntd.status, Some(Status::Unproven));
    }

    #[test]
    fn spaces_stay_inside_names_and_pipes_can_be_escaped() {
        let text = "! id: a\n! name: A\n! category: new-age\n! action: quiet\n! default: off\n:x |  =Jeff and Shaleia  | =A \\| B | =C \\\\ D\r\n    source: https://example.org/x\n";
        let list = parse(text, "a").unwrap();
        assert_eq!(list.records[0].names, vec!["Jeff and Shaleia", "A | B", "C \\ D"]);
    }

    #[test]
    fn mistakes_are_reported_with_their_line() {
        let text = "! id: b\n! name: B\n! category: religion, sports\n! action: block\n! default: on\n:Bad | NTD\n:ok | UC123\n:ok | =x \\n\n:dup | =Same\n:dup2 | =same\n    colour: red\n! late: header\n";
        let errors = parse(text, "a").unwrap_err();
        let messages: Vec<String> = errors.iter().map(ToString::to_string).collect();
        for expected in [
            "line 3: unknown category sports",
            "line 4: action is hide, quiet, demote or label, not block",
            "line 6: the slug \"Bad\" is not lowercase letters, digits and -",
            "line 6: NTD has no prefix: UC…, @, = or ^",
            "line 7: UC123 is not a channel id",
            "line 8: unknown escape \\n",
            "line 10: =same is already in another record of this list",
            "line 11: unknown attribute colour",
            "line 12: a header line after the first record",
            "line 1: the id b differs from the file name a",
            "line 1: only a list of safety categories alone may be on by default",
        ] {
            assert!(messages.iter().any(|m| m == expected), "missing {expected:?} in {messages:#?}");
        }
    }

    #[test]
    fn a_record_without_conditions_or_a_list_without_headers_fails() {
        let errors = parse(":lonely\n", "c").unwrap_err();
        let messages: Vec<String> = errors.iter().map(|e| e.message.clone()).collect();
        assert!(messages.contains(&"the record lonely matches nothing".to_string()));
        assert!(messages.contains(&"the id header is missing".to_string()));
        assert!(messages.contains(&"the category header is missing".to_string()));
    }

    #[test]
    fn retired_keys_and_repeated_ids_are_refused_across_lists() {
        let list = parse(EXAMPLE, "falun-gong-media").unwrap();
        let retired = HashSet::from(["falun-gong-media/ntd".to_string()]);
        let problems = check_all(&[list.clone(), list], &retired);
        assert!(problems.contains(&"the list id falun-gong-media is used twice".to_string()));
        assert!(problems.contains(&"falun-gong-media/ntd was retired and cannot be used again".to_string()));
    }

    #[test]
    fn compiles_to_json_without_empty_fields() {
        let list = parse(EXAMPLE, "falun-gong-media").unwrap();
        let json = serde_json::to_value(Bundle { version: 7, built: "2026-11-08T00:00:00Z", lists: std::slice::from_ref(&list) }).unwrap();
        assert_eq!(json["version"], 7);
        let ntd = &json["lists"][0]["records"][1];
        assert_eq!(ntd["status"], "unproven");
        assert!(ntd.get("ids").is_none());
        assert!(json["lists"][0]["records"][0].get("status").is_none());
    }

    #[test]
    fn safety_lists_alone_start_on_and_take_no_topic_or_unproven_record() {
        let ok = "! id: s\n! name: S\n! category: financial-scams, malware-phishing\n! action: hide\n! default: on\n:a | UCaaaaaaaaaaaaaaaaaaaaaa\n    source: https://example.org/a\n";
        assert!(parse(ok, "s").unwrap().default_on);
        let unsourced = ok.replace("    source: https://example.org/a\n", "").replace("! default: on\n", "! default: on\n! source: https://example.org/list\n");
        let messages: Vec<String> = parse(&unsourced, "s").unwrap_err().into_iter().map(|e| e.message).collect();
        assert_eq!(messages, vec!["the record a has no source, and every record of a safety list needs its own"]);
        let bad = "! id: s\n! name: S\n! category: financial-scams\n! action: hide\n! default: on\n! topic: crypto\n:a | UCaaaaaaaaaaaaaaaaaaaaaa\n    status: unproven\n";
        let messages: Vec<String> = parse(bad, "s").unwrap_err().into_iter().map(|e| e.message).collect();
        assert!(messages.iter().any(|m| m.starts_with("a safety list has no topic")));
        assert!(messages.contains(&"the record a is unproven, and a safety list takes confirmed records only".to_string()));
        let mixed = "! id: m\n! name: M\n! category: medical-fraud, new-age\n! action: quiet\n! default: on\n:a | =A\n";
        let messages: Vec<String> = parse(mixed, "m").unwrap_err().into_iter().map(|e| e.message).collect();
        assert!(messages.contains(&"only a list of safety categories alone may be on by default".to_string()));
        assert!(messages.contains(&"the record a is confirmed but neither it nor the list has a source".to_string()));
    }

    #[test]
    fn reads_a_folder_and_reports_what_changed() {
        let dir = std::env::temp_dir().join(format!("lumtub-lists-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("religion")).unwrap();
        std::fs::write(dir.join("religion/falun-gong-media.txt"), EXAMPLE).unwrap();
        let (old, _) = load_dir(&dir).unwrap();
        let changed = EXAMPLE.replace(" | ^NTD\n", "\n").replace(":epoch-times", ":the-paper") + ":shen-yun | @ShenYun\n    source: https://example.org/s\n";
        std::fs::write(dir.join("religion/falun-gong-media.txt"), changed).unwrap();
        std::fs::write(dir.join("retired.txt"), "falun-gong-media/epoch-times\n").unwrap();
        let (new, retired) = load_dir(&dir).unwrap();
        let lines = diff(&old, &new, &retired);
        assert!(unretired(&old, &new, &retired).is_empty());
        assert_eq!(unretired(&old, &new, &HashSet::new()), vec!["falun-gong-media/epoch-times was removed but is not in retired.txt"]);
        assert!(lines.contains(&"- falun-gong-media/epoch-times".to_string()), "{lines:#?}");
        assert!(lines.contains(&"+ falun-gong-media/shen-yun: @shenyun".to_string()), "{lines:#?}");
        assert!(lines.contains(&"~ falun-gong-media/ntd: +[] -[^NTD]".to_string()), "{lines:#?}");
        std::fs::create_dir_all(dir.join("sports")).unwrap();
        std::fs::create_dir_all(dir.join("state-media")).unwrap();
        std::fs::write(dir.join("state-media/falun-gong-media.txt"), EXAMPLE.replace(":epoch-times", ":epoch")).unwrap();
        let problems = load_dir(&dir).unwrap_err();
        assert!(problems.contains(&"sports/ is not a category".to_string()), "{problems:#?}");
        assert!(problems.contains(&"state-media/falun-gong-media.txt: the list is not in the state-media category".to_string()), "{problems:#?}");
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
