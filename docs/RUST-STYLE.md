# Rust style

Rust in this repository (the core in `native/lumtub_core`, its fuzzers and
the website) follows [Google's Rust style guide][guide], which builds on the
official [Rust Style Guide][rust-style] and [API Guidelines][api]. This page
lists what is checked by machine, the rules to keep in mind when writing new
code, and where Lumtub reads the guide in its own way. The safety rules in
[SECURE-CODING.md](SECURE-CODING.md) come first wherever the two meet. The
other languages are in [CODE-STYLE.md](CODE-STYLE.md).

[guide]: https://google.github.io/styleguide/rustguide.html
[rust-style]: https://doc.rust-lang.org/nightly/style-guide/
[api]: https://rust-lang.github.io/api-guidelines/

## Checked by machine

- **rustfmt** with `rustfmt.toml`: width 100, imports grouped by module
  (`use a::b::{C, D};`, never `use a::{b::C, d::E};`), lower-case hex
  literals, formatted macro matchers. The last three exist only in nightly
  rustfmt, so Checks runs a pinned nightly for them; stable rustfmt ignores
  them with a warning. Format with `cargo +nightly fmt`.
- **clippy** with `-D warnings`, plus these lints from `lib.rs`:
  - `undocumented_unsafe_blocks`: every `unsafe` block and `unsafe impl`
    starts with a `// SAFETY:` comment saying why it is sound;
  - `unwrap_used`: library code never calls `unwrap()`; tests may
    (`clippy.toml`);
  - `needless_for_each`, `wildcard_imports`, `redundant_clone`.
- Clippy runs on Linux only, so code under `cfg(windows)`, macOS, Android
  and iOS is held to the same rules by review.

## Writing new code

**Safety**

- `unsafe` only where the work cannot be done safely, which in practice is
  the FFI edge (Dart, Windows, Apple and system libraries). Keep each block
  as small as the call it wraps, away from the logic around it.
- Every `pub unsafe extern "C" fn` has a `# Safety` section saying what Dart
  must guarantee: pointers, lengths, UTF-8, who frees what.
- Never read through a poisoned lock (`PoisonError::into_inner`): its data
  may be half-changed. `lock().expect("lock poisoned by a panic")` is the
  form used here; release builds abort on panic, so it cannot fire there.

**Errors and panics**

- `Option` for a simple, obvious miss; `Result` when the caller needs to
  know why; `panic!` only for bugs. Text from outside (YouTube, files,
  devices, Dart) never panics: it returns `None` or an error.
- When an invariant the types cannot express makes a panic impossible, use
  `expect("<why it holds>")`, not `unwrap()`. Prefer `if let` / `let … else`
  over checking and then unwrapping.
- Document the panics of a function that can panic on bad input.
- No `catch_unwind`; release builds use `panic = "abort"`.

**Performance and memory**

- Borrow instead of copying: take `&str`, `&[T]` and `Option<&T>`, not
  `&String`, `&Vec<T>` or `&Option<T>`. `.clone()` only when a copy is really
  needed (cloning an `Arc` is fine).
- Unique ownership first; `Arc` where data is truly shared between threads.
- Return iterators when callers only walk the result; return a `Vec` when
  they keep it.
- Say the complexity of anything that may grow with outside data, and keep
  it linear or `n log n` unless there is a reason. Every reader of outside
  data has a size budget (SECURE-CODING rule 13).

**Shape and naming**

- Name files and modules after their main item. Only `mod` lines and
  re-exports in `lib.rs`.
- Import types and traits by name (`Regex`, but `io::Error` where names
  clash); call free functions through their module (`mem::take`, `fs::read`).
  Import a trait inside the function that uses it, unless the whole file
  does.
- Glob imports only for `use super::*` in tests and an enum's variants in a
  function about that enum.
- Constructors are `new`, `new_with_…`, `try_new` (returns `Result`);
  conversions `from_…` with a `From` impl. Getters are `foo()`, `foo_mut()`,
  `set_foo()`, `take_foo()`. A type with `len()` has `is_empty()`; one with
  `new()` and no arguments has `Default`.
- Implement the standard trait instead of a look-alike method
  (`FromStr`, not `from_str`); derive what can be derived.
- An `enum` instead of a `bool` parameter whose meaning is not obvious at the
  call site; otherwise name it in a comment: `run(&job, /* retry= */ true)`.
- Named fields instead of tuples except in very local code; a newtype
  instead of a type alias when values are easy to mix up.
- No abbreviations a newcomer would not know.
- Plain `for` loops; no combinator chain in a `for` header (bind it first)
  and no long chains. `format!` instead of `a + b + c`.
- Functions over macros; `macro_rules!` before code generation; no unstable
  features.

**Comments**

- `///` on items, `//!` at the top of a module, `//` inside code. Full
  sentences that say what the code does not. Public functions of the crate
  are documented.
- Code, comments, `expect` and error messages are in English. Chinese may
  follow the English, such as an interface name in brackets, but never
  stands alone. Other text in other languages appears only as data:
  examples of what a parser reads (view counts, titles, subtitles) and the
  strings it matches.

## Where Lumtub differs

- **One crate.** Google prefers many small crates; the core is one
  `cdylib` so Dart loads a single library, with one file per subject.
- **Tests use `#[test]`.** The guide's test-framework rules are about
  Google's own build systems.
- **Threads and `async`** are allowed (the guide forbids them only in
  Chromium).
- **`#[non_exhaustive]` and `missing_docs`** are not used: nothing outside
  this repository uses the crate's Rust API.
