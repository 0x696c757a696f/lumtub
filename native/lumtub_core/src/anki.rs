//! Anki packages (.apkg): a deck, one note type and its notes in the
//! collection format every Anki since 2.1 imports (schema 11), with the
//! notes' sound and pictures beside it in one zip file.

use std::ffi::c_char;
use std::fs::{self, File};
use std::io::{BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{Connection, params};
use serde::Deserialize;
use serde_json::{Value, json};
use sha1::{Digest, Sha1};

use crate::taste::{give, text};

/// The most a package holds, so a damaged book cannot fill the disk.
const MAX_NOTES: usize = 100_000;
const MAX_MEDIA_FILE: u64 = 64 << 20;
const MAX_MEDIA_TOTAL: u64 = 2 << 30;

#[derive(Deserialize)]
pub struct Template {
    pub name: String,
    pub front: String,
    pub back: String,
}

#[derive(Deserialize)]
pub struct Model {
    pub id: i64,
    pub name: String,
    pub fields: Vec<String>,
    pub templates: Vec<Template>,
    pub css: String,
}

#[derive(Deserialize)]
pub struct Deck {
    pub id: i64,
    pub name: String,
    #[serde(default)]
    pub description: String,
}

#[derive(Deserialize)]
pub struct Note {
    pub guid: String,
    pub fields: Vec<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    /// Seconds since 1970: Anki keeps a note it already has unless this
    /// is newer, so exporting the same book twice changes nothing.
    pub modified: i64,
}

#[derive(Deserialize)]
pub struct Media {
    /// The name the notes use for it, such as `lumtub-abc.wav`.
    pub name: String,
    pub path: String,
}

#[derive(Deserialize)]
pub struct Package {
    pub out: String,
    pub model: Model,
    pub deck: Deck,
    pub notes: Vec<Note>,
    #[serde(default)]
    pub media: Vec<Media>,
}

/// A media name Anki stores as given: no folders, no characters file
/// systems refuse, nothing hidden.
fn plain_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 120
        && !name.starts_with('.')
        && name.chars().all(|c| {
            !c.is_control() && !matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|')
        })
}

/// [field] without HTML tags, as Anki sorts and checks duplicates by.
fn strip_html(field: &str) -> String {
    let mut out = String::with_capacity(field.len());
    let mut inside = false;
    for c in field.chars() {
        match c {
            '<' => inside = true,
            '>' if inside => inside = false,
            _ if !inside => out.push(c),
            _ => {}
        }
    }
    out.replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&amp;", "&")
        .trim()
        .to_string()
}

/// The first 8 hex digits of SHA-1 of the sort field, as Anki's checksum.
fn checksum(field: &str) -> i64 {
    let digest = Sha1::digest(strip_html(field).as_bytes());
    i64::from(u32::from_be_bytes([
        digest[0], digest[1], digest[2], digest[3],
    ]))
}

fn now() -> (i64, i64) {
    let since = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    (since.as_secs() as i64, since.as_millis() as i64)
}

const SCHEMA: &str = "
CREATE TABLE col (id integer primary key, crt integer not null, mod integer not null, scm integer not null, ver integer not null,
  dty integer not null, usn integer not null, ls integer not null, conf text not null, models text not null, decks text not null,
  dconf text not null, tags text not null);
CREATE TABLE notes (id integer primary key, guid text not null, mid integer not null, mod integer not null, usn integer not null,
  tags text not null, flds text not null, sfld integer not null, csum integer not null, flags integer not null, data text not null);
CREATE TABLE cards (id integer primary key, nid integer not null, did integer not null, ord integer not null, mod integer not null,
  usn integer not null, type integer not null, queue integer not null, due integer not null, ivl integer not null,
  factor integer not null, reps integer not null, lapses integer not null, left integer not null, odue integer not null,
  odid integer not null, flags integer not null, data text not null);
CREATE TABLE revlog (id integer primary key, cid integer not null, usn integer not null, ease integer not null, ivl integer not null,
  lastIvl integer not null, factor integer not null, time integer not null, type integer not null);
