//! The learning pack's dictionaries, looked up on disk.
//!
//! Each language's dictionary is a read-only SQLite file built by the
//! learning packs workflow (`.github/learning/sqlite_pack.py`):
//!
//! - `meta(key, value)`: `format`, `language`, `version`;
//! - `entry(id, line)`: the word list's line, which the app reads;
//! - `term(key, entry, form)`: a word as written and in lower case
//!   (`form` 0), or one of its forms (`form` 1), to its entry.
//!
//! Nothing is read into memory beyond SQLite's own small page cache, so
//! having many languages installed costs disk only.

use std::collections::HashMap;
use std::os::raw::c_char;
use std::sync::{Mutex, OnceLock};

use rusqlite::{Connection, OpenFlags};
use serde::{Deserialize, Serialize};

use crate::taste::{give_json, text};

/// The pack format this build reads.
pub const VERSION: &str = "1";

/// Most keys looked up in one call.
const MOST_KEYS: usize = 512;
/// Most entries one key may give.
const MOST_ENTRIES: usize = 32;

pub struct Lexicon {
    db: Connection,
    /// The language's code, such as `es`: Spanish and Italian look for
    /// the word under its attached pronouns ([crate::words::without_pronouns]).
    language: String,
}

/// An entry found for a key: its line and whether the key is a form of it.
#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct Found {
    pub line: String,
    pub form: bool,
}

impl Lexicon {
    pub fn open(language: &str, path: &str) -> Result<Lexicon, String> {
        // Read-only and immutable: the file is replaced, never changed in
        // place, so SQLite skips locking and journal checks.
        let uri = format!("file://{}?mode=ro&immutable=1", uri_path(path));
        let db = Connection::open_with_flags(
            &uri,
            OpenFlags::SQLITE_OPEN_READ_ONLY
                | OpenFlags::SQLITE_OPEN_NO_MUTEX
                | OpenFlags::SQLITE_OPEN_URI,
        )
        .map_err(|e| format!("{path}: {e}"))?;
        let version: String = db
            .query_row("SELECT value FROM meta WHERE key = 'version'", [], |row| {
                row.get(0)
            })
            .map_err(|e| format!("{path}: not a dictionary ({e})"))?;
        if version != VERSION {
            return Err(format!(
                "{path}: dictionary format {version}, this version reads {VERSION}"
            ));
        }
        // A small cache: lookups are a few pages each.
        let _ = db.execute_batch(
            "PRAGMA cache_size = -2048; PRAGMA query_only = 1; PRAGMA mmap_size = 67108864;",
        );
        Ok(Lexicon {
            db,
            language: language.to_string(),
        })
    }

    /// The entries for [key] as written, else in lower case, else folded
    /// as subtitles write words ([fold]); words themselves before the
    /// words [key] is a form of. A Spanish or Italian word not found is
    /// looked for without the pronouns it may carry (`hacerlo`, `dammelo`),
    /// its entries then counting as what it is a form of.
    pub fn find(&self, key: &str) -> Vec<Found> {
        let lower = key.to_lowercase();
        for candidate in [key.to_string(), lower.clone(), fold(&lower)] {
            if candidate.is_empty() {
                continue;
            }
            let found = self.find_exact(&candidate);
            if !found.is_empty() {
                return found;
            }
        }
        for stem in crate::words::without_pronouns(&self.language, &lower) {
            let found = self.find_exact(&stem);
            if !found.is_empty() {
                return found
                    .into_iter()
                    .map(|f| Found {
                        line: f.line,
                        form: true,
                    })
                    .collect();
            }
        }
        Vec::new()
    }

    /// Whether [key] is a word or form here, as [find] looks it up.
    pub fn knows(&self, key: &str) -> bool {
        !self.find(key).is_empty()
    }

    fn find_exact(&self, key: &str) -> Vec<Found> {
        let Ok(mut query) = self.db.prepare_cached(
            "SELECT e.line, t.form FROM term t JOIN entry e ON e.id = t.entry WHERE t.key = ?1 ORDER BY t.form, t.entry LIMIT ?2",
        ) else {
            return Vec::new();
        };
        query
            .query_map(rusqlite::params![key, MOST_ENTRIES as i64], |row| {
                Ok(Found {
                    line: row.get(0)?,
                    form: row.get::<_, i64>(1)? != 0,
                })
            })
            .map(|rows| rows.filter_map(Result::ok).collect())
            .unwrap_or_default()
    }
}

/// A word without stress marks and with ё as е, as subtitles write
/// Russian; the packs index this form too.
pub fn fold(word: &str) -> String {
    word.chars()
        .filter(|c| !matches!(c, '\u{0301}' | '\u{0300}'))
        .map(|c| match c {
            'ё' => 'е',
            'Ё' => 'Е',
            other => other,
        })
        .collect()
}

/// [path] for a `file:` URI: `/` between folders, and the characters a
/// URI gives meaning to, and every byte past ASCII, escaped. A Windows path gains a leading `/`.
fn uri_path(path: &str) -> String {
    let mut out = String::new();
    let slashed = path.replace('\\', "/");
    if !slashed.starts_with('/') {
        out.push('/');
    }
    for byte in slashed.bytes() {
        match byte {
            b'?' | b'#' | b'%' | b' ' | b'&' | b'=' | 0x80.. => {
                out.push_str(&format!("%{byte:02X}"))
            }
            _ => out.push(byte as char),
        }
    }
    out
}

/// The open dictionaries, by language.
pub(crate) fn open_lexicons() -> &'static Mutex<HashMap<String, Lexicon>> {
    static OPEN: OnceLock<Mutex<HashMap<String, Lexicon>>> = OnceLock::new();
    OPEN.get_or_init(|| Mutex::new(HashMap::new()))
}

