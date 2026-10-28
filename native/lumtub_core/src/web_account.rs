//! The cookie sign-in: the youtube.com cookies of a browser session, taken
//! from a browser window opened for it (browser_sign_in.rs) or from a
//! cookies.txt, used to make InnerTube requests as the YouTube website
//! signed in, the way yt-dlp's `--cookies` does. It is what liking posts,
//! voting in polls and writing under posts take, which the TV-code sign-in
//! cannot reach.
//!
//! The cookies are sealed on disk by vault.rs (a TPM key behind Windows
//! Hello where the user has it, and DPAPI; the keychain or keyring elsewhere). They are opened the first time
//! a request needs them after the app starts, and from then on kept
//! encrypted in memory, decrypted only while a request is built. Dart never
//! sees them: it asks for a request and gets the answer back.

use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex};
use std::time::Duration;

use reqwest::header::HeaderValue;
use serde::Deserialize;
use serde_json::{Value, json};
use zeroize::{Zeroize, Zeroizing};

use crate::browser_sign_in;
use crate::http::{Item, client, post, runtime};
use crate::taste::{give_json, text};
use crate::vault::{self, Failure, Guard, Sealer, Secret};

/// Cookies by name, in the order they came; wiped when dropped.
#[derive(Default)]
pub struct Jar(Vec<(String, String)>);

impl Jar {
    pub fn set(&mut self, name: &str, value: &str) {
        let (name, value) = (name.trim(), value.trim());
        if name.is_empty() || name.contains([' ', ';', '=']) || value.contains(';') {
            return;
        }
        match self.0.iter_mut().find(|(n, _)| n == name) {
            Some(slot) => {
                slot.1.zeroize();
                slot.1 = value.to_owned();
            }
            None => self.0.push((name.to_owned(), value.to_owned())),
        }
    }

