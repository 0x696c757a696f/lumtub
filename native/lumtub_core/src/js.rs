//! JavaScript run inside the core with QuickJS (rquickjs), for yt-dlp's
//! YouTube challenge solver (yt-dlp-ejs) where no separate JavaScript
//! program may run: iOS, and Android without spawning libqjs. The yt-dlp
//! plugin in `python/lumtub_jsc` hands each script here.
//!
//! Once yt-dlp holds a player the solver preprocessed, [solve] answers its
//! challenges without the solver's scripts: the preprocessed player is
//! compiled to QuickJS bytecode once, kept beside it on disk, and loaded on
//! a thread that stays a little while for the next video.

use std::ffi::c_char;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use rquickjs::function::Rest;
use rquickjs::{CatchResultExt, Coerced, Context, Function, Object, Runtime, qjs};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};

use crate::taste::{give_json, text};

/// How long one script may run before it is stopped.
const TIME_LIMIT: Duration = Duration::from_secs(180);
/// The heap one script may use; the solver needs well under 200 MB.
const MEMORY_LIMIT: usize = 1024 * 1024 * 1024;
/// The script runs on its own thread with this much stack: a phone's
/// worker threads have 512 KB, too little for the player's parser.
const THREAD_STACK: usize = 32 * 1024 * 1024;
/// QuickJS's own stack check, below the thread's stack.
const JS_STACK: usize = 8 * 1024 * 1024;

#[derive(Serialize, Debug, PartialEq)]
pub struct Output {
    /// What the script printed with console.log, one line per call.
    pub out: String,
    /// Why the script failed, when it did.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    pub ms: u64,
}

/// Runs [source] and gives back what it printed.
pub fn run(source: &str) -> Output {
    let source = source.to_owned();
    let started = Instant::now();
    let worker = std::thread::Builder::new()
        .name("lumtub-js".into())
        .stack_size(THREAD_STACK)
        .spawn(move || run_here(&source));
    let (out, error) = match worker.map(|w| w.join()) {
        Ok(Ok(result)) => result,
        Ok(Err(_)) => (String::new(), Some("The JavaScript thread panicked".into())),
        Err(e) => (
            String::new(),
            Some(format!("Could not start the JavaScript thread: {e}")),
        ),
    };
    Output {
        out,
        error,
        ms: started.elapsed().as_millis() as u64,
    }
}

fn run_here(source: &str) -> (String, Option<String>) {
    let runtime = match Runtime::new() {
        Ok(runtime) => runtime,
        Err(e) => return (String::new(), Some(format!("QuickJS did not start: {e}"))),
    };
    runtime.set_memory_limit(MEMORY_LIMIT);
    runtime.set_max_stack_size(JS_STACK);
    let deadline = Instant::now() + TIME_LIMIT;
    let stopped = Arc::new(AtomicBool::new(false));
    let flag = stopped.clone();
    runtime.set_interrupt_handler(Some(Box::new(move || {
        let late = Instant::now() > deadline;
        if late {
            flag.store(true, Ordering::Relaxed);
        }
        late
    })));
    let context = match Context::full(&runtime) {
        Ok(context) => context,
        Err(e) => return (String::new(), Some(format!("QuickJS did not start: {e}"))),
    };
    let printed = Arc::new(std::sync::Mutex::new(String::new()));
    let result = context.with(|ctx| -> Result<(), String> {
        let sink = printed.clone();
        let log = Function::new(ctx.clone(), move |parts: Rest<Coerced<String>>| {
            let line = parts
                .0
                .into_iter()
                .map(|p| p.0)
                .collect::<Vec<_>>()
                .join(" ");
            let mut out = sink.lock().expect("lock poisoned by a panic");
            out.push_str(&line);
            out.push('\n');
        })
        .map_err(|e| e.to_string())?;
        let console = Object::new(ctx.clone()).map_err(|e| e.to_string())?;
        console.set("log", log).map_err(|e| e.to_string())?;
        ctx.globals()
            .set("console", console)
            .map_err(|e| e.to_string())?;
        ctx.eval::<(), _>(source.as_bytes())
            .catch(&ctx)
            .map_err(|e| e.to_string())
    });
    let out = std::mem::take(&mut *printed.lock().expect("lock poisoned by a panic"));
    match result {
        Ok(()) => (out, None),
        Err(_) if stopped.load(Ordering::Relaxed) => (
            out,
            Some(format!(
                "The script ran longer than {} s",
                TIME_LIMIT.as_secs()
            )),
        ),
        Err(e) => (out, Some(e)),
    }
}

