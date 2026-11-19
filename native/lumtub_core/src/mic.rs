//! 跟读录音: records the microphone while the person repeats a subtitle
//! line, as 16-bit mono, and writes the take as a WAV file.
//!
//! Windows, macOS and iOS record through cpal. Linux and Android load
//! their system's audio library only when recording starts (libasound,
//! libaaudio), so the core loads where neither is installed, and on
//! Android 7, which has no AAudio, only recording is missing.

use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

use crate::taste::{give_json, text};

/// The longest take kept, in seconds; anything after it is dropped.
const LONGEST_SECONDS: usize = 180;

/// What a capture thread fills while it runs.
#[derive(Default)]
struct Heard {
    samples: Vec<i16>,
    rate: u32,
}

impl Heard {
    /// Adds [frames] of [channels] interleaved samples as mono.
    fn add<S: Copy>(&mut self, frames: &[S], channels: usize, to_i16: impl Fn(S) -> i16) {
        let channels = channels.max(1);
        let room =
            (self.rate.max(8000) as usize * LONGEST_SECONDS).saturating_sub(self.samples.len());
        for frame in frames.chunks(channels).take(room) {
            let sum: i32 = frame.iter().map(|&s| to_i16(s) as i32).sum();
            self.samples.push((sum / frame.len() as i32) as i16);
        }
    }
}

/// A recording going on: its thread stops when [stop] is set.
struct Recording {
    stop: Arc<AtomicBool>,
    heard: Arc<Mutex<Heard>>,
    thread: Option<JoinHandle<()>>,
}

static RECORDING: Mutex<Option<Recording>> = Mutex::new(None);

/// Starts recording; an error says why it could not.
pub fn start() -> Result<(), String> {
    let mut recording = RECORDING.lock().map_err(|_| "busy".to_string())?;
    if recording.is_some() {
        return Ok(());
    }
    let stop = Arc::new(AtomicBool::new(false));
    let heard = Arc::new(Mutex::new(Heard::default()));
    let (ready, started) = std::sync::mpsc::channel::<Result<(), String>>();
    let thread = {
        let stop = stop.clone();
        let heard = heard.clone();
        std::thread::Builder::new()
            .name("lumtub-mic".into())
            .spawn(move || platform::capture(stop, heard, ready))
            .map_err(|e| e.to_string())?
    };
    match started.recv_timeout(std::time::Duration::from_secs(10)) {
        Ok(Ok(())) => {
            *recording = Some(Recording {
                stop,
                heard,
                thread: Some(thread),
            });
            Ok(())
        }
        Ok(Err(e)) => {
            let _ = thread.join();
            Err(e)
        }
        Err(_) => {
            stop.store(true, Ordering::SeqCst);
            Err("the microphone did not start".into())
        }
    }
}

/// Stops recording and gives what was heard, mono 16-bit, and its rate.
pub fn stop() -> Option<(Vec<i16>, u32)> {
    let mut recording = RECORDING.lock().ok()?.take()?;
    recording.stop.store(true, Ordering::SeqCst);
    if let Some(thread) = recording.thread.take() {
        let _ = thread.join();
    }
    let heard = std::mem::take(&mut *recording.heard.lock().ok()?);
    Some((heard.samples, heard.rate))
}

/// [samples], 16-bit mono at [rate], as a WAV file.
pub fn wav(samples: &[i16], rate: u32) -> Vec<u8> {
    let data = (samples.len() * 2) as u32;
    let mut out = Vec::with_capacity(44 + data as usize);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&rate.to_le_bytes());
    out.extend_from_slice(&(rate * 2).to_le_bytes());
    out.extend_from_slice(&2u16.to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data.to_le_bytes());
    for sample in samples {
        out.extend_from_slice(&sample.to_le_bytes());
    }
    out
}

/// Starts recording. Null when it did, else why not; free it with
/// lumtub_string_free.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_mic_start() -> *mut c_char {
    match start() {
        Ok(()) => std::ptr::null_mut(),
        Err(e) => give_json(&serde_json::json!({ "error": e })),
    }
}

/// Stops recording and writes the take to the file at [path] as WAV:
/// `{"seconds", "rate"}`, or `{"error"}`. Free it with lumtub_string_free.
///
/// # Safety
/// [path] must point at [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_mic_stop(path: *const u8, length: usize) -> *mut c_char {
    let path = unsafe { text(path, length) };
    let Some((samples, rate)) = stop() else {
        return give_json(&serde_json::json!({ "error": "not recording" }));
    };
    if rate == 0 {
        return give_json(&serde_json::json!({ "error": "nothing was heard" }));
    }
    match std::fs::write(path, wav(&samples, rate)) {
        Ok(()) => give_json(
            &serde_json::json!({ "seconds": samples.len() as f64 / rate as f64, "rate": rate }),
        ),
        Err(e) => give_json(&serde_json::json!({ "error": e.to_string() })),
    }
}

