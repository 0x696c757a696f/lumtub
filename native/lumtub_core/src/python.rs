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
    /// Settings the runner and the plugins read (LUMTUB_CORE,
    /// SSL_CERT_FILE…), handed to Python as the runner's `SETTINGS`. The
    /// process environment is never changed: another thread may be
    /// reading it.
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
    let mut state = STATE.lock().expect("lock poisoned by a panic");
    if matches!(*state, State::Unconfigured | State::Configured(_)) {
        *state = State::Configured(config);
    }
}

/// Python, started on the first call; the error says why it cannot run.
fn api() -> Result<Api, String> {
    let mut state = STATE.lock().expect("lock poisoned by a panic");
    let config = match &*state {
        State::Ready(api) => return Ok(*api),
        State::Failed(error) => return Err(error.clone()),
        State::Unconfigured => return Err("Python is not set up in this app".into()),
        State::Configured(config) => config.clone(),
    };
    // SAFETY: `start_python` runs once, under the STATE lock, and its `config` names the Python
    // library to load.
    let result = unsafe { start_python(&config) };
    *state = match &result {
        Ok(api) => State::Ready(*api),
        Err(error) => State::Failed(error.clone()),
    };
    result
}

unsafe fn symbol<T>(library: *mut c_void, name: &str) -> Result<T, String> {
    let c = CString::new(name).unwrap_or_default();
    // SAFETY: `library` is a live dlopen handle and `c` ends in NUL.
    let found = unsafe { libc::dlsym(library, c.as_ptr()) };
    if found.is_null() {
        return Err(format!("Python has no {name}"));
    }
    // SAFETY: `found` is the non-null address of `name`, and the caller picks `T` as the pointer
    // type that symbol has.
    Ok(unsafe { std::mem::transmute_copy::<*mut c_void, T>(&found) })
}

fn dl_error() -> String {
    // SAFETY: dlerror takes no arguments and returns null or a NUL-terminated message.
    let error = unsafe { libc::dlerror() };
    if error.is_null() {
        return "unknown error".into();
    }
    // SAFETY: `error` is non-null and NUL-terminated, and is read before any other dl call.
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

type Settings<'a> = ([(&'static str, &'a str); 2], [(&'static str, i64); 5]);

/// The interpreter's settings, as PYTHONHOME, PYTHONUTF8 and the like
/// would give them: (name, string value) or (name, number).
fn settings(config: &Config) -> Settings<'_> {
    (
        [("home", config.home.as_str()), ("stdio_encoding", "utf-8")],
        [
            ("utf8_mode", 1),
            ("write_bytecode", 0),
            ("user_site_directory", 0),
            ("buffered_stdio", 0),
            // Python leaves the app's signal handlers alone.
            ("install_signal_handlers", 0),
        ],
    )
}

/// Starts Python with [settings] through PEP 741's PyInitConfig (Python
/// 3.14 on), which needs nothing from the process environment. None when
/// this Python has no PyInitConfig.
unsafe fn initialize_configured(
    library: *mut c_void,
    config: &Config,
) -> Option<Result<(), String>> {
    type Create = unsafe extern "C" fn() -> *mut c_void;
    type Free = unsafe extern "C" fn(*mut c_void);
    type SetStr = unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char) -> c_int;
    type SetInt = unsafe extern "C" fn(*mut c_void, *const c_char, i64) -> c_int;
    type Start = unsafe extern "C" fn(*mut c_void) -> c_int;
    type GetError = unsafe extern "C" fn(*mut c_void, *mut *const c_char) -> c_int;
    // SAFETY: dlsym finds `PyInitConfig_Create`, whose C signature matches `Create`.
    let create: Create = unsafe { symbol(library, "PyInitConfig_Create") }.ok()?;
    // SAFETY: dlsym finds `PyInitConfig_Free`, whose C signature matches `Free`.
    let free: Free = unsafe { symbol(library, "PyInitConfig_Free") }.ok()?;
    // SAFETY: dlsym finds `PyInitConfig_SetStr`, whose C signature matches `SetStr`.
    let set_str: SetStr = unsafe { symbol(library, "PyInitConfig_SetStr") }.ok()?;
    // SAFETY: dlsym finds `PyInitConfig_SetInt`, whose C signature matches `SetInt`.
    let set_int: SetInt = unsafe { symbol(library, "PyInitConfig_SetInt") }.ok()?;
    // SAFETY: dlsym finds `Py_InitializeFromInitConfig`, whose C signature matches `Start`.
    let start: Start = unsafe { symbol(library, "Py_InitializeFromInitConfig") }.ok()?;
    // SAFETY: dlsym finds `PyInitConfig_GetError`, whose C signature matches `GetError`.
    let get_error: GetError = unsafe { symbol(library, "PyInitConfig_GetError") }.ok()?;
    // SAFETY: `create` takes no arguments; its result is checked for null below.
    let init = unsafe { create() };
    if init.is_null() {
        return Some(Err("Python could not be configured".into()));
    }
    let (strings, numbers) = settings(config);
    let mut ok = true;
    for (name, value) in strings {
        let (Ok(name), Ok(value)) = (CString::new(name), CString::new(value)) else {
            ok = false;
            break;
        };
        // SAFETY: [init] is live and both strings end in NUL.
        ok &= unsafe { set_str(init, name.as_ptr(), value.as_ptr()) } == 0;
    }
    for (name, value) in numbers {
        let name = CString::new(name).unwrap_or_default();
        // SAFETY: [init] is live and [name] ends in NUL.
        ok &= unsafe { set_int(init, name.as_ptr(), value) } == 0;
    }
    // SAFETY: [init] is live until freed below.
    ok = ok && unsafe { start(init) } == 0;
    let result = if ok {
        Ok(())
    } else {
        let mut message: *const c_char = std::ptr::null();
        // SAFETY: the message, when given, lives as long as [init].
        let detail = if unsafe { get_error(init, &mut message) } == 1 && !message.is_null() {
            // SAFETY: [message] is non-null, NUL-terminated and lives until [init] is freed.
            unsafe { std::ffi::CStr::from_ptr(message) }
                .to_string_lossy()
                .into_owned()
        } else {
            "unknown error".into()
        };
        Err(format!("Python did not start: {detail}"))
    };
    // SAFETY: `init` is non-null and live, and is freed only here.
    unsafe { free(init) };
    Some(result)
}

