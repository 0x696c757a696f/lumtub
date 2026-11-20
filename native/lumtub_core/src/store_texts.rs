//! Texts made for a video, kept in lumtub.db beside the library: subtitle
//! transcripts (recognized from the audio, or later fetched) and AI
//! summaries. Each is made once and read many times, and each row says
//! where it came from, so machine-made text is never taken for a person's.

use std::os::raw::c_char;

use rusqlite::{OptionalExtension, params};
use serde::{Deserialize, Serialize};

use crate::store::{StoreError, error_json, with_db};
use crate::taste::{give, text};

/// Where a transcript came from.
pub const ORIGINS: &[&str] = &["human", "youtube-auto", "machine-local", "machine-cloud"];

/// Bodies beyond this are refused: an hour of subtitles is about 60 KB.
const MOST_BODY: usize = 16 << 20;

#[derive(Debug, PartialEq, Serialize)]
pub struct Transcript {
    pub lang: String,
    pub origin: String,
    pub model: String,
    pub body: String,
    pub created: i64,
}

#[derive(Debug, PartialEq, Serialize)]
pub struct Summary {
    pub lang: String,
    pub provider: String,
    pub body: String,
    pub created: i64,
}

fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

fn bad(message: &str) -> StoreError {
    StoreError::Other(message.into())
}

fn check_key(video: &str, lang: &str) -> Result<(), StoreError> {
    if video.is_empty() || video.len() > 64 || lang.is_empty() || lang.len() > 35 {
        return Err(bad("A video id and a language are needed"));
    }
    Ok(())
}

/// Keeps [body] as [video]'s transcript in [lang] from [origin], then
/// drops the oldest of that origin beyond [keep] (0 keeps all).
pub fn put_transcript(
    path: &str,
    video: &str,
    lang: &str,
    origin: &str,
    model: &str,
    body: &str,
    keep: usize,
) -> Result<usize, StoreError> {
    check_key(video, lang)?;
    if !ORIGINS.contains(&origin) {
        return Err(bad("Unknown transcript origin"));
    }
    if body.len() > MOST_BODY || model.len() > 200 {
        return Err(bad("The transcript is too large"));
    }
    with_db(path, |db| {
        let transaction = db.transaction()?;
        transaction.execute(
            "INSERT INTO transcript(video, lang, origin, model, body, created) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(video, lang, origin) DO UPDATE SET model = excluded.model, body = excluded.body, created = excluded.created",
            params![video, lang, origin, model, body, now()],
        )?;
        let dropped = if keep > 0 {
            transaction.execute(
                "DELETE FROM transcript WHERE origin = ?1 AND rowid NOT IN
                 (SELECT rowid FROM transcript WHERE origin = ?1 ORDER BY created DESC, rowid DESC LIMIT ?2)",
                params![origin, keep as i64],
            )?
        } else {
            0
        };
        transaction.commit()?;
        Ok(dropped)
    })
}

