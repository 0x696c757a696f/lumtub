//! YouTube's search suggestions, from the completion service the website
//! uses (see lib/search_suggestions.dart for the side that calls this):
//! `["query", ["suggestion", …], …]`.

use std::ffi::c_char;

use serde_json::Value;

use crate::taste::give_json;

/// The most an answer may be: a real one is well under 2 KB.
pub const MAX_ANSWER: usize = 64 << 10;
/// How many suggestions are kept, and how long each may be: YouTube gives
/// about ten short ones.
const MAX_SUGGESTIONS: usize = 20;
const MAX_LENGTH: usize = 200;

/// The suggestions in [body]; none when it is not such an answer.
pub fn suggestions(body: &[u8]) -> Vec<String> {
    if body.len() > MAX_ANSWER {
        return Vec::new();
    }
    let text = String::from_utf8_lossy(body);
    let Ok(Value::Array(answer)) = serde_json::from_str::<Value>(&text) else {
        return Vec::new();
    };
    let Some(Value::Array(list)) = answer.get(1) else {
        return Vec::new();
    };
    list.iter()
        .filter_map(Value::as_str)
        .filter(|s| s.chars().count() <= MAX_LENGTH)
        .take(MAX_SUGGESTIONS)
        .map(str::to_owned)
        .collect()
}

/// [suggestions] of [body] as a JSON list.
///
/// # Safety
/// [body] must point to [len] bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_search_suggestions(body: *const u8, len: usize) -> *mut c_char {
    if body.is_null() || len > MAX_ANSWER {
        return give_json(&Vec::<String>::new());
    }
    give_json(&suggestions(unsafe {
        std::slice::from_raw_parts(body, len)
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_list_and_nothing_else() {
        assert_eq!(
            suggestions(br#"["lum",["lumtub","lumen",3,null],[],{}]"#),
            ["lumtub", "lumen"]
        );
        assert!(suggestions(b"[\"lum\"]").is_empty());
        assert!(suggestions(b"<html>").is_empty());
        assert!(suggestions(b"{\"a\":[]}").is_empty());
        let long = format!("[\"q\",[\"{}\",\"ok\"]]", "x".repeat(300));
        assert_eq!(suggestions(long.as_bytes()), ["ok"]);
        let many = format!("[\"q\",[{}]]", vec!["\"s\""; 50].join(","));
        assert_eq!(suggestions(many.as_bytes()).len(), 20);
    }
}