/// How long the solving thread waits for the next challenge before it ends
/// and gives its memory back: a video's challenges and the next one's
/// prefetch come within seconds.
const SOLVER_IDLE: Duration = Duration::from_secs(20);
/// How long one batch of challenges may take.
const SOLVE_LIMIT: Duration = Duration::from_secs(60);

#[derive(Deserialize)]
struct SolveInput {
    /// The player as yt-dlp-ejs preprocessed it: a function body that sets
    /// `_result.n` and `_result.sig`.
    player: String,
    requests: Vec<SolveRequest>,
    /// The folder the compiled player is kept in, beside yt-dlp's own copy.
    #[serde(default)]
    cache: Option<String>,
}

#[derive(Deserialize)]
struct SolveRequest {
    #[serde(rename = "type")]
    kind: String,
    challenges: Vec<String>,
}

struct SolveJob {
    input: SolveInput,
    reply: SyncSender<Result<Value, String>>,
}

/// The thread holding the loaded player, while it waits for more.
static SOLVER: Mutex<Option<SyncSender<SolveJob>>> = Mutex::new(None);

/// Answers yt-dlp-ejs's challenges against an already preprocessed player,
/// as its `jsc()` does for input of type "preprocessed". [input] is
/// `{"player", "requests": [{"type": "n"|"sig", "challenges"}], "cache"}`;
/// the answer is jsc's output JSON in [Output::out].
pub fn solve(input: &str) -> Output {
    let started = Instant::now();
    let result = serde_json::from_str::<SolveInput>(input)
        .map_err(|e| format!("Unreadable challenge request: {e}"))
        .and_then(solve_on_thread);
    let (out, error) = match result {
        Ok(value) => (value.to_string(), None),
        Err(e) => (String::new(), Some(e)),
    };
    Output {
        out,
        error,
        ms: started.elapsed().as_millis() as u64,
    }
}

fn solve_on_thread(input: SolveInput) -> Result<Value, String> {
    let (reply, answer) = mpsc::sync_channel(1);
    let mut job = SolveJob { input, reply };
    loop {
        let (thread, waiting) = {
            let mut solver = SOLVER.lock().expect("lock poisoned by a panic");
            let Some(thread) = solver.clone() else {
                *solver = Some(start_solver(job)?);
                break;
            };
            match thread.try_send(job) {
                Ok(()) => break,
                // A full queue is waited on without the lock, which the
                // thread takes before it ends.
                Err(TrySendError::Full(waiting)) => (thread, waiting),
                // It had just ended.
                Err(TrySendError::Disconnected(waiting)) => {
                    *solver = Some(start_solver(waiting)?);
                    break;
                }
            }
        };
        match thread.send(waiting) {
            Ok(()) => break,
            Err(e) => job = e.0,
        }
    }
    answer
        .recv()
        .unwrap_or_else(|_| Err("The JavaScript thread ended without an answer".into()))
}

/// A new solver thread, given [job] first.
fn start_solver(job: SolveJob) -> Result<SyncSender<SolveJob>, String> {
    let (thread, jobs) = mpsc::sync_channel::<SolveJob>(4);
    std::thread::Builder::new()
        .name("lumtub-js-solver".into())
        .stack_size(THREAD_STACK)
        .spawn(move || solver_thread(jobs))
        .map_err(|e| format!("Could not start the JavaScript thread: {e}"))?;
    thread
        .send(job)
        .map_err(|_| "The JavaScript thread ended at once".to_string())?;
    Ok(thread)
}

