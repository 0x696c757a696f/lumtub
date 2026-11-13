//! yt-dlp inside the app's own process, for iOS, where an app may not
//! start other programs. The app carries Python as a framework; the core
//! loads it on first use, starts the interpreter once and runs each yt-dlp
//! in a Python thread (`python_runner.py`). Output and exit codes go to the
//! Dart port the run was started with, as `[1, bytes]` (stdout),
//! `[2, bytes]` (stderr) and `[3, code]`.

use std::collections::HashMap;
use std::ffi::{CString, c_char, c_int, c_void};
use std::sync::Mutex;

use serde::Deserialize;

use crate::http::{Item, post};
use crate::taste::text;

const RUNNER: &str = include_str!("python_runner.py");
const STDOUT: i64 = 1;
const STDERR: i64 = 2;
const EXIT: i64 = 3;
/// What a run exits with when Python could not be started.
const NO_PYTHON: i64 = 127;

#[derive(Deserialize, Clone, Debug, PartialEq)]
pub struct Config {
    /// The Python library: `Python.framework/Python` in the app.
    pub library: String,
    /// The folder holding `lib/python3.N`, set as PYTHONHOME.
    pub home: String,
    /// Where a failure to start is written for the core to read.
    pub temporary: String,
    /// Set in the environment before Python starts (LUMTUB_CORE,
    /// SSL_CERT_FILE…).
    #[serde(default)]
    pub environment: HashMap<String, String>,
}

type RunString = unsafe extern "C" fn(*const c_char) -> c_int;
type GilEnsure = unsafe extern "C" fn() -> c_int;
type GilRelease = unsafe extern "C" fn(c_int);

#[derive(Clone, Copy)]
struct Api {
    run: RunString,
    ensure: GilEnsure,
    release: GilRelease,
}

enum State {
    Unconfigured,
    Configured(Config),
    Ready(Api),
    Failed(String),
}

static STATE: Mutex<State> = Mutex::new(State::Unconfigured);

/// Records where Python is; it starts with the first run. A second call
/// with other settings is ignored once Python has started.
pub fn configure(config: Config) {
    let mut state = STATE.lock().unwrap_or_else(|e| e.into_inner());
    if matches!(*state, State::Unconfigured | State::Configured(_)) {
        *state = State::Configured(config);
    }
}

/// Python, started on the first call; the error says why it cannot run.
fn api() -> Result<Api, String> {
    let mut state = STATE.lock().unwrap_or_else(|e| e.into_inner());
    let config = match &*state {
        State::Ready(api) => return Ok(*api),
        State::Failed(error) => return Err(error.clone()),
        State::Unconfigured => return Err("Python is not set up in this app".into()),
        State::Configured(config) => config.clone(),
    };
    let result = unsafe { start_python(&config) };
    *state = match &result {
        Ok(api) => State::Ready(*api),
        Err(error) => State::Failed(error.clone()),
    };
    result
}

unsafe fn symbol<T>(library: *mut c_void, name: &str) -> Result<T, String> {
    let c = CString::new(name).unwrap_or_default();
    let found = unsafe { libc::dlsym(library, c.as_ptr()) };
    if found.is_null() {
        return Err(format!("Python has no {name}"));
    }
    Ok(unsafe { std::mem::transmute_copy::<*mut c_void, T>(&found) })
}

fn dl_error() -> String {
    let error = unsafe { libc::dlerror() };
    if error.is_null() {
        return "unknown error".into();
    }
    unsafe { std::ffi::CStr::from_ptr(error) }
        .to_string_lossy()
        .into_owned()
}

/// Python source that sets `name` to the string [value] without quoting
/// trouble.
fn literal(value: &str) -> String {
    let hex: String = value.bytes().map(|b| format!("{b:02x}")).collect();
    format!("bytes.fromhex('{hex}').decode()")
}

unsafe fn start_python(config: &Config) -> Result<Api, String> {
    for (name, value) in [
        ("PYTHONHOME", config.home.as_str()),
        ("PYTHONUTF8", "1"),
        ("PYTHONIOENCODING", "utf-8"),
        ("PYTHONDONTWRITEBYTECODE", "1"),
        ("PYTHONNOUSERSITE", "1"),
        ("PYTHONUNBUFFERED", "1"),
    ] {
        unsafe { std::env::set_var(name, value) };
    }
    for (name, value) in &config.environment {
        unsafe { std::env::set_var(name, value) };
    }
    let path = CString::new(config.library.as_str()).map_err(|e| e.to_string())?;
    let library = unsafe { libc::dlopen(path.as_ptr(), libc::RTLD_NOW | libc::RTLD_GLOBAL) };
    if library.is_null() {
        return Err(format!("Could not load Python: {}", dl_error()));
    }
    let initialize: unsafe extern "C" fn(c_int) = unsafe { symbol(library, "Py_InitializeEx")? };
    let is_initialized: unsafe extern "C" fn() -> c_int =
        unsafe { symbol(library, "Py_IsInitialized")? };
    let save_thread: unsafe extern "C" fn() -> *mut c_void =
        unsafe { symbol(library, "PyEval_SaveThread")? };
    let api = Api {
        run: unsafe { symbol(library, "PyRun_SimpleString")? },
        ensure: unsafe { symbol(library, "PyGILState_Ensure")? },
        release: unsafe { symbol(library, "PyGILState_Release")? },
    };
    // Text is UTF-8 whatever the locale says (the default from 3.15).
    if let Ok(utf8) = unsafe { symbol::<*mut c_int>(library, "Py_UTF8Mode") } {
        unsafe { *utf8 = 1 };
    }
    // 0: Python leaves the app's signal handlers alone.
    unsafe { initialize(0) };
    if unsafe { is_initialized() } == 0 {
        return Err("Python did not start".into());
    }
    let error_file = format!("{}/python-error.txt", config.temporary);
    let _ = std::fs::remove_file(&error_file);
    let bootstrap = format!(
        "try:\n    import sys, types\n    _m = types.ModuleType('_lumtub_runner')\n    exec(compile({}, 'lumtub_runner', 'exec'), _m.__dict__)\n    sys.modules['_lumtub_runner'] = _m\n    del _m\nexcept BaseException:\n    import traceback\n    with open({}, 'w') as _f:\n        _f.write(traceback.format_exc())\n    raise\n",
        literal(RUNNER),
        literal(&error_file)
    );
    let ok = unsafe { run_code(&api, &bootstrap, false) };
    // The thread that started Python lets go of it; every later call
    // takes it again with PyGILState_Ensure.
    unsafe { save_thread() };
    if !ok {
        let detail = std::fs::read_to_string(&error_file).unwrap_or_default();
        return Err(format!(
            "yt-dlp's runner did not start in Python: {}",
            detail.trim()
        ));
    }
    Ok(api)
}

