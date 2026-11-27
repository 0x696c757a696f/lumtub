//! 读这个词: the system's own voice reads a word or a line into a WAV
//! file, which the app plays. Windows speaks with its OneCore voices
//! (Windows.Media.SpeechSynthesis), macOS with `say`, Linux with
//! espeak-ng when it is installed. No voice for the language is an
//! error the app shows as "not installed".

use std::os::raw::c_char;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::taste::{give_json, text};

/// At most this many characters are read: a word or a subtitle line.
const MAX_CHARS: usize = 400;

#[derive(Serialize)]
struct Failed {
    error: String,
}

/// Reads [text] in [language] (a code such as `ja` or `fr`) into a WAV
/// file at [out].
pub fn speak(text: &str, language: &str, out: &Path) -> Result<(), String> {
    let text: String = text
        .chars()
        .filter(|c| !c.is_control())
        .take(MAX_CHARS)
        .collect();
    if text.trim().is_empty() {
        return Err("nothing to read".into());
    }
    if language.is_empty()
        || !language
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-')
    {
        return Err("unknown language".into());
    }
    system::speak(&text, language, out)
}

/// Whether the system has a voice for [language].
pub fn has_voice(language: &str) -> bool {
    system::has_voice(language)
}

/// Whether a voice's language tag (`ja-JP`, `ja_JP`, `ja`) is [language].
fn speaks(tag: &str, language: &str) -> bool {
    let tag = tag.trim().to_ascii_lowercase().replace('_', "-");
    let language = language.to_ascii_lowercase();
    tag == language || tag.starts_with(&format!("{language}-"))
}

#[cfg(windows)]
mod system {
    use std::path::Path;

    use windows::Media::SpeechSynthesis::{SpeechSynthesizer, VoiceInformation};
    use windows::Storage::Streams::DataReader;
    use windows::Win32::System::WinRT::{RO_INIT_MULTITHREADED, RoInitialize};
    use windows::core::HSTRING;

    fn voice(language: &str) -> Option<VoiceInformation> {
        // Already set up on this thread (perhaps single-threaded) is fine.
        // SAFETY: RoInitialize takes a valid apartment type and has no other preconditions.
        let _ = unsafe { RoInitialize(RO_INIT_MULTITHREADED) };
        let voices = SpeechSynthesizer::AllVoices().ok()?;
        let count = voices.Size().ok()?;
        (0..count).filter_map(|i| voices.GetAt(i).ok()).find(|v| {
            v.Language()
                .map(|tag| super::speaks(&tag.to_string(), language))
                .unwrap_or(false)
        })
    }

    pub fn has_voice(language: &str) -> bool {
        voice(language).is_some()
    }

    pub fn speak(text: &str, language: &str, out: &Path) -> Result<(), String> {
        let voice = voice(language).ok_or("no voice")?;
        let synthesizer = SpeechSynthesizer::new().map_err(|e| e.to_string())?;
        synthesizer.SetVoice(&voice).map_err(|e| e.to_string())?;
        let stream = synthesizer
            .SynthesizeTextToStreamAsync(&HSTRING::from(text))
            .and_then(|op| op.join())
            .map_err(|e| e.to_string())?;
        let size =
            u32::try_from(stream.Size().map_err(|e| e.to_string())?).map_err(|_| "too long")?;
        let input = stream.GetInputStreamAt(0).map_err(|e| e.to_string())?;
        let reader = DataReader::CreateDataReader(&input).map_err(|e| e.to_string())?;
        reader
            .LoadAsync(size)
            .and_then(|op| op.join())
            .map_err(|e| e.to_string())?;
        let mut bytes = vec![0u8; size as usize];
        reader.ReadBytes(&mut bytes).map_err(|e| e.to_string())?;
        std::fs::write(out, bytes).map_err(|e| e.to_string())
    }
}

#[cfg(target_os = "macos")]
mod system {
    use std::path::Path;
    use std::process::{Command, Stdio};

    /// The first of `say -v ?`'s voices for [language]: lines such as
    /// `Kyoko               ja_JP    # こんにちは`.
    fn voice(language: &str) -> Option<String> {
        let out = Command::new("/usr/bin/say")
            .arg("-v")
            .arg("?")
            .stdin(Stdio::null())
            .output()
            .ok()?;
        String::from_utf8_lossy(&out.stdout)
            .lines()
            .find_map(|line| {
                let (head, _) = line.split_once('#')?;
                let mut parts = head.split_whitespace().collect::<Vec<_>>();
                let tag = parts.pop()?;
                (super::speaks(tag, language) && !parts.is_empty()).then(|| parts.join(" "))
            })
    }

    pub fn has_voice(language: &str) -> bool {
        voice(language).is_some()
    }