unsafe fn start_python(config: &Config) -> Result<Api, String> {
    let path = CString::new(config.library.as_str()).map_err(|e| e.to_string())?;
    // SAFETY: `path` ends in NUL; the handle is checked for null below.
    let library = unsafe { libc::dlopen(path.as_ptr(), libc::RTLD_NOW | libc::RTLD_GLOBAL) };
    if library.is_null() {
        return Err(format!("Could not load Python: {}", dl_error()));
    }
    let is_initialized: unsafe extern "C" fn() -> c_int =
        // SAFETY: dlsym finds `Py_IsInitialized`, whose C signature is `int (void)`.
        unsafe { symbol(library, "Py_IsInitialized")? };
    let save_thread: unsafe extern "C" fn() -> *mut c_void =
        // SAFETY: dlsym finds `PyEval_SaveThread`, whose C signature is `void *(void)`.
        unsafe { symbol(library, "PyEval_SaveThread")? };
    // SAFETY: dlsym finds each of these three names, and each `Api` field type
    // is the C signature of that function.
    let run = unsafe { symbol(library, "PyRun_SimpleString")? };
    // SAFETY: as for `run` above.
    let ensure = unsafe { symbol(library, "PyGILState_Ensure")? };
    // SAFETY: as for `run` above.
    let release = unsafe { symbol(library, "PyGILState_Release")? };
    let api = Api {
        run,
        ensure,
        release,
    };
    // SAFETY: `library` is a live handle and this function's caller holds the STATE lock.
    let Some(started) = (unsafe { initialize_configured(library, config) }) else {
        return Err("This Python is older than 3.14, which Lumtub needs".into());
    };
    started?;
    // SAFETY: `is_initialized` is `Py_IsInitialized`, which may be called at any time.
    if unsafe { is_initialized() } == 0 {
        return Err("Python did not start".into());
    }
    let error_file = format!("{}/python-error.txt", config.temporary);
    let _ = std::fs::remove_file(&error_file);
    let settings_json = serde_json::to_string(&config.environment).map_err(|e| e.to_string())?;
    let bootstrap = format!(
        "try:\n    import json, sys, types\n    _m = types.ModuleType('_lumtub_runner')\n    _m.SETTINGS = json.loads({})\n    exec(compile({}, 'lumtub_runner', 'exec'), _m.__dict__)\n    sys.modules['_lumtub_runner'] = _m\n    del _m\nexcept BaseException:\n    import traceback\n    with open({}, 'w') as _f:\n        _f.write(traceback.format_exc())\n    raise\n",
        literal(&settings_json),
        literal(RUNNER),
        literal(&error_file)
    );
    // SAFETY: Python is initialized, and the GIL is held by this thread (it started Python), so
    // `lock` is false.
    let ok = unsafe { run_code(&api, &bootstrap, false) };
    // The thread that started Python lets go of it; every later call
    // takes it again with PyGILState_Ensure.
    // SAFETY: This thread started Python and holds the GIL, which PyEval_SaveThread releases.
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
        // SAFETY: `api.ensure` is PyGILState_Ensure, valid once Python is initialized.
        Some(unsafe { (api.ensure)() })
    } else {
        None
    };
    // SAFETY: `api.run` is PyRun_SimpleString, `code` ends in NUL, and this thread holds the GIL.
    let result = unsafe { (api.run)(code.as_ptr()) };
    if let Some(gil) = gil {
        // SAFETY: `gil` is what PyGILState_Ensure returned on this thread.
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
                // SAFETY: `api` came from `start_python`, so Python is initialized; `lock` takes
                // the GIL.
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
            // SAFETY: `api` came from `start_python`, so Python is initialized; `lock` takes the
            // GIL.
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
    // SAFETY: The caller passes `json` pointing at `len` readable bytes, as this function requires.
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
    // SAFETY: The caller passes `json` pointing at `len` readable bytes, as this function requires.
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
    // SAFETY: `data` is non-null here and, per this function's `# Safety`, points at `len` readable
    // bytes.
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

    /// Starts a real Python 3.14+ through PyInitConfig and reads back what
    /// it was given. Runs when LUMTUB_TEST_PYTHON_LIBRARY names a shared
    /// libpython and LUMTUB_TEST_PYTHON_HOME its prefix (CI's Linux job and
    /// a local check; the iOS framework takes the same calls).
    #[test]
    fn python_starts_with_its_settings_and_no_python_variables() {
        let (Ok(library), Ok(home)) = (
            std::env::var("LUMTUB_TEST_PYTHON_LIBRARY"),
            std::env::var("LUMTUB_TEST_PYTHON_HOME"),
        ) else {
            return;
        };
        let temporary = std::env::temp_dir().join(format!("lumtub-python-{}", std::process::id()));
        std::fs::create_dir_all(&temporary).unwrap();
        let config = Config {
            library,
            home: home.clone(),
            temporary: temporary.to_string_lossy().into_owned(),
            environment: HashMap::from([
                ("LUMTUB_TEST_SETTING".to_string(), "kept".to_string()),
                // The runner loads the core for its callbacks.
                (
                    "LUMTUB_CORE".to_string(),
                    std::env::var("LUMTUB_TEST_CORE").unwrap_or_else(|_| {
                        concat!(
                            env!("CARGO_MANIFEST_DIR"),
                            "/target/debug/liblumtub_core.so"
                        )
                        .to_string()
                    }),
                ),
            ]),
        };
        // Whatever the shell running the tests has set stays out of the check.
        let inherited: Vec<String> = std::env::vars()
            .map(|(k, _)| k)
            .filter(|k| k.starts_with("PYTHON"))
            .collect();
        let handler = |signal| {
            // SAFETY: `sigaction` is a C struct for which all-zero bytes are valid.
            let mut action: libc::sigaction = unsafe { std::mem::zeroed() };
            assert_eq!(
                // SAFETY: The new action is null, so this only reads the current handler into
                // `action`.
                unsafe { libc::sigaction(signal, std::ptr::null(), &mut action) },
                0
            );
            action.sa_sigaction
        };
        let handlers = [handler(libc::SIGINT), handler(libc::SIGPIPE)];
        // SAFETY: The test calls this once, before any other Python use in the process.
        let api = unsafe { start_python(&config) }.unwrap();
        // The process's own handlers are as they were: Python installs
        // none when it starts.
        for (signal, before) in [libc::SIGINT, libc::SIGPIPE].into_iter().zip(handlers) {
            assert_eq!(handler(signal), before, "signal {signal}");
        }
        let out = temporary.join("seen.json");
        let code = format!(
            "import json, os, sys, ssl\nwith open({}, 'w') as f:\n    json.dump({{'utf8': sys.flags.utf8_mode, 'bytecode': sys.dont_write_bytecode, 'user_site': sys.flags.no_user_site, 'prefix': sys.prefix, 'python_vars': sorted(k for k in os.environ if k.startswith('PYTHON')), 'setting': sys.modules['_lumtub_runner'].SETTINGS.get('LUMTUB_TEST_SETTING'), 'in_environ': 'LUMTUB_TEST_SETTING' in os.environ, 'stdout': sys.stdout.encoding, 'runner': '_lumtub_runner' in sys.modules}}, f)\n",
            literal(&out.to_string_lossy())
        );
        // SAFETY: `api` came from `start_python`, so Python is initialized; `lock` takes the GIL.
        assert!(unsafe { run_code(&api, &code, true) });
        let seen: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&out).unwrap()).unwrap();
        let _ = std::fs::remove_dir_all(&temporary);
        assert_eq!(seen["utf8"], 1, "{seen}");
        assert_eq!(seen["bytecode"], true, "{seen}");
        assert_eq!(seen["user_site"], 1, "{seen}");
        assert_eq!(seen["prefix"], home.as_str(), "{seen}");
        let set: Vec<&str> = seen["python_vars"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|v| v.as_str())
            .filter(|k| !inherited.iter().any(|i| i == k))
            .collect();
        assert!(set.is_empty(), "{seen}");
        assert_eq!(seen["setting"], "kept", "{seen}");
        // The settings reach the runner, not the process environment.
        assert_eq!(seen["in_environ"], false, "{seen}");
        assert_eq!(seen["stdout"], "utf-8", "{seen}");
        assert_eq!(seen["runner"], true, "{seen}");
    }

    #[test]
    fn literal_survives_quotes() {
        assert_eq!(literal("a'\"\n"), "bytes.fromhex('6127220a').decode()");
    }
}
