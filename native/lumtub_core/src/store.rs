//! lumtub.db: the library (favorites, 稍后观看, playlists, followed
//! channels, watch progress) and the watch history, in SQLite. Texts
//! made for a video, such as recognized subtitles and AI summaries, are
//! kept in the same file (store_texts.rs).
//!
//! The app keeps its lists in memory and hands each changed list over as
//! an edit when no entry moved: the keys removed, the keys added each with
//! the key before it, and the bodies that are new or changed; only those
//! rows are read or written. When entries moved it hands the list over
//! whole as its keys in order, and rows keep their positions wherever the
//! order still allows, so putting a video first in a history of thousands
//! writes one row instead of the whole file.
//!
//! SQLite's rollback journal with full syncs: a power cut loses at most
//! the write in progress, never the file.

use rusqlite::{Connection, ErrorCode, params};
use serde::Deserialize;
use serde_json::value::RawValue;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard};

use crate::taste::{give, text};

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS entry(
  list TEXT NOT NULL,
  key TEXT NOT NULL,
  pos REAL NOT NULL,
  body TEXT NOT NULL,
  PRIMARY KEY(list, key)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS entry_order ON entry(list, pos);
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS transcript(
  video TEXT NOT NULL,
  lang TEXT NOT NULL,
  origin TEXT NOT NULL,
  model TEXT NOT NULL,
  body TEXT NOT NULL,
  created INTEGER NOT NULL,
  PRIMARY KEY(video, lang, origin)
);
CREATE INDEX IF NOT EXISTS transcript_age ON transcript(origin, created);
CREATE TABLE IF NOT EXISTS summary(
  video TEXT NOT NULL,
  lang TEXT NOT NULL,
  provider TEXT NOT NULL,
  body TEXT NOT NULL,
  created INTEGER NOT NULL,
  PRIMARY KEY(video, lang)
);
CREATE INDEX IF NOT EXISTS summary_age ON summary(created);
CREATE TABLE IF NOT EXISTS note(
  id INTEGER PRIMARY KEY,
  video TEXT NOT NULL,
  title TEXT NOT NULL,
  at INTEGER NOT NULL,
  quote TEXT NOT NULL,
  body TEXT NOT NULL,
  created INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS note_video ON note(video, at);
";

/// One call at a time, so the app's isolates never wait on each other's
/// locks inside SQLite.
static BUSY: Mutex<()> = Mutex::new(());

fn lock() -> MutexGuard<'static, ()> {
    BUSY.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

#[derive(Debug)]
pub enum StoreError {
    /// The file is not a database or is damaged; it has been moved to
    /// the path given, and the next call starts a new one.
    Broken(String),
    Other(String),
}

impl From<rusqlite::Error> for StoreError {
    fn from(error: rusqlite::Error) -> Self {
        StoreError::Other(error.to_string())
    }
}

fn is_broken(error: &rusqlite::Error) -> bool {
    matches!(
        error.sqlite_error_code(),
        Some(ErrorCode::DatabaseCorrupt | ErrorCode::NotADatabase)
    )
}

fn connect(path: &Path) -> rusqlite::Result<Connection> {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let connection = Connection::open(path)?;
    connection.busy_timeout(std::time::Duration::from_secs(5))?;
    connection.execute_batch(SCHEMA)?;
    Ok(connection)
}

/// Moves a damaged database and its journal aside, under a name with the
/// time in it, and says where the database went.
fn set_aside(path: &Path) -> String {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let moved = PathBuf::from(format!("{}.broken-{stamp}", path.display()));
    let _ = std::fs::rename(path, &moved);
    let journal = PathBuf::from(format!("{}-journal", path.display()));
    let _ = std::fs::rename(&journal, format!("{}-journal", moved.display()));
    moved.display().to_string()
}

/// Runs [work] on the database at [path]. The database is opened for each
/// call and closed after it, so no file stays open between the app's
/// rare writes (the data folder can be moved or deleted at any time). A
/// damaged database is set aside.
pub(crate) fn with_db<T>(
    path: &str,
    work: impl FnOnce(&mut Connection) -> rusqlite::Result<T>,
) -> Result<T, StoreError> {
    if path.is_empty() {
        return Err(StoreError::Other("No database path".into()));
    }
    let path = PathBuf::from(path);
    let _busy = lock();
    let result = connect(&path).and_then(|mut connection| {
        let result = work(&mut connection);
        drop(connection);
        result
    });
    match result {
        Ok(value) => Ok(value),
        Err(error) if is_broken(&error) => Err(StoreError::Broken(set_aside(&path))),
        Err(error) => Err(error.into()),
    }
}

/// The lists named, and those starting with one of [prefixes], each as
/// `(key, body)` in order, and every meta value.
pub type Lists = BTreeMap<String, Vec<(String, String)>>;

pub fn read(
    path: &str,
    names: &[String],
    prefixes: &[String],
) -> Result<(Lists, BTreeMap<String, String>), StoreError> {
    with_db(path, |db| {
        let mut lists = Lists::new();
        for name in names {
            lists.insert(name.clone(), Vec::new());
        }
        let mut wanted: Vec<String> = names.to_vec();
        {
            let mut all = db.prepare("SELECT DISTINCT list FROM entry")?;
            let found = all.query_map([], |row| row.get::<_, String>(0))?;
            for list in found {
                let list = list?;
                if prefixes
                    .iter()
                    .any(|prefix| list.starts_with(prefix.as_str()))
                    && !wanted.contains(&list)
                {
                    lists.insert(list.clone(), Vec::new());
                    wanted.push(list);
                }
            }
        }
        let mut rows = db.prepare("SELECT key, body FROM entry WHERE list = ?1 ORDER BY pos")?;
        for name in &wanted {
            let entries = rows
                .query_map([name], |row| {
                    Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
                })?
                .collect::<rusqlite::Result<Vec<_>>>()?;
            lists.insert(name.clone(), entries);
        }
        let mut meta = BTreeMap::new();
        let mut values = db.prepare("SELECT key, value FROM meta")?;
        for pair in values.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })? {
            let (key, value) = pair?;
            meta.insert(key, value);
        }
        Ok((lists, meta))
    })
}

