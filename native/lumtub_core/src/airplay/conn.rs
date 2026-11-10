//! One connection to an AirPlay receiver: HTTP and RTSP requests on the
//! same socket, plain until pairing is verified and encrypted after.

use super::crypto::Framing;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct Response {
    pub code: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl Response {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }
}

pub struct Conn {
    stream: TcpStream,
    framing: Option<Framing>,
    /// Plain bytes received and not yet taken.
    buffer: Vec<u8>,
}

const MAX_HEAD: usize = 64 << 10;
const MAX_BODY: usize = 1 << 20;

/// Where a message's head ends and how long its body is. `None` until the
/// head is complete; an error when the head or body would be unreasonably big.
pub fn message_end(data: &[u8]) -> Result<Option<(usize, usize)>, String> {
    let Some(end) = data.windows(4).position(|w| w == b"\r\n\r\n") else {
        if data.len() > MAX_HEAD {
            return Err("the message head is too long".into());
        }
        return Ok(None);
    };
    let head = end + 4;
    if head > MAX_HEAD {
        return Err("the message head is too long".into());
    }
    let text = String::from_utf8_lossy(&data[..head]);
    let length: usize = text
        .lines()
        .find_map(|l| {
            l.split_once(':')
                .filter(|(k, _)| k.trim().eq_ignore_ascii_case("content-length"))
                .and_then(|(_, v)| v.trim().parse().ok())
        })
        .unwrap_or(0);
    if length > MAX_BODY {
        return Err("the message body is too long".into());
    }
    head.checked_add(length)
        .ok_or_else(|| "the message is too long".to_string())?;
    Ok(Some((head, length)))
}

/// The first line and the headers of a message head.
pub fn parse_head(head: &[u8]) -> (String, Vec<(String, String)>) {
    let text = String::from_utf8_lossy(head);
    let mut lines = text.split("\r\n");
    let first = lines.next().unwrap_or("").to_string();
    let headers = lines
        .filter_map(|l| l.split_once(':'))
        .map(|(k, v)| (k.trim().to_string(), v.trim().to_string()))
        .collect();
    (first, headers)
}

impl Conn {
    pub fn open(address: SocketAddr) -> std::io::Result<Conn> {
        let stream = TcpStream::connect_timeout(&address, Duration::from_secs(5))?;
        stream.set_read_timeout(Some(Duration::from_secs(10)))?;
        stream.set_write_timeout(Some(Duration::from_secs(10)))?;
        let _ = stream.set_nodelay(true);
        Ok(Conn {
            stream,
            framing: None,
            buffer: Vec::new(),
        })
    }

    pub fn local_ip(&self) -> String {
        self.stream
            .local_addr()
            .map(|a| a.ip().to_string())
            .unwrap_or_default()
    }

    pub fn peer(&self) -> Option<SocketAddr> {
        self.stream.peer_addr().ok()
    }

    pub fn encrypt(&mut self, write: &[u8; 32], read: &[u8; 32]) {
        self.framing = Some(Framing::new(write, read));
    }

    /// Sends a request and reads its answer. `protocol` is `HTTP/1.1` or
    /// `RTSP/1.0`.
    pub fn request(
        &mut self,
        method: &str,
        uri: &str,
        protocol: &str,
        headers: &[(&str, String)],
        body: &[u8],
    ) -> Result<Response, String> {
        let mut out = format!("{method} {uri} {protocol}\r\n");
        for (k, v) in headers {
            out.push_str(&format!("{k}: {v}\r\n"));
        }
        if !body.is_empty() {
            out.push_str(&format!("Content-Length: {}\r\n", body.len()));
        }
        out.push_str("\r\n");
        let mut bytes = out.into_bytes();
        bytes.extend_from_slice(body);
        if let Some(f) = self.framing.as_mut() {
            bytes = f.encrypt(&bytes);
        }
        self.stream
            .write_all(&bytes)
            .map_err(|e| format!("could not send {method} {uri}: {e}"))?;
        self.answer()
            .map_err(|e| format!("no answer to {method} {uri}: {e}"))
    }

    fn answer(&mut self) -> Result<Response, String> {
        let mut chunk = [0u8; 16 << 10];
        loop {
            if let Some((head, length)) = message_end(&self.buffer)?
                && self.buffer.len() >= head + length
            {
                let (first, headers) = parse_head(&self.buffer[..head - 4]);
                let body = self.buffer[head..head + length].to_vec();
                self.buffer.drain(..head + length);
                let code = first
                    .split_whitespace()
                    .nth(1)
                    .and_then(|c| c.parse().ok())
                    .ok_or_else(|| format!("bad answer: {first}"))?;
                return Ok(Response {
                    code,
                    headers,
                    body,
                });
            }
            let n = match self.stream.read(&mut chunk) {
                Ok(n) => n,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(e.to_string()),
            };
            if n == 0 {
                return Err("the device closed the connection".into());
            }
            match self.framing.as_mut() {
                Some(f) => self
                    .buffer
                    .extend(f.decrypt(&chunk[..n]).ok_or("an answer did not decrypt")?),
                None => self.buffer.extend_from_slice(&chunk[..n]),
            }
        }
    }

    pub fn shutdown(&self) {
        let _ = self.stream.shutdown(std::net::Shutdown::Both);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn message_end_reads_length() {
        let m = b"RTSP/1.0 200 OK\r\nContent-Length: 5\r\n\r\nhello";
        assert_eq!(message_end(m).unwrap(), Some((m.len() - 5, 5)));
        assert_eq!(message_end(b"RTSP/1.0 200 OK\r\nCont").unwrap(), None);
    }

    #[test]
    fn message_end_rejects_huge_length() {
        let m = b"HTTP/1.1 200 OK\r\nContent-Length: 18446744073709551615\r\n\r\n";
        assert!(message_end(m).is_err());
        let m = b"HTTP/1.1 200 OK\r\nContent-Length: 99999999\r\n\r\n";
        assert!(message_end(m).is_err());
    }

    #[test]
    fn message_end_rejects_endless_head() {
        assert!(message_end(&vec![b'a'; MAX_HEAD + 1]).is_err());
    }
}