    pub fn get(&self, name: &str) -> Option<&str> {
        self.0.iter().find(|(n, _)| n == name).map(|(_, v)| v.as_str()).filter(|v| !v.is_empty())
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// Whether these are a signed-in session: they hold an `SAPISID`.
    pub fn signed_in(&self) -> bool {
        self.get("SAPISID").or_else(|| self.get("__Secure-3PAPISID")).is_some()
    }

    /// The `Cookie` header.
    pub fn header(&self) -> String {
        self.0.iter().map(|(n, v)| format!("{n}={v}")).collect::<Vec<_>>().join("; ")
    }
}

impl Drop for Jar {
    fn drop(&mut self) {
        for (name, value) in &mut self.0 {
            name.zeroize();
            value.zeroize();
        }
    }
}

/// The youtube.com cookies in a Netscape cookies.txt, or in a `Cookie:`
/// header.
pub fn read_cookies(text: &str) -> Jar {
    let mut jar = Jar::default();
    let text = text.trim_start_matches('\u{feff}');
    if text.lines().any(|line| line.split('\t').count() >= 7) {
        for line in text.lines() {
            let line = line.strip_prefix("#HttpOnly_").unwrap_or(line);
            if line.starts_with('#') {
                continue;
            }
            let fields: Vec<&str> = line.trim_end_matches('\r').split('\t').collect();
            if fields.len() < 7 {
                continue;
            }
            let domain = fields[0].trim_start_matches('.');
            if domain == "youtube.com" || domain.ends_with(".youtube.com") {
                jar.set(fields[5], fields[6]);
            }
        }
    } else {
        let header = text.trim().strip_prefix("Cookie:").or_else(|| text.trim().strip_prefix("cookie:")).unwrap_or(text);
        for pair in header.split(';') {
            if let Some((name, value)) = pair.split_once('=') {
                jar.set(name, value);
            }
        }
    }
    jar
}

fn sha1_hex(text: &str) -> String {
    <sha1::Sha1 as sha1::Digest>::digest(text.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
}

/// The `Authorization` header the website sends with [jar] at [seconds]
/// since 1970: `SAPISIDHASH` and, where their cookies are there, the 1P and
/// 3P variants. The hash is SHA-1 because YouTube takes only that; it signs
/// one request and keeps nothing secret.
pub fn authorization(jar: &Jar, seconds: u64, origin: &str) -> Option<String> {
    let hash = |kind: &str, id: &str| format!("{kind} {seconds}_{}", sha1_hex(&format!("{seconds} {id} {origin}")));
    let main = jar.get("SAPISID").or_else(|| jar.get("__Secure-3PAPISID"))?;
    let mut parts = vec![hash("SAPISIDHASH", main)];
    if let Some(id) = jar.get("__Secure-1PAPISID") {
        parts.push(hash("SAPISID1PHASH", id));
    }
    if let Some(id) = jar.get("__Secure-3PAPISID") {
        parts.push(hash("SAPISID3PHASH", id));
    }
    Some(parts.join(" "))
}

struct Session {
    file: Option<PathBuf>,
    base: String,
    /// What the Windows Hello prompt says.
    reason: String,
    /// The sealed file as read, until it is opened.
    sealed: Option<Vec<u8>>,
    guard: Option<Guard>,
    /// The `Cookie` header, encrypted in memory, and what sealed it.
    open: Option<(Secret, Sealer)>,
    /// The user closed the Windows Hello prompt; asked again only for
    /// something they do.
    declined: bool,
}

static SESSION: LazyLock<Mutex<Session>> = LazyLock::new(|| {
    Mutex::new(Session { file: None, base: "https://www.youtube.com".into(), reason: "Lumtub".into(), sealed: None, guard: None, open: None, declined: false })
});

/// Held while the Windows Hello prompt is up, so requests ask once.
static OPENING: Mutex<()> = Mutex::new(());

fn session() -> std::sync::MutexGuard<'static, Session> {
    SESSION.lock().unwrap_or_else(|e| e.into_inner())
}

fn write_file(file: &Path, sealed: &[u8]) -> Result<(), String> {
    vault::write_private(file, sealed).map_err(|e| e.to_string())
}

/// Keeps [jar] as the sign-in, sealed with a new key; making a Windows
/// Hello key asks the user.
fn keep(jar: &Jar, hello: bool) -> Result<Guard, String> {
    if !jar.signed_in() {
        return Err("not signed in".into());
    }
    let (file, reason) = {
        let session = session();
        (session.file.clone().ok_or("the sign-in has no folder")?, session.reason.clone())
    };
    let header = Zeroizing::new(jar.header());
    let sealer = Sealer::new(hello, &reason);
    let sealed = sealer.seal(header.as_bytes()).ok_or("Windows could not encrypt the cookies")?;
    write_file(&file, &sealed)?;
    let secret = Secret::new(header.as_bytes()).ok_or("out of memory")?;
    let guard = sealer.guard();
    let mut session = session();
    session.open = Some((secret, sealer));
    session.sealed = None;
    session.guard = Some(guard);
    session.declined = false;
    Ok(guard)
}

enum Shut {
    SignedOut,
    Declined,
    Broken(String),
}

/// Opens the sealed cookies if they are not yet; Windows Hello asks the
/// user first where it guards them. [ask] asks again after the user
/// closed the prompt once.
fn unlock(ask: bool) -> Result<(), Shut> {
    let _opening = OPENING.lock().unwrap_or_else(|e| e.into_inner());
    let (sealed, reason) = {
        let mut session = session();
        if session.open.is_some() {
            return Ok(());
        }
        if session.declined && !ask {
            return Err(Shut::Declined);
        }
        session.declined = false;
        (session.sealed.clone().ok_or(Shut::SignedOut)?, session.reason.clone())
    };
    match vault::open(&sealed, &reason) {
        Ok((plain, sealer)) => {
            let secret = Secret::new(&plain).ok_or_else(|| Shut::Broken("out of memory".into()))?;
            let mut session = session();
            session.open = Some((secret, sealer));
            session.sealed = None;
            Ok(())
        }
        Err(Failure::Cancelled) => {
            session().declined = true;
            Err(Shut::Declined)
        }
        Err(Failure::Broken(why)) => Err(Shut::Broken(why)),
    }
}

/// Cookies YouTube set again in an answer replace the old values, so the
/// session lasts as it does in a browser.
fn renew(answer: &reqwest::Response) {
    let fresh: Vec<(String, Zeroizing<String>)> = answer
        .headers()
        .get_all("set-cookie")
        .iter()
        .filter_map(|v| v.to_str().ok())
        .filter_map(|v| v.split(';').next()?.split_once('=').map(|(n, v)| (n.trim().to_owned(), Zeroizing::new(v.trim().to_owned()))))
        .filter(|(_, v)| !v.is_empty())
        .collect();
    if fresh.is_empty() {
        return;
    }
    let mut session = session();
    let Some((secret, sealer)) = &session.open else { return };
    let changed = secret.reveal(|header| {
        let mut jar = read_cookies(std::str::from_utf8(header).unwrap_or(""));
        let mut changed = false;
        for (name, value) in &fresh {
            if jar.get(name).is_some_and(|old| old != value.as_str()) {
                jar.set(name, value);
                changed = true;
            }
        }
        changed.then(|| Zeroizing::new(jar.header()))
    });
    let Some(Some(header)) = changed else { return };
    let (Some(secret), Some(sealed)) = (Secret::new(header.as_bytes()), sealer.seal(header.as_bytes())) else { return };
    if let Some(file) = &session.file {
        let _ = write_file(file, &sealed);
    }
    if let Some(open) = session.open.as_mut() {
        open.0 = secret;
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Request {
    endpoint: String,
    #[serde(default)]
    body: Value,
    #[serde(default)]
    hl: String,
    #[serde(default)]
    language: String,
    client_version: String,
    /// Made for something the user did: Windows Hello may ask again.
    #[serde(default)]
    ask: bool,
}

/// Endpoints Dart may call through the sign-in; anything else is refused.
const ENDPOINTS: [&str; 10] = [
    "next",
    "browse",
    "account/accounts_list",
    "comment/perform_comment_action",
    "comment/create_comment",
    "comment/create_comment_reply",
    "like/like",
    "like/dislike",
    "like/removelike",
    "feedback",
];

/// The website's InnerTube request body: its client and [body]'s fields.
pub fn web_body(body: &Value, hl: &str, version: &str) -> Value {
    let mut out = json!({"context": {"client": {"clientName": "WEB", "clientVersion": version, "hl": if hl.is_empty() { "en" } else { hl }}}});
    if let (Some(out), Some(fields)) = (out.as_object_mut(), body.as_object()) {
        for (key, value) in fields {
            if key != "context" {
                out.insert(key.clone(), value.clone());
            }
        }
    }
    out
}

fn sensitive(text: &str) -> Option<HeaderValue> {
    let mut value = HeaderValue::from_str(text).ok()?;
    value.set_sensitive(true);
    Some(value)
}

/// Answers on [port]: `[status, body_bytes]`, `[-1]` signed out, `[-4]`
/// Windows Hello was closed, or `[-3, why]`.
async fn innertube(port: i64, request: Request) {
    if !ENDPOINTS.contains(&request.endpoint.as_str()) {
        post(port, vec![Item::Int(-3), Item::Text(format!("endpoint {} is not allowed", request.endpoint))]);
        return;
    }
    let ask = request.ask;
    let fail = |code: i64, why: Option<String>| {
        post(port, std::iter::once(Item::Int(code)).chain(why.map(Item::Text)).collect());
    };
    match runtime().spawn_blocking(move || unlock(ask)).await {
        Ok(Ok(())) => {}
        Ok(Err(Shut::SignedOut)) => return fail(-1, None),
        Ok(Err(Shut::Declined)) => return fail(-4, None),
        Ok(Err(Shut::Broken(why))) => return fail(-3, Some(why)),
        Err(e) => return fail(-3, Some(e.to_string())),
    }
    let seconds = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let (headers, base) = {
        let session = session();
        let headers = session.open.as_ref().and_then(|(secret, _)| {
            secret.reveal(|header| {
                let jar = read_cookies(std::str::from_utf8(header).unwrap_or(""));
                let cookie = Zeroizing::new(jar.header());
                let authorization = Zeroizing::new(authorization(&jar, seconds, "https://www.youtube.com")?);
                Some((sensitive(&cookie)?, sensitive(&authorization)?))
            })
        });
        (headers.flatten(), session.base.clone())
    };
    let Some((cookie, authorization)) = headers else { return fail(-1, None) };
    let body = web_body(&request.body, &request.hl, &request.client_version);
    let sent = client()
        .post(format!("{base}/youtubei/v1/{}?prettyPrint=false", request.endpoint))
        .header("Cookie", cookie)
        .header("Authorization", authorization)
        .header("X-Origin", "https://www.youtube.com")
        .header("Origin", "https://www.youtube.com")
        .header("X-Goog-AuthUser", "0")
        .header("X-Youtube-Client-Name", "1")
        .header("X-Youtube-Client-Version", request.client_version.as_str())
        .header("Accept-Language", if request.language.is_empty() { "en" } else { request.language.as_str() })
        .header("Content-Type", "application/json")
        .body(body.to_string())
        .timeout(Duration::from_secs(20))
        .send()
        .await;
    let response = match sent {
        Ok(response) => response,
        Err(e) => return fail(-3, Some(e.without_url().to_string())),
    };
    renew(&response);
    let status = response.status().as_u16() as i64;
    match response.bytes().await {
        Ok(bytes) => {
            post(port, vec![Item::Int(status), Item::Bytes(bytes.to_vec())]);
        }
        Err(e) => fail(-3, Some(e.without_url().to_string())),
    }
}

fn status() -> Value {
    let session = session();
    json!({
        "signedIn": session.open.is_some() || session.sealed.is_some(),
        "guard": session.guard.map(Guard::name),
        "unlocked": session.open.is_some(),
    })
}

/// Opens the sign-in kept in folder [json] `{"folder", "reason", "base"?}`
/// without asking the user anything, and answers
/// `{"signedIn", "guard", "unlocked"}`. [reason] is what the Windows Hello
/// prompt will say.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_web_open(json: *const u8, length: usize) -> *mut std::os::raw::c_char {
    let options: Value = serde_json::from_str(unsafe { text(json, length) }).unwrap_or_default();
    let Some(folder) = options.get("folder").and_then(Value::as_str) else { return give_json(&status()) };
    let file = PathBuf::from(folder).join("youtube-cookies.bin");
    let sealed = std::fs::read(&file).ok();
    let guard = sealed.as_deref().and_then(vault::guard);
    {
        let mut session = session();
        if let Some(base) = options.get("base").and_then(Value::as_str) {
            session.base = base.trim_end_matches('/').to_owned();
        }
        if let Some(reason) = options.get("reason").and_then(Value::as_str) {
            session.reason = reason.to_owned();
        }
        session.open = None;
        session.declined = false;
        session.sealed = sealed.filter(|_| guard.is_some());
        session.guard = guard;
        session.file = Some(file);
    }
    give_json(&status())
}

/// `{"signedIn", "guard", "unlocked"}`.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_web_status() -> *mut std::os::raw::c_char {
    give_json(&status())
}

fn answer(port: i64, kept: Result<(usize, Guard), String>) {
    match kept {
        Ok((count, guard)) => post(port, vec![Item::Int(0), Item::Int(count as i64), Item::Text(guard.name().into())]),
        Err(why) => post(port, vec![Item::Int(-2), Item::Text(why)]),
    };
}

/// Wipes and deletes [file].
fn shred(file: &Path) {
    if let Ok(metadata) = std::fs::metadata(file) {
        let _ = std::fs::write(file, vec![0u8; metadata.len() as usize]);
    }
    let _ = std::fs::remove_file(file);
}

/// Keeps the cookies of the cookies.txt at [json] `{"path", "hello",
/// "delete"}` as the sign-in, and wipes and deletes the file when
/// [delete]. Answers on [port] `[0, cookies, guard]` or `[-2, why]`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_web_import(port: i64, json: *const u8, length: usize) -> bool {
    let options: Value = serde_json::from_str(unsafe { text(json, length) }).unwrap_or_default();
    let Some(path) = options.get("path").and_then(Value::as_str).map(PathBuf::from) else { return false };
    let hello = options.get("hello").and_then(Value::as_bool).unwrap_or(true);
    let delete = options.get("delete").and_then(Value::as_bool).unwrap_or(false);
    runtime().spawn_blocking(move || {
        let kept = (|| {
            let mut bytes = std::fs::read(&path).map_err(|e| e.to_string())?;
            let jar = read_cookies(&String::from_utf8_lossy(&bytes));
            bytes.zeroize();
            if jar.is_empty() {
                return Err("no youtube.com cookies".to_owned());
            }
            let guard = keep(&jar, hello)?;
            if delete {
                shred(&path);
            }
            Ok((jar.len(), guard))
        })();
        answer(port, kept);
    });
    true
}