/// A player compiled and run, by the hash of its source.
struct Loaded {
    hash: String,
    // The context keeps the runtime alive, but the runtime has to outlive it.
    context: Context,
    runtime: Runtime,
}

fn solver_thread(jobs: mpsc::Receiver<SolveJob>) {
    let mut loaded: Option<Loaded> = None;
    loop {
        let job = match jobs.recv_timeout(SOLVER_IDLE) {
            Ok(job) => job,
            Err(RecvTimeoutError::Timeout) => {
                // Jobs sent after this point find the sender gone and start
                // a new thread.
                let mut solver = SOLVER.lock().expect("lock poisoned by a panic");
                match jobs.try_recv() {
                    Ok(job) => {
                        drop(solver);
                        run_job(&mut loaded, job);
                        continue;
                    }
                    Err(_) => {
                        *solver = None;
                        return;
                    }
                }
            }
            Err(RecvTimeoutError::Disconnected) => return,
        };
        run_job(&mut loaded, job);
    }
}

fn run_job(loaded: &mut Option<Loaded>, job: SolveJob) {
    let SolveJob { input, reply } = job;
    let hash = player_hash(&input.player);
    if loaded.as_ref().is_none_or(|l| l.hash != hash) {
        *loaded = None;
        match load_player(&input.player, &hash, input.cache.as_deref().map(Path::new)) {
            Ok((runtime, context)) => {
                *loaded = Some(Loaded {
                    hash,
                    context,
                    runtime,
                })
            }
            Err(e) => {
                let _ = reply.send(Err(e));
                return;
            }
        }
    }
    let player = loaded.as_ref().expect("loaded above");
    set_deadline(&player.runtime, SOLVE_LIMIT, None);
    let _ = reply.send(answer(&player.context, &input.requests));
}

