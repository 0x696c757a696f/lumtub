//! The TV-code sign-in: signing in the way YouTube's TV app does (a short
//! code typed at youtube.com/activate), keeping its credential encrypted on
//! disk, and making InnerTube requests as the TV app with it. YouTube's own
//! endpoints take only this kind of sign-in for liking comments and posts,
//! reading the account's home feed, history and the like. Dart never sees
//! the tokens: it asks for a request and gets the answer back.
//!
//! The client, endpoints and request shape follow SmartTube's
//! MediaServiceCore and YouTube.js.

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};

use serde::Deserialize;
use serde_json::{Value, json};

use crate::http::{Item, client, post, runtime};
use crate::taste::text;

/// The YouTube TV app's own client. It is read from the TV app's script
/// each sign-in, as SmartTube and YouTube.js do; these are for when that
/// cannot be read.
const CLIENT_ID: &str = "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com";
const CLIENT_SECRET: &str = "SboVhoG9s0rNafixCSGGKXAT";
const SCOPE: &str = "http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content";
pub const TV_CLIENT_NAME: &str = "TVHTML5";
pub const TV_CLIENT_VERSION: &str = "7.20260901.15.00";
const TV_USER_AGENT: &str = "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)";

#[derive(Default)]
struct Account {
    /// Where the encrypted credential lives.
    file: Option<PathBuf>,
    /// `https://www.youtube.com`, or a test server.
    base: String,
    refresh: Option<Credential>,
    access: Option<(String, Instant)>,
}

/// A sign-in's refresh token and the client it belongs to, which every
/// refresh must name again.
#[derive(Clone, Debug, PartialEq)]
pub struct Credential {
    pub refresh: String,
    pub client_id: String,
    pub client_secret: String,
}

static ACCOUNT: LazyLock<Mutex<Account>> = LazyLock::new(|| Mutex::new(Account { base: "https://www.youtube.com".into(), ..Default::default() }));

/// Bumped by every new sign-in and by cancelling, so an older wait stops.
static ATTEMPT: AtomicU64 = AtomicU64::new(0);

fn account() -> std::sync::MutexGuard<'static, Account> {
    ACCOUNT.lock().unwrap_or_else(|e| e.into_inner())
}

/// The body of an InnerTube request as the TV app sends it: its client
/// context (as SmartTube's `AppClient.TV` builds it) and [body]'s fields.
pub fn tv_body(body: &Value, hl: &str, gl: &str) -> Value {
    let mut out = json!({
        "context": {
            "client": {
                "clientName": TV_CLIENT_NAME,
                "clientVersion": TV_CLIENT_VERSION,
                "clientScreen": "WATCH",
                "userAgent": TV_USER_AGENT,
                "hl": hl,
                "tvAppInfo": {"appQuality": "TV_APP_QUALITY_FULL_ANIMATION", "zylonLeftNav": true},
                "webpSupport": false,
                "animatedWebpSupport": true,
            },
            "user": {"enableSafetyMode": false, "lockedSafetyMode": false},
        },
        "racyCheckOk": true,
        "contentCheckOk": true,
    });
    // Without a region YouTube goes by where the request comes from.
    if !gl.is_empty() {
        out["context"]["client"]["gl"] = Value::from(gl);
    }
    if let (Some(out), Some(fields)) = (out.as_object_mut(), body.as_object()) {
        for (key, value) in fields {
            if key != "context" {
                out.insert(key.clone(), value.clone());
            }
        }
    }
    out
}

/// What a token answer says.
#[derive(Debug, PartialEq)]
pub enum TokenAnswer {
    Tokens { access: String, refresh: Option<String>, seconds: u64 },
    Pending,
    SlowDown,
    Denied,
    Expired,
    /// The refresh token is no longer valid.
    Revoked,
    Failed(String),
}