/// Whether recording goes on now.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_mic_recording() -> bool {
    RECORDING.lock().map(|r| r.is_some()).unwrap_or(false)
}

type Ready = std::sync::mpsc::Sender<Result<(), String>>;

/// Sleeps on the capture thread until [stop] is set.
#[allow(dead_code)]
fn wait(stop: &AtomicBool) {
    while !stop.load(Ordering::SeqCst) {
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
}

#[cfg(any(windows, target_os = "macos", target_os = "ios"))]
mod platform {
    use super::*;
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

    pub(super) fn capture(stop: Arc<AtomicBool>, heard: Arc<Mutex<Heard>>, ready: Ready) {
        let stream = match open(heard) {
            Ok(stream) => stream,
            Err(e) => {
                let _ = ready.send(Err(e));
                return;
            }
        };
        if let Err(e) = stream.play() {
            let _ = ready.send(Err(e.to_string()));
            return;
        }
        let _ = ready.send(Ok(()));
        // The stream lives on this thread: it cannot move to another.
        wait(&stop);
        drop(stream);
    }

    fn open(heard: Arc<Mutex<Heard>>) -> Result<cpal::Stream, String> {
        let device = cpal::default_host()
            .default_input_device()
            .ok_or("no microphone")?;
        let config = device.default_input_config().map_err(|e| e.to_string())?;
        let channels = config.channels() as usize;
        heard.lock().map_err(|e| e.to_string())?.rate = config.sample_rate();
        let failed = |e: cpal::Error| eprintln!("lumtub: the microphone stopped: {e}");
        let stream_config: cpal::StreamConfig = config.into();
        macro_rules! stream {
            ($t:ty, $convert:expr) => {{
                let heard = heard.clone();
                device.build_input_stream(
                    stream_config.clone(),
                    move |data: &[$t], _: &cpal::InputCallbackInfo| {
                        if let Ok(mut heard) = heard.lock() {
                            heard.add(data, channels, $convert);
                        }
                    },
                    failed,
                    None,
                )
            }};
        }
        let stream = match config.sample_format() {
            cpal::SampleFormat::I16 => stream!(i16, |s: i16| s),
            cpal::SampleFormat::U16 => stream!(u16, |s: u16| (s as i32 - 32768) as i16),
            cpal::SampleFormat::I32 => stream!(i32, |s: i32| (s >> 16) as i16),
            cpal::SampleFormat::F32 => stream!(f32, |s: f32| (s.clamp(-1.0, 1.0) * 32767.0) as i16),
            cpal::SampleFormat::F64 => stream!(f64, |s: f64| (s.clamp(-1.0, 1.0) * 32767.0) as i16),
            other => return Err(format!("the microphone gives {other} samples")),
        };
        stream.map_err(|e| e.to_string())
    }
}

/// libasound, opened when recording starts: its "default" device is
/// PulseAudio's or PipeWire's on a desktop, in Flatpak too.
#[cfg(target_os = "linux")]
mod platform {
    use super::*;
    use std::ffi::c_void;
    use std::os::raw::{c_int, c_long, c_uint, c_ulong};

    type Open = unsafe extern "C" fn(*mut *mut c_void, *const c_char, c_int, c_int) -> c_int;
    type SetParams =
        unsafe extern "C" fn(*mut c_void, c_int, c_int, c_uint, c_uint, c_int, c_uint) -> c_int;
    type Read = unsafe extern "C" fn(*mut c_void, *mut c_void, c_ulong) -> c_long;
    type Recover = unsafe extern "C" fn(*mut c_void, c_int, c_int) -> c_int;
    type Close = unsafe extern "C" fn(*mut c_void) -> c_int;

    const CAPTURE: c_int = 1;
    const S16_LE: c_int = 2;
    const RW_INTERLEAVED: c_int = 3;
    const RATE: u32 = 44100;

    unsafe fn symbol<T>(library: *mut c_void, name: &[u8]) -> Option<T> {
        let found = unsafe { libc::dlsym(library, name.as_ptr() as *const c_char) };
        (!found.is_null()).then(|| unsafe { std::mem::transmute_copy::<*mut c_void, T>(&found) })
    }

    pub(super) fn capture(stop: Arc<AtomicBool>, heard: Arc<Mutex<Heard>>, ready: Ready) {
        let library = unsafe {
            libc::dlopen(
                c"libasound.so.2".as_ptr(),
                libc::RTLD_NOW | libc::RTLD_LOCAL,
            )
        };
        if library.is_null() {
            let _ = ready.send(Err("libasound.so.2 is not installed".into()));
            return;
        }
        let functions = unsafe {
            (
                symbol::<Open>(library, b"snd_pcm_open\0"),
                symbol::<SetParams>(library, b"snd_pcm_set_params\0"),
                symbol::<Read>(library, b"snd_pcm_readi\0"),
                symbol::<Recover>(library, b"snd_pcm_recover\0"),
                symbol::<Close>(library, b"snd_pcm_close\0"),
            )
        };
        let (Some(open), Some(set_params), Some(read), Some(recover), Some(close)) = functions
        else {
            let _ = ready.send(Err("libasound is missing functions".into()));
            return;
        };
        let mut pcm: *mut c_void = std::ptr::null_mut();
        let opened = unsafe { open(&mut pcm, c"default".as_ptr(), CAPTURE, 0) };
        if opened < 0 || pcm.is_null() {
            let _ = ready.send(Err(format!("no microphone (ALSA error {opened})")));
            return;
        }
        // Half a second of buffer; ALSA resamples to this rate if need be.
        let set = unsafe { set_params(pcm, S16_LE, RW_INTERLEAVED, 1, RATE, 1, 500_000) };
        if set < 0 {
            unsafe { close(pcm) };
            let _ = ready.send(Err(format!(
                "the microphone refused 16-bit mono (ALSA error {set})"
            )));
            return;
        }
        if let Ok(mut heard) = heard.lock() {
            heard.rate = RATE;
        }
        let _ = ready.send(Ok(()));
        let mut buffer = vec![0i16; 2048];
        while !stop.load(Ordering::SeqCst) {
            let got = unsafe {
                read(
                    pcm,
                    buffer.as_mut_ptr() as *mut c_void,
                    buffer.len() as c_ulong,
                )
            };
            if got < 0 {
                if unsafe { recover(pcm, got as c_int, 1) } < 0 {
                    break;
                }
                continue;
            }
            if let Ok(mut heard) = heard.lock() {
                heard.add(&buffer[..got as usize], 1, |s| s);
            }
        }
        unsafe { close(pcm) };
    }
}

/// AAudio (Android 8 and later), opened when recording starts.
#[cfg(target_os = "android")]
mod platform {
    use super::*;
    use std::ffi::c_void;

    type Result32 = i32;
    type CreateBuilder = unsafe extern "C" fn(*mut *mut c_void) -> Result32;
    type SetI32 = unsafe extern "C" fn(*mut c_void, i32);
    type OpenStream = unsafe extern "C" fn(*mut c_void, *mut *mut c_void) -> Result32;
    type DeleteBuilder = unsafe extern "C" fn(*mut c_void) -> Result32;
    type StreamCall = unsafe extern "C" fn(*mut c_void) -> Result32;
    type StreamRead = unsafe extern "C" fn(*mut c_void, *mut c_void, i32, i64) -> Result32;

    const DIRECTION_INPUT: i32 = 1;
    const FORMAT_PCM_I16: i32 = 1;
    const RATE: i32 = 44100;

    unsafe fn symbol<T>(library: *mut c_void, name: &[u8]) -> Option<T> {
        let found = unsafe { libc::dlsym(library, name.as_ptr() as *const c_char) };
        (!found.is_null()).then(|| unsafe { std::mem::transmute_copy::<*mut c_void, T>(&found) })
    }

    pub(super) fn capture(stop: Arc<AtomicBool>, heard: Arc<Mutex<Heard>>, ready: Ready) {
        let library = unsafe { libc::dlopen(c"libaaudio.so".as_ptr(), libc::RTLD_NOW) };
        if library.is_null() {
            let _ = ready.send(Err("recording needs Android 8 or later".into()));
            return;
        }
        let f = unsafe {
            (
                symbol::<CreateBuilder>(library, b"AAudio_createStreamBuilder\0"),
                symbol::<SetI32>(library, b"AAudioStreamBuilder_setDirection\0"),
                symbol::<SetI32>(library, b"AAudioStreamBuilder_setFormat\0"),
                symbol::<SetI32>(library, b"AAudioStreamBuilder_setChannelCount\0"),
                symbol::<SetI32>(library, b"AAudioStreamBuilder_setSampleRate\0"),
                symbol::<OpenStream>(library, b"AAudioStreamBuilder_openStream\0"),
                symbol::<DeleteBuilder>(library, b"AAudioStreamBuilder_delete\0"),
                symbol::<StreamCall>(library, b"AAudioStream_requestStart\0"),
                symbol::<StreamRead>(library, b"AAudioStream_read\0"),
                symbol::<StreamCall>(library, b"AAudioStream_requestStop\0"),
                symbol::<StreamCall>(library, b"AAudioStream_close\0"),
                symbol::<StreamCall>(library, b"AAudioStream_getSampleRate\0"),
            )
        };
        let (
            Some(create),
            Some(direction),
            Some(format),
            Some(channels),
            Some(rate),
            Some(open),
            Some(delete),
            Some(start),
            Some(read),
            Some(stop_stream),
            Some(close),
            Some(sample_rate),
        ) = f
        else {
            let _ = ready.send(Err("AAudio is missing functions".into()));
            return;
        };
        let mut builder: *mut c_void = std::ptr::null_mut();
        if unsafe { create(&mut builder) } < 0 || builder.is_null() {
            let _ = ready.send(Err("AAudio could not start".into()));
            return;
        }
        let mut stream: *mut c_void = std::ptr::null_mut();
        let opened = unsafe {
            direction(builder, DIRECTION_INPUT);
            format(builder, FORMAT_PCM_I16);
            channels(builder, 1);
            rate(builder, RATE);
            let opened = open(builder, &mut stream);
            delete(builder);
            opened
        };
        if opened < 0 || stream.is_null() {
            let _ = ready.send(Err(format!("no microphone (AAudio error {opened})")));
            return;
        }
        let started = unsafe { start(stream) };
        if started < 0 {
            unsafe { close(stream) };
            let _ = ready.send(Err(format!(
                "the microphone did not start (AAudio error {started})"
            )));
            return;
        }
        if let Ok(mut heard) = heard.lock() {
            heard.rate = unsafe { sample_rate(stream) }.max(8000) as u32;
        }
        let _ = ready.send(Ok(()));
        let mut buffer = vec![0i16; 2048];
        while !stop.load(Ordering::SeqCst) {
            // A tenth of a second at most, so stopping is quick.
            let got = unsafe {
                read(
                    stream,
                    buffer.as_mut_ptr() as *mut c_void,
                    buffer.len() as i32,
                    100_000_000,
                )
            };
            if got < 0 {
                break;
            }
            if let Ok(mut heard) = heard.lock() {
                heard.add(&buffer[..got as usize], 1, |s| s);
            }
        }
        unsafe {
            stop_stream(stream);
            close(stream);
        }
    }
}

#[cfg(not(any(
    windows,
    target_os = "macos",
    target_os = "ios",
    target_os = "linux",
    target_os = "android"
)))]
mod platform {
    use super::*;

