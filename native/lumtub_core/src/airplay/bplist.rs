//! Binary property lists (`bplist00`), which AirPlay bodies are written in:
//! enough of the format to write requests and read answers.

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Bool(bool),
    Int(i64),
    Real(f64),
    String(String),
    Data(Vec<u8>),
    Array(Vec<Value>),
    Dict(Vec<(String, Value)>),
}

impl Value {
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Dict(entries) => entries.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn number(&self) -> Option<f64> {
        match self {
            Value::Int(i) => Some(*i as f64),
            Value::Real(r) => Some(*r),
            Value::Bool(b) => Some(*b as u8 as f64),
            _ => None,
        }
    }
}

pub fn dict(entries: Vec<(&str, Value)>) -> Value {
    Value::Dict(
        entries
            .into_iter()
            .map(|(k, v)| (k.to_string(), v))
            .collect(),
    )
}

// ---- writing ----

fn flatten(value: &Value, objects: &mut Vec<Vec<u8>>, width: usize) -> u64 {
    let index = objects.len();
    objects.push(Vec::new());
    let mut out = Vec::new();
    let refs = |ids: &[u64], out: &mut Vec<u8>| {
        for id in ids {
            out.extend_from_slice(&id.to_be_bytes()[8 - width..]);
        }
    };
    match value {
        Value::Bool(b) => out.push(if *b { 0x09 } else { 0x08 }),
        Value::Int(i) => {
            out.push(0x13);
            out.extend_from_slice(&i.to_be_bytes());
        }
        Value::Real(r) => {
            out.push(0x23);
            out.extend_from_slice(&r.to_be_bytes());
        }
        Value::String(s) if s.is_ascii() => {
            marker(&mut out, 0x5, s.len());
            out.extend_from_slice(s.as_bytes());
        }
        Value::String(s) => {
            let units: Vec<u16> = s.encode_utf16().collect();
            marker(&mut out, 0x6, units.len());
            for u in units {
                out.extend_from_slice(&u.to_be_bytes());
            }
        }
        Value::Data(d) => {
            marker(&mut out, 0x4, d.len());
            out.extend_from_slice(d);
        }
        Value::Array(items) => {
            let ids: Vec<u64> = items.iter().map(|v| flatten(v, objects, width)).collect();
            marker(&mut out, 0xA, ids.len());
            refs(&ids, &mut out);
        }
        Value::Dict(entries) => {
            let keys: Vec<u64> = entries
                .iter()
                .map(|(k, _)| flatten(&Value::String(k.clone()), objects, width))
                .collect();
            let values: Vec<u64> = entries
                .iter()
                .map(|(_, v)| flatten(v, objects, width))
                .collect();
            marker(&mut out, 0xD, keys.len());
            refs(&keys, &mut out);
            refs(&values, &mut out);
        }
    }
    objects[index] = out;
    index as u64
}

fn marker(out: &mut Vec<u8>, kind: u8, count: usize) {
    if count < 15 {
        out.push(kind << 4 | count as u8);
    } else {
        out.push(kind << 4 | 0xF);
        out.push(0x13);
        out.extend_from_slice(&(count as u64).to_be_bytes());
    }
}

fn count(value: &Value) -> usize {
    1 + match value {
        Value::Array(items) => items.iter().map(count).sum(),
        Value::Dict(entries) => entries.iter().map(|(_, v)| 1 + count(v)).sum(),
        _ => 0,
    }
}

pub fn write(value: &Value) -> Vec<u8> {
    let total = count(value);
    let width = if total < 256 {
        1
    } else if total < 65536 {
        2
    } else {
        4
    };
    let mut objects = Vec::new();
    flatten(value, &mut objects, width);
    let mut out = b"bplist00".to_vec();
    let mut offsets = Vec::with_capacity(objects.len());
    for o in &objects {
        offsets.push(out.len() as u64);
        out.extend_from_slice(o);
    }
    let table = out.len() as u64;
    let offset_width = if table < 256 {
        1
    } else if table < 65536 {
        2
    } else if table < 1 << 32 {
        4
    } else {
        8
    };
    for o in offsets {
        out.extend_from_slice(&o.to_be_bytes()[8 - offset_width..]);
    }
    out.extend_from_slice(&[0; 6]);
    out.push(offset_width as u8);
    out.push(width as u8);
    out.extend_from_slice(&(objects.len() as u64).to_be_bytes());
    out.extend_from_slice(&0u64.to_be_bytes());
    out.extend_from_slice(&table.to_be_bytes());
    out
}

// ---- reading ----

struct Reader<'a> {
    data: &'a [u8],
    offsets: Vec<usize>,
    width: usize,
}

fn uint(b: &[u8]) -> u64 {
    b.iter().fold(0, |n, &x| n << 8 | x as u64)
}