pub fn read_token_answer(answer: &Value) -> TokenAnswer {
    match answer.get("error").and_then(Value::as_str) {
        Some("authorization_pending") => TokenAnswer::Pending,
        Some("slow_down") => TokenAnswer::SlowDown,
        Some("access_denied") => TokenAnswer::Denied,
        Some("expired_token") => TokenAnswer::Expired,
        Some("invalid_grant") => TokenAnswer::Revoked,
        Some(other) => TokenAnswer::Failed(other.to_owned()),
        None => match answer.get("access_token").and_then(Value::as_str) {
            Some(access) => TokenAnswer::Tokens {
                access: access.to_owned(),
                refresh: answer.get("refresh_token").and_then(Value::as_str).map(str::to_owned),
                seconds: answer.get("expires_in").and_then(Value::as_u64).unwrap_or(3600),
            },
            None => TokenAnswer::Failed("no access_token".into()),
        },
    }
}

async fn send(url: String, body: Value) -> Result<Value, String> {
    let response = client()
        .post(url)
        .header("Content-Type", "application/json")
        .header("User-Agent", TV_USER_AGENT)
        .body(body.to_string())
        .timeout(Duration::from_secs(20))
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let status = response.status().as_u16();
    let bytes = response.bytes().await.map_err(|e| e.to_string())?;
    match serde_json::from_slice::<Value>(&bytes) {
        Ok(value) if value.is_object() => Ok(value),
        _ => Err(format!("YouTube answered {status}")),
    }
}

/// The TV app's client id and secret in its script, the first
/// `clientId:"…apps.googleusercontent.com",<name>:"<secret>"`.
pub fn client_in_script(script: &str) -> Option<(String, String)> {
    let mut rest = script;
    while let Some(at) = rest.find("clientId:\"") {
        rest = &rest[at + 10..];
        let Some(end) = rest.find('"') else { break };
        let id = &rest[..end];
        let after = rest[end + 1..].trim_start_matches(',').trim_start();
        let secret = after.split_once(":\"").and_then(|(name, value)| {
            let name_ok = !name.is_empty() && name.chars().all(|c| c == '$' || c == '_' || c.is_ascii_alphanumeric());
            let secret = &value[..value.find('"')?];
            (name_ok && !secret.is_empty() && secret.chars().all(|c| c == '_' || c == '-' || c.is_ascii_alphanumeric())).then_some(secret)
        });
        if id.ends_with(".apps.googleusercontent.com")
            && let Some(secret) = secret
        {
            return Some((id.to_owned(), secret.to_owned()));
        }
    }
    None
}

/// The address of the TV app's script in its page.
pub fn script_in_page(page: &str) -> Option<String> {
    let at = page.find("id=\"base-js\"")?;
    let tail = &page[at..];
    let start = tail.find("src=\"")? + 5;
    let src = &tail[start..start + tail[start..].find('"')?];
    Some(if src.starts_with("//") { format!("https:{src}") } else if src.starts_with('/') { format!("https://www.youtube.com{src}") } else { src.to_owned() })
}

async fn get(url: &str) -> Option<String> {
    let response = client().get(url).header("User-Agent", TV_USER_AGENT).header("Referer", "https://www.youtube.com/tv").header("Accept-Language", "en-US").timeout(Duration::from_secs(20)).send().await.ok()?;
    response.status().is_success().then_some(())?;
    response.text().await.ok()
}

/// The TV app's current client, read from its page and script; the known
/// one when they cannot be read.
async fn tv_client(base: &str) -> (String, String) {
    let found = async {
        let page = get(&format!("{base}/tv")).await?;
        let script = script_in_page(&page)?;
        let script = if script.starts_with("https://www.youtube.com") && base != "https://www.youtube.com" { script.replacen("https://www.youtube.com", base, 1) } else { script };
        client_in_script(&get(&script).await?)
    }
    .await;
    found.unwrap_or_else(|| (CLIENT_ID.to_owned(), CLIENT_SECRET.to_owned()))
}

fn device_id() -> String {
    let mut bytes = [0u8; 16];
    let seed = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0) ^ (std::process::id() as u128) << 64;
    let digest = <sha2::Sha256 as sha2::Digest>::digest(seed.to_le_bytes());
    bytes.copy_from_slice(&digest[..16]);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!("{}-{}-{}-{}-{}", &hex[..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..])
}

