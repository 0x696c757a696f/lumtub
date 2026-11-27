//! What casting reads from devices on the local network: Chromecast
//! messages (length-framed protobuf), mDNS replies, SSDP replies, UPnP
//! device descriptions and SOAP answers. Anything on the network can
//! send these, so they are read here, bounds-checked and fuzzed, and the
//! app gets plain JSON. Sockets, and deciding what to trust, stay in Dart.

use serde::Serialize;
use serde_json::{Map, Value, json};
use std::collections::BTreeMap;
use std::net::{Ipv4Addr, Ipv6Addr};
use std::os::raw::c_char;

use crate::feed::decode;
use crate::taste::{give, text};

/// The largest Chromecast message accepted, as the Cast SDK caps them.
pub const MAX_CAST_MESSAGE: usize = 1 << 20;

#[derive(Debug, Serialize, PartialEq)]
pub struct CastMessage {
    pub source: String,
    pub destination: String,
    pub namespace: String,
    pub payload: String,
}

/// One CastMessage; fields not used are skipped, and the binary payload
/// (field 7) is ignored.
pub fn cast_message(bytes: &[u8]) -> Result<CastMessage, &'static str> {
    let mut i = 0;
    let varint = |i: &mut usize| -> Result<u64, &'static str> {
        let mut value = 0u64;
        let mut shift = 0;
        loop {
            let b = *bytes.get(*i).ok_or("bad varint")?;
            *i += 1;
            if shift > 63 {
                return Err("bad varint");
            }
            value |= u64::from(b & 0x7f) << shift;
            if b & 0x80 == 0 {
                return Ok(value);
            }
            shift += 7;
        }
    };
    let mut strings: BTreeMap<u64, String> = BTreeMap::new();
    while i < bytes.len() {
        let tag = varint(&mut i)?;
        match tag & 7 {
            0 => {
                varint(&mut i)?;
            }
            2 => {
                let length = varint(&mut i)?;
                let length = usize::try_from(length)
                    .ok()
                    .filter(|l| *l <= bytes.len() - i)
                    .ok_or("truncated field")?;
                if tag >> 3 != 7 {
                    strings.insert(
                        tag >> 3,
                        String::from_utf8_lossy(&bytes[i..i + length]).into_owned(),
                    );
                }
                i += length;
            }
            1 => {
                i = i
                    .checked_add(8)
                    .filter(|end| *end <= bytes.len())
                    .ok_or("truncated field")?
            }
            5 => {
                i = i
                    .checked_add(4)
                    .filter(|end| *end <= bytes.len())
                    .ok_or("truncated field")?
            }
            _ => return Err("bad wire type"),
        }
    }
    let mut take = |field| strings.remove(&field).unwrap_or_default();
    Ok(CastMessage {
        source: take(2),
        destination: take(3),
        namespace: take(4),
        payload: take(6),
    })
}

/// The whole messages at the start of [buffer] (each with its 4-byte
/// big-endian length) and how many bytes they took.
pub fn cast_frames(buffer: &[u8]) -> Result<(Vec<CastMessage>, usize), &'static str> {
    let mut messages = Vec::new();
    let mut used = 0;
    while buffer.len() - used >= 4 {
        let length =
            u32::from_be_bytes(buffer[used..used + 4].try_into().unwrap_or_default()) as usize;
        if length > MAX_CAST_MESSAGE {
            return Err("message too long");
        }
        if buffer.len() - used - 4 < length {
            break;
        }
        messages.push(cast_message(&buffer[used + 4..used + 4 + length])?);
        used += 4 + length;
    }
    Ok((messages, used))
}

/// The records of one mDNS packet that discovery uses, as far as the
/// packet could be read: a truncated one gives the records before the cut.
#[derive(Debug, Default, Serialize, PartialEq)]
pub struct MdnsRecords {
    /// (owner, target) of each PTR record.
    pub ptr: Vec<(String, String)>,
    /// (name, target, port) of each SRV record.
    pub srv: Vec<(String, String, u16)>,
    /// (name, entries with keys in lower case) of each TXT record.
    pub txt: Vec<(String, BTreeMap<String, String>)>,
    /// (name, address) of each A and AAAA record.
    pub addresses: Vec<(String, String)>,
}