/// Runs [code] in the interpreter, taking the GIL first when [lock].
unsafe fn run_code(api: &Api, code: &str, lock: bool) -> bool {
    let Ok(code) = CString::new(code) else {
        return false;
    };
    let gil = if lock {
        Some(unsafe { (api.ensure)() })
    } else {
        None
    };
    let result = unsafe { (api.run)(code.as_ptr()) };
    if let Some(gil) = gil {
        unsafe { (api.release)(gil) };
    }
    result == 0
}

fn spawn(name: &str, work: impl FnOnce() + Send + 'static) -> bool {
    std::thread::Builder::new()
        .name(name.into())
        .stack_size(8 * 1024 * 1024)
        .spawn(work)
        .is_ok()
}

/// Starts yt-dlp [request] (`{"app": zip app, "argv": [...]}`) and posts
/// what it prints to [port]; returns at once (the first run waits for
/// Python to start, about a second).
pub fn start(port: i64, request: String) -> bool {
    let parsed: serde_json::Value = serde_json::from_str(&request).unwrap_or_default();
    if !parsed["app"].is_string() || !parsed["argv"].is_array() {
        return false;
    }
    spawn("lumtub-python", move || {
        let failed = match api() {
            Ok(api) => {
                let code = format!(
                    "import _lumtub_runner\n_lumtub_runner.start({port}, {})\n",
                    literal(&request)
                );
                if unsafe { run_code(&api, &code, true) } {
                    None
                } else {
                    Some("Python could not start yt-dlp".to_string())
                }
            }
            Err(error) => Some(error),
        };
        if let Some(error) = failed {
            post(
                port,
                vec![
                    Item::Int(STDERR),
                    Item::Bytes(format!("ERROR: {error}\n").into_bytes()),
                ],
            );
            post(port, vec![Item::Int(EXIT), Item::Int(NO_PYTHON)]);
        }
    })
}

/// Interrupts the run posting to [port]; its exit (-9) is posted at once.
pub fn kill(port: i64) {
    spawn("lumtub-python-kill", move || {
        if let Ok(api) = api() {
            let code = format!("import _lumtub_runner\n_lumtub_runner.kill({port})\n");
            unsafe { run_code(&api, &code, true) };
        }
    });
}

/// Records where Python is, from JSON `{"library", "home", "temporary",
/// "environment": {…}}`; false when it does not parse.
///
/// # Safety
/// [json] must point to [len] bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_py_configure(json: *const u8, len: usize) -> bool {
    match serde_json::from_str::<Config>(unsafe { text(json, len) }) {
        Ok(config) => {
            configure(config);
            true
        }
        Err(_) => false,
    }
}

/// Starts a yt-dlp run from JSON `{"app", "argv"}`, posting to [port]
/// (see the module's notes); false when the JSON does not parse.
///
/// # Safety
/// [json] must point to [len] bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_py_start(port: i64, json: *const u8, len: usize) -> bool {
    start(port, unsafe { text(json, len) }.to_owned())
}

#[unsafe(no_mangle)]
pub extern "C" fn lumtub_py_kill(port: i64) {
    kill(port);
}

/// Called by `python_runner.py` with what a run printed.
///
/// # Safety
/// [data] must point to [len] bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_py_emit(port: i64, fd: i32, data: *const u8, len: usize) {
    if data.is_null() || len == 0 {
        return;
    }
    let bytes = unsafe { std::slice::from_raw_parts(data, len) }.to_vec();
    let fd = if fd as i64 == STDOUT { STDOUT } else { STDERR };
    post(port, vec![Item::Int(fd), Item::Bytes(bytes)]);
}

/// Called by `python_runner.py` when a run ends.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_py_exit(port: i64, code: i32) {
    post(port, vec![Item::Int(EXIT), Item::Int(code as i64)]);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn literal_survives_quotes() {
        assert_eq!(literal("a'\"\n"), "bytes.fromhex('6127220a').decode()");
    }
}