/// The steps of a sign-in, posted to Dart: `[0, code, address]` once the
/// code is there, `[1]` when signed in, `[2, why]` when it failed and `[3]`
/// when cancelled.
async fn sign_in(port: i64, attempt: u64) {
    let base = account().base.clone();
    let (client_id, client_secret) = tv_client(&base).await;
    let device = match send(
        format!("{base}/o/oauth2/device/code"),
        json!({"client_id": client_id, "scope": SCOPE, "device_id": device_id(), "device_model": "ytlr::"}),
    )
    .await
    {
        Ok(device) => device,
        Err(why) => {
            post(port, vec![Item::Int(2), Item::Text(why)]);
            return;
        }
    };
    let (Some(code), Some(user_code)) = (device.get("device_code").and_then(Value::as_str), device.get("user_code").and_then(Value::as_str)) else {
        post(port, vec![Item::Int(2), Item::Text("no code".into())]);
        return;
    };
    let address = device.get("verification_url").and_then(Value::as_str).unwrap_or("https://www.youtube.com/activate");
    post(port, vec![Item::Int(0), Item::Text(user_code.into()), Item::Text(address.into())]);
    let mut wait = Duration::from_secs(device.get("interval").and_then(Value::as_u64).unwrap_or(5));
    let until = Instant::now() + Duration::from_secs(device.get("expires_in").and_then(Value::as_u64).unwrap_or(1800));
    loop {
        tokio::time::sleep(wait).await;
        if ATTEMPT.load(Ordering::SeqCst) != attempt {
            post(port, vec![Item::Int(3)]);
            return;
        }
        if Instant::now() > until {
            post(port, vec![Item::Int(2), Item::Text("expired_token".into())]);
            return;
        }
        let answer = send(
            format!("{base}/o/oauth2/token"),
            json!({"client_id": client_id, "client_secret": client_secret, "code": code, "grant_type": "http://oauth.net/grant_type/device/1.0"}),
        )
        .await;
        if ATTEMPT.load(Ordering::SeqCst) != attempt {
            post(port, vec![Item::Int(3)]);
            return;
        }
        match answer.map(|a| read_token_answer(&a)) {
            Ok(TokenAnswer::Pending) => continue,
            Ok(TokenAnswer::SlowDown) => wait += Duration::from_secs(5),
            Ok(TokenAnswer::Tokens { access, refresh: Some(refresh), seconds }) => {
                let credential = Credential { refresh, client_id: client_id.clone(), client_secret: client_secret.clone() };
                let saved = {
                    let mut account = account();
                    account.refresh = Some(credential.clone());
                    account.access = Some((access, Instant::now() + Duration::from_secs(seconds.saturating_sub(60))));
                    account.file.clone().map(|file| store::save(&file, &credential))
                };
                match saved {
                    Some(Err(why)) => post(port, vec![Item::Int(2), Item::Text(why)]),
                    _ => post(port, vec![Item::Int(1)]),
                };
                return;
            }
            Ok(TokenAnswer::Tokens { .. }) => {
                post(port, vec![Item::Int(2), Item::Text("no refresh_token".into())]);
                return;
            }
            Ok(TokenAnswer::Denied) => {
                post(port, vec![Item::Int(2), Item::Text("access_denied".into())]);
                return;
            }
            Ok(TokenAnswer::Expired) => {
                post(port, vec![Item::Int(2), Item::Text("expired_token".into())]);
                return;
            }
            Ok(TokenAnswer::Revoked) => {
                post(port, vec![Item::Int(2), Item::Text("invalid_grant".into())]);
                return;
            }
            Ok(TokenAnswer::Failed(why)) | Err(why) => {
                post(port, vec![Item::Int(2), Item::Text(why)]);
                return;
            }
        }
    }
}

/// Why a request could not be made signed in.
enum NoToken {
    SignedOut,
    /// Google no longer takes the saved sign-in; it is now signed out.
    Revoked,
    Failed(String),
}