pub fn mdns_records(packet: &[u8]) -> MdnsRecords {
    let mut records = MdnsRecords::default();
    let _ = read_mdns(packet, &mut records);
    records
}

fn read_mdns(packet: &[u8], out: &mut MdnsRecords) -> Option<()> {
    let u16_at = |at: usize| {
        packet
            .get(at..at + 2)
            .map(|b| u16::from_be_bytes([b[0], b[1]]))
    };
    let questions = u16_at(4)?;
    let count = u32::from(u16_at(6)?) + u32::from(u16_at(8)?) + u32::from(u16_at(10)?);
    let mut offset = 12;
    for _ in 0..questions {
        offset = skip_name(packet, offset)? + 4;
    }
    for _ in 0..count {
        let (name, after) = read_name(packet, offset)?;
        let kind = u16_at(after)?;
        let length = usize::from(u16_at(after + 8)?);
        let start = after + 10;
        let end = start + length;
        let data = packet.get(start..end)?;
        match kind {
            12 => out.ptr.push((name, read_name(packet, start)?.0)),
            33 => {
                let port = u16_at(start + 4)?;
                out.srv
                    .push((name, read_name(packet, start + 6)?.0.to_lowercase(), port));
            }
            16 => out.txt.push((name, txt(data))),
            1 if length == 4 => out.addresses.push((
                name.to_lowercase(),
                Ipv4Addr::new(data[0], data[1], data[2], data[3]).to_string(),
            )),
            28 if length == 16 => {
                let bytes: [u8; 16] = data.try_into().ok()?;
                out.addresses
                    .push((name.to_lowercase(), Ipv6Addr::from(bytes).to_string()));
            }
            _ => {}
        }
        offset = end;
    }
    Some(())
}

fn txt(data: &[u8]) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    let mut i = 0;
    while i < data.len() {
        let length = usize::from(data[i]);
        i += 1;
        let Some(entry) = data.get(i..i + length) else {
            break;
        };
        i += length;
        let entry = String::from_utf8_lossy(entry);
        if let Some((key, value)) = entry.split_once('=').filter(|(key, _)| !key.is_empty()) {
            out.insert(key.to_lowercase(), value.to_string());
        }
    }
    out
}

fn skip_name(packet: &[u8], mut offset: usize) -> Option<usize> {
    loop {
        let length = *packet.get(offset)?;
        if length == 0 {
            return Some(offset + 1);
        }
        if length & 0xc0 == 0xc0 {
            return Some(offset + 2);
        }
        offset += usize::from(length) + 1;
    }
}

/// A possibly compressed name, and the offset after it.
fn read_name(packet: &[u8], mut offset: usize) -> Option<(String, usize)> {
    let mut labels: Vec<String> = Vec::new();
    let mut after = None;
    let mut hops = 0;
    loop {
        let length = *packet.get(offset)?;
        if length == 0 {
            return Some((labels.join("."), after.unwrap_or(offset + 1)));
        }
        if length & 0xc0 == 0xc0 {
            after.get_or_insert(offset + 2);
            offset = (usize::from(length & 0x3f) << 8) | usize::from(*packet.get(offset + 1)?);
            hops += 1;
            if hops > 20 {
                return None;
            }
            continue;
        }
        let label = packet.get(offset + 1..offset + 1 + usize::from(length))?;
        labels.push(String::from_utf8_lossy(label).into_owned());
        offset += usize::from(length) + 1;
    }
}

/// The headers of an SSDP search reply or NOTIFY, names in lower case;
/// None for anything else.
pub fn ssdp(text: &str) -> Option<BTreeMap<String, String>> {
    let mut lines = text.lines();
    let first = lines.next()?;
    if !(first.starts_with("HTTP/1.1 200") || first.starts_with("NOTIFY")) {
        return None;
    }
    Some(
        lines
            .filter_map(|line| line.split_once(':'))
            .filter(|(name, _)| !name.trim().is_empty())
            .map(|(name, value)| (name.trim().to_lowercase(), value.trim().to_string()))
            .collect(),
    )
}