/// One list as it should now be: its keys in order, and the bodies of
/// the entries that are new or changed.
pub struct ListWrite<'a> {
    pub name: &'a str,
    pub keys: Vec<&'a str>,
    pub bodies: HashMap<&'a str, &'a str>,
}

/// One list changed with no entry moved: [remove] goes, each of [insert]
/// goes right after the key named with it (first when none, in this
/// order, so one may follow another added just before), and [bodies]
/// replaces the bodies of the keys it names.
pub struct ListEdit<'a> {
    pub name: &'a str,
    pub remove: Vec<&'a str>,
    pub insert: Vec<(&'a str, Option<&'a str>)>,
    pub bodies: HashMap<&'a str, &'a str>,
}

/// Rows written, for tests.
#[derive(Debug, Default, PartialEq)]
pub struct Written {
    pub inserted: usize,
    pub updated: usize,
    pub deleted: usize,
}

/// Writes the lists, drops the lists in [drop] and sets [meta], all in
/// one transaction.
pub fn write(
    path: &str,
    lists: &[ListWrite],
    drop: &[&str],
    meta: &[(&str, &str)],
) -> Result<Written, StoreError> {
    write_all(path, lists, &[], drop, meta)
}

/// As [write], with [edits] as well.
pub fn write_all(
    path: &str,
    lists: &[ListWrite],
    edits: &[ListEdit],
    drop: &[&str],
    meta: &[(&str, &str)],
) -> Result<Written, StoreError> {
    with_db(path, |db| {
        let transaction = db.transaction()?;
        let mut written = Written::default();
        for name in drop {
            written.deleted += transaction.execute("DELETE FROM entry WHERE list = ?1", [name])?;
        }
        for list in lists {
            let counted = write_list(&transaction, list)?;
            written.inserted += counted.inserted;
            written.updated += counted.updated;
            written.deleted += counted.deleted;
        }
        for edit in edits {
            let counted = edit_list(&transaction, edit)?;
            written.inserted += counted.inserted;
            written.updated += counted.updated;
            written.deleted += counted.deleted;
        }
        for (key, value) in meta {
            transaction.execute("INSERT INTO meta(key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value", params![key, value])?;
        }
        transaction.commit()?;
        Ok(written)
    })
}

