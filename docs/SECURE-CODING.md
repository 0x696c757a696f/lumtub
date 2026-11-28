# Secure coding rules

Lumtub reads a great deal of text it did not write: YouTube's answers, video
titles, comments, devices on the local network, files people open, and pull
requests from anyone. These rules keep that text from turning into commands,
file access or a signed package. Checks enforces what can be checked by
machine:

- `zizmor` reads every workflow (settings in `.github/zizmor.yml`);
- `.github/scripts/security_lint.py` looks for the patterns below;
- `cargo deny`, the nightly fuzzers and the Dart and Rust tests do the rest.

When a rule really has to be broken, say why on the line, so the exception is
reviewed with the code: `security-lint: allow <rule> (<reason>)` within the
four lines above, or `# zizmor: ignore[<audit>] <reason>` in a workflow.

## Workflows

1. **No expression inside a script.** `${{ … }}` never goes into `run:`;
   pass it through `env:` and quote the variable (`"$TAG"`). This holds for
   values that look safe too, such as a step's output: what fills it may
   change later.
2. **Least permissions.** The workflow says `permissions: {}` or
   `contents: read`; a job that writes asks for exactly what it writes.
3. **No credentials left behind.** `actions/checkout` takes
   `persist-credentials: false`, except in a job that pushes with git.
4. **Pin everything.** Actions by full commit with the version in a comment;
   container images by digest, or a written reason why not; downloads by
   SHA-256.
5. **Never trust a run you did not start.** A `workflow_run`, artifact, cache
   or branch name can come from a fork's pull request, which runs its own
   copy of the workflows. Before acting on another run, check its
   `event`, `head_repository.full_name` (this repository) and `path` (the
   workflow you expect). A fork's branch can be called `main` or `v1.0`.
6. **Release builds use no cache.** Steps that restore a cache are skipped
   on `refs/tags/`. Packages that a release signs come only from runs of this
   repository's own Build (see the `reuse` job).
7. **No untrusted code with secrets.** `pull_request_target` and
   `workflow_run` jobs never check out or run a pull request's code. Signing
   keys live in the `release` environment, which only `main` and `v*` tags
   reach.

## Starting programs

8. **No shell.** `Process.start(program, [arguments])`; never
   `runInShell: true`, never a command line built from strings.
   A program that comes with Windows (`reg`, `tar`, `powershell`, `explorer`,
   `rundll32`) starts by its full path from `windowsProgram()`, never by bare
   name, which Windows looks for in the current folder first.
9. **Values by argument or environment.** When a shell or PowerShell is
   unavoidable, the script is a raw constant string (`r'…'`) and values come
   in as `"$1"` or `$env:NAME`. PowerShell also reads curly quotes as quotes,
   so escaping is not enough.
10. **`--` before outside text.** yt-dlp, ffmpeg and any other tool get `'--'`
    right before an address, a file name or an id, so a value starting with
    `-` cannot become an option. Keep `'--'` on the same line as the value.
11. **yt-dlp runs isolated:** `--ignore-config --no-plugin-dirs` (see
    `ProcessTree.ytDlpIsolation`); the player's own mpv options cannot set
    `ytdl-raw-options`.
12. **Opening links:** only `http` and `https` reach the browser
    (`webLink`/`openExternal`); a folder opens only through
    `openInExplorer`.

## Network

13. **Size limits on everything read from outside.** A reply from a device on
    the LAN goes through `readDeviceReply`; Rust parsers take a budget
    (bytes, objects, depth) and have a fuzz target.
14. **No redirects or hops a device chooses.** A DLNA device is only asked at
    the address its answer came from, never at a host it names; redirects are
    off for device requests.
15. **Certificates are always checked.** No `badCertificateCallback`, no
    rustls `dangerous()` verifier, no `onReceivedSslError` override.
16. **Local servers** (cast, relay) bind with a random port and an
    unguessable token from `getrandom`, and serve only what was registered.

## Native code

17. **Rust first.** New parsing of outside data goes in the Rust core, not in
    C++, Kotlin or Swift. `unsafe` only at the FFI edge, each block with a
    `// SAFETY:` comment; integer arithmetic on outside numbers uses
    `checked_*`/`saturating_*`. The rest of the Rust rules are in
    [RUST-STYLE.md](RUST-STYLE.md); the other languages' in
    [CODE-STYLE.md](CODE-STYLE.md).
18. **Every new parser gets a fuzz target** in `native/lumtub_core/fuzz`.

## Android

19. **Nothing exported** except the launcher activity and its aliases.
20. **WebView:** https only, no file or content access, no
    `addJavascriptInterface`.
21. **PendingIntent** is `FLAG_IMMUTABLE` unless the system has to fill it
    in (the package installer), and then it is explicit and goes to an
    unexported receiver.
22. `usesCleartextTraffic` stays on only because casting talks plain HTTP to
    TVs on the LAN (UPnP has no TLS); Lumtub's own requests to the internet
    are https.

## Secrets and updates

23. **No keys in the repository**, not even for tests outside `testdata/`.
24. **Updates** install only after both signatures (Ed25519 and ML-DSA-65)
    hold, and the file is checked again through a handle that keeps it from
    changing until it runs.
25. **Logs** never hold cookies, tokens or stream addresses.

## Before merging

- Checks is green, including `zizmor` and the security lint.
- A change that reads new outside data says where the size limit is.
- A new workflow, or a new trigger in one, is read against rules 1–7.