async fn access_token() -> Result<String, NoToken> {
    let (refresh, base) = {
        let account = account();
        if let Some((token, until)) = &account.access
            && Instant::now() < *until
        {
            return Ok(token.clone());
        }
        (account.refresh.clone().ok_or(NoToken::SignedOut)?, account.base.clone())
    };
    let answer = send(
        format!("{base}/o/oauth2/token"),
        json!({"client_id": refresh.client_id, "client_secret": refresh.client_secret, "refresh_token": refresh.refresh, "grant_type": "refresh_token"}),
    )
    .await
    .map_err(NoToken::Failed)?;
    match read_token_answer(&answer) {
        TokenAnswer::Tokens { access, seconds, .. } => {
            account().access = Some((access.clone(), Instant::now() + Duration::from_secs(seconds.saturating_sub(60))));
            Ok(access)
        }
        TokenAnswer::Revoked => {
            let mut account = account();
            if account.refresh.as_ref() == Some(&refresh) {
                account.refresh = None;
                account.access = None;
                if let Some(file) = &account.file {
                    let _ = std::fs::remove_file(file);
                }
            }
            Err(NoToken::Revoked)
        }
        TokenAnswer::Failed(why) => Err(NoToken::Failed(why)),
        other => Err(NoToken::Failed(format!("{other:?}"))),
    }
}

#[derive(Deserialize)]
struct InnerTubeRequest {
    endpoint: String,
    #[serde(default)]
    body: Value,
    #[serde(default = "english")]
    hl: String,
    #[serde(default)]
    gl: String,
    #[serde(default = "english")]
    language: String,
}

fn english() -> String {
    "en".into()
}

/// Endpoints Dart may call through the sign-in; anything else is refused.
const ENDPOINTS: [&str; 6] = ["next", "browse", "comment/perform_comment_action", "like/like", "like/dislike", "like/removelike"];

/// Answers on [port]: `[status, body_bytes]`, or `[-1]` signed out, `[-2]`
/// when the sign-in was revoked (now signed out), `[-3, why]` on failure.
async fn innertube(port: i64, request: InnerTubeRequest) {
    if !ENDPOINTS.contains(&request.endpoint.as_str()) {
        post(port, vec![Item::Int(-3), Item::Text(format!("endpoint {} is not allowed", request.endpoint))]);
        return;
    }
    let token = match access_token().await {
        Ok(token) => token,
        Err(NoToken::SignedOut) => {
            post(port, vec![Item::Int(-1)]);
            return;
        }
        Err(NoToken::Revoked) => {
            post(port, vec![Item::Int(-2)]);
            return;
        }
        Err(NoToken::Failed(why)) => {
            post(port, vec![Item::Int(-3), Item::Text(why)]);
            return;
        }
    };
    let base = account().base.clone();
    let body = tv_body(&request.body, &request.hl, &request.gl);
    let sent = client()
        .post(format!("{base}/youtubei/v1/{}?prettyPrint=false", request.endpoint))
        .bearer_auth(token)
        .header("User-Agent", TV_USER_AGENT)
        .header("Accept-Language", request.language)
        .header("Origin", "https://www.youtube.com")
        .header("Referer", "https://www.youtube.com/tv")
        .header("X-YouTube-Client-Name", "7")
        .header("X-YouTube-Client-Version", TV_CLIENT_VERSION)
        .header("Content-Type", "application/json")
        .body(body.to_string())
        .timeout(Duration::from_secs(20))
        .send()
        .await;
    let response = match sent {
        Ok(response) => response,
        Err(e) => {
            post(port, vec![Item::Int(-3), Item::Text(e.to_string())]);
            return;
        }
    };
    let status = response.status().as_u16() as i64;
    if status == 401 {
        // A token that stopped working early: get a new one next time.
        account().access = None;
    }
    match response.bytes().await {
        Ok(bytes) => post(port, vec![Item::Int(status), Item::Bytes(bytes.to_vec())]),
        Err(e) => post(port, vec![Item::Int(-3), Item::Text(e.to_string())]),
    };
}