fn write_list(db: &rusqlite::Transaction, list: &ListWrite) -> rusqlite::Result<Written> {
    let mut existing: HashMap<String, f64> = HashMap::new();
    {
        let mut rows = db.prepare_cached("SELECT key, pos FROM entry WHERE list = ?1")?;
        for row in rows.query_map([list.name], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, f64>(1)?))
        })? {
            let (key, pos) = row?;
            existing.insert(key, pos);
        }
    }
    let mut seen = HashSet::new();
    // A new key without a body has nothing to store and is left out.
    let keys: Vec<&str> = list
        .keys
        .iter()
        .copied()
        .filter(|key| {
            seen.insert(*key) && (existing.contains_key(*key) || list.bodies.contains_key(key))
        })
        .collect();
    let old: Vec<Option<f64>> = keys.iter().map(|key| existing.get(*key).copied()).collect();
    let positions = positions(&old);
    let mut written = Written::default();
    let mut insert =
        db.prepare_cached("INSERT INTO entry(list, key, pos, body) VALUES (?1, ?2, ?3, ?4)")?;
    let mut move_row =
        db.prepare_cached("UPDATE entry SET pos = ?3 WHERE list = ?1 AND key = ?2")?;
    let mut change =
        db.prepare_cached("UPDATE entry SET pos = ?3, body = ?4 WHERE list = ?1 AND key = ?2")?;
    let mut delete = db.prepare_cached("DELETE FROM entry WHERE list = ?1 AND key = ?2")?;
    let kept: HashSet<&str> = keys.iter().copied().collect();
    for key in existing.keys() {
        if !kept.contains(key.as_str()) {
            written.deleted += delete.execute(params![list.name, key])?;
        }
    }
    for ((key, before), pos) in keys.iter().zip(&old).zip(&positions) {
        match (before, list.bodies.get(key)) {
            (None, Some(body)) => {
                insert.execute(params![list.name, key, pos, body])?;
                written.inserted += 1;
            }
            (Some(_), Some(body)) => {
                change.execute(params![list.name, key, pos, body])?;
                written.updated += 1;
            }
            (Some(before), None) if before != pos => {
                move_row.execute(params![list.name, key, pos])?;
                written.updated += 1;
            }
            _ => {}
        }
    }
    Ok(written)
}

/// Applies [edit], reading and writing only the rows it names and their
/// neighbours: O(changes · log n) with the `entry_order` index.
fn edit_list(db: &rusqlite::Transaction, edit: &ListEdit) -> rusqlite::Result<Written> {
    let mut written = Written::default();
    let mut delete = db.prepare_cached("DELETE FROM entry WHERE list = ?1 AND key = ?2")?;
    for key in &edit.remove {
        written.deleted += delete.execute(params![edit.name, key])?;
    }
    let added: HashSet<&str> = edit.insert.iter().map(|(key, _)| *key).collect();
    let mut change =
        db.prepare_cached("UPDATE entry SET body = ?3 WHERE list = ?1 AND key = ?2")?;
    for (key, body) in &edit.bodies {
        if !added.contains(key) {
            written.updated += change.execute(params![edit.name, key, body])?;
        }
    }
    let mut insert = db.prepare_cached(
        "INSERT INTO entry(list, key, pos, body) VALUES (?1, ?2, ?3, ?4) \
         ON CONFLICT(list, key) DO UPDATE SET pos = excluded.pos, body = excluded.body",
    )?;
    for &(key, after) in &edit.insert {
        // A new key without a body has nothing to store and is left out.
        let Some(body) = edit.bodies.get(key) else {
            continue;
        };
        let pos = match place(db, edit.name, after)? {
            Some(pos) => pos,
            None => {
                // No room left between two neighbours: the list is
                // numbered again, which is rare.
                renumber(db, edit.name)?;
                place(db, edit.name, after)?.unwrap_or_default()
            }
        };
        insert.execute(params![edit.name, key, pos, body])?;
        written.inserted += 1;
    }
    Ok(written)
}

