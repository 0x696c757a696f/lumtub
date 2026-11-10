//! The proxy in a proxy auto-config (PAC) script, as proxy tools such as
//! Clash, v2rayN and Shadowsocks serve one in their PAC mode. The script is
//! not run: these send every site they proxy to one proxy, named as a
//! `PROXY host:port` or `SOCKS5 host:port` string in the script, and
//! YouTube is always among the proxied sites.

use crate::taste::{give, text};
use std::os::raw::c_char;
use std::time::Duration;

/// The first proxy the script names, as an address the app takes:
/// `http://host:port`, `socks5h://host:port` or `socks4a://host:port`.
pub fn proxy_in(script: &str) -> Option<String> {
    let words: Vec<&str> = script
        .split(|c: char| c.is_whitespace() || matches!(c, '"' | '\'' | ';' | '+' | '(' | ')' | ','))
        .filter(|w| !w.is_empty())
        .collect();
    words.windows(2).find_map(|pair| {
        let scheme = match pair[0] {
            "PROXY" | "HTTP" => "http",
            "SOCKS" | "SOCKS5" => "socks5h",
            "SOCKS4" => "socks4a",
            _ => return None,
        };
        let address = pair[1];
        let (host, port) = address.rsplit_once(':')?;
        let port: u16 = port.parse().ok()?;
        let host_ok = !host.is_empty()
            && host
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '[' | ']' | ':'));
        (host_ok && port > 0).then(|| format!("{scheme}://{host}:{port}"))
    })
}

/// The script at [url]: `file://` read from disk, `http(s)://` fetched
/// directly, as the proxy tool serves it on this PC.
pub fn fetch(url: &str) -> Result<String, String> {
    if let Some(path) = url.strip_prefix("file://") {
        let path = path
            .strip_prefix('/')
            .filter(|p| p.as_bytes().get(1) == Some(&b':'))
            .unwrap_or(path);
        let path = path.replace("%20", " ");
        return std::fs::read_to_string(path).map_err(|e| e.to_string());
    }
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return Err("not an http, https or file address".into());
    }
    let client = reqwest::Client::builder()
        .no_proxy()
        .timeout(Duration::from_secs(5))
        .build()
        .map_err(|e| e.to_string())?;
    crate::http::runtime().block_on(async {
        let response = client.get(url).send().await.map_err(|e| e.to_string())?;
        if !response.status().is_success() {
            return Err(format!("HTTP {}", response.status().as_u16()));
        }
        let body = response.bytes().await.map_err(|e| e.to_string())?;
        if body.len() > 4 << 20 {
            return Err("too large for a PAC script".into());
        }
        Ok(String::from_utf8_lossy(&body).into_owned())
    })
}

/// The proxy of the PAC script at [url] as JSON `{"proxy": "…"}`, with
/// `null` when it names none, or `{"error": "…"}`. Blocks while fetching.
///
/// # Safety
/// [url] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_pac_proxy(url: *const u8, length: usize) -> *mut c_char {
    let url = unsafe { text(url, length) }.trim().to_string();
    let answer = match fetch(&url) {
        Ok(script) => serde_json::json!({ "proxy": proxy_in(&script) }),
        Err(e) => serde_json::json!({ "error": e }),
    };
    give(answer.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_the_proxy_of_common_pac_scripts() {
        let clash = r#"function FindProxyForURL(url, host) { if (isPlainHostName(host)) return "DIRECT"; return "PROXY 127.0.0.1:7890; SOCKS5 127.0.0.1:7890; DIRECT"; }"#;
        assert_eq!(proxy_in(clash).as_deref(), Some("http://127.0.0.1:7890"));
        let shadowsocks = "var proxy = \"SOCKS5 127.0.0.1:1080; SOCKS 127.0.0.1:1080; DIRECT;\";\nvar rules = [\"||youtube.com\"];";
        assert_eq!(
            proxy_in(shadowsocks).as_deref(),
            Some("socks5h://127.0.0.1:1080")
        );
        let joined = "return 'PROXY ' + '10.0.0.2:3128';";
        assert_eq!(proxy_in(joined).as_deref(), Some("http://10.0.0.2:3128"));
        assert_eq!(
            proxy_in("function FindProxyForURL(u, h) { return \"DIRECT\"; }"),
            None
        );
        assert_eq!(
            proxy_in("// PROXY settings below\nreturn \"PROXY proxy.lan:8080\";").as_deref(),
            Some("http://proxy.lan:8080")
        );
    }

    #[test]
    fn reads_a_script_from_a_file() {
        let dir = std::env::temp_dir().join(format!("lumtub-pac-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("proxy.pac");
        std::fs::write(&file, "return \"SOCKS5 127.0.0.1:10808\";").unwrap();
        let script = fetch(&format!("file://{}", file.display())).unwrap();
        assert_eq!(
            proxy_in(&script).as_deref(),
            Some("socks5h://127.0.0.1:10808")
        );
        std::fs::remove_dir_all(dir).unwrap();
    }
}