/// Opens a browser window of its own at Google's sign-in, as
/// browser_sign_in.rs does, and keeps the cookies once the user signed in.
/// [json] is `{"hello", "url"?}`. Answers on [port] `[1, browser]` once the
/// window is up, then `[0, cookies, guard]`, `[-4]` when it was closed
/// first, or `[-2, why]`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_web_browser_sign_in(port: i64, json: *const u8, length: usize) -> bool {
    let options: Value = serde_json::from_str(unsafe { text(json, length) }).unwrap_or_default();
    let hello = options.get("hello").and_then(Value::as_bool).unwrap_or(true);
    let url = options.get("url").and_then(Value::as_str).unwrap_or(browser_sign_in::SIGN_IN_URL).to_owned();
    let Some(folder) = session().file.as_ref().and_then(|f| f.parent()).map(Path::to_path_buf) else { return false };
    let Some(browser) = browser_sign_in::find_browser() else {
        post(port, vec![Item::Int(-2), Item::Text("no browser".into())]);
        return true;
    };
    std::thread::spawn(move || {
        let name = browser_sign_in::browser_name(&browser);
        let outcome = browser_sign_in::sign_in(&browser, &folder, &url, || {
            post(port, vec![Item::Int(1), Item::Text(name)]);
        });
        match outcome {
            browser_sign_in::Outcome::SignedIn(jar) => answer(port, keep(&jar, hello).map(|guard| (jar.len(), guard))),
            browser_sign_in::Outcome::Closed => {
                post(port, vec![Item::Int(-4)]);
            }
            browser_sign_in::Outcome::Failed(why) => answer(port, Err(why)),
        }
    });
    true
}