/// A position right after [after] (first when none) in [list]; none when
/// there is no room left before the next entry.
fn place(
    db: &rusqlite::Transaction,
    list: &str,
    after: Option<&str>,
) -> rusqlite::Result<Option<f64>> {
    let (low, high): (Option<f64>, Option<f64>) = match after {
        Some(after) => {
            let low: f64 = db
                .prepare_cached("SELECT pos FROM entry WHERE list = ?1 AND key = ?2")?
                .query_row(params![list, after], |r| r.get(0))?;
            let high = db
                .prepare_cached("SELECT MIN(pos) FROM entry WHERE list = ?1 AND pos > ?2")?
                .query_row(params![list, low], |r| r.get(0))?;
            (Some(low), high)
        }
        None => {
            let high = db
                .prepare_cached("SELECT MIN(pos) FROM entry WHERE list = ?1")?
                .query_row([list], |r| r.get(0))?;
            (None, high)
        }
    };
    Ok(match (low, high) {
        (None, None) => Some(0.0),
        (None, Some(high)) => Some(high - 1.0),
        (Some(low), None) => Some(low + 1.0),
        (Some(low), Some(high)) => {
            let mid = low + (high - low) / 2.0;
            (low < mid && mid < high).then_some(mid)
        }
    })
}

/// Numbers the entries of [list] 0, 1, 2… in their order.
fn renumber(db: &rusqlite::Transaction, list: &str) -> rusqlite::Result<()> {
    let keys = db
        .prepare_cached("SELECT key FROM entry WHERE list = ?1 ORDER BY pos")?
        .query_map([list], |row| row.get::<_, String>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    let mut move_row =
        db.prepare_cached("UPDATE entry SET pos = ?3 WHERE list = ?1 AND key = ?2")?;
    for (i, key) in keys.iter().enumerate() {
        move_row.execute(params![list, key, i as f64])?;
    }
    Ok(())
}

/// Positions for a list whose entries had the positions [old] (None for
/// new ones), keeping as many as the new order allows: the longest run
/// of old positions that still increases stays, and the rest go in the
/// gaps. When a gap has no room left between two numbers, every entry
/// is numbered again.
pub fn positions(old: &[Option<f64>]) -> Vec<f64> {
    let kept = longest_increasing(old);
    let mut out = vec![0.0; old.len()];
    let mut start = 0;
    let mut low: Option<f64> = None;
    let anchors = kept.iter().copied().map(Some).chain(std::iter::once(None));
    for anchor in anchors {
        let end = anchor.unwrap_or(old.len());
        let high = anchor.and_then(|at| old[at]);
        let count = end - start;
        for i in 0..count {
            out[start + i] = match (low, high) {
                (None, None) => i as f64,
                (None, Some(high)) => high - (count - i) as f64,
                (Some(low), None) => low + (i + 1) as f64,
                (Some(low), Some(high)) => low + (high - low) * (i + 1) as f64 / (count + 1) as f64,
            };
        }
        if let Some(at) = anchor {
            out[at] = high.unwrap_or_default();
            low = high;
            start = at + 1;
        }
    }
    let ordered =
        out.windows(2).all(|pair| pair[0] < pair[1]) && out.iter().all(|pos| pos.is_finite());
    if ordered {
        out
    } else {
        (0..old.len()).map(|i| i as f64).collect()
    }
}

/// Indices of a longest strictly increasing run among the known
/// positions, in order.
fn longest_increasing(old: &[Option<f64>]) -> Vec<usize> {
    // tails[k]: index ending the best run of length k + 1.
    let mut tails: Vec<usize> = Vec::new();
    let mut before: Vec<Option<usize>> = vec![None; old.len()];
    for (i, pos) in old.iter().enumerate() {
        let Some(pos) = *pos else { continue };
        let at = tails.partition_point(|&t| old[t].unwrap_or(f64::NEG_INFINITY) < pos);
        before[i] = at.checked_sub(1).map(|k| tails[k]);
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
        next = before[i];
    }
    run.reverse();
    run
}

#[derive(Deserialize)]
struct ReadAsk {
    path: String,
    #[serde(default)]
    lists: Vec<String>,
    #[serde(default)]
    prefixes: Vec<String>,
}

#[derive(Deserialize)]
struct ListAsk<'a> {
    // Owned, not borrowed: a name or key holding `"` or `\` arrives
    // escaped and cannot be borrowed from the request.
    name: String,
    #[serde(default)]
    keys: Vec<String>,
    #[serde(borrow, default)]
    bodies: HashMap<String, &'a RawValue>,
    /// An edit ([ListEdit]) rather than the whole list.
    #[serde(default)]
    remove: Option<Vec<String>>,
    #[serde(default)]
    insert: Option<Vec<(String, Option<String>)>>,
}