/// Opens the sign-in kept in folder [json] `{"folder", "base"?}` and says
/// whether there is one.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_tv_open(json: *const u8, length: usize) -> bool {
    let options: Value = serde_json::from_str(unsafe { text(json, length) }).unwrap_or_default();
    let Some(folder) = options.get("folder").and_then(Value::as_str) else { return false };
    let file = PathBuf::from(folder).join("youtube-tv.bin");
    let mut account = account();
    if let Some(base) = options.get("base").and_then(Value::as_str) {
        account.base = base.trim_end_matches('/').to_owned();
    }
    account.refresh = store::load(&file);
    account.access = None;
    account.file = Some(file);
    account.refresh.is_some()
}

/// Starts a sign-in, its steps posted to [port] as `sign_in` describes.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_tv_sign_in(port: i64) {
    let attempt = ATTEMPT.fetch_add(1, Ordering::SeqCst) + 1;
    runtime().spawn(sign_in(port, attempt));
}

/// Stops a sign-in that is waiting for its code.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_tv_cancel() {
    ATTEMPT.fetch_add(1, Ordering::SeqCst);
}

/// Forgets the sign-in and its saved credential.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_tv_sign_out() {
    ATTEMPT.fetch_add(1, Ordering::SeqCst);
    let mut account = account();
    account.refresh = None;
    account.access = None;
    if let Some(file) = &account.file {
        let _ = std::fs::remove_file(file);
    }
}

/// Whether there is a sign-in.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_tv_signed_in() -> bool {
    account().refresh.is_some()
}

/// Makes the InnerTube request [json] `{"endpoint", "body", "hl", "gl",
/// "language"}` as the TV app with the sign-in, answering on [port].
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_tv_innertube(port: i64, json: *const u8, length: usize) -> bool {
    let Ok(request) = serde_json::from_str::<InnerTubeRequest>(unsafe { text(json, length) }) else {
        return false;
    };
    runtime().spawn(innertube(port, request));
    true
}

/// The credential on disk: `{"refresh_token": …}` as JSON, encrypted with
/// Windows DPAPI for the current user, the same way the Google sign-in is.
mod store {
    use std::path::Path;

    use serde_json::{Value, json};

    use super::{CLIENT_ID, CLIENT_SECRET, Credential};

    pub fn load(file: &Path) -> Option<Credential> {
        let data = protect::unprotect(&std::fs::read(file).ok()?)?;
        let value: Value = serde_json::from_slice(&data).ok()?;
        let field = |key: &str| value.get(key).and_then(Value::as_str).filter(|t| !t.is_empty()).map(str::to_owned);
        Some(Credential {
            refresh: field("refresh_token")?,
            // A sign-in saved before the client was kept is the known one's.
            client_id: field("client_id").unwrap_or_else(|| CLIENT_ID.to_owned()),
            client_secret: field("client_secret").unwrap_or_else(|| CLIENT_SECRET.to_owned()),
        })
    }

    pub fn save(file: &Path, credential: &Credential) -> Result<(), String> {
        let data = serde_json::to_vec(&json!({"refresh_token": credential.refresh, "client_id": credential.client_id, "client_secret": credential.client_secret})).map_err(|e| e.to_string())?;
        let sealed = protect::protect(&data).ok_or("Windows could not encrypt the sign-in")?;
        let temporary = file.with_extension("bin.tmp");
        std::fs::write(&temporary, sealed).map_err(|e| e.to_string())?;
        std::fs::rename(&temporary, file).map_err(|e| e.to_string())
    }

    #[cfg(windows)]
    mod protect {
        use windows_sys::Win32::Foundation::{HLOCAL, LocalFree};
        use windows_sys::Win32::Security::Cryptography::{CRYPT_INTEGER_BLOB, CRYPTPROTECT_UI_FORBIDDEN, CryptProtectData, CryptUnprotectData};

        // The app's earlier name; the Dart side used the same, so a sign-in
        // saved by it still opens.
        const ENTROPY: &[u8] = b"YTPlus account v1";

