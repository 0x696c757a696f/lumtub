//! Hides what must not reach the log file: OAuth values, bearer tokens and
//! signed stream addresses.

use std::os::raw::c_char;

use crate::taste::{give, text};

/// Names whose values are secret, in queries, forms and JSON.
const SECRETS: [&str; 6] = ["access_token", "refresh_token", "id_token", "client_secret", "code", "token"];

fn is_host(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-')
}

/// Whether `s` starts with `name`, ignoring ASCII case.
fn starts_with_ignore_case(s: &str, name: &str) -> bool {
    s.len() >= name.len() && s.as_bytes()[..name.len()].eq_ignore_ascii_case(name.as_bytes())
}

/// The length of the text that shows `s` is a secret's name and separator,
/// such as `refresh_token=` or `"access_token": "`.
fn secret_prefix(s: &str) -> Option<usize> {
    let name = SECRETS.iter().find(|name| starts_with_ignore_case(s, name))?;
    let mut at = name.len();
    let rest = |at: usize| s[at..].chars().next();
    if matches!(rest(at), Some('"' | '\'')) {
        at += 1;
    }
    while let Some(c) = rest(at).filter(|c| c.is_whitespace()) {
        at += c.len_utf8();
    }
    if !matches!(rest(at), Some(':' | '=')) {
        return None;
    }
    at += 1;
    while let Some(c) = rest(at).filter(|c| c.is_whitespace()) {
        at += c.len_utf8();
    }
    if matches!(rest(at), Some('"' | '\'')) {
        at += 1;
    }
    Some(at)
}

fn is_secret_value(c: char) -> bool {
    !c.is_whitespace() && !matches!(c, '&' | '"' | '\'' | ',' | '}')
}

/// The length of the run at the start of `s` whose characters pass `keep`.
fn run(s: &str, keep: impl Fn(char) -> bool) -> usize {
    s.find(|c: char| !keep(c)).unwrap_or(s.len())
}

/// Replaces every match that `find` reports at a position of `message`: it
/// returns the length of the part to keep and of the whole match.
fn replace(message: &str, find: impl Fn(&str) -> Option<(usize, usize, &'static str)>) -> String {
    let mut out = String::with_capacity(message.len());
    let mut at = 0;
    while at < message.len() {
        let rest = &message[at..];
        if let Some((keep, whole, with)) = find(rest) {
            out.push_str(&rest[..keep]);
            out.push_str(with);
            at += whole;
        } else {
            let c = rest.chars().next().unwrap();
            out.push(c);
            at += c.len_utf8();
        }
    }
    out
}

/// [message] without OAuth values, bearer tokens or the path and query of
/// googlevideo.com addresses, which are signed for one viewer; the host is
/// kept to tell what failed.
pub fn redact(message: &str) -> String {
    let text = replace(message, |s| {
        let scheme = if s.starts_with("https://") {
            8
        } else if s.starts_with("http://") {
            7
        } else {
            return None;
        };
        let host = run(&s[scheme..], is_host);
        let end = scheme + host;
        if !s[scheme..end].ends_with("googlevideo.com") || !s[end..].starts_with('/') {
            return None;
        }
        Some((end + 1, end + 1 + run(&s[end + 1..], |c| !c.is_whitespace()), "…"))
    });
    let text = replace(&text, |s| {
        let keep = secret_prefix(s)?;
        let value = run(&s[keep..], is_secret_value);
        (value > 0).then_some((keep, keep + value, "***"))
    });
    replace(&text, |s| {
        if !starts_with_ignore_case(s, "bearer") {
            return None;
        }
        let space = run(&s[6..], char::is_whitespace);
        let value = run(&s[6 + space..], |c| !c.is_whitespace());
        (space > 0 && value > 0).then_some((6 + space, 6 + space + value, "***"))
    })
}

/// [redact] for Dart. Free the text with `lumtub_string_free`.
///
/// # Safety
/// [message] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_redact(message: *const u8, length: usize) -> *mut c_char {
    give(redact(unsafe { text(message, length) }).replace('\0', ""))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hides_tokens_and_signed_stream_addresses() {
        let line = "POST code=4/0Ab-secret&code_verifier=x refresh_token=1//abc \
            {\"access_token\": \"ya29.zzz\"} Authorization: Bearer ya29.qqq \
            Failed to open https://rr3---sn-abc.googlevideo.com/videoplayback?expire=1&sig=ABC";
        let redacted = redact(line);
        for secret in ["4/0Ab-secret", "1//abc", "ya29.zzz", "ya29.qqq", "sig=ABC", "expire=1"] {
            assert!(!redacted.contains(secret), "{secret} in {redacted}");
        }
        assert_eq!(
            redacted,
            "POST code=***&code_verifier=x refresh_token=*** {\"access_token\": \"***\"} Authorization: Bearer *** \
             Failed to open https://rr3---sn-abc.googlevideo.com/…"
        );
    }

    #[test]
    fn leaves_other_text_alone() {
        for line in ["播放失败 dQw4w9WgXcQ", "token", "code: ", "https://www.youtube.com/watch?v=x", "Bearer", "http://googlevideo.com"] {
            assert_eq!(redact(line), line);
        }
    }

    #[test]
    fn ignores_case_of_names() {
        assert_eq!(redact("Client_Secret = 'abc'"), "Client_Secret = '***'");
        assert_eq!(redact("authorization: bearer\tXYZ"), "authorization: bearer\t***");
    }
}