impl ListAsk<'_> {
    fn is_edit(&self) -> bool {
        self.remove.is_some() || self.insert.is_some()
    }

    fn bodies(&self) -> HashMap<&str, &str> {
        self.bodies
            .iter()
            .map(|(key, body)| (key.as_str(), body.get()))
            .collect()
    }
}

#[derive(Deserialize)]
struct WriteAsk<'a> {
    path: String,
    #[serde(borrow, default)]
    lists: Vec<ListAsk<'a>>,
    #[serde(default)]
    drop: Vec<String>,
    #[serde(default)]
    meta: HashMap<String, String>,
}

pub(crate) fn error_json(error: StoreError) -> String {
    match error {
        StoreError::Broken(moved) => {
            serde_json::json!({"error": "The library database was damaged", "setAside": moved})
                .to_string()
        }
        StoreError::Other(message) => serde_json::json!({"error": message}).to_string(),
    }
}

fn read_json(ask: &str) -> String {
    let ask: ReadAsk = match serde_json::from_str(ask) {
        Ok(ask) => ask,
        Err(error) => return serde_json::json!({"error": error.to_string()}).to_string(),
    };
    match read(&ask.path, &ask.lists, &ask.prefixes) {
        Ok((lists, meta)) => {
            // Bodies were checked as JSON when written, so they go out as
            // they are rather than parsed and printed again.
            let mut out = String::from("{\"lists\":{");
            for (n, (name, entries)) in lists.iter().enumerate() {
                if n > 0 {
                    out.push(',');
                }
                out.push_str(&serde_json::to_string(name).unwrap_or_default());
                out.push_str(":[");
                for (i, (key, body)) in entries.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    out.push('[');
                    out.push_str(&serde_json::to_string(key).unwrap_or_default());
                    out.push(',');
                    out.push_str(body);
                    out.push(']');
                }
                out.push(']');
            }
            out.push_str("},\"meta\":");
            out.push_str(&serde_json::to_string(&meta).unwrap_or_else(|_| "{}".into()));
            out.push('}');
            out
        }
        Err(error) => error_json(error),
    }
}