        fn run(data: &[u8], seal: bool) -> Option<Vec<u8>> {
            let input = CRYPT_INTEGER_BLOB { cbData: data.len() as u32, pbData: data.as_ptr() as *mut u8 };
            let entropy = CRYPT_INTEGER_BLOB { cbData: ENTROPY.len() as u32, pbData: ENTROPY.as_ptr() as *mut u8 };
            let mut output = CRYPT_INTEGER_BLOB { cbData: 0, pbData: std::ptr::null_mut() };
            // SAFETY: the blobs point to live buffers; the output is freed below.
            let ok = unsafe {
                if seal {
                    CryptProtectData(&input, std::ptr::null(), &entropy, std::ptr::null(), std::ptr::null(), CRYPTPROTECT_UI_FORBIDDEN, &mut output)
                } else {
                    CryptUnprotectData(&input, std::ptr::null_mut(), &entropy, std::ptr::null(), std::ptr::null(), CRYPTPROTECT_UI_FORBIDDEN, &mut output)
                }
            };
            if ok == 0 || output.pbData.is_null() {
                return None;
            }
            // SAFETY: Windows filled [output] with cbData bytes.
            let bytes = unsafe { std::slice::from_raw_parts(output.pbData, output.cbData as usize) }.to_vec();
            unsafe { LocalFree(output.pbData as HLOCAL) };
            Some(bytes)
        }

        pub fn protect(data: &[u8]) -> Option<Vec<u8>> {
            run(data, true)
        }

        pub fn unprotect(data: &[u8]) -> Option<Vec<u8>> {
            run(data, false)
        }
    }

    // Elsewhere only tests run; the file is kept as it is.
    #[cfg(not(windows))]
    mod protect {
        pub fn protect(data: &[u8]) -> Option<Vec<u8>> {
            Some(data.to_vec())
        }

        pub fn unprotect(data: &[u8]) -> Option<Vec<u8>> {
            Some(data.to_vec())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_the_tv_apps_request() {
        let body = tv_body(&json!({"videoId": "x", "context": {"client": {"clientName": "WEB"}}}), "zh-CN", "CN");
        assert_eq!(body["context"]["client"]["clientName"], "TVHTML5");
        assert_eq!(body["context"]["client"]["hl"], "zh-CN");
        assert_eq!(body["videoId"], "x");
        assert_eq!(body["racyCheckOk"], true);
    }

    #[test]
    fn reads_the_client_from_the_tv_apps_page_and_script() {
        assert_eq!(script_in_page(r#"<script id="base-js" src="/s/_/kabuki/base.js" nonce="x"></script>"#).as_deref(), Some("https://www.youtube.com/s/_/kabuki/base.js"));
        let script = r#"a={clientId:"nope",b:"x"};c={clientId:"861-abc.apps.googleusercontent.com",
$q:"Sec_ret-1"}"#;
        assert_eq!(client_in_script(script), Some(("861-abc.apps.googleusercontent.com".into(), "Sec_ret-1".into())));
        assert_eq!(client_in_script("nothing here"), None);
    }

    #[test]
    fn reads_token_answers() {
        assert_eq!(read_token_answer(&json!({"error": "authorization_pending"})), TokenAnswer::Pending);
        assert_eq!(read_token_answer(&json!({"error": "invalid_grant"})), TokenAnswer::Revoked);
        assert_eq!(
            read_token_answer(&json!({"access_token": "a", "refresh_token": "r", "expires_in": 100})),
            TokenAnswer::Tokens { access: "a".into(), refresh: Some("r".into()), seconds: 100 }
        );
    }

    #[test]
    fn keeps_the_credential() {
        let folder = std::env::temp_dir().join(format!("lumtub-tv-{}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        let file = folder.join("youtube-tv.bin");
        let credential = Credential { refresh: "secret".into(), client_id: "id".into(), client_secret: "s".into() };
        store::save(&file, &credential).unwrap();
        assert_eq!(store::load(&file), Some(credential));
        std::fs::remove_dir_all(&folder).unwrap();
    }
}