CREATE TABLE graves (usn integer not null, oid integer not null, type integer not null);
CREATE INDEX ix_notes_usn on notes (usn);
CREATE INDEX ix_cards_usn on cards (usn);
CREATE INDEX ix_revlog_usn on revlog (usn);
CREATE INDEX ix_cards_nid on cards (nid);
CREATE INDEX ix_cards_sched on cards (did, queue, due);
CREATE INDEX ix_revlog_cid on revlog (cid);
CREATE INDEX ix_notes_csum on notes (csum);
";

fn deck_json(id: i64, name: &str, description: &str, modified: i64) -> Value {
    json!({
        "id": id, "name": name, "desc": description, "mod": modified, "usn": -1, "conf": 1, "dyn": 0, "collapsed": false,
        "extendNew": 0, "extendRev": 50, "newToday": [0, 0], "revToday": [0, 0], "lrnToday": [0, 0], "timeToday": [0, 0],
    })
}

fn collection(path: &Path, package: &Package) -> Result<(), String> {
    let model = &package.model;
    let (seconds, millis) = now();
    let db = Connection::open(path).map_err(|e| e.to_string())?;
    db.execute_batch(SCHEMA).map_err(|e| e.to_string())?;
    let models = json!({ model.id.to_string(): {
        "id": model.id, "name": model.name, "type": 0, "mod": seconds, "usn": -1, "sortf": 0, "did": package.deck.id,
        "flds": model.fields.iter().enumerate().map(|(i, name)| json!({
            "name": name, "ord": i, "sticky": false, "rtl": false, "font": "Arial", "size": 20, "media": [],
        })).collect::<Vec<_>>(),
        "tmpls": model.templates.iter().enumerate().map(|(i, t)| json!({
            "name": t.name, "ord": i, "qfmt": t.front, "afmt": t.back, "bqfmt": "", "bafmt": "", "did": null, "bfont": "", "bsize": 0,
        })).collect::<Vec<_>>(),
        "css": model.css, "latexPre": "", "latexPost": "", "latexsvg": false, "req": [[0, "any", [0]]], "tags": [], "vers": [],
    }});
    let decks = json!({
        "1": deck_json(1, "Default", "", seconds),
        package.deck.id.to_string(): deck_json(package.deck.id, &package.deck.name, &package.deck.description, seconds),
    });
    let dconf = json!({ "1": {
        "id": 1, "name": "Default", "mod": 0, "usn": 0, "maxTaken": 60, "autoplay": true, "timer": 0, "replayq": true, "dyn": false,
        "new": { "bury": true, "delays": [1, 10], "initialFactor": 2500, "ints": [1, 4, 7], "order": 1, "perDay": 20, "separate": true },
        "rev": { "bury": true, "ease4": 1.3, "fuzz": 0.05, "ivlFct": 1, "maxIvl": 36500, "minSpace": 1, "perDay": 200 },
        "lapse": { "delays": [10], "leechAction": 1, "leechFails": 8, "minInt": 1, "mult": 0 },
    }});
    let conf = json!({
        "activeDecks": [1], "curDeck": 1, "curModel": model.id.to_string(), "nextPos": package.notes.len() + 1,
        "sortType": "noteFld", "sortBackwards": false, "addToCur": true, "collapseTime": 1200, "dueCounts": true,
        "estTimes": true, "newSpread": 0, "timeLim": 0,
    });
    db.execute(
        "INSERT INTO col VALUES (1, ?1, ?2, ?2, 11, 0, 0, 0, ?3, ?4, ?5, ?6, '{}')",
        params![
            seconds - seconds % 86_400,
            millis,
            conf.to_string(),
            models.to_string(),
            decks.to_string(),
            dconf.to_string()
        ],
    )
    .map_err(|e| e.to_string())?;
    let transaction = db.unchecked_transaction().map_err(|e| e.to_string())?;
    {
        let mut note_row = transaction
            .prepare("INSERT INTO notes VALUES (?1, ?2, ?3, ?4, -1, ?5, ?6, ?7, ?8, 0, '')")
            .map_err(|e| e.to_string())?;
        let mut card_row = transaction
            .prepare("INSERT INTO cards VALUES (?1, ?2, ?3, ?4, ?5, -1, 0, 0, ?6, 0, 0, 0, 0, 0, 0, 0, 0, '')")
            .map_err(|e| e.to_string())?;
        let cards_per_note = model.templates.len() as i64;
        for (i, note) in package.notes.iter().enumerate() {
            let index = i as i64;
            let id = millis.saturating_add(index);
            let tags = note
                .tags
                .iter()
                .filter(|t| !t.is_empty() && !t.chars().any(char::is_whitespace))
                .cloned()
                .collect::<Vec<_>>();
            let tags = if tags.is_empty() {
                String::new()
            } else {
                format!(" {} ", tags.join(" "))
            };
            let sort = strip_html(&note.fields[0]);
            note_row
                .execute(params![
                    id,
                    note.guid,
                    model.id,
                    note.modified,
                    tags,
                    note.fields.join("\u{1f}"),
                    sort,
                    checksum(&note.fields[0])
                ])
                .map_err(|e| e.to_string())?;
            for ord in 0..cards_per_note {
                let card = millis
                    .saturating_add(package.notes.len() as i64)
                    .saturating_add(index * cards_per_note + ord);
                card_row
                    .execute(params![
                        card,
                        id,
                        package.deck.id,
                        ord,
                        note.modified,
                        index + 1
                    ])
                    .map_err(|e| e.to_string())?;
            }
        }
    }
    transaction.commit().map_err(|e| e.to_string())?;
    db.close().map_err(|(_, e)| e.to_string())
}

