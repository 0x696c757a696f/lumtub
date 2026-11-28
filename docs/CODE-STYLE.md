# Code style

Each language follows Google's published guide for it, or the guide Google
points to for that language. This page says which guide applies, what is
checked by machine, and where Lumtub reads a guide in its own way. Rust has
its own page, [RUST-STYLE.md](RUST-STYLE.md). The rules in
[SECURE-CODING.md](SECURE-CODING.md) come first wherever they meet. What a change must
meet beyond style (performance, network, design, usability and more) is in
[REQUIREMENTS.md](REQUIREMENTS.md).

| Code | Guide | Checked by |
| --- | --- | --- |
| Dart and Flutter (`lib/`, `test/`) | [Effective Dart][dart] | `flutter analyze` and `dart format` with `analysis_options.yaml` |
| Rust (`native/lumtub_core`, `website/`) | [Google's Rust style guide][rust] | rustfmt, clippy ([RUST-STYLE.md](RUST-STYLE.md)) |
| C++ (Windows and Linux runners) | [Google C++ Style Guide][cpp] | clang-format with `.clang-format` |
| Kotlin (`android/`) | [Android Kotlin style guide][kotlin] | review; `.editorconfig` for editors and ktlint |
| Swift (`ios/`, `macos/`) | [Google Swift Style Guide][swift] | review |
| Python (yt-dlp runner, CI and packaging scripts) | [Google Python Style Guide][python] | Ruff with `ruff.toml` |
| Shell (`*.sh`, workflow steps) | [Google Shell Style Guide][shell] | ShellCheck, actionlint |
| JavaScript (`license-server/`, `docs/cards/`) | [Google JavaScript Style Guide][js] | ESLint with `.github/lint/eslint.config.mjs` |
| GitHub Actions workflows | the rules below, [SECURE-CODING.md](SECURE-CODING.md) | actionlint, zizmor |

[dart]: https://dart.dev/effective-dart
[rust]: https://google.github.io/styleguide/rustguide.html
[cpp]: https://google.github.io/styleguide/cppguide.html
[kotlin]: https://developer.android.com/kotlin/style-guide
[swift]: https://google.github.io/swift/
[python]: https://google.github.io/styleguide/pyguide.html
[shell]: https://google.github.io/styleguide/shellguide.html
[js]: https://google.github.io/styleguide/jsguide.html

## Every language

- **English.** Names, comments, log lines, exception and `expect`
  messages are in English. Chinese may follow the English, such as an
  interface name in brackets (`Shuffles the home feed (换一批)`), but never
  stands alone. Text in other languages appears only as data: what a
  parser reads, test fixtures, licence texts as their authors wrote them,
  and the strings the interface shows (those live in `assets/l10n`).
- **Comments say what the code does not:** why, the limits, what outside
  data can do. Full sentences.
- **No author or tool lines** in code, commits or pull requests. Licence
  and copyright notices that a licence requires stay.
- **Line ends and paths.** Shell and Python files keep LF
  (`.gitattributes`). Code never assumes a case-insensitive file system,
  and paths shown to the user use the platform's separator.
- **Outside data never crashes the app.** Check its type and size before use
  (SECURE-CODING rule 13); a wrong value is skipped or reported, not cast
  blindly.
- **Performance is part of correctness.** Say the complexity of work that
  grows with outside data and keep it linear or `n log n`, or bound its
  input and say why (REQUIREMENTS.md section 7); nothing slow or blocking
  on the UI thread.

## Dart and Flutter

Effective Dart is the guide; `analysis_options.yaml` checks most of it and
Checks fails on any finding.

- **Types are strict:** `strict-casts`, `strict-inference` and
  `strict-raw-types`. JSON and platform-channel values are `Object?` until
  checked: use a pattern (`if (json case {'id': final String id})`) or an
  `is` check, not `as` on data from outside. No calls on `dynamic`
  (`avoid_dynamic_calls`).
- **Futures are awaited or marked:** `unawaited(...)` says on purpose that
  nothing waits (`unawaited_futures`, `discarded_futures`). Subscriptions
  are cancelled and sinks closed by their owner.
- Throw only `Exception` or `Error` subclasses. No `print`: use the app log.
- Effective Dart's style: single quotes, `const` where possible, `final` for
  locals and fields that do not change, imports ordered (`dart:`,
  `package:`, relative), constructors first, required named parameters
  first, no positional `bool` parameters, super parameters, no redundant
  arguments or parentheses.
- Doc comments use `///` and refer to names in scope with `[name]`.
- **Formatting:** `dart format lib test`, 100 columns (`formatter` in
  `analysis_options.yaml`); Checks fails on any change it would make. The
  commit that formatted every file is in `.git-blame-ignore-revs`.
- `BuildContext` is not used after an `await` unless `mounted` was checked
  (`use_build_context_synchronously`, from `flutter_lints`).
- `unawaited(...)` only says nothing waits: the future still handles its
  own errors and is cancelled by its owner.
- Widgets: split a `build` method by responsibility and rebuild boundary
  into widgets, not helper methods; `const` constructors for widgets that take
  no changing values.

## C++ (Windows and Linux runners)

Google's C++ style, formatted by clang-format 18 with `.clang-format`
(Google, 80 columns). Checks runs `clang-format --dry-run --Werror`.

- Includes keep their written order (`SortIncludes: Never`), because some
  Windows headers need `windows.h` first.
- Names: `PascalCase` types and functions, `snake_case` variables,
  `trailing_` members, `kConstant` constants. Win32 calls are written
  `::Function` so they read as the system's.
- Ownership: `std::unique_ptr` and RAII wrappers for handles; no `new`
  without an owner. Check every Win32 and GLib result.
- Code generated by Visual Studio (`resource.h`) is left as it is
  (`.clang-format-ignore`).
- New logic goes in the Rust core, not here (SECURE-CODING rule 17).

## Kotlin (Android)

The Android Kotlin style guide (ktlint's `android_studio` style, 100
columns, in `.editorconfig`).

- `PascalCase` classes, `camelCase` functions and properties,
  `SCREAMING_SNAKE_CASE` constants.
- No `!!` on values from the system or from Dart; handle the `null`.
- KDoc (`/** */`) on classes and on functions Dart calls through the
  method channel.

## Swift (iOS and macOS)

The Google Swift Style Guide: 100 columns, two-space indent,
`lowerCamelCase` functions and properties, `UpperCamelCase` types.

- No force unwrap (`!`) or `try!` on values from the system or from Dart;
  use `guard let`.
- `///` doc comments on types and on the methods Dart calls.
- `[weak self]` in closures kept by the system.

## Python

Google's Python style, checked by Ruff (`ruff.toml`) in Checks › Scripts:
pycodestyle, pyflakes, bugbear, import order, naming, newer syntax,
shadowed builtins, catch-all excepts, a set of security checks (`exec`,
`eval`, pickle, unsafe YAML, `shell=True`, weak hashes) and Ruff's own
rules. Files are formatted with `ruff format`.

Where Lumtub differs from Google's guide, on purpose:

- **100 columns, not 80**, the same as the Rust and Kotlin code.
- **No docstring or annotation checks** (Ruff `D`, `ANN`) and no type
  checker yet: the Python is scripts and one runner, not a library.
  Functions others call still get a docstring.
- **`from module import name`** is allowed for standard library names;
  Ruff does not check Google's modules-only import rule.

- Scripts that read outside data (`.github/scripts`, the yt-dlp runner)
  check its type before use, like the Dart code.
- `subprocess.run` says `check=True` or `check=False`; a command is a list,
  never a shell string.
- Python that ships in the app (`native/lumtub_core/src/python_runner.py`,
  `python/`) reads its settings from the runner, not from `os.environ`,
  which other threads may be changing.
- Scripts run with `python3 -I` in CI, so nothing in the working directory
  is imported by accident.
- `# noqa: CODE` only with a reason after it.

## Shell

Google's Shell style, checked by ShellCheck for `*.sh` files and by
actionlint (which runs ShellCheck) for every workflow step.

- Bash, starting with `set -euo pipefail`. The smoke, showcase and glass
  checks are the exception: they keep going to collect every log.
- Quote every expansion. Where words are split on purpose, split them
  into an array with `read -ra` first; a `# shellcheck disable=` line
  says why.
- `rm -rf` on a variable path uses `"${dir:?}/…"`, so an empty variable
  can never remove `/`.
- Anything longer than a page, or with real logic, is Python instead.

## JavaScript

Google's JavaScript style, checked by ESLint (`@eslint/js` recommended
rules plus Google's: `const` by default, `let` when reassigned, never
`var`; one variable per declaration; braces except for a one-line `if`
with no `else` (Google 4.1.1); `===`, with `== null` allowed; no thrown
literals; no `eval`, `new Function` or changes to built-in prototypes).
ESLint's versions are locked in `.github/lint/package-lock.json`.