/// The text of the first element [name] in [xml], whatever its namespace
/// prefix, with character references decoded.
pub fn xml_text(xml: &str, name: &str) -> Option<String> {
    element(xml, name).map(|(_, body)| decode(body))
}

/// The first element [name] (prefix ignored): its full tag name and raw
/// content. An empty element `<name/>` has empty content.
fn element<'a>(xml: &'a str, name: &str) -> Option<(&'a str, &'a str)> {
    element_at(xml, name).map(|(full, body, _)| (full, body))
}

/// [element], and where in [xml] its content ends (for a self-closing
/// tag, where the tag ends).
fn element_at<'a>(xml: &'a str, name: &str) -> Option<(&'a str, &'a str, usize)> {
    let mut from = 0;
    while let Some(at) = xml[from..].find('<') {
        let start = from + at + 1;
        from = start;
        let tag = &xml[start..];
        let end_name = tag
            .find(|c: char| c == '>' || c == '/' || c.is_whitespace())
            .unwrap_or(tag.len());
        let full = &tag[..end_name];
        if local(full) != name {
            continue;
        }
        let close = tag.find('>')?;
        if tag[..close].ends_with('/') {
            return Some((full, "", start + close + 1));
        }
        let body = &tag[close + 1..];
        return closing(body, name).map(|end| (full, &body[..end], start + close + 1 + end));
    }
    None
}

fn local(name: &str) -> &str {
    name.rsplit(':').next().unwrap_or(name)
}

/// Where the first `</prefix:name>` or `</name>` in [body] starts.
fn closing(body: &str, name: &str) -> Option<usize> {
    let mut from = 0;
    while let Some(at) = body[from..].find("</") {
        let start = from + at;
        let tag = &body[start + 2..];
        let end = tag.find('>')?;
        if local(tag[..end].trim()) == name {
            return Some(start);
        }
        from = start + 2;
    }
    None
}

/// Every element [name] (prefix ignored), as raw content.
fn elements<'a>(xml: &'a str, name: &str) -> Vec<&'a str> {
    let mut out = Vec::new();
    let mut rest = xml;
    while let Some((_, body, end)) = element_at(rest, name) {
        out.push(body);
        rest = &rest[end..];
        if rest.is_empty() {
            break;
        }
    }
    out
}

/// What a UPnP device description says, as raw (decoded) text: the app
/// resolves and checks the addresses.
pub fn description(xml: &str) -> Value {
    let mut out = Map::new();
    for field in [
        "URLBase",
        "friendlyName",
        "UDN",
        "manufacturer",
        "modelName",
        "modelDescription",
    ] {
        if let Some(value) = xml_text(xml, field) {
            out.insert(field.to_string(), Value::String(value));
        }
    }
    let services: Vec<Value> = elements(xml, "service")
        .into_iter()
        .filter_map(|block| {
            let kind = xml_text(block, "serviceType")?;
            let control = xml_text(block, "controlURL").filter(|c| !c.is_empty())?;
            Some(json!({"type": kind, "control": control}))
        })
        .collect();
    out.insert("services".into(), Value::Array(services));
    Value::Object(out)
}

/// A SOAP answer: `{fault: {code?, description}}`, or `{args: {name:
/// text}}` with the output arguments of its `…Response` element.
pub fn soap(xml: &str) -> Value {
    if xml.contains("Fault>") {
        let description = xml_text(xml, "errorDescription")
            .or_else(|| xml_text(xml, "faultstring"))
            .unwrap_or_default();
        return json!({"fault": {"code": xml_text(xml, "errorCode"), "description": description}});
    }
    let mut args = Map::new();
    let response = {
        let mut from = 0;
        let mut found = None;
        while let Some(at) = xml[from..].find('<') {
            let start = from + at + 1;
            from = start;
            let tag = &xml[start..];
            let end_name = tag
                .find(|c: char| c == '>' || c == '/' || c.is_whitespace())
                .unwrap_or(tag.len());
            let name = local(&tag[..end_name]);
            if name.len() > "Response".len() && name.ends_with("Response") && !tag.starts_with('/')
            {
                found = element(&xml[start - 1..], name).map(|(_, body)| body);
                break;
            }
        }
        found
    };
    if let Some(body) = response {
        let mut rest = body;
        while let Some(at) = rest.find('<') {
            let tag = &rest[at + 1..];
            let end_name = tag
                .find(|c: char| c == '>' || c == '/' || c.is_whitespace())
                .unwrap_or(tag.len());
            let name = &tag[..end_name];
            if name.is_empty() || !name.chars().all(|c| c.is_alphanumeric() || c == '_') {
                rest = tag;
                continue;
            }
            let Some(close) = tag.find('>') else { break };
            if tag[..close].trim_end().ends_with('/') {
                args.insert(name.to_string(), Value::String(String::new()));
                rest = &tag[close + 1..];
                continue;
            }
            let inner = &tag[close + 1..];
            let closer = format!("</{name}>");
            let Some(end) = inner.find(&closer) else {
                rest = inner;
                continue;
            };
            args.insert(name.to_string(), Value::String(decode(&inner[..end])));
            rest = &inner[end + closer.len()..];
        }
    }
    json!({"args": args})
}