fn write_json(ask: &str) -> String {
    let ask: WriteAsk = match serde_json::from_str(ask) {
        Ok(ask) => ask,
        Err(error) => return serde_json::json!({"error": error.to_string()}).to_string(),
    };
    let lists: Vec<ListWrite> = ask
        .lists
        .iter()
        .filter(|list| !list.is_edit())
        .map(|list| ListWrite {
            name: &list.name,
            keys: list.keys.iter().map(String::as_str).collect(),
            bodies: list.bodies(),
        })
        .collect();
    let edits: Vec<ListEdit> = ask
        .lists
        .iter()
        .filter(|list| list.is_edit())
        .map(|list| ListEdit {
            name: &list.name,
            remove: list.remove.iter().flatten().map(String::as_str).collect(),
            insert: list
                .insert
                .iter()
                .flatten()
                .map(|(key, after)| (key.as_str(), after.as_deref()))
                .collect(),
            bodies: list.bodies(),
        })
        .collect();
    let drop: Vec<&str> = ask.drop.iter().map(String::as_str).collect();
    let meta: Vec<(&str, &str)> = ask
        .meta
        .iter()
        .map(|(k, v)| (k.as_str(), v.as_str()))
        .collect();
    match write_all(&ask.path, &lists, &edits, &drop, &meta) {
        Ok(written) => serde_json::json!({"inserted": written.inserted, "updated": written.updated, "deleted": written.deleted}).to_string(),
        Err(error) => error_json(error),
    }
}

/// Reads lists from a database. [json] is `{path, lists: [name],
/// prefixes: [prefix]}`; the answer is `{lists: {name: [[key, body]]},
/// meta: {key: value}}` or `{error, setAside?}`. Free it with
/// `lumtub_string_free`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_store_read(json: *const u8, length: usize) -> *mut c_char {
    give(read_json(unsafe { text(json, length) }))
}