Google has frozen its JavaScript guide and points to its TypeScript guide.
The license server is small and runs as plain JavaScript on Cloudflare, so
it stays on the JavaScript guide; a rewrite would move it to TypeScript.

- Two-space indent, single quotes, semicolons, as the files already are.
  No formatter checks them yet.
- The license server checks every field of a request before use and
  never trusts a webhook without its signature.

## Workflows

- Every action is pinned by commit hash with its version in a comment;
  every download is pinned by checksum (`.github/pins.env` or the step).
- `persist-credentials: false` on checkout, the smallest `permissions`,
  and no `${{ }}` of outside data inside `run:` (zizmor checks these).
- Tools installed with pip use `--require-hashes --only-binary=:all:`;
  npm uses `npm ci --ignore-scripts` from a lockfile.

## Other files

Checked by review only:

- **PowerShell** (`build_windows.ps1`, `windows/packaging`):
  `$ErrorActionPreference = 'Stop'` except in the checks that collect
  logs, full cmdlet names rather than aliases.
- **CMake** (Windows and Linux): the Flutter-generated files are left as
  they are; our own lines follow the surrounding file.
- **Gradle Kotlin scripts** (`android/*.gradle.kts`): the Kotlin rules
  above.
- **Inno Setup** (`windows/installer/lumtub.iss`) and **CSS**
  (`website/style.css`): the style of the file.
- **GLSL shaders** (`assets/shaders`) come from their authors unchanged,
  with their licence headers.
- **Data** (JSON, JSONC, TSV, XML, plist): valid for its format, read by
  code that checks it (rule 13).