    pub(super) fn capture(_stop: Arc<AtomicBool>, _heard: Arc<Mutex<Heard>>, ready: Ready) {
        let _ = ready.send(Err("recording is not supported here".into()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wav_header_and_samples() {
        let file = wav(&[1, -2, 300], 48000);
        assert_eq!(&file[0..4], b"RIFF");
        assert_eq!(u32::from_le_bytes(file[4..8].try_into().unwrap()), 36 + 6);
        assert_eq!(&file[8..16], b"WAVEfmt ");
        assert_eq!(u16::from_le_bytes(file[20..22].try_into().unwrap()), 1);
        assert_eq!(u16::from_le_bytes(file[22..24].try_into().unwrap()), 1);
        assert_eq!(u32::from_le_bytes(file[24..28].try_into().unwrap()), 48000);
        assert_eq!(u32::from_le_bytes(file[28..32].try_into().unwrap()), 96000);
        assert_eq!(&file[36..40], b"data");
        assert_eq!(u32::from_le_bytes(file[40..44].try_into().unwrap()), 6);
        assert_eq!(&file[44..], &[1, 0, 0xFE, 0xFF, 0x2C, 0x01]);
    }

    #[test]
    fn channels_become_one_and_long_takes_stop_growing() {
        let mut heard = Heard {
            samples: Vec::new(),
            rate: 8000,
        };
        heard.add(&[100i16, 300, -100, -300], 2, |s| s);
        assert_eq!(heard.samples, vec![200, -200]);
        heard.add(&[0.5f32, 0.5], 1, |s: f32| (s * 32767.0) as i16);
        assert_eq!(heard.samples[2..], [16383, 16383]);
        let long = vec![1i16; 8000 * (LONGEST_SECONDS + 5)];
        heard.add(&long, 1, |s| s);
        assert_eq!(heard.samples.len(), 8000 * LONGEST_SECONDS);
    }

    #[test]
    fn stopping_without_recording_says_so() {
        assert!(stop().is_none());
        assert!(!lumtub_mic_recording());
    }
}