/// A zip file of stored (uncompressed) entries: sound and pictures are
/// compressed already, and every Anki reads it.
struct Zip<W: Write> {
    out: W,
    at: u64,
    entries: Vec<(String, u32, u64, u64)>,
}

impl<W: Write> Zip<W> {
    fn new(out: W) -> Self {
        Zip {
            out,
            at: 0,
            entries: Vec::new(),
        }
    }

    fn put(&mut self, bytes: &[u8]) -> Result<(), String> {
        self.out.write_all(bytes).map_err(|e| e.to_string())?;
        self.at = self.at.saturating_add(bytes.len() as u64);
        Ok(())
    }

    fn add(&mut self, name: &str, data: &[u8]) -> Result<(), String> {
        let size = u32::try_from(data.len()).map_err(|_| format!("{name} is too big"))?;
        if self.at > u64::from(u32::MAX) - u64::from(size) - 1024 {
            return Err("The package is too big".into());
        }
        let crc = crc32fast::hash(data);
        let offset = self.at;
        let mut head = Vec::with_capacity(30 + name.len());
        head.extend_from_slice(&0x0403_4b50u32.to_le_bytes());
        head.extend_from_slice(&20u16.to_le_bytes());
        head.extend_from_slice(&0x0800u16.to_le_bytes()); // names are UTF-8
        head.extend_from_slice(&0u16.to_le_bytes()); // stored
        head.extend_from_slice(&0u32.to_le_bytes()); // time and date
        head.extend_from_slice(&crc.to_le_bytes());
        head.extend_from_slice(&size.to_le_bytes());
        head.extend_from_slice(&size.to_le_bytes());
        head.extend_from_slice(&(name.len() as u16).to_le_bytes());
        head.extend_from_slice(&0u16.to_le_bytes());
        head.extend_from_slice(name.as_bytes());
        self.put(&head)?;
        self.put(data)?;
        self.entries
            .push((name.to_string(), crc, u64::from(size), offset));
        Ok(())
    }