/// The first 16 bytes of the SHA-256 of [player], in hex.
fn player_hash(player: &str) -> String {
    Sha256::digest(player.as_bytes())[..16]
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn set_deadline(runtime: &Runtime, limit: Duration, stopped: Option<Arc<AtomicBool>>) {
    let deadline = Instant::now() + limit;
    runtime.set_interrupt_handler(Some(Box::new(move || {
        let late = Instant::now() > deadline;
        if late && let Some(flag) = &stopped {
            flag.store(true, Ordering::Relaxed);
        }
        late
    })));
}

fn new_runtime() -> Result<(Runtime, Context), String> {
    let runtime = Runtime::new().map_err(|e| format!("QuickJS did not start: {e}"))?;
    runtime.set_memory_limit(MEMORY_LIMIT);
    runtime.set_max_stack_size(JS_STACK);
    set_deadline(&runtime, SOLVE_LIMIT, None);
    let context = Context::full(&runtime).map_err(|e| format!("QuickJS did not start: {e}"))?;
    Ok((runtime, context))
}

/// Kept bytecode: the SHA-256 of [code], then [code].
fn sealed(code: &[u8]) -> Vec<u8> {
    [Sha256::digest(code).as_slice(), code].concat()
}

/// The bytecode in [sealed] when it is whole, as [sealed] wrote it.
fn unsealed(sealed: &[u8]) -> Option<&[u8]> {
    let (digest, code) = sealed.split_at_checked(32)?;
    (Sha256::digest(code).as_slice() == digest).then_some(code)
}

/// A runtime with [player] loaded into it, from its bytecode in [cache]
/// when that is there, whole and from this QuickJS, compiled (and kept
/// there) otherwise. QuickJS trusts the bytecode it reads, so a file cut
/// short or written by another version is never given to it.
fn load_player(
    player: &str,
    hash: &str,
    cache: Option<&Path>,
) -> Result<(Runtime, Context), String> {
    let version = env!("LUMTUB_QUICKJS");
    let kept: Option<PathBuf> =
        cache.map(|folder| folder.join(format!("lumtub-player-{hash}-qjs{version}.qbc")));
    if let Some(path) = &kept
        && let Ok(file) = std::fs::read(path)
    {
        if let Some(code) = unsealed(&file) {
            let (runtime, context) = new_runtime()?;
            if context.with(|ctx| run_bytecode(&ctx, code)).is_ok() {
                return Ok((runtime, context));
            }
        }
        let _ = std::fs::remove_file(path);
    }
    let code = compile(player)?;
    let (runtime, context) = new_runtime()?;
    context.with(|ctx| run_bytecode(&ctx, &code))?;
    if let Some(path) = &kept {
        let partial = path.with_extension("qbc.part");
        if std::fs::write(&partial, sealed(&code)).is_ok() {
            if std::fs::rename(&partial, path).is_err() {
                let _ = std::fs::remove_file(&partial);
            } else {
                forget_other_players(path);
            }
        }
    }
    Ok((runtime, context))
}

/// Removes the bytecode of earlier players and QuickJS versions beside
/// [kept]: none of it is read again.
fn forget_other_players(kept: &Path) {
    let (Some(folder), Some(name)) = (kept.parent(), kept.file_name()) else {
        return;
    };
    let Ok(entries) = std::fs::read_dir(folder) else {
        return;
    };
    for entry in entries.flatten() {
        let other = entry.file_name();
        let text = other.to_string_lossy();
        if other != name && text.starts_with("lumtub-player-") && text.ends_with(".qbc") {
            let _ = std::fs::remove_file(entry.path());
        }
    }
}

fn exception(ctx: &rquickjs::Ctx) -> String {
    let thrown = ctx.catch();
    if let Some(e) = thrown.as_exception() {
        return e.to_string();
    }
    thrown
        .get::<Coerced<String>>()
        .map(|s| s.0)
        .unwrap_or_else(|_| "JavaScript exception".into())
}

/// QuickJS bytecode for a script that runs the preprocessed [player] the
/// way yt-dlp-ejs's `getFromPrepared` does, leaving the solvers in the
/// global `_lumtubSolvers`. Source and debug information are left out.
fn compile(player: &str) -> Result<Vec<u8>, String> {
    let (_runtime, context) = new_runtime()?;
    // QuickJS reads the source up to a NUL after it.
    let source = format!(
        "var _lumtubSolvers = {{n: null, sig: null}};\n(function (_result) {{\n{player}\n}})(_lumtubSolvers);\n\0"
    );
    context.with(|ctx| {
        let raw = ctx.as_raw().as_ptr();
        let flags = (qjs::JS_EVAL_TYPE_GLOBAL | qjs::JS_EVAL_FLAG_COMPILE_ONLY) as i32;
        // SAFETY: [source] ends in a NUL, and its length is given without it;
        // the compiled function is freed below.
        let function = unsafe {
            qjs::JS_Eval(
                raw,
                source.as_ptr().cast(),
                (source.len() - 1) as _,
                c"player.js".as_ptr(),
                flags,
            )
        };
        if unsafe { qjs::JS_IsException(function) } {
            return Err(format!("The player did not compile: {}", exception(&ctx)));
        }
        let mut length = 0;
        let flags = (qjs::JS_WRITE_OBJ_BYTECODE
            | qjs::JS_WRITE_OBJ_STRIP_SOURCE
            | qjs::JS_WRITE_OBJ_STRIP_DEBUG) as i32;
        // SAFETY: [function] is the live value JS_Eval gave; it is freed
        // once written, and the buffer is copied before js_free.
        unsafe {
            let buffer = qjs::JS_WriteObject(raw, &mut length, function, flags);
            qjs::JS_FreeValue(raw, function);
            if buffer.is_null() {
                return Err("The player's bytecode could not be written".into());
            }
            let code = std::slice::from_raw_parts(buffer, length as usize).to_vec();
            qjs::js_free(raw, buffer.cast());
            Ok(code)
        }
    })
}

/// Runs bytecode from [compile] in [ctx].
fn run_bytecode(ctx: &rquickjs::Ctx, code: &[u8]) -> Result<(), String> {
    let raw = ctx.as_raw().as_ptr();
    // SAFETY: JS_ReadObject only reads [code]; JS_EvalFunction takes over
    // the function it gave, and the result is freed.
    unsafe {
        let function = qjs::JS_ReadObject(
            raw,
            code.as_ptr(),
            code.len() as _,
            qjs::JS_READ_OBJ_BYTECODE as i32,
        );
        if qjs::JS_IsException(function) {
            return Err(format!(
                "The player's bytecode did not load: {}",
                exception(ctx)
            ));
        }
        let result = qjs::JS_EvalFunction(raw, function);
        if qjs::JS_IsException(result) {
            return Err(format!("The player did not run: {}", exception(ctx)));
        }
        qjs::JS_FreeValue(raw, result);
    }
    Ok(())
}

/// jsc's output for [requests], solved with the loaded player.
fn answer(context: &Context, requests: &[SolveRequest]) -> Result<Value, String> {
    context.with(|ctx| {
        let solvers: Object = ctx
            .globals()
            .get("_lumtubSolvers")
            .map_err(|_| "The player left no solvers".to_string())?;
        let responses = requests
            .iter()
            .map(|request| {
                if request.kind != "n" && request.kind != "sig" {
                    return json!({"type": "error", "error": format!("Unknown request type: {}", request.kind)});
                }
                let Ok(Some(solver)) = solvers.get::<_, Option<Function>>(request.kind.as_str()) else {
                    return json!({"type": "error", "error": format!("Failed to extract {} function", request.kind)});
                };
                let mut data = Map::new();
                for challenge in &request.challenges {
                    match solver.call::<_, Coerced<String>>((challenge.as_str(),)) {
                        Ok(solved) => {
                            data.insert(challenge.clone(), Value::String(solved.0));
                        }
                        Err(_) => return json!({"type": "error", "error": exception(&ctx)}),
                    }
                }
                json!({"type": "result", "data": data})
            })
            .collect::<Vec<_>>();
        Ok(json!({"type": "result", "responses": responses}))
    })
}

/// Solves yt-dlp-ejs challenges against a preprocessed player, as [solve]
/// describes; [input] is UTF-8 JSON of [len] bytes. Gives back
/// {"out": jsc's output JSON, "error", "ms"}. Blocks; call it off the UI
/// thread. Free it with `lumtub_string_free`.
///
/// # Safety
/// [input] points at [len] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_js_solve(input: *const u8, len: usize) -> *mut c_char {
    give_json(&solve(unsafe { text(input, len) }))
}