/// Writes lists in one transaction. [json] is `{path, lists: [{name,
/// keys: [key], bodies: {key: body}}], drop: [name], meta: {key:
/// value}}`, where a list may instead be an edit `{name, remove: [key],
/// insert: [[key, after|null]], bodies}` ([ListEdit]); the answer is
/// `{inserted, updated, deleted}` or `{error, setAside?}`. Free it with
/// `lumtub_string_free`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_store_write(json: *const u8, length: usize) -> *mut c_char {
    give(write_json(unsafe { text(json, length) }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> String {
        let dir = std::env::temp_dir().join(format!("lumtub-store-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir.join("lumtub.db").display().to_string()
    }

    fn list<'a>(name: &'a str, keys: &[&'a str], bodies: &[(&'a str, &'a str)]) -> ListWrite<'a> {
        ListWrite {
            name,
            keys: keys.to_vec(),
            bodies: bodies.iter().copied().collect(),
        }
    }

    fn keys(path: &str, name: &str) -> Vec<String> {
        read(path, &[name.to_string()], &[]).unwrap().0[name]
            .iter()
            .map(|(k, _)| k.clone())
            .collect()
    }

    #[test]
    fn positions_keep_what_they_can() {
        assert_eq!(positions(&[None, None]), vec![0.0, 1.0]);
        assert_eq!(
            positions(&[None, Some(0.0), Some(1.0)]),
            vec![-1.0, 0.0, 1.0]
        );
        assert_eq!(
            positions(&[Some(0.0), Some(1.0), None]),
            vec![0.0, 1.0, 2.0]
        );
        assert_eq!(
            positions(&[Some(0.0), None, Some(1.0)]),
            vec![0.0, 0.5, 1.0]
        );
        // The last moved to the front: only it changes.
        assert_eq!(
            positions(&[Some(2.0), Some(0.0), Some(1.0)]),
            vec![-1.0, 0.0, 1.0]
        );
        let many: Vec<Option<f64>> = (0..1000).map(|i| Some(i as f64)).collect();
        assert_eq!(
            positions(&many),
            (0..1000).map(|i| i as f64).collect::<Vec<_>>()
        );
    }

    #[test]
    fn positions_renumber_when_a_gap_runs_out() {
        let tight = [Some(1.0), None, Some(1.0 + f64::EPSILON)];
        assert_eq!(positions(&tight), vec![0.0, 1.0, 2.0]);
    }

    #[test]
    fn a_new_first_entry_writes_one_row() {
        let path = temp("front");
        let names: Vec<String> = (0..500).map(|i| format!("v{i}")).collect();
        let all: Vec<&str> = names.iter().map(String::as_str).collect();
        let bodies: Vec<(&str, &str)> = all.iter().map(|k| (*k, "{\"a\":1}")).collect();
        let first = write(&path, &[list("history", &all, &bodies)], &[], &[]).unwrap();
        assert_eq!(
            first,
            Written {
                inserted: 500,
                updated: 0,
                deleted: 0
            }
        );
        let mut again = vec!["new"];
        again.extend(&all[..499]);
        let second = write(
            &path,
            &[list("history", &again, &[("new", "{\"b\":[1,2]}")])],
            &[],
            &[],
        )
        .unwrap();
        assert_eq!(
            second,
            Written {
                inserted: 1,
                updated: 0,
                deleted: 1
            }
        );
        let read_back = keys(&path, "history");
        assert_eq!(read_back.first().map(String::as_str), Some("new"));
        assert_eq!(read_back.len(), 500);
        // Played again: moved to the front, one row.
        let mut moved = vec!["v10", "new"];
        moved.extend(all[..499].iter().filter(|k| **k != "v10"));
        let third = write(&path, &[list("history", &moved, &[])], &[], &[]).unwrap();
        assert_eq!(
            third,
            Written {
                inserted: 0,
                updated: 1,
                deleted: 0
            }
        );
        assert_eq!(keys(&path, "history")[..3], ["v10", "new", "v0"]);
    }

    #[test]
    fn bodies_and_meta_round_trip() {
        let path = temp("trip");
        write(
            &path,
            &[
                list(
                    "playlist:a",
                    &["x"],
                    &[("x", "{\"title\":\"中文 \\\"q\\\"\"}")],
                ),
                list("favorites", &["y"], &[("y", "[1,2]")]),
            ],
            &[],
            &[("library", "1")],
        )
        .unwrap();
        let answer = read_json(&serde_json::json!({"path": path, "lists": ["favorites", "watchLater"], "prefixes": ["playlist:"]}).to_string());
        let value: serde_json::Value = serde_json::from_str(&answer).unwrap();
        assert_eq!(
            value["lists"]["favorites"],
            serde_json::json!([["y", [1, 2]]])
        );
        assert_eq!(value["lists"]["watchLater"], serde_json::json!([]));
        assert_eq!(value["lists"]["playlist:a"][0][1]["title"], "中文 \"q\"");
        assert_eq!(value["meta"]["library"], "1");
        // A changed body replaces the old one; a dropped list goes.
        write(
            &path,
            &[list("favorites", &["y"], &[("y", "[3]")])],
            &["playlist:a"],
            &[],
        )
        .unwrap();
        let (lists, _) = read(&path, &["favorites".into()], &["playlist:".into()]).unwrap();
        assert_eq!(
            lists["favorites"],
            vec![("y".to_string(), "[3]".to_string())]
        );
        assert!(!lists.contains_key("playlist:a"));
    }

    #[test]
    fn bad_bodies_are_refused_and_nothing_is_written() {
        let path = temp("bad");
        let answer = write_json(&format!(
            "{{\"path\":{},\"lists\":[{{\"name\":\"f\",\"keys\":[\"a\"],\"bodies\":{{\"a\":nope}}}}]}}",
            serde_json::to_string(&path).unwrap()
        ));
        assert!(answer.contains("error"), "{answer}");
        assert!(keys(&path, "f").is_empty());
    }

    #[test]
    fn names_and_keys_with_quotes_and_backslashes_are_written() {
        let path = temp("escaped");
        let odd = "Music \"live\" A\\B\n";
        let ask = serde_json::json!({
            "path": path,
            "lists": [{"name": odd, "keys": [odd, "plain"], "bodies": {odd: {"a": 1}, "plain": {"b": "\"x\""}}}],
            "drop": ["gone \"old\""],
            "meta": {odd: odd},
        });
        let answer: serde_json::Value =
            serde_json::from_str(&write_json(&ask.to_string())).unwrap();
        assert_eq!(answer["inserted"], 2, "{answer}");
        assert_eq!(keys(&path, odd), vec![odd.to_string(), "plain".to_string()]);
        let (lists, meta) = read(&path, &[odd.to_string()], &[]).unwrap();
        assert_eq!(lists[odd][1].1, "{\"b\":\"\\\"x\\\"\"}");
        assert_eq!(meta[odd], odd);
    }

    fn edit(path: &str, list: serde_json::Value) -> serde_json::Value {
        let ask = serde_json::json!({"path": path, "lists": [list]});
        serde_json::from_str(&write_json(&ask.to_string())).unwrap()
    }

    #[test]
    fn an_edit_touches_only_the_rows_it_names() {
        let path = temp("edit");
        let all: Vec<String> = (0..5).map(|i| format!("v{i}")).collect();
        let names: Vec<&str> = all.iter().map(String::as_str).collect();
        let bodies: Vec<(&str, &str)> = names.iter().map(|k| (*k, "1")).collect();
        write(&path, &[list("h", &names, &bodies)], &[], &[]).unwrap();
        let answer = edit(
            &path,
            serde_json::json!({"name": "h", "remove": ["v2"], "insert": [["new", null], ["mid", "v3"], ["end", "v4"], ["after", "new"]],
                "bodies": {"new": 2, "mid": 2, "end": 2, "after": 2, "v1": 3, "nobody": null}}),
        );
        assert_eq!(
            answer,
            serde_json::json!({"inserted": 4, "updated": 1, "deleted": 1})
        );
        assert_eq!(
            keys(&path, "h"),
            ["new", "after", "v0", "v1", "v3", "mid", "v4", "end"]
        );
        let (lists, _) = read(&path, &["h".to_string()], &[]).unwrap();
        assert_eq!(lists["h"][3], ("v1".to_string(), "3".to_string()));
        // A key added without a body is left out.
        edit(
            &path,
            serde_json::json!({"name": "h", "remove": [], "insert": [["bare", "v0"]]}),
        );
        assert!(!keys(&path, "h").contains(&"bare".to_string()));
        // An edit out of step with the file fails whole.
        let answer = edit(
            &path,
            serde_json::json!({"name": "h", "remove": ["v0"], "insert": [["x", "gone"]], "bodies": {"x": 1}}),
        );
        assert!(answer["error"].is_string(), "{answer}");
        assert!(keys(&path, "h").contains(&"v0".to_string()));
    }

    #[test]
    fn edits_in_one_gap_renumber_when_it_runs_out() {
        let path = temp("gap");
        write(
            &path,
            &[list("h", &["a", "z"], &[("a", "1"), ("z", "1")])],
            &[],
            &[],
        )
        .unwrap();
        let mut after = "a".to_string();
        let mut expected = vec!["a".to_string()];
        for i in 0..200 {
            let key = format!("k{i}");
            edit(
                &path,
                serde_json::json!({"name": "h", "remove": [], "insert": [[key, after]], "bodies": {&key: 1}}),
            );
            // Each goes right after the one before: the gap halves each time.
            expected.push(key.clone());
            after = key;
        }
        expected.push("z".into());
        assert_eq!(keys(&path, "h"), expected);
    }

    #[test]
    fn a_damaged_file_is_set_aside() {
        let path = temp("broken");
        std::fs::write(
            &path,
            b"this is not a database at all, not even close to one....",
        )
        .unwrap();
        let answer: serde_json::Value = serde_json::from_str(&read_json(
            &serde_json::json!({"path": path, "lists": ["f"]}).to_string(),
        ))
        .unwrap();
        let moved = answer["setAside"].as_str().expect("set aside");
        assert!(Path::new(moved).exists());
        // The next call starts a new, empty database.
        assert!(keys(&path, "f").is_empty());
    }
}