/// [video]'s transcripts, newest first, those from [origins] only when any
/// are given.
pub fn transcripts(
    path: &str,
    video: &str,
    origins: &[String],
) -> Result<Vec<Transcript>, StoreError> {
    with_db(path, |db| {
        let mut rows = db.prepare(
            "SELECT lang, origin, model, body, created FROM transcript WHERE video = ?1 ORDER BY created DESC, rowid DESC",
        )?;
        let found = rows
            .query_map([video], |row| {
                Ok(Transcript {
                    lang: row.get(0)?,
                    origin: row.get(1)?,
                    model: row.get(2)?,
                    body: row.get(3)?,
                    created: row.get(4)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(found
            .into_iter()
            .filter(|t| origins.is_empty() || origins.contains(&t.origin))
            .collect())
    })
}

/// Forgets [video]'s transcripts, from [origin] only when given. With no
/// video, forgets every transcript from [origin].
pub fn forget_transcripts(path: &str, video: &str, origin: &str) -> Result<usize, StoreError> {
    with_db(path, |db| {
        Ok(match (video.is_empty(), origin.is_empty()) {
            (true, true) => db.execute("DELETE FROM transcript", [])?,
            (true, false) => db.execute("DELETE FROM transcript WHERE origin = ?1", [origin])?,
            (false, true) => db.execute("DELETE FROM transcript WHERE video = ?1", [video])?,
            (false, false) => db.execute(
                "DELETE FROM transcript WHERE video = ?1 AND origin = ?2",
                [video, origin],
            )?,
        })
    })
}

/// Keeps [body] as [video]'s summary in [lang], dropping the oldest beyond
/// [keep] (0 keeps all).
pub fn put_summary(
    path: &str,
    video: &str,
    lang: &str,
    provider: &str,
    body: &str,
    keep: usize,
) -> Result<usize, StoreError> {
    check_key(video, lang)?;
    if body.len() > MOST_BODY || provider.len() > 200 {
        return Err(bad("The summary is too large"));
    }
    with_db(path, |db| {
        let transaction = db.transaction()?;
        transaction.execute(
            "INSERT INTO summary(video, lang, provider, body, created) VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(video, lang) DO UPDATE SET provider = excluded.provider, body = excluded.body, created = excluded.created",
            params![video, lang, provider, body, now()],
        )?;
        let dropped = if keep > 0 {
            transaction.execute(
                "DELETE FROM summary WHERE rowid NOT IN (SELECT rowid FROM summary ORDER BY created DESC, rowid DESC LIMIT ?1)",
                [keep as i64],
            )?
        } else {
            0
        };
        transaction.commit()?;
        Ok(dropped)
    })
}

pub fn summary(path: &str, video: &str, lang: &str) -> Result<Option<Summary>, StoreError> {
    with_db(path, |db| {
        db.query_row(
            "SELECT lang, provider, body, created FROM summary WHERE video = ?1 AND lang = ?2",
            [video, lang],
            |row| {
                Ok(Summary {
                    lang: row.get(0)?,
                    provider: row.get(1)?,
                    body: row.get(2)?,
                    created: row.get(3)?,
                })
            },
        )
        .optional()
    })
}

/// Forgets [video]'s summaries in every language; with no video, all.
pub fn forget_summaries(path: &str, video: &str) -> Result<usize, StoreError> {
    with_db(path, |db| {
        Ok(if video.is_empty() {
            db.execute("DELETE FROM summary", [])?
        } else {
            db.execute("DELETE FROM summary WHERE video = ?1", [video])?
        })
    })
}

#[derive(Deserialize)]
struct Ask {
    path: String,
    op: String,
    #[serde(default)]
    video: String,
    #[serde(default)]
    lang: String,
    #[serde(default)]
    origin: String,
    #[serde(default)]
    origins: Vec<String>,
    #[serde(default)]
    model: String,
    #[serde(default)]
    provider: String,
    #[serde(default)]
    body: String,
    #[serde(default)]
    keep: usize,
}

fn answer(ask: &str) -> String {
    let ask: Ask = match serde_json::from_str(ask) {
        Ok(ask) => ask,
        Err(error) => return serde_json::json!({"error": error.to_string()}).to_string(),
    };
    let path = ask.path.as_str();
    let result = match ask.op.as_str() {
        "transcript.put" => put_transcript(
            path,
            &ask.video,
            &ask.lang,
            &ask.origin,
            &ask.model,
            &ask.body,
            ask.keep,
        )
        .map(|dropped| serde_json::json!({"dropped": dropped})),
        "transcript.get" => transcripts(path, &ask.video, &ask.origins)
            .map(|found| serde_json::json!({"transcripts": found})),
        "transcript.forget" => forget_transcripts(path, &ask.video, &ask.origin)
            .map(|n| serde_json::json!({"deleted": n})),
        "summary.put" => put_summary(
            path,
            &ask.video,
            &ask.lang,
            &ask.provider,
            &ask.body,
            ask.keep,
        )
        .map(|dropped| serde_json::json!({"dropped": dropped})),
        "summary.get" => {
            summary(path, &ask.video, &ask.lang).map(|found| serde_json::json!({"summary": found}))
        }
        "summary.forget" => {
            forget_summaries(path, &ask.video).map(|n| serde_json::json!({"deleted": n}))
        }
        _ => Err(bad("Unknown operation")),
    };
    match result {
        Ok(value) => value.to_string(),
        Err(error) => error_json(error),
    }
}

/// Keeps, reads or forgets a transcript or summary. [json] is `{path, op,
/// ...}` with op one of `transcript.put` (video, lang, origin, model,
/// body, keep), `transcript.get` (video, origins), `transcript.forget`
/// (video, origin), `summary.put` (video, lang, provider, body, keep),
/// `summary.get` (video, lang) and `summary.forget` (video). Answers
/// `{error, setAside?}` on failure. Free it with `lumtub_string_free`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_store_texts(json: *const u8, length: usize) -> *mut c_char {
    give(answer(unsafe { text(json, length) }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> String {
        let dir = std::env::temp_dir().join(format!("lumtub-texts-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir.join("lumtub.db").display().to_string()
    }

    #[test]
    fn transcripts_round_trip_and_replace() {
        let path = temp("round");
        put_transcript(
            &path,
            "abc",
            "en",
            "machine-cloud",
            "whisper-1",
            "WEBVTT\n\nA",
            0,
        )
        .unwrap();
        put_transcript(
            &path,
            "abc",
            "en",
            "machine-cloud",
            "whisper-1",
            "WEBVTT\n\nB",
            0,
        )
        .unwrap();
        put_transcript(&path, "abc", "ja", "human", "", "WEBVTT\n\nC", 0).unwrap();
        let all = transcripts(&path, "abc", &[]).unwrap();
        assert_eq!(all.len(), 2);
        let machine = transcripts(&path, "abc", &["machine-cloud".into()]).unwrap();
        assert_eq!(machine.len(), 1);
        assert_eq!(machine[0].body, "WEBVTT\n\nB");
        assert_eq!(machine[0].model, "whisper-1");
        assert!(transcripts(&path, "other", &[]).unwrap().is_empty());
        assert_eq!(forget_transcripts(&path, "abc", "human").unwrap(), 1);
        assert_eq!(transcripts(&path, "abc", &[]).unwrap().len(), 1);
    }

    #[test]
    fn transcripts_past_keep_are_dropped_per_origin() {
        let path = temp("keep");
        put_transcript(&path, "keep-me", "en", "human", "", "x", 0).unwrap();
        for i in 0..5 {
            put_transcript(&path, &format!("v{i}"), "en", "machine-cloud", "", "x", 3).unwrap();
        }
        let left: Vec<usize> = (0..5)
            .filter(|i| {
                !transcripts(&path, &format!("v{i}"), &[])
                    .unwrap()
                    .is_empty()
            })
            .collect();
        assert_eq!(left, vec![2, 3, 4]);
        assert_eq!(transcripts(&path, "keep-me", &[]).unwrap().len(), 1);
    }

    #[test]
    fn bad_input_is_refused() {
        let path = temp("bad");
        assert!(put_transcript(&path, "v", "en", "robot", "", "x", 0).is_err());
        assert!(put_transcript(&path, "", "en", "human", "", "x", 0).is_err());
        assert!(put_summary(&path, "v", "", "p", "x", 0).is_err());
        let answer = answer(&serde_json::json!({"path": path, "op": "nope"}).to_string());
        assert!(answer.contains("error"));
    }

    #[test]
    fn summaries_round_trip() {
        let path = temp("summary");
        assert_eq!(summary(&path, "v", "zh-Hans").unwrap(), None);
        put_summary(&path, "v", "zh-Hans", "cloud:deepseek-chat", "要点", 0).unwrap();
        put_summary(&path, "v", "en", "cloud:deepseek-chat", "Points", 0).unwrap();
        assert_eq!(
            summary(&path, "v", "zh-Hans").unwrap().unwrap().body,
            "要点"
        );
        for i in 0..4 {
            put_summary(&path, &format!("w{i}"), "en", "p", "x", 3).unwrap();
        }
        assert!(summary(&path, "v", "en").unwrap().is_none());
        assert!(summary(&path, "w3", "en").unwrap().is_some());
        assert_eq!(forget_summaries(&path, "w3").unwrap(), 1);
    }

    #[test]
    fn the_library_tables_live_beside_them() {
        let path = temp("beside");
        put_summary(&path, "v", "en", "p", "x", 0).unwrap();
        crate::store::write(&path, &[], &[], &[("library", "1")]).unwrap();
        let (_, meta) = crate::store::read(&path, &[], &[]).unwrap();
        assert_eq!(meta.get("library").map(String::as_str), Some("1"));
        assert!(summary(&path, "v", "en").unwrap().is_some());
    }

    #[test]
    fn the_ffi_answer_reads() {
        let path = temp("ffi");
        let put = answer(
            &serde_json::json!({"path": path, "op": "transcript.put", "video": "v", "lang": "en",
                "origin": "machine-cloud", "model": "m", "body": "WEBVTT", "keep": 10})
            .to_string(),
        );
        assert_eq!(put, r#"{"dropped":0}"#);
        let got = answer(
            &serde_json::json!({"path": path, "op": "transcript.get", "video": "v"}).to_string(),
        );
        let value: serde_json::Value = serde_json::from_str(&got).unwrap();
        assert_eq!(value["transcripts"][0]["origin"], "machine-cloud");
    }
}
