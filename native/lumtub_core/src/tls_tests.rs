use super::*;
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use rustls::{ClientConnection, ServerConfig, ServerConnection, StreamOwned};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};

fn offered(quantum: Quantum) -> Vec<NamedGroup> {
    groups(quantum).iter().map(|g| g.name()).collect()
}

#[test]
fn prefer_offers_the_hybrid_first_then_classic_groups() {
    let groups = offered(Quantum::Prefer);
    assert_eq!(groups[0], NamedGroup::X25519MLKEM768);
    assert!(groups.contains(&NamedGroup::X25519));
    assert!(groups.contains(&NamedGroup::secp256r1));
    assert_eq!(versions(Quantum::Prefer).len(), 2);
}

#[test]
fn off_offers_no_hybrid() {
    let groups = offered(Quantum::Off);
    assert!(!groups.is_empty());
    assert!(groups.iter().all(|g| !hybrid(*g)));
    assert_eq!(groups[0], NamedGroup::X25519);
}

#[test]
fn require_offers_only_hybrids_over_tls_13() {
    let groups = offered(Quantum::Require);
    assert!(!groups.is_empty());
    assert!(groups.iter().all(|g| hybrid(*g)));
    let versions = versions(Quantum::Require);
    assert_eq!(versions.len(), 1);
    assert_eq!(versions[0].version, rustls::ProtocolVersion::TLSv1_3);
}

#[test]
fn every_setting_builds() {
    for roots in [Roots::System, Roots::Mozilla, Roots::Google] {
        for quantum in [Quantum::Prefer, Quantum::Off, Quantum::Require] {
            let tls = Tls { roots, quantum };
            config(tls).unwrap();
            apply(reqwest::Client::builder(), tls).build().unwrap();
        }
    }
}