#[derive(Serialize)]
struct Failed {
    error: String,
}

/// Opens a language's dictionary, [json] being `{language, path}`, in
/// place of the one open for it. Answers `{"words": n}` or `{"error"}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_lexicon_open(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        language: String,
        path: String,
    }
    #[derive(Serialize)]
    struct Opened {
        words: i64,
    }
    let answer = serde_json::from_str::<Ask>(unsafe { text(json, length) })
        .map_err(|e| e.to_string())
        .and_then(|ask| {
            let lexicon = Lexicon::open(&ask.language, &ask.path)?;
            let words = lexicon
                .db
                .query_row("SELECT count(*) FROM entry", [], |row| row.get(0))
                .unwrap_or(0);
            let mut open = open_lexicons()
                .lock()
                .map_err(|_| "lexicons poisoned".to_string())?;
            open.insert(ask.language, lexicon);
            Ok(Opened { words })
        });
    match answer {
        Ok(opened) => give_json(&opened),
        Err(error) => give_json(&Failed { error }),
    }
}

/// Closes a language's dictionary, [json] being `{language}`, so its file
/// can be deleted or replaced. Answers `{}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_lexicon_close(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        language: String,
    }
    if let Ok(ask) = serde_json::from_str::<Ask>(unsafe { text(json, length) })
        && let Ok(mut open) = open_lexicons().lock()
    {
        open.remove(&ask.language);
    }
    give_json(&serde_json::json!({}))
}

/// Looks up keys in a language's dictionary, [json] being `{language,
/// keys}`. Answers `{"found": [[{line, form}, …], …]}`, one list per key,
/// or `{"error"}` when the language has no open dictionary.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_lexicon_find(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        language: String,
        keys: Vec<String>,
    }
    #[derive(Serialize)]
    struct Answer {
        found: Vec<Vec<Found>>,
    }
    let answer = serde_json::from_str::<Ask>(unsafe { text(json, length) })
        .map_err(|e| e.to_string())
        .and_then(|ask| {
            let open = open_lexicons()
                .lock()
                .map_err(|_| "lexicons poisoned".to_string())?;
            let lexicon = open
                .get(&ask.language)
                .ok_or_else(|| format!("no dictionary for {}", ask.language))?;
            Ok(Answer {
                found: ask
                    .keys
                    .iter()
                    .take(MOST_KEYS)
                    .map(|key| lexicon.find(key))
                    .collect(),
            })
        });
    match answer {
        Ok(found) => give_json(&found),
        Err(error) => give_json(&Failed { error }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(path: &std::path::Path) {
        let db = Connection::open(path).unwrap();
        db.execute_batch(
            "CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
             CREATE TABLE entry(id INTEGER PRIMARY KEY, line TEXT NOT NULL);
             CREATE TABLE term(key TEXT NOT NULL, entry INTEGER NOT NULL, form INTEGER NOT NULL, PRIMARY KEY(key, entry)) WITHOUT ROWID;
             INSERT INTO meta VALUES ('version', '1');
             INSERT INTO entry VALUES (1, 'hablar\tv. 说话'), (2, 'Haus\tn. 房子');
             INSERT INTO term VALUES ('hablar', 1, 0), ('hablo', 1, 1), ('Haus', 2, 0), ('haus', 2, 0);",
        )
        .unwrap();
    }

    #[test]
    fn finds_words_and_their_forms() {
        let folder = std::env::temp_dir().join(format!("lumtub-lexicon-{}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        let path = folder.join("es.sqlite");
        let _ = std::fs::remove_file(&path);
        sample(&path);
        let lexicon = Lexicon::open("es", path.to_str().unwrap()).unwrap();
        assert_eq!(
            lexicon.find("hablo"),
            vec![Found {
                line: "hablar\tv. 说话".into(),
                form: true
            }]
        );
        assert!(!lexicon.find("hablar")[0].form);
        assert_eq!(lexicon.find("HAUS").len(), 1);
        assert_eq!(lexicon.find("Haus").len(), 1);
        assert!(lexicon.find("nada").is_empty());
        assert_eq!(
            lexicon.find("Hablarlo"),
            vec![Found {
                line: "hablar\tv. 说话".into(),
                form: true
            }]
        );
        drop(lexicon);
        std::fs::remove_dir_all(folder).unwrap();
    }

    #[test]
    fn folds_russian_and_opens_any_path() {
        assert_eq!(fold("за́мок"), "замок");
        assert_eq!(fold("ёлка"), "елка");
        assert_eq!(
            uri_path("C:\\Users\\Zoë\\a b.sqlite"),
            "/C:/Users/Zo%C3%AB/a%20b.sqlite"
        );
        let folder = std::env::temp_dir().join(format!("lumtub-lexicon-é ?{}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        let path = folder.join("ru.sqlite");
        sample(&path);
        let lexicon = Lexicon::open("es", path.to_str().unwrap()).unwrap();
        assert_eq!(lexicon.find("HABLO").len(), 1);
        drop(lexicon);
        std::fs::remove_dir_all(folder).unwrap();
    }

    #[test]
    fn refuses_other_files() {
        let folder =
            std::env::temp_dir().join(format!("lumtub-lexicon-bad-{}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        let path = folder.join("bad.sqlite");
        Connection::open(&path)
            .unwrap()
            .execute_batch("CREATE TABLE x(y)")
            .unwrap();
        assert!(Lexicon::open("es", path.to_str().unwrap()).is_err());
        assert!(Lexicon::open("es", folder.join("missing.sqlite").to_str().unwrap()).is_err());
        std::fs::remove_dir_all(folder).unwrap();
    }
}