/// Runs the JavaScript in [source] (UTF-8, [len] bytes) and gives back
/// {"out": what it printed, "error": why it failed, "ms": time taken} as
/// JSON. Blocks until the script ends; call it off the UI thread. Free it
/// with `lumtub_string_free`.
///
/// # Safety
/// [source] points at [len] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_js_run(source: *const u8, len: usize) -> *mut c_char {
    give_json(&run(unsafe { text(source, len) }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_back_only_whole_bytecode() {
        let kept = sealed(b"code");
        assert_eq!(unsealed(&kept), Some(&b"code"[..]));
        assert_eq!(unsealed(&kept[..kept.len() - 1]), None);
        assert_eq!(unsealed(b"code"), None);
    }

    #[test]
    fn prints_what_console_log_gets() {
        let output =
            run("console.log(JSON.stringify({a: [1, 2].map(x => x * 2)})); console.log(3)");
        assert_eq!(output.error, None);
        assert_eq!(output.out, "{\"a\":[2,4]}\n3\n");
    }

    #[test]
    fn reports_errors_with_what_was_printed() {
        let output = run("console.log('before'); throw new Error('broken')");
        assert_eq!(output.out, "before\n");
        assert!(output.error.unwrap().contains("broken"));
    }

    #[test]
    fn deep_recursion_fails_instead_of_crashing() {
        let output = run("function f(n) { return n ? f(n - 1) + 1 : 0 } console.log(f(1e7))");
        assert!(output.error.is_some());
    }

    #[test]
    fn modern_syntax_runs() {
        let output = run(
            "const {a, ...rest} = {a: 1, b: 2}; console.log(a + rest.b, 10n ** 2n, [1,2,3].at(-1), 'x'.replaceAll('x', 'y'))",
        );
        assert_eq!(output.error, None);
        assert_eq!(output.out, "3 100 3 y\n");
    }

    const PLAYER: &str = "var twice = function (s) { return s + s; };\n_result.n = function (n) { return n.split('').reverse().join(''); };\n_result.sig = function (s) { if (s === 'bad') throw new Error('no sig'); return twice(s); };";

    fn ask(player: &str, cache: Option<&Path>, requests: Value) -> Output {
        solve(&json!({"player": player, "requests": requests, "cache": cache.map(|c| c.to_string_lossy())}).to_string())
    }

    #[test]
    fn solves_with_a_preprocessed_player_and_keeps_its_bytecode() {
        let folder = std::env::temp_dir().join(format!("lumtub-js-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        std::fs::create_dir_all(&folder).unwrap();
        // A player of its own: the solving thread may hold PLAYER, loaded
        // by another test, and would not compile it again.
        let player = format!("{PLAYER}\n// kept");
        let player = player.as_str();
        let requests = json!([{"type": "n", "challenges": ["abc", "xyz"]}, {"type": "sig", "challenges": ["q"]}]);
        let first = ask(player, Some(&folder), requests.clone());
        assert_eq!(first.error, None);
        let answer: Value = serde_json::from_str(&first.out).unwrap();
        assert_eq!(
            answer,
            json!({"type": "result", "responses": [
                {"type": "result", "data": {"abc": "cba", "xyz": "zyx"}},
                {"type": "result", "data": {"q": "qq"}}
            ]})
        );
        let kept: Vec<_> = std::fs::read_dir(&folder)
            .unwrap()
            .flatten()
            .map(|e| e.path())
            .collect();
        assert_eq!(kept.len(), 1);
        let code = std::fs::read(&kept[0]).unwrap();
        assert!(
            !String::from_utf8_lossy(&code).contains("reverse().join"),
            "source was kept in the bytecode"
        );

        // Another thread (as after the idle exit) loads the kept bytecode.
        let (_runtime, context) = load_player(player, &player_hash(player), Some(&folder)).unwrap();
        let again = answer_of(&context, &requests);
        assert_eq!(again, answer);

        // Damaged bytecode is compiled again.
        std::fs::write(&kept[0], b"broken").unwrap();
        let (_runtime, context) = load_player(player, &player_hash(player), Some(&folder)).unwrap();
        assert_eq!(answer_of(&context, &requests), answer);
        assert_ne!(std::fs::read(&kept[0]).unwrap(), b"broken");
        let _ = std::fs::remove_dir_all(&folder);
    }

    fn answer_of(context: &Context, requests: &Value) -> Value {
        let requests: Vec<SolveRequest> = serde_json::from_value(requests.clone()).unwrap();
        answer(context, &requests).unwrap()
    }

    #[test]
    fn reports_failures_per_request_as_jsc_does() {
        let only_n = "_result.n = function (n) { return n + '!'; };";
        let output = ask(
            only_n,
            None,
            json!([
                {"type": "sig", "challenges": ["a"]},
                {"type": "n", "challenges": ["a"]},
                {"type": "x", "challenges": []}
            ]),
        );
        let answer: Value = serde_json::from_str(&output.out).unwrap();
        assert_eq!(
            answer["responses"][0],
            json!({"type": "error", "error": "Failed to extract sig function"})
        );
        assert_eq!(
            answer["responses"][1],
            json!({"type": "result", "data": {"a": "a!"}})
        );
        assert_eq!(answer["responses"][2]["type"], "error");

        let thrown = ask(
            PLAYER,
            None,
            json!([{"type": "sig", "challenges": ["bad"]}]),
        );
        let answer: Value = serde_json::from_str(&thrown.out).unwrap();
        assert_eq!(answer["responses"][0]["type"], "error");
        assert!(
            answer["responses"][0]["error"]
                .as_str()
                .unwrap()
                .contains("no sig")
        );
    }

    #[test]
    fn a_player_that_does_not_compile_is_an_error() {
        let output = ask("_result.n = function (", None, json!([]));
        assert!(output.error.unwrap().contains("compile"));
    }
}