    fn finish(mut self) -> Result<W, String> {
        let start = self.at;
        let entries = std::mem::take(&mut self.entries);
        for (name, crc, size, offset) in &entries {
            let mut row = Vec::with_capacity(46 + name.len());
            row.extend_from_slice(&0x0201_4b50u32.to_le_bytes());
            row.extend_from_slice(&20u16.to_le_bytes());
            row.extend_from_slice(&20u16.to_le_bytes());
            row.extend_from_slice(&0x0800u16.to_le_bytes());
            row.extend_from_slice(&0u16.to_le_bytes());
            row.extend_from_slice(&0u32.to_le_bytes());
            row.extend_from_slice(&crc.to_le_bytes());
            row.extend_from_slice(&(*size as u32).to_le_bytes());
            row.extend_from_slice(&(*size as u32).to_le_bytes());
            row.extend_from_slice(&(name.len() as u16).to_le_bytes());
            row.extend_from_slice(&[0; 8]); // extra, comment, disk, internal attributes
            row.extend_from_slice(&0u32.to_le_bytes());
            row.extend_from_slice(&(*offset as u32).to_le_bytes());
            row.extend_from_slice(name.as_bytes());
            self.put(&row)?;
        }
        let length = self.at - start;
        let count = u16::try_from(entries.len()).map_err(|_| "Too many files")?;
        let mut end = Vec::with_capacity(22);
        end.extend_from_slice(&0x0605_4b50u32.to_le_bytes());
        end.extend_from_slice(&[0; 4]);
        end.extend_from_slice(&count.to_le_bytes());
        end.extend_from_slice(&count.to_le_bytes());
        end.extend_from_slice(&(length as u32).to_le_bytes());
        end.extend_from_slice(&(start as u32).to_le_bytes());
        end.extend_from_slice(&0u16.to_le_bytes());
        self.put(&end)?;
        Ok(self.out)
    }
}

fn read_limited(path: &str, left: &mut u64) -> Result<Vec<u8>, String> {
    let file = File::open(path).map_err(|e| format!("{path}: {e}"))?;
    let size = file.metadata().map_err(|e| e.to_string())?.len();
    if size > MAX_MEDIA_FILE || size > *left {
        return Err(format!("{path} is too big"));
    }
    let mut bytes = Vec::with_capacity(size as usize);
    file.take(size)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    *left -= bytes.len() as u64;
    Ok(bytes)
}

fn check(package: &Package) -> Result<(), String> {
    let model = &package.model;
    if model.fields.is_empty()
        || model.templates.is_empty()
        || model.name.is_empty()
        || package.deck.name.is_empty()
    {
        return Err("The note type needs a name, fields and a card".into());
    }
    if package.notes.len() > MAX_NOTES {
        return Err("Too many notes".into());
    }
    if let Some(note) = package
        .notes
        .iter()
        .find(|n| n.fields.len() != model.fields.len() || n.guid.is_empty())
    {
        return Err(format!(
            "A note has {} fields, the note type {}",
            note.fields.len(),
            model.fields.len()
        ));
    }
    let mut names = std::collections::HashSet::new();
    if let Some(media) = package
        .media
        .iter()
        .find(|m| !plain_name(&m.name) || !names.insert(m.name.as_str()))
    {
        return Err(format!("Bad media name {:?}", media.name));
    }
    Ok(())
}

/// Writes [package] to its `out` file, through a temporary file beside it.
pub fn write(package: &Package) -> Result<(), String> {
    check(package)?;
    let out = PathBuf::from(&package.out);
    let base = out
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or("Bad output path")?;
    let database = out.with_file_name(format!("{base}.collection.tmp"));
    let partial = out.with_file_name(format!("{base}.part"));
    let result = (|| {
        let _ = fs::remove_file(&database);
        collection(&database, package)?;
        let mut zip = Zip::new(BufWriter::new(
            File::create(&partial).map_err(|e| e.to_string())?,
        ));
        zip.add(
            "collection.anki2",
            &fs::read(&database).map_err(|e| e.to_string())?,
        )?;
        let index = package
            .media
            .iter()
            .enumerate()
            .map(|(i, m)| (i.to_string(), Value::from(m.name.as_str())))
            .collect::<serde_json::Map<_, _>>();
        zip.add("media", Value::Object(index).to_string().as_bytes())?;
        let mut left = MAX_MEDIA_TOTAL;
        for (i, media) in package.media.iter().enumerate() {
            zip.add(&i.to_string(), &read_limited(&media.path, &mut left)?)?;
        }
        zip.finish()?
            .into_inner()
            .map_err(|e| e.to_string())?
            .sync_all()
            .map_err(|e| e.to_string())?;
        fs::rename(&partial, &out).map_err(|e| e.to_string())
    })();
    let _ = fs::remove_file(&database);
    if result.is_err() {
        let _ = fs::remove_file(&partial);
    }
    result
}