/// Closes a browser sign-in that is waiting.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_web_browser_cancel() {
    browser_sign_in::cancel();
}

/// Forgets the cookies and deletes their file.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_web_sign_out() {
    let mut session = session();
    session.open = None;
    session.sealed = None;
    session.guard = None;
    if let Some(file) = &session.file {
        shred(file);
    }
}

/// Makes the InnerTube request [json] `{"endpoint", "body", "hl",
/// "language", "clientVersion", "ask"}` as the signed-in website,
/// answering on [port].
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_web_innertube(port: i64, json: *const u8, length: usize) -> bool {
    let Ok(request) = serde_json::from_str::<Request>(unsafe { text(json, length) }) else {
        return false;
    };
    runtime().spawn(innertube(port, request));
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_cookies_txt_and_headers() {
        let file = "# Netscape HTTP Cookie File\n\
            .youtube.com\tTRUE\t/\tTRUE\t0\tSAPISID\tabc/def\n\
            #HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tsid1\n\
            .google.com\tTRUE\t/\tTRUE\t0\tSID\tother\n\
            www.youtube.com\tFALSE\t/\tFALSE\t0\tPREF\thl=en\r\n";
        let jar = read_cookies(file);
        assert_eq!(jar.header(), "SAPISID=abc/def; SID=sid1; PREF=hl=en");
        assert!(jar.signed_in());
        assert_eq!(read_cookies("Cookie: a=1; SAPISID=x; b=2=3").header(), "a=1; SAPISID=x; b=2=3");
        assert!(!read_cookies("PREF=hl=en").signed_in());
    }

    #[test]
    fn signs_requests_as_the_website_does() {
        let mut jar = Jar::default();
        jar.set("SAPISID", "abc");
        jar.set("__Secure-3PAPISID", "abc");
        let hash = sha1_hex("1700000000 abc https://www.youtube.com");
        assert_eq!(authorization(&jar, 1_700_000_000, "https://www.youtube.com").unwrap(), format!("SAPISIDHASH 1700000000_{hash} SAPISID3PHASH 1700000000_{hash}"));
        assert_eq!(sha1_hex("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d");
        assert_eq!(authorization(&Jar::default(), 1, "o"), None);
    }

    #[test]
    fn builds_the_websites_request() {
        let body = web_body(&json!({"continuation": "C", "context": "ignored"}), "zh-CN", "2.2026");
        assert_eq!(body, json!({"context": {"client": {"clientName": "WEB", "clientVersion": "2.2026", "hl": "zh-CN"}}, "continuation": "C"}));
    }

    #[test]
    fn keeps_and_reopens_the_cookies() {
        let folder = std::env::temp_dir().join(format!("lumtub-web-{}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        let options = json!({"folder": folder.to_string_lossy()}).to_string();
        unsafe { crate::taste::lumtub_string_free(lumtub_web_open(options.as_ptr(), options.len())) };
        assert_eq!(status()["signedIn"], false);
        let jar = read_cookies("SAPISID=abc; LOGIN_INFO=x");
        let guard = keep(&jar, true).unwrap();
        unsafe { crate::taste::lumtub_string_free(lumtub_web_open(options.as_ptr(), options.len())) };
        assert_eq!(status(), json!({"signedIn": true, "guard": guard.name(), "unlocked": false}));
        assert!(unlock(false).is_ok());
        let header = session().open.as_ref().unwrap().0.reveal(|h| String::from_utf8(h.to_vec()).unwrap());
        assert_eq!(header.as_deref(), Some("SAPISID=abc; LOGIN_INFO=x"));
        lumtub_web_sign_out();
        assert!(!folder.join("youtube-cookies.bin").exists());
        std::fs::remove_dir_all(&folder).unwrap();
    }
}
