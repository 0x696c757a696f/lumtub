//! The redirect rule every client in the core follows: a redirect keeps to
//! the rules the first request was checked against. A reply from a public
//! server cannot send the app to this PC or the user's network, and an
//! https request is not continued over plain http.

use std::net::IpAddr;

use reqwest::Url;

/// Hops followed before a request gives up.
pub(crate) const HOPS: usize = 10;

/// Why a redirect is refused; reqwest names it in the request's error.
#[derive(Debug)]
pub(crate) struct Refused(pub &'static str);

impl std::fmt::Display for Refused {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "redirect refused: {}", self.0)
    }
}

impl std::error::Error for Refused {}

/// The policy for a client: every hop is checked against the first address.
pub(crate) fn policy() -> reqwest::redirect::Policy {
    reqwest::redirect::Policy::custom(|attempt| {
        if attempt.previous().len() >= HOPS {
            return attempt.error(Refused("too many redirects"));
        }
        let Some(first) = attempt.previous().first() else {
            return attempt.follow();
        };
        match check(first, attempt.url()) {
            Ok(()) => attempt.follow(),
            Err(why) => attempt.error(Refused(why)),
        }
    })
}

/// Whether a request that started at [first] may go on to [next].
pub(crate) fn check(first: &Url, next: &Url) -> Result<(), &'static str> {
    if !matches!(next.scheme(), "http" | "https") {
        return Err("not http");
    }
    if first.scheme() == "https" && next.scheme() != "https" {
        return Err("https to http");
    }
    if !next.username().is_empty() || next.password().is_some() {
        return Err("credentials in the address");
    }
    if is_local(next.host_str().unwrap_or_default())
        && !is_local(first.host_str().unwrap_or_default())
    {
        return Err("a public server pointed to a local address");
    }
    Ok(())
}

/// Whether [host] is this PC or on the local network: loopback, private,
/// link-local, unspecified, `localhost` or `.local`, as `isLocalHost` in
/// the app.
pub(crate) fn is_local(host: &str) -> bool {
    let host = host.trim_end_matches('.').to_ascii_lowercase();
    if host.is_empty()
        || host == "localhost"
        || host.ends_with(".localhost")
        || host.ends_with(".local")
    {
        return true;
    }
    let bare = host.trim_start_matches('[').trim_end_matches(']');
    match bare.parse::<IpAddr>() {
        Ok(IpAddr::V4(ip)) => {
            ip.is_loopback() || ip.is_private() || ip.is_link_local() || ip.is_unspecified()
        }
        Ok(IpAddr::V6(ip)) => match ip.to_ipv4_mapped() {
            Some(v4) => is_local(&v4.to_string()),
            None => {
                let first = ip.segments()[0];
                ip.is_loopback()
                    || ip.is_unspecified()
                    || (first & 0xfe00) == 0xfc00
                    || (first & 0xffc0) == 0xfe80
            }
        },
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader, Write};
    use std::net::TcpListener;

    fn url(s: &str) -> Url {
        Url::parse(s).unwrap()
    }

    #[test]
    fn public_hops_are_followed() {
        let first = url("https://www.youtube.com/watch?v=x");
        assert!(check(&first, &url("https://m.youtube.com/watch?v=x")).is_ok());
        assert!(
            check(
                &first,
                &url("https://rr1---sn-x.googlevideo.com/videoplayback")
            )
            .is_ok()
        );
        assert!(check(&url("http://example.com/"), &url("https://example.com/")).is_ok());
    }

    #[test]
    fn https_is_not_downgraded() {
        let first = url("https://piped.example/streams");
        assert_eq!(
            check(&first, &url("http://piped.example/streams")),
            Err("https to http")
        );
        assert!(check(&first, &url("ftp://piped.example/")).is_err());
    }

    #[test]
    fn a_public_server_cannot_point_inside() {
        let first = url("https://piped.example/");
        for inside in [
            "https://127.0.0.1/",
            "https://localhost:8080/",
            "https://router.local/",
            "https://10.0.0.1/",
            "https://172.16.4.2/",
            "https://192.168.1.1/admin",
            "https://169.254.169.254/latest/meta-data",
            "https://0.0.0.0/",
            "https://[::1]/",
            "https://[fd00::1]/",
            "https://[fe80::1]/",
            "https://[::ffff:192.168.1.1]/",
        ] {
            assert!(check(&first, &url(inside)).is_err(), "{inside}");
        }
        assert!(check(&first, &url("https://user:pw@piped.example/")).is_err());
    }

    #[test]
    fn a_local_server_may_stay_local() {
        let first = url("http://192.168.1.20:8080/api");
        assert!(check(&first, &url("http://192.168.1.20:8081/api")).is_ok());
        assert!(check(&first, &url("http://nas.local/api")).is_ok());
        assert!(check(&first, &url("https://pipedapi.example/")).is_ok());
    }

    #[test]
    fn public_addresses_are_not_local() {
        for public in [
            "8.8.8.8",
            "172.32.0.1",
            "[2001:4860::8888]",
            "googlevideo.com",
        ] {
            assert!(!is_local(public), "{public}");
        }
    }

    /// Answers every request with a redirect to [to], or to itself.
    fn redirector(to: Option<String>) -> u16 {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        std::thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut line = String::new();
                while reader.read_line(&mut line).is_ok_and(|n| n > 2) {
                    line.clear();
                }
                let to = to
                    .clone()
                    .unwrap_or_else(|| format!("http://127.0.0.1:{port}/again"));
                let _ = write!(
                    &stream,
                    "HTTP/1.1 302 Found\r\nLocation: {to}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                );
            }
        });
        port
    }

    fn fetch(client: reqwest::Client, url: String) -> Result<reqwest::Response, reqwest::Error> {
        crate::http::runtime().block_on(client.get(url).send())
    }

    #[test]
    fn a_client_refuses_a_hop_inside() {
        let port = redirector(Some("http://127.0.0.1:9/secret".into()));
        // A public name that happens to reach the test server.
        let client = crate::tls::apply(reqwest::Client::builder(), crate::tls::current())
            .resolve("public.test", ([127, 0, 0, 1], port).into())
            .no_proxy()
            .redirect(policy())
            .build()
            .unwrap();
        let error = fetch(client, format!("http://public.test:{port}/")).unwrap_err();
        assert!(error.is_redirect(), "{error:?}");
        let mut text = error.to_string();
        let mut source = std::error::Error::source(&error);
        while let Some(inner) = source {
            text = format!("{text}: {inner}");
            source = inner.source();
        }
        assert!(text.contains("local address"), "{text}");
    }

    #[test]
    fn a_client_stops_after_the_hop_limit() {
        let port = redirector(None);
        let client = crate::tls::apply(reqwest::Client::builder(), crate::tls::current())
            .no_proxy()
            .redirect(policy())
            .build()
            .unwrap();
        let error = fetch(client, format!("http://127.0.0.1:{port}/")).unwrap_err();
        assert!(error.is_redirect(), "{error:?}");
    }
}