/// Writes the Anki package JSON [Package] describes; answers `{}` or
/// `{"error"}`.
///
/// # Safety
/// [json] points at [length] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_anki_package(json: *const u8, length: usize) -> *mut c_char {
    // SAFETY: the caller passes [length] readable bytes at [json].
    let request = unsafe { text(json, length) };
    let answer = serde_json::from_str::<Package>(request)
        .map_err(|e| e.to_string())
        .and_then(|p| write(&p));
    give(match answer {
        Ok(()) => "{}".to_string(),
        Err(error) => json!({ "error": error }).to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn package(out: &Path, media: Vec<Media>) -> Package {
        Package {
            out: out.to_string_lossy().into_owned(),
            model: Model {
                id: 1_763_900_000_001,
                name: "Lumtub".into(),
                fields: vec!["Word".into(), "Meaning".into()],
                templates: vec![Template {
                    name: "Card".into(),
                    front: "{{Word}}".into(),
                    back: "{{Meaning}}".into(),
                }],
                css: ".card {}".into(),
            },
            deck: Deck {
                id: 1_763_900_000_002,
                name: "Lumtub".into(),
                description: String::new(),
            },
            notes: vec![
                Note {
                    guid: "a".into(),
                    fields: vec!["<b>学习</b>".into(), "to study".into()],
                    tags: vec!["lumtub".into()],
                    modified: 1,
                },
                Note {
                    guid: "b".into(),
                    fields: vec!["docteur".into(), "医生".into()],
                    tags: vec![],
                    modified: 2,
                },
            ],
            media,
        }
    }

    #[test]
    fn strips_html_for_sorting() {
        assert_eq!(strip_html("<b>a</b> &amp; b<br>"), "a & b");
        assert_eq!(checksum("<b>学习</b>"), checksum("学习"));
    }

    #[test]
    fn writes_a_zip_with_the_collection_and_media() {
        let dir = std::env::temp_dir().join(format!("lumtub-anki-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let sound = dir.join("line.wav");
        fs::write(&sound, b"RIFF....WAVE").unwrap();
        let out = dir.join("book.apkg");
        write(&package(
            &out,
            vec![Media {
                name: "lumtub-1.wav".into(),
                path: sound.to_string_lossy().into_owned(),
            }],
        ))
        .unwrap();
        let bytes = fs::read(&out).unwrap();
        assert_eq!(&bytes[..4], b"PK\x03\x04");
        assert!(bytes.windows(16).any(|w| w == b"collection.anki2"));
        assert!(bytes.windows(12).any(|w| w == b"RIFF....WAVE"));
        assert!(bytes.windows(20).any(|w| w == br#"{"0":"lumtub-1.wav"}"#));
        assert!(
            !dir.join("book.apkg.part").exists() && !dir.join("book.apkg.collection.tmp").exists()
        );
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn refuses_bad_media_names_and_field_counts() {
        let out = std::env::temp_dir().join("lumtub-anki-refused.apkg");
        for name in ["../x.wav", "a/b.wav", ".hidden", "", "a\u{0}b"] {
            assert!(
                write(&package(
                    &out,
                    vec![Media {
                        name: name.into(),
                        path: "x".into()
                    }]
                ))
                .is_err(),
                "{name}"
            );
        }
        let mut wrong = package(&out, vec![]);
        wrong.notes[0].fields.pop();
        assert!(write(&wrong).is_err());
        assert!(!out.exists());
    }
}