impl Reader<'_> {
    fn length(&self, at: usize, low: u8) -> Option<(usize, usize)> {
        if low != 0xF {
            return Some((low as usize, at + 1));
        }
        let size = 1usize << (self.data.get(at + 1)? & 0xF);
        Some((
            uint(self.data.get(at + 2..at + 2 + size)?) as usize,
            at + 2 + size,
        ))
    }

    fn refs(&self, at: usize, n: usize) -> Option<Vec<usize>> {
        (0..n)
            .map(|i| {
                self.data
                    .get(at + i * self.width..at + (i + 1) * self.width)
                    .map(|b| uint(b) as usize)
            })
            .collect()
    }

    fn object(&self, id: usize, depth: u8) -> Option<Value> {
        if depth > 32 {
            return None;
        }
        let at = *self.offsets.get(id)?;
        let byte = *self.data.get(at)?;
        let (kind, low) = (byte >> 4, byte & 0xF);
        Some(match kind {
            0x0 => match low {
                0x8 => Value::Bool(false),
                0x9 => Value::Bool(true),
                _ => Value::Int(0),
            },
            0x1 => {
                let size = 1usize << low;
                let b = self.data.get(at + 1..at + 1 + size)?;
                Value::Int(if size == 8 {
                    i64::from_be_bytes(b.try_into().ok()?)
                } else {
                    uint(b) as i64
                })
            }
            0x2 => match low {
                2 => Value::Real(
                    f32::from_be_bytes(self.data.get(at + 1..at + 5)?.try_into().ok()?) as f64,
                ),
                _ => Value::Real(f64::from_be_bytes(
                    self.data.get(at + 1..at + 9)?.try_into().ok()?,
                )),
            },
            0x3 => Value::Real(f64::from_be_bytes(
                self.data.get(at + 1..at + 9)?.try_into().ok()?,
            )),
            0x4 => {
                let (n, from) = self.length(at, low)?;
                Value::Data(self.data.get(from..from + n)?.to_vec())
            }
            0x5 => {
                let (n, from) = self.length(at, low)?;
                Value::String(String::from_utf8_lossy(self.data.get(from..from + n)?).into_owned())
            }
            0x6 => {
                let (n, from) = self.length(at, low)?;
                let units: Vec<u16> = self
                    .data
                    .get(from..from + n * 2)?
                    .chunks(2)
                    .map(|c| u16::from_be_bytes([c[0], c[1]]))
                    .collect();
                Value::String(String::from_utf16_lossy(&units))
            }
            0x8 => Value::Int(uint(self.data.get(at + 1..at + 2 + low as usize)?) as i64),
            0xA | 0xC => {
                let (n, from) = self.length(at, low)?;
                Value::Array(
                    self.refs(from, n)?
                        .into_iter()
                        .map(|r| self.object(r, depth + 1))
                        .collect::<Option<_>>()?,
                )
            }
            0xD => {
                let (n, from) = self.length(at, low)?;
                let keys = self.refs(from, n)?;
                let values = self.refs(from + n * self.width, n)?;
                let mut entries = Vec::with_capacity(n);
                for (k, v) in keys.into_iter().zip(values) {
                    let Value::String(key) = self.object(k, depth + 1)? else {
                        return None;
                    };
                    entries.push((key, self.object(v, depth + 1)?));
                }
                Value::Dict(entries)
            }
            _ => return None,
        })
    }
}

pub fn read(data: &[u8]) -> Option<Value> {
    if !data.starts_with(b"bplist00") || data.len() < 40 {
        return None;
    }
    let trailer = &data[data.len() - 32..];
    let offset_width = trailer[6] as usize;
    let width = trailer[7] as usize;
    let objects = uint(&trailer[8..16]) as usize;
    let top = uint(&trailer[16..24]) as usize;
    let table = uint(&trailer[24..32]) as usize;
    if offset_width == 0 || width == 0 || objects > data.len() {
        return None;
    }
    let offsets = (0..objects)
        .map(|i| {
            data.get(table + i * offset_width..table + (i + 1) * offset_width)
                .map(|b| uint(b) as usize)
        })
        .collect::<Option<Vec<_>>>()?;
    Reader {
        data,
        offsets,
        width,
    }
    .object(top, 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_what_it_reads() {
        let value = dict(vec![
            (
                "Content-Location",
                Value::String("http://192.168.1.2:4000/x.m3u8".into()),
            ),
            ("Start-Position-Seconds", Value::Real(12.5)),
            ("rate", Value::Real(1.0)),
            ("isMultiSelectAirPlay", Value::Bool(true)),
            ("timingPort", Value::Int(7011)),
            ("name", Value::String("Wohnzimmer – 客厅".into())),
            (
                "value",
                dict(vec![("flags", Value::Int(0)), ("epoch", Value::Int(-1))]),
            ),
            ("list", Value::Array(vec![Value::Data(vec![1, 2, 3]); 20])),
        ]);
        let data = write(&value);
        assert!(data.starts_with(b"bplist00"));
        assert_eq!(read(&data), Some(value));
    }

    /// Written by Python's plistlib: {"duration": 120.5, "position": 3,
    /// "rate": 1.0, "readyToPlay": True, "loadedTimeRanges": [{"start": 0.0}]}.
    #[test]
    fn reads_another_writer() {
        let data = include_bytes!("plist_sample.bin");
        let value = read(data).expect("read");
        assert_eq!(value.get("duration").and_then(Value::number), Some(120.5));
        assert_eq!(value.get("position").and_then(Value::number), Some(3.0));
        assert_eq!(value.get("readyToPlay"), Some(&Value::Bool(true)));
        assert!(matches!(value.get("loadedTimeRanges"), Some(Value::Array(a)) if a.len() == 1));
    }
}