unsafe fn bytes<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if ptr.is_null() || len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(ptr, len) }
    }
}

fn answer(value: Value) -> *mut c_char {
    give(value.to_string())
}

/// The whole Chromecast messages at the start of a socket's bytes:
/// `{messages: [{source, destination, namespace, payload}], used}` or
/// `{error}`. Free it with `lumtub_string_free`.
///
/// # Safety
/// [data] must point to [length] bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_cast_frames(data: *const u8, length: usize) -> *mut c_char {
    answer(match cast_frames(unsafe { bytes(data, length) }) {
        Ok((messages, used)) => json!({"messages": messages, "used": used}),
        Err(error) => json!({"error": error}),
    })
}

/// One Chromecast message without its length: `{source, destination,
/// namespace, payload}` or `{error}`.
///
/// # Safety
/// [data] must point to [length] bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_cast_message(data: *const u8, length: usize) -> *mut c_char {
    answer(match cast_message(unsafe { bytes(data, length) }) {
        Ok(message) => serde_json::to_value(message).unwrap_or_default(),
        Err(error) => json!({"error": error}),
    })
}

/// The records of an mDNS packet, see [MdnsRecords].
///
/// # Safety
/// [data] must point to [length] bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_mdns_records(data: *const u8, length: usize) -> *mut c_char {
    answer(serde_json::to_value(mdns_records(unsafe { bytes(data, length) })).unwrap_or_default())
}

/// An SSDP reply's headers, or `null`.
///
/// # Safety
/// [data] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_ssdp(data: *const u8, length: usize) -> *mut c_char {
    answer(serde_json::to_value(ssdp(unsafe { text(data, length) })).unwrap_or_default())
}

/// A UPnP device description, see [description].
///
/// # Safety
/// [data] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_upnp_description(data: *const u8, length: usize) -> *mut c_char {
    answer(description(unsafe { text(data, length) }))
}