    pub fn speak(text: &str, language: &str, out: &Path) -> Result<(), String> {
        let voice = voice(language).ok_or("no voice")?;
        // The text goes in a file, so nothing in it reads as an option.
        let input = out.with_extension("txt");
        std::fs::write(&input, text).map_err(|e| e.to_string())?;
        let status = Command::new("/usr/bin/say")
            .arg("-v")
            .arg(&voice)
            .arg("--file-format=WAVE")
            .arg("--data-format=LEI16@22050")
            .arg("-o")
            .arg(out)
            .arg("-f")
            .arg(&input)
            .stdin(Stdio::null())
            .status();
        let _ = std::fs::remove_file(&input);
        match status {
            Ok(s) if s.success() => Ok(()),
            Ok(s) => Err(format!("say: {s}")),
            Err(e) => Err(e.to_string()),
        }
    }
}

#[cfg(target_os = "linux")]
mod system {
    use std::path::Path;
    use std::process::{Command, Stdio};

    fn espeak() -> Option<&'static str> {
        [
            "/usr/bin/espeak-ng",
            "/usr/local/bin/espeak-ng",
            "/usr/bin/espeak",
        ]
        .into_iter()
        .find(|p| Path::new(p).exists())
    }

    pub fn has_voice(language: &str) -> bool {
        let Some(program) = espeak() else {
            return false;
        };
        let Ok(out) = Command::new(program)
            .arg("--voices")
            .stdin(Stdio::null())
            .output()
        else {
            return false;
        };
        // Lines such as ` 5  ja             --/M      Japanese     jpx/ja`.
        String::from_utf8_lossy(&out.stdout)
            .lines()
            .skip(1)
            .any(|line| {
                line.split_whitespace()
                    .nth(1)
                    .is_some_and(|tag| super::speaks(tag, language))
            })
    }

    pub fn speak(text: &str, language: &str, out: &Path) -> Result<(), String> {
        let program = espeak().ok_or("no voice")?;
        if !has_voice(language) {
            return Err("no voice".into());
        }
        let input = out.with_extension("txt");
        std::fs::write(&input, text).map_err(|e| e.to_string())?;
        let status = Command::new(program)
            .arg("-v")
            .arg(language)
            .arg("-w")
            .arg(out)
            .arg("-f")
            .arg(&input)
            .stdin(Stdio::null())
            .status();
        let _ = std::fs::remove_file(&input);
        match status {
            Ok(s) if s.success() => Ok(()),
            Ok(s) => Err(format!("espeak-ng: {s}")),
            Err(e) => Err(e.to_string()),
        }
    }
}

#[cfg(not(any(windows, target_os = "macos", target_os = "linux")))]
mod system {
    use std::path::Path;

    pub fn has_voice(_: &str) -> bool {
        false
    }

    pub fn speak(_: &str, _: &str, _: &Path) -> Result<(), String> {
        Err("no voice".into())
    }
}

/// Reads [json]'s `{text, language, out}` into a WAV file at `out`.
/// Answers `{}` or `{"error"}`; "no voice" when the system has none for
/// the language. Blocks while it speaks: call it off the UI thread.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_speak(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        text: String,
        language: String,
        out: String,
    }
    // SAFETY: The caller passes `json` pointing at `length` readable bytes, as this function
    // requires.
    let answer = serde_json::from_str::<Ask>(unsafe { text(json, length) })
        .map_err(|e| e.to_string())
        .and_then(|ask| speak(&ask.text, &ask.language, Path::new(&ask.out)));
    match answer {
        Ok(()) => give_json(&serde_json::json!({})),
        Err(error) => give_json(&Failed { error }),
    }
}

/// Answers `{"voice": bool}`: whether [json]'s `{language}` has a voice.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_speech_voice(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        language: String,
    }
    // SAFETY: The caller passes `json` pointing at `length` readable bytes, as this function
    // requires.
    let voice = serde_json::from_str::<Ask>(unsafe { text(json, length) })
        .map(|ask| has_voice(&ask.language))
        .unwrap_or(false);
    give_json(&serde_json::json!({ "voice": voice }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_language_tags() {
        assert!(speaks("ja-JP", "ja"));
        assert!(speaks("ja_JP", "ja"));
        assert!(speaks("fr", "fr"));
        assert!(!speaks("fr-CA", "f"));
        assert!(!speaks("en-US", "es"));
    }

    #[test]
    fn refuses_empty_text_and_odd_languages() {
        let out = std::env::temp_dir().join("lumtub-speech-test.wav");
        assert!(speak("  ", "fr", &out).is_err());
        assert!(speak("mot", "fr; rm", &out).is_err());
    }
}