#[test]
fn reads_the_setting() {
    for (json, quantum) in [
        (r#""prefer""#, Quantum::Prefer),
        (r#""off""#, Quantum::Off),
        (r#""require""#, Quantum::Require),
    ] {
        assert_eq!(serde_json::from_str::<Quantum>(json).unwrap(), quantum);
    }
}

#[test]
fn notes_each_host_once_with_its_latest_group() {
    let a = ServerName::try_from("a.example").unwrap();
    let b = ServerName::try_from("b.example").unwrap();
    let store = Noting(ClientSessionMemoryCache::new(4));
    store.set_kx_hint(a.clone(), NamedGroup::X25519);
    store.set_kx_hint(b, NamedGroup::X25519MLKEM768);
    store.set_kx_hint(a, NamedGroup::X25519MLKEM768);
    let seen: Vec<Seen> = seen()
        .into_iter()
        .filter(|s| s.host.ends_with(".example"))
        .collect();
    assert_eq!(seen.len(), 2);
    assert!(
        seen.iter()
            .all(|s| s.group == "X25519MLKEM768" && s.quantum)
    );
}

/// Tests that read what "localhost" agreed on take turns.
static LOCALHOST: Mutex<()> = Mutex::new(());

fn test_roots() -> Arc<rustls::RootCertStore> {
    let mut store = rustls::RootCertStore::empty();
    store.add_parsable_certificates(
        CertificateDer::pem_slice_iter(include_bytes!("../testdata/ca.pem")).flatten(),
    );
    Arc::new(store)
}

/// A local HTTPS server for "localhost" knowing only [groups] and
/// [versions]; answers every request with "ok".
fn server(
    groups: Vec<&'static dyn SupportedKxGroup>,
    versions: &'static [&'static SupportedProtocolVersion],
) -> std::net::SocketAddr {
    let certs: Vec<CertificateDer<'static>> =
        CertificateDer::pem_slice_iter(include_bytes!("../testdata/server.pem"))
            .flatten()
            .collect();
    let key = PrivateKeyDer::from_pem_slice(include_bytes!("../testdata/server.key")).unwrap();
    let provider = CryptoProvider {
        kx_groups: groups,
        ..aws_lc_rs::default_provider()
    };
    let mut config = ServerConfig::builder_with_provider(Arc::new(provider))
        .with_protocol_versions(versions)
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .unwrap();
    config.alpn_protocols = vec![b"http/1.1".to_vec()];
    let config = Arc::new(config);
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    std::thread::spawn(move || {
        for socket in listener.incoming().flatten() {
            let config = config.clone();
            std::thread::spawn(move || {
                let Ok(connection) = ServerConnection::new(config) else {
                    return;
                };
                let mut stream = StreamOwned::new(connection, socket);
                let mut asked = Vec::new();
                let mut buffer = [0u8; 1024];
                while !asked.windows(4).any(|w| w == b"\r\n\r\n") {
                    match stream.read(&mut buffer) {
                        Ok(0) | Err(_) => return,
                        Ok(n) => asked.extend_from_slice(&buffer[..n]),
                    }
                }
                let _ = stream.write_all(
                    b"HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: close\r\n\r\nok",
                );
                stream.conn.send_close_notify();
                let _ = stream.flush();
            });
        }
    });
    address
}

/// The group and version a handshake with [config] agreed on.
fn handshake(
    config: ClientConfig,
    host: &str,
    address: impl std::net::ToSocketAddrs,
) -> Result<(String, rustls::ProtocolVersion), String> {
    let server = ServerName::try_from(host.to_string()).map_err(|e| e.to_string())?;
    let mut connection =
        ClientConnection::new(Arc::new(config), server).map_err(|e| e.to_string())?;
    let mut socket = TcpStream::connect(address).map_err(|e| e.to_string())?;
    socket
        .set_read_timeout(Some(std::time::Duration::from_secs(15)))
        .map_err(|e| e.to_string())?;
    while connection.is_handshaking() {
        connection
            .complete_io(&mut socket)
            .map_err(|e| e.to_string())?;
    }
    let version = connection.protocol_version().ok_or("no version")?;
    let group = match connection.negotiated_key_exchange_group() {
        Some(group) => name(group.name()),
        None => "none".into(),
    };
    Ok((group, version))
}

fn local(quantum: Quantum) -> ClientConfig {
    config_trusting(quantum, Some(test_roots())).unwrap()
}

#[test]
fn a_server_with_the_hybrid_agrees_on_it() {
    let address = server(aws_lc_rs::DEFAULT_KX_GROUPS.to_vec(), TLS13_AND_12);
    let (group, version) = handshake(local(Quantum::Prefer), "localhost", address).unwrap();
    assert_eq!(group, "X25519MLKEM768");
    assert_eq!(version, rustls::ProtocolVersion::TLSv1_3);
    let (group, _) = handshake(local(Quantum::Require), "localhost", address).unwrap();
    assert_eq!(group, "X25519MLKEM768");
    let (group, _) = handshake(local(Quantum::Off), "localhost", address).unwrap();
    assert_eq!(group, "X25519");
}

#[test]
fn a_classic_only_server_is_reached_except_when_the_hybrid_is_required() {
    let address = server(vec![aws_lc_rs::kx_group::X25519], TLS13_AND_12);
    let (group, version) = handshake(local(Quantum::Prefer), "localhost", address).unwrap();
    assert_eq!(group, "X25519");
    assert_eq!(version, rustls::ProtocolVersion::TLSv1_3);
    assert!(handshake(local(Quantum::Require), "localhost", address).is_err());

    let p256 = server(vec![aws_lc_rs::kx_group::SECP256R1], TLS13_AND_12);
    let (group, _) = handshake(local(Quantum::Prefer), "localhost", p256).unwrap();
    assert_eq!(group, "P-256");
}

#[test]
fn a_tls_12_server_is_reached_except_when_the_hybrid_is_required() {
    static TLS12_ONLY: &[&SupportedProtocolVersion] = &[&rustls::version::TLS12];
    let address = server(aws_lc_rs::DEFAULT_KX_GROUPS.to_vec(), TLS12_ONLY);
    let (_, version) = handshake(local(Quantum::Prefer), "localhost", address).unwrap();
    assert_eq!(version, rustls::ProtocolVersion::TLSv1_2);
    assert!(handshake(local(Quantum::Require), "localhost", address).is_err());
}

#[test]
fn an_unknown_authority_is_refused_in_every_setting() {
    let address = server(aws_lc_rs::DEFAULT_KX_GROUPS.to_vec(), TLS13_AND_12);
    for roots in [Roots::Mozilla, Roots::Google] {
        for quantum in [Quantum::Prefer, Quantum::Off, Quantum::Require] {
            let config = config(Tls { roots, quantum }).unwrap();
            assert!(handshake(config, "localhost", address).is_err());
        }
    }
}

/// A local HTTP proxy answering CONNECT, or a SOCKS5 one; returns its
/// address.
fn proxy(socks: bool) -> std::net::SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    std::thread::spawn(move || {
        for mut client in listener.incoming().flatten() {
            std::thread::spawn(move || {
                let target = if socks {
                    let mut hello = [0u8; 3];
                    client.read_exact(&mut hello).ok()?;
                    client.write_all(&[5, 0]).ok()?;
                    let mut head = [0u8; 4];
                    client.read_exact(&mut head).ok()?;
                    let host = match head[3] {
                        1 => {
                            let mut ip = [0u8; 4];
                            client.read_exact(&mut ip).ok()?;
                            std::net::Ipv4Addr::from(ip).to_string()
                        }
                        3 => {
                            let mut length = [0u8; 1];
                            client.read_exact(&mut length).ok()?;
                            let mut name = vec![0u8; length[0] as usize];
                            client.read_exact(&mut name).ok()?;
                            String::from_utf8(name).ok()?
                        }
                        _ => return None,
                    };
                    let mut port = [0u8; 2];
                    client.read_exact(&mut port).ok()?;
                    client.write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0]).ok()?;
                    format!("{host}:{}", u16::from_be_bytes(port))
                } else {
                    let mut asked = Vec::new();
                    let mut byte = [0u8; 1];
                    while !asked.ends_with(b"\r\n\r\n") {
                        client.read_exact(&mut byte).ok()?;
                        asked.push(byte[0]);
                    }
                    let line = String::from_utf8(asked).ok()?;
                    let target = line.split_whitespace().nth(1)?.to_string();
                    client
                        .write_all(b"HTTP/1.1 200 Connection established\r\n\r\n")
                        .ok()?;
                    target
                };
                let target = target.replace("localhost", "127.0.0.1");
                let server = TcpStream::connect(target).ok()?;
                let (mut a, mut b) = (client.try_clone().ok()?, server.try_clone().ok()?);
                let up = std::thread::spawn(move || std::io::copy(&mut a, &mut b));
                let mut server = server;
                let _ = std::io::copy(&mut server, &mut client);
                let _ = up.join();
                Some(())
            });
        }
    });
    address
}