/// A SOAP answer, see [soap].
///
/// # Safety
/// [data] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_soap_response(data: *const u8, length: usize) -> *mut c_char {
    answer(soap(unsafe { text(data, length) }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn field(out: &mut Vec<u8>, number: u8, value: &str) {
        out.push((number << 3) | 2);
        let mut length = value.len();
        while length > 0x7f {
            out.push((length as u8 & 0x7f) | 0x80);
            length >>= 7;
        }
        out.push(length as u8);
        out.extend_from_slice(value.as_bytes());
    }

    fn message(payload: &str) -> Vec<u8> {
        let mut out = vec![0x08, 0x00];
        field(&mut out, 2, "sender-0");
        field(&mut out, 3, "receiver-0");
        field(&mut out, 4, "urn:x-cast:com.google.cast.media");
        out.extend_from_slice(&[0x28, 0x00]);
        field(&mut out, 6, payload);
        out
    }

    #[test]
    fn reads_cast_messages_and_frames() {
        let one = message(r#"{"type":"PING"}"#);
        let decoded = cast_message(&one).unwrap();
        assert_eq!(decoded.destination, "receiver-0");
        assert_eq!(decoded.payload, r#"{"type":"PING"}"#);
        let long = "x".repeat(300);
        let two = message(&long);
        let mut stream = Vec::new();
        for m in [&one, &two] {
            stream.extend_from_slice(&(m.len() as u32).to_be_bytes());
            stream.extend_from_slice(m);
        }
        stream.extend_from_slice(&[0, 0, 0, 9, 1]);
        let (messages, used) = cast_frames(&stream).unwrap();
        assert_eq!(messages.len(), 2);
        assert_eq!(messages[1].payload, long);
        assert_eq!(used, stream.len() - 5);
        assert!(cast_frames(&[0xff, 0xff, 0xff, 0xff]).is_err());
    }

    #[test]
    fn refuses_bad_lengths() {
        let negative = [
            0x0a, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0x41,
        ];
        assert!(cast_message(&negative).is_err());
        assert!(cast_message(&[0x0a, 0xff, 0xff, 0xff, 0xff, 0x7f, 0x41]).is_err());
        assert!(cast_message(&[0x09, 1, 2]).is_err());
        assert!(cast_message(&[0x0b]).is_err());
    }

    fn mdns_packet() -> Vec<u8> {
        let mut out = vec![0, 0, 0x84, 0, 0, 0, 0, 4, 0, 0, 0, 0];
        let mut ptr_name = Vec::new();
        for label in ["_googlecast", "_tcp", "local"] {
            ptr_name.push(label.len() as u8);
            ptr_name.extend_from_slice(label.as_bytes());
        }
        ptr_name.push(0);
        out.extend_from_slice(&ptr_name);
        out.extend_from_slice(&[0, 12, 0, 1, 0, 0, 0, 120]);
        let mut ptr_data = vec![14];
        ptr_data.extend_from_slice(b"Chromecast-abc");
        ptr_data.extend_from_slice(&[0xc0, 12]);
        out.extend_from_slice(&[0, ptr_data.len() as u8]);
        out.extend_from_slice(&ptr_data);
        let mut instance = vec![14];
        instance.extend_from_slice(b"Chromecast-abc");
        instance.extend_from_slice(&[0xc0, 12]);
        out.extend_from_slice(&instance);
        let mut target = vec![6];
        target.extend_from_slice(b"abc123");
        target.push(5);
        target.extend_from_slice(b"local");
        target.push(0);
        out.extend_from_slice(&[
            0,
            33,
            0x80,
            1,
            0,
            0,
            0,
            120,
            0,
            6 + target.len() as u8,
            0,
            0,
            0,
            0,
            0x1f,
            0x49,
        ]);
        out.extend_from_slice(&target);
        out.extend_from_slice(&instance);
        let mut txt = Vec::new();
        for entry in ["id=0f1e2d", "FN=Bedroom TV", "novalue"] {
            txt.push(entry.len() as u8);
            txt.extend_from_slice(entry.as_bytes());
        }
        out.extend_from_slice(&[0, 16, 0x80, 1, 0, 0, 0, 120, 0, txt.len() as u8]);
        out.extend_from_slice(&txt);
        out.extend_from_slice(&target);
        out.extend_from_slice(&[0, 1, 0x80, 1, 0, 0, 0, 120, 0, 4, 192, 168, 1, 77]);
        out
    }

    #[test]
    fn reads_mdns_replies() {
        let records = mdns_records(&mdns_packet());
        assert_eq!(
            records.ptr,
            vec![(
                "_googlecast._tcp.local".to_string(),
                "Chromecast-abc._googlecast._tcp.local".to_string()
            )]
        );
        assert_eq!(
            records.srv,
            vec![(
                "Chromecast-abc._googlecast._tcp.local".to_string(),
                "abc123.local".to_string(),
                8009
            )]
        );
        assert_eq!(
            records.txt[0].1.get("fn").map(String::as_str),
            Some("Bedroom TV")
        );
        assert_eq!(records.txt[0].1.len(), 2);
        assert_eq!(
            records.addresses,
            vec![("abc123.local".to_string(), "192.168.1.77".to_string())]
        );
        let packet = mdns_packet();
        let cut = mdns_records(&packet[..packet.len() - 20]);
        assert!(cut.addresses.is_empty());
        assert_eq!(cut.ptr.len(), 1);
        assert_eq!(mdns_records(&[1, 2, 3]), MdnsRecords::default());
        // A name pointing at itself.
        let mut looping = vec![0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0xc0, 12];
        looping.extend_from_slice(&[0, 12, 0, 1, 0, 0, 0, 0, 0, 0]);
        assert_eq!(mdns_records(&looping), MdnsRecords::default());
    }

    #[test]
    fn reads_ssdp_and_descriptions() {
        let headers = ssdp(
            "HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.20:8080/desc.xml\r\nST: urn:x\r\n\r\n",
        )
        .unwrap();
        assert_eq!(headers["location"], "http://192.168.1.20:8080/desc.xml");
        assert!(ssdp("HTTP/1.1 500 Error\r\n").is_none());
        let xml = r#"<root><URLBase>http://192.168.1.20:8080/</URLBase><device><friendlyName>Living Room &amp; TV</friendlyName><UDN>uuid:1</UDN>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>/upnp/control</controlURL></service>
<service><serviceType>x</serviceType><controlURL></controlURL></service>
<s:service><s:serviceType>urn:y</s:serviceType><s:controlURL>_urn:y</s:controlURL></s:service></serviceList></device></root>"#;
        let d = description(xml);
        assert_eq!(d["friendlyName"], "Living Room & TV");
        assert_eq!(d["URLBase"], "http://192.168.1.20:8080/");
        assert_eq!(
            d["services"],
            json!([{"type": "urn:schemas-upnp-org:service:AVTransport:1", "control": "/upnp/control"}, {"type": "urn:y", "control": "_urn:y"}])
        );
        assert_eq!(description("")["services"], json!([]));
    }

    #[test]
    fn reads_soap_answers() {
        let ok = r#"<?xml version="1.0"?><s:Envelope xmlns:s="x"><s:Body><u:GetPositionInfoResponse xmlns:u="y"><Track>1</Track><TrackDuration>0:03:25</TrackDuration><TrackMetaData>&lt;DIDL-Lite&gt;&lt;/DIDL-Lite&gt;</TrackMetaData><RelTime>0:01:02</RelTime><AbsTime/></u:GetPositionInfoResponse></s:Body></s:Envelope>"#;
        let args = &soap(ok)["args"];
        assert_eq!(args["RelTime"], "0:01:02");
        assert_eq!(args["TrackMetaData"], "<DIDL-Lite></DIDL-Lite>");
        assert_eq!(args["AbsTime"], "");
        let fault = r#"<s:Envelope><s:Body><s:Fault><faultstring>UPnPError</faultstring><detail><UPnPError><errorCode>701</errorCode><errorDescription>Transition not available</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>"#;
        assert_eq!(
            soap(fault)["fault"],
            json!({"code": "701", "description": "Transition not available"})
        );
        assert_eq!(soap("<x>")["args"], json!({}));
    }

    #[test]
    fn self_closing_service_in_a_list_is_skipped() {
        // Found by fuzzing: a self-closing <service/> before more text.
        let text = "r<\u{1}\0\0\0\0\0\0\n<<<<<<<service//////></<<<r<r<FFFF<<9<<<\0<%\0<<<\0<%\0\u{2}0</\0<";
        let _ = description(text);
        let _ = soap(text);
        assert_eq!(
            elements("<a><service/>x<service>y</service></a>", "service"),
            vec!["", "y"]
        );
    }

    #[test]
    fn random_input_never_panics() {
        let mut seed: u64 = 0x2545_f491_4f6c_dd1d;
        let mut next = || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        let pieces: [&[u8]; 8] = [
            b"<",
            b">",
            b"</",
            b"Response>",
            b"service",
            b"&#x",
            b";",
            b"\xC0\x0C",
        ];
        for _ in 0..20_000 {
            let mut data = Vec::new();
            for _ in 0..(next() % 40) {
                if next() % 3 == 0 {
                    data.extend_from_slice(pieces[(next() % 8) as usize]);
                } else {
                    data.push(next() as u8);
                }
            }
            let _ = cast_frames(&data);
            let _ = mdns_records(&data);
            let text = String::from_utf8_lossy(&data);
            let _ = ssdp(&text);
            let _ = description(&text);
            let _ = soap(&text);
            let _ = crate::feed::parse(&text);
        }
    }
}
