//! JavaScript run inside the core with QuickJS (rquickjs), for yt-dlp's
//! YouTube challenge solver (yt-dlp-ejs) where no separate JavaScript
//! program may run: iOS, and Android without spawning libqjs. The yt-dlp
//! plugin in `python/lumtub_jsc` hands each script here.

use std::ffi::c_char;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use rquickjs::function::Rest;
use rquickjs::{CatchResultExt, Coerced, Context, Function, Object, Runtime};
use serde::Serialize;

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
            let mut out = sink.lock().unwrap_or_else(|e| e.into_inner());
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
    let out = std::mem::take(&mut *printed.lock().unwrap_or_else(|e| e.into_inner()));
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
}