async fn fetch(client: reqwest::Client, url: &str) -> Result<String, String> {
    let answer = client.get(url).send().await.map_err(|e| e.to_string())?;
    answer.text().await.map_err(|e| e.to_string())
}

fn client(proxy: Option<String>) -> reqwest::Client {
    let builder = reqwest::Client::builder().timeout(std::time::Duration::from_secs(20));
    let builder = match proxy {
        Some(p) => builder.proxy(reqwest::Proxy::all(p).unwrap()),
        None => builder.no_proxy(),
    };
    builder
        .tls_backend_preconfigured(local(Quantum::Prefer))
        .build()
        .unwrap()
}

#[test]
fn direct_http_and_socks5_connections_agree_on_the_hybrid() {
    let _turn = LOCALHOST.lock().unwrap_or_else(|e| e.into_inner());
    let server = server(aws_lc_rs::DEFAULT_KX_GROUPS.to_vec(), TLS13_AND_12);
    let url = format!("https://localhost:{}/", server.port());
    let routes = [
        None,
        Some(format!("http://{}", proxy(false))),
        Some(format!("socks5h://{}", proxy(true))),
    ];
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for route in routes {
        SEEN.lock().unwrap().remove("localhost");
        let body = runtime
            .block_on(fetch(client(route.clone()), &url))
            .unwrap_or_else(|e| panic!("{route:?}: {e}"));
        assert_eq!(body, "ok", "{route:?}");
        let seen = seen().into_iter().find(|s| s.host == "localhost");
        assert_eq!(
            seen.map(|s| s.group).as_deref(),
            Some("X25519MLKEM768"),
            "{route:?}"
        );
    }
}

/// Live checks against real servers, run by CI (`--ignored`): Cloudflare
/// must agree on the hybrid in every certificate setting; YouTube's hosts
/// are only reported.
#[test]
#[ignore]
fn live_cloudflare_agrees_on_the_hybrid() {
    for roots in [Roots::System, Roots::Mozilla, Roots::Google] {
        for quantum in [Quantum::Prefer, Quantum::Require] {
            let config = config(Tls { roots, quantum }).unwrap();
            let (group, version) = handshake(config, "cloudflare.com", "cloudflare.com:443")
                .unwrap_or_else(|e| panic!("{roots:?} {quantum:?}: {e}"));
            println!("cloudflare.com {roots:?} {quantum:?}: {group} {version:?}");
            assert_eq!(group, "X25519MLKEM768", "{roots:?} {quantum:?}");
            assert_eq!(version, rustls::ProtocolVersion::TLSv1_3);
        }
    }
    let config = config(Tls {
        roots: Roots::System,
        quantum: Quantum::Off,
    })
    .unwrap();
    let (group, _) = handshake(config, "cloudflare.com", "cloudflare.com:443").unwrap();
    assert_eq!(group, "X25519");
}

#[test]
#[ignore]
fn live_requests_note_what_each_host_agreed_on() {
    let tls = Tls {
        roots: Roots::System,
        quantum: Quantum::Prefer,
    };
    let client = apply(
        reqwest::Client::builder().timeout(std::time::Duration::from_secs(20)),
        tls,
    )
    .build()
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let trace = runtime
        .block_on(fetch(
            client.clone(),
            "https://cloudflare.com/cdn-cgi/trace",
        ))
        .unwrap();
    println!("{trace}");
    let cloudflare = seen().into_iter().find(|s| s.host == "cloudflare.com");
    assert_eq!(
        cloudflare.map(|s| s.group).as_deref(),
        Some("X25519MLKEM768")
    );
    for url in [
        "https://www.youtube.com/generate_204",
        "https://youtubei.googleapis.com/generate_204",
        "https://redirector.googlevideo.com/generate_204",
        "https://i.ytimg.com/generate_204",
    ] {
        let answer = runtime.block_on(fetch(client.clone(), url));
        println!(
            "{url}: {}",
            answer.map_or_else(|e| e, |_| "answered".into())
        );
    }
    for host in seen() {
        println!("{} agreed on {}", host.host, host.group);
    }
    for host in [
        "www.youtube.com",
        "youtubei.googleapis.com",
        "redirector.googlevideo.com",
    ] {
        let required = config(Tls {
            roots: Roots::System,
            quantum: Quantum::Require,
        })
        .unwrap();
        println!(
            "{host} with the hybrid required: {:?}",
            handshake(required, host, (host, 443))
        );
    }
}
