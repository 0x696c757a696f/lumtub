# Engineering requirements

What every change to Lumtub has to meet, beyond working. Each section is
short and points to the detailed page where there is one
([SECURE-CODING.md](SECURE-CODING.md), [PERFORMANCE.md](PERFORMANCE.md),
[ACCESSIBILITY.md](ACCESSIBILITY.md), [CODE-STYLE.md](CODE-STYLE.md),
[RUST-STYLE.md](RUST-STYLE.md)).

## How to read this page

Every rule carries one of four levels. The words MUST, SHOULD and MAY are
used as in RFC 2119.

| Level | Means | When a change breaks it |
| --- | --- | --- |
| **MUST** | Security, correctness, the user's data, the accessibility floor | It does not merge. |
| **SHOULD** | Performance, accessibility beyond the floor, compatibility | It merges only with the exception written down (below). |
| **TARGET** | A measured goal | It is measured, and the gap is recorded. |
| **DEFAULT** | A design or product choice | It may differ where the situation needs it; say why in the PR. |

**Exceptions** are written in the pull request and opened as an issue
labelled `exception`, with the reason, the effect, and what would end it.
The [known gaps](#known-gaps-已知差距) at the end of this page, and of each
detailed page, list the open ones.

**When rules meet**, a MUST wins over a SHOULD whatever page it is on. Among
MUSTs: security first, then the user's data, then accessibility. Performance
never removes an accessibility feature; it may make it cheaper.

The numbers come from the standards named next to them (WCAG 2.2 with
WCAG2ICT for native software, the platform guides, Nielsen's response
limits) or are Lumtub's own choices, marked *project value*.

Contents:

1. [Architecture](#1-architecture-架构)
2. [Playback](#2-playback-播放)
3. [Performance](#3-performance-性能)
4. [Security](#4-security-安全)
5. [Privacy](#5-privacy-隐私)
6. [Network](#6-network-网络)
7. [Complexity](#7-complexity-复杂度)
8. [Design](#8-design-设计)
9. [UI and UX](#9-ui-and-ux-界面和体验)
10. [Animation](#10-animation-动画)
11. [Usability](#11-usability-可用性)
12. [Human factors](#12-human-factors-人因工程)
13. [Accessibility](#13-accessibility-无障碍)
14. [Completeness](#14-completeness-完整性)
15. [Reliability and data](#15-reliability-and-data-可靠性和数据)
16. [Languages and regions](#16-languages-and-regions-语言和地区)
17. [Power and heat](#17-power-and-heat-耗电和发热)
18. [Compatibility, updates and distribution](#18-compatibility-updates-and-distribution-兼容更新和分发)
19. [Logs and diagnostics](#19-logs-and-diagnostics-日志和诊断)
20. [Tests](#20-tests-测试)
21. [Dependencies, supply chain and licences](#21-dependencies-supply-chain-and-licences-依赖供应链和许可)
22. [Package size](#22-package-size-安装包大小)
23. [AI features](#23-ai-features-ai-功能)
24. [Pull request checklist](#pull-request-checklist-提交前自查)

## 1. Architecture (架构)

- **MUST — FFI ownership.** Every function across the Dart–Rust edge says
  who allocates, who frees (and with which function), how long a pointer
  lives, which thread may call, and that strings are UTF-8 with a length.
  Errors come back as values, never as a pointer the caller must guess
  about. No pointer is used after it is freed or freed twice.
- **MUST — panics stay in Rust.** Release builds abort on panic, so a panic
  never unwinds into Dart. A callback from native code (mpv, the core's
  threads) checks that its receiver still exists before it runs; nothing
  calls into a disposed isolate, player or window.
- **MUST — concurrency.** No lock is held across an `await` or a blocking
  call. Where two locks are taken, the order is written next to them. Every
  queue and channel has a bound. Background work has an owner that cancels
  it.
- **MUST — cancellation reaches the bottom.** Cancelling in Dart stops the
  Rust task behind it and kills the child process it started (yt-dlp,
  ffmpeg, Deno); nothing keeps running for a screen that is gone.
- **MUST — child processes** belong to the process tree (Job Objects on
  Windows, a process group and parent-death signal elsewhere), so they end
  when Lumtub ends, even after a crash. Their output pipes are always read,
  so a full pipe never blocks them, and their number is limited.
- **SHOULD — large data across the FFI** (subtitle tracks, long lists,
  pictures) moves as one buffer handed over with its owner, not as many
  small calls or repeated JSON round trips.
- **MUST — time.** Saved times are UTC. Time-outs, back-off, cache ages and
  rate limits use a monotonic clock, so sleep, wake and clock changes do
  not break them.
- **SHOULD — one instance on desktop.** Starting Lumtub again brings the
  running window forward and hands it the link it was started with; two
  instances never write the same files.
- **MUST — lifecycles in order.** Resources are released in a written order:
  player observers, then the video output and its textures, then the player,
  then the audio device, files and child processes. Shutdown waits for that
  with a time limit (the 0.2.20 exit crash came from the wrong order).
- **SHOULD — one source of truth.** Each piece of state has one owner. A
  copy (a UI snapshot, a cache, a row in the database, a mirror in the core)
  is allowed when it is derived from the owner and the way it is kept in
  step is written down.
- **SHOULD — Rust for shared logic.** Parsing of outside data and logic
  shared by platforms go into the Rust core (SECURE-CODING rule 17).
  Platform integration (media sessions, lifecycle, windowing, the system's
  media APIs) stays in the platform layer. A long call into the core is
  asynchronous and can be cancelled; moving work to Rust does not help if
  the UI thread waits for it.

## 2. Playback (播放)

The player is the product, so it has its own rules.

- **MUST — a defined state machine**: idle, loading, buffering, playing,
  paused, seeking, ended, error, disposed. Each event is valid only in the
  states that allow it; anything else is ignored and logged. A stale event
  (from the previous video or a cancelled seek) never changes the current
  one.
- **MUST — seek.** A new seek replaces the pending one; a quick series of
  seeks ends at the last position. Seeks outside the buffered or available
  range are handled (live: go to live edge or say it is not available).
- **SHOULD — A/V sync** stays within what mpv reports as in sync after
  normal play, seek, speed change and recovery from buffering. *TARGET*:
  |A−V| under 45 ms (ITU-R BT.1359 detectability), measured with mpv's
  statistics.
- **SHOULD — continuity.** Rebuffers and failures are counted in the log;
  recovery retries are bounded (PERFORMANCE.md) and the reason is shown.
- **MUST — decoder fallback.** Hardware decoding first. When it fails at
  start or while playing, or shows known bad output on that driver, play
  falls back to software, keeps the position, and logs why. The user can
  choose software decoding.
- **SHOULD — audio.** Audio follows the system's device changes (headphones
  out, Bluetooth on or off, a new default device) without stopping the
  video for good; unplugging headphones pauses. On phones it respects
  audio focus (pause for calls, lower for navigation) and the iOS audio
  session. Speed changes keep the pitch. Bluetooth delay is compensated
  where the system reports it.
- **MUST — system media controls**: SMTC on Windows, Now Playing on macOS
  and iOS, MPRIS on Linux, MediaSession on Android, with the title, the
  picture and the position kept current.
- **MUST — the screen stays on** while a video plays in the foreground,
  and is released at once on pause, at the end, and when only audio plays
  in the background.
- **SHOULD — TV**: the display's frame rate follows the video (24, 25, 30,
  50, 60 fps) where the system allows and the user turned it on; subtitles
  stay inside the overscan-safe area and move up while the controls show.
- **SHOULD — colour.** SDR, HDR and colour range are passed to mpv as the
  stream states; HDR on an SDR display is tone-mapped, not clipped.
- **MUST — subtitles** stay in time at every speed; overlapping lines,
  right-to-left text and font fallback work; positions follow the user's
  settings.
- **SHOULD — display changes.** Moving to another monitor, a DPI or refresh
  rate change, full screen, mini player and picture in picture keep
  playing without a black frame that lasts.
- **MUST — a lost GPU device** (driver reset, wake from sleep, a remote
  session) rebuilds the video output and keeps the position.
- **MUST — system lifecycle.** Sleep and wake, going to the background on
  Android and iOS, and being killed by the system leave the player in a
  state it can resume from. A memory warning (`onTrimMemory`, iOS memory
  warnings) frees picture caches and read-ahead first.
- **MUST — downloads.** Partial files resume, are checked against the
  expected size, are cleaned up when cancelled, and a full disk stops the
  download with a message, not a corrupt file.

## 3. Performance (性能)

[PERFORMANCE.md](PERFORMANCE.md) has the budgets and how to measure.

- **SHOULD** — no work for UI that is not visible (hidden pages, closed
  panels, a minimised window). Work the user asked to run in the
  background (downloads, audio, casting, subscription checks) is allowed
  and has its own limits.
- **MUST** — every request, process, timer, queue and cache has a limit,
  written in PERFORMANCE.md.
- **SHOULD** — nothing slow on the UI thread. *TARGET*: UI and raster
  thread each under the frame time of the display (16.7 ms at 60 Hz,
  8.3 ms at 120 Hz) at P95 on the scenarios in PERFORMANCE.md; playback
  dropped frames are measured separately from the player's statistics.
- **SHOULD** — budgets differ by device class (desktop, phone, low-memory
  device, TV) where PERFORMANCE.md says so.
- **MUST** — a change made for speed or memory shows numbers from before and
  after.

*TARGET* regression gates, measured on the reference machines in
PERFORMANCE.md: cold start to first page, first frame after a click, seek
latency, peak memory, frame time P95/P99, and memory growth over one hour
of playback. A change that makes one worse by more than 10 % (*project
value*) says why.

## 4. Security (安全)

[SECURE-CODING.md](SECURE-CODING.md) has the rules.

- **MUST — trust levels.** Lumtub trusts its own signed releases. It
  treats everything else as untrusted data: YouTube and its mirrors
  (Piped, Invidious), devices on the LAN, AI services, files the user
  opens, and its own saved files, which another program may have changed.
  Untrusted data is checked, size-limited and never run.
- **MUST — code that runs** comes only from Lumtub's release or from a
  pinned, verified tool (yt-dlp, Deno, ffmpeg, Python), never from data.
- **MUST — verification.** Lumtub's own updates install only after both
  signatures check (SECURE-CODING rule 24), and a version older than the
  installed one is refused unless the user asks for it. A checksum served
  next to the file proves the file is whole, not who made it: third-party
  tools are checked against the publisher's signature where one exists,
  else against a checksum pinned in Lumtub's own release.
- **MUST — requests to addresses outside data names.** A URL from outside
  data (a redirect, a link in a description, a device's answer) is not
  fetched if it points to a private, loopback or link-local address,
  except the LAN devices the user is casting to (SECURE-CODING rule 14).
- **SHOULD — isolation.** Rust's safety does not cover libmpv, FFmpeg,
  CPython or GPU drivers. Outside programs run in their own process with
  limits (process tree, Job Objects); when a native library parses
  hostile input in-process, a fuzz target or a separate process is
  considered.
- **MUST — vulnerabilities** are reported as [SECURITY.md](SECURITY.md)
  says. A fix for a severe one ships as its own release, names the
  affected versions in the notes, and may skip the dependency cooldown.

## 5. Privacy (隐私)

- **MUST — data inventory.** Every kind of data that leaves the device is
  one of: *needed* for what the user asked (a search sends the query and
  the IP address to YouTube, playing sends the video id), *optional* (only
  after the user turns the feature on: sign-in, AI services, translation,
  sync, sending a crash report), or *never* (analytics, tracking, contacts,
  files the user did not choose). The settings page of an optional feature
  says what it sends and to whom.
- **MUST — no browser cookies** are read. Sign-in uses the user's own
  account, kept in the system's secure store, and is sent only with the
  calls that need it.
- **MUST — secrets** (tokens, keys, cookies) are stored only in the secure
  store, held in memory only while needed, and never written to logs, crash
  reports, screenshots or error text. Where no secure store exists (some
  Linux desktops), the app says so and asks before keeping a secret in its
  own encrypted file.
- **SHOULD — retention.** Local history, caches and logs have a size or age
  limit, and the user can export and delete each of them. Deleting the
  account data removes it from the device; data the user sent to a third
  party (comments, AI requests) is that party's to delete, and the app says
  so.

## 6. Network (网络)

- **MUST — time limits** of the kind the request needs: connecting, the
  first byte, and silence while reading. A total limit only for requests
  that should end (API calls); downloads, live streams and casting have no
  total limit but stop after a long silence.
- **MUST — bounded retries with back-off and jitter.** Only requests that
  are safe to repeat are retried automatically (reads, and writes with an
  idempotency key or a check that they did not happen). A comment, like or
  subscription is never sent twice: one request at a time per action
  (single flight), and a failed one is shown with a retry button.
- **MUST — 429 and bot checks** back off longer and are reported, never
  hammered.
- **SHOULD — leaving a screen cancels the requests that only that screen
  needs.** Work the user started (a download, a sent comment) keeps going.
  A reply for a screen that is gone is dropped.
- **SHOULD — offline is a normal state.** Pages show what is saved
  (library, history, downloads) and say plainly that they are offline.
  When the network returns, failed reads are retried.
- **MUST — the user's network settings hold on every path** (proxy, IPv4
  only, encrypted DNS, certificate roots). Each backend (core HTTP client,
  yt-dlp, libmpv, casting) supports a different set of them; a backend that
  cannot honour a setting fails with a message, it never connects directly
  in silence.
- **SHOULD — metered and slow networks**: no prefetch, previews or large
  downloads on a metered connection unless the user allows it.
- **SHOULD — fallbacks** (Piped, Invidious, quick start) are chosen by
  recent health: a source that just failed waits out a cool-down instead of
  adding its delay to every play. The order and the choice are logged, and
  the user can see which source played the video.
- **MUST** — replies are read with a size limit (SECURE-CODING rule 13) and
  parsed off the UI thread.

## 7. Complexity (复杂度)

- **SHOULD — algorithms.** Anything that grows with outside data states its
  complexity in a comment and stays linear or `n log n`. Higher cost
  (fuzzy search, edit distance, subtitle alignment) is allowed with a size
  limit on its input, the reason, and a test that times the limit case.
- **SHOULD — code.** One subject per file, named after it; split a file or
  widget by responsibility and rebuild boundaries, not by length. A
  function does one thing that its name says. No option, parameter or
  layer without a present use.
- **DEFAULT — settings.** A new setting first tries to be a good default
  that needs no setting. Settings that interact are explained where they
  are set.

## 8. Design (设计)

Lumtub's look is flat and calm: content first, chrome quiet.

- **SHOULD — tokens for visual constants.** Gaps and paddings from `Space`,
  radii from `Radii` and `AppStyle`, colours from the theme and palette,
  type from the theme's text styles. Values computed from layout (a width
  that fills a row, a video's aspect ratio) are not tokens and need none.
- **DEFAULT — separation by hairline borders.** Surfaces on the page have
  no shadow. Floating layers (menus, dialogs, controls over video) may use
  a shadow or scrim where they need to stand apart.
- **DEFAULT — colour roles.** The accent marks what is chosen or on;
  links, focus and the main action have their own theme roles. Large areas
  and body text are never accent-coloured.
- **DEFAULT — nested corners** are concentric: inner radius =
  max(0, outer radius − inset) (`Radii.inner`).
- **MUST** — every palette and skin, light and dark, meets the contrast in
  ACCESSIBILITY.md.
- **SHOULD** — platform manners: window controls, menus, shortcuts (Ctrl on
  Windows and Linux, Cmd on macOS), the back gesture on Android, the TV
  remote's focus.

## 9. UI and UX (界面和体验)

- **SHOULD — the states that apply are designed**: loading, loaded, empty,
  error, offline, signed out, permission denied, service unavailable, and
  partly loaded. An empty state says why and what to do.
- **SHOULD — feedback.** The input updates the pressed state in the next
  frame, so the press shows within 100 ms end to end; the result or a
  progress mark follows (section 12).
- **MUST — errors** say what happened and what to do, in the user's
  language (`friendlyError`), with a retry where it can help. Detail goes
  to the log.
- **SHOULD — consistency.** The same thing looks and acts the same
  everywhere. A new pattern that replaces an old one lists the places
  still to move in an issue, and they move in later changes.
- **SHOULD — the user's place.** Back returns to where they were, with
  scroll position and focus. Restart restores the page and position when
  the saved state still checks out (the video exists, it was not played in
  a private mode); the user can turn restoring off.
- **SHOULD** — content that loads late does not move what the user is about
  to press: its space is reserved.
- **MUST** — autoplay, sound, full screen and opening other apps happen only
  on the user's action or a setting they chose.

## 10. Animation (动画)

- **DEFAULT — motion has a purpose**: show where something came from or
  went, a change of state, or keep the eye on what moved. Nothing loops for
  decoration.
- **MUST** — every duration goes through `Motion.of`, so the system's
  reduce-motion setting, Appearance › Motion and frame pressure turn it off.
- **MUST** — animation never blocks input. An animation the user interrupts
  (a drag, a reverse, a new press) is redirected from where it is, not
  restarted and not finished first.
- **DEFAULT — lengths** from `lib/ui/motion.dart`, by size and device:

  | Motion | Desktop | Phone, tablet, TV |
  | --- | --- | --- |
  | Press feedback | 80–120 ms (`Ease.press` 120) | same |
  | Fade, small change | 100–200 ms (`Ease.fade` 200) | 150–200 ms |
  | Page or panel move | 150–250 ms | 200–350 ms (`Ease.move` 320) |

  Exits are shorter than entrances. Ranges follow Material's and NN/g's
  guidance; the token values are *project values*.
- **SHOULD** — on large areas, prefer transform and opacity; whether an
  effect is cheap enough is decided by raster and GPU measurements, not by
  the kind of effect. Nothing animates over playing video except the
  player's own controls.
- **SHOULD** — frame rate follows the display (60, 90, 120 Hz or variable);
  an animation that misses frames on the slowest supported device is made
  cheaper first, shortened second.
- **MUST** — no content flashes more than three times a second, and no red
  flash (WCAG 2.3.1).

## 11. Usability (可用性)

- **DEFAULT — good defaults**: a new user gets a working app with no setup.
- **SHOULD — confirm by consequence.** What can be undone (removing from
  history, a playlist, the queue) is undone from the snackbar instead of a
  dialog. A dialog for what cannot be undone or is public or costs money
  (deleting files, clearing all, posting a comment where posting is
  instant, a purchase). The dialog names the thing and the button names the
  action ("Delete 12 files"), never "OK". Files go to the system's bin
  where it has one.
- **SHOULD — recognition over recall**: actions are visible or one menu
  away; a shortcut is a second way, never the only one.
- **SHOULD — forgiving input**, within stated limits: every YouTube link
  form, pasted text with spaces, a video id; search corrections come from
  YouTube's own suggestions. A wrong value in a field says what is expected.
- **MUST — interruptions are safe**: closing, losing the network or the
  computer sleeping never loses a download or a setting. A comment being
  written is kept as a draft until sent or discarded, for at most 7 days
  (*project value*), and only on the device.
- **SHOULD — words the user knows**: labels name what the user wants, not
  how it works; no codes or exception names in the interface.

## 12. Human factors (人因工程)

- **MUST — target sizes** (the touch or click area, not the drawn icon):

  | Input | Minimum | Source |
  | --- | --- | --- |
  | Pointer (desktop) | 24 × 24 logical px, or spacing that makes up for it | WCAG 2.2 SC 2.5.8 (AA) |
  | Touch, Android | 48 × 48 dp, 8 dp apart | Android accessibility guidance |
  | Touch, iOS | 44 × 44 pt | Apple HIG |
  | TV focus | 56 logical px | *project value*, tvOS HIG minimum; to check on a real TV |

  Often used controls are larger and near where the hand or pointer
  already is; destructive ones are apart from them.
- **SHOULD — response times** (Nielsen's 0.1 / 1 / 10 s): within 0.1 s the
  press shows; within 1 s the result or a progress mark; past 10 s a
  progress bar (or an indeterminate one when the remaining time is unknown,
  never a made-up percentage) and a way to cancel.
- **DEFAULT — choices by component**: a phone's bottom bar 3–5
  destinations; the TV rail 3–7; action menus in groups of about 3–5 by
  meaning. Long lists of like items (subtitle languages, qualities) scroll
  and can be searched instead of being split.
- **DEFAULT — type sizes** in logical pixels, before the system's text
  scale, which is always applied:

  | Use | Desktop | Phone | TV (about 3 m away) |
  | --- | --- | --- | --- |
  | Body | 14–16 | 16 | 20–24 |
  | Secondary | 12–13 | 12–14 | 18 |

  Prose lines are no longer than about 80 characters (40 for CJK).
- **SHOULD — the TV layout** is for a remote and a sofa: one clear focus,
  large type, no hover-only actions, content inside the overscan-safe area
  (5 % of each edge). Closing a dialog or drawer returns the focus to what
  opened it; a held direction key repeats at a steady rate the list can
  follow.
- **SHOULD — attention**: the app does not steal focus, notify or make sound
  except for what the user asked (a finished download, a live that starts).
- **MUST — errors of habit**: two look-alike actions are never side by side
  if one destroys data, and a repeated press never repeats a one-time
  action (single flight, section 6).

## 13. Accessibility (无障碍)

[ACCESSIBILITY.md](ACCESSIBILITY.md) has the rules and the manual checks.

- **MUST — the floor**: WCAG 2.2 AA, read for native software through
  WCAG2ICT (and EN 301 549 for the EU), with each platform's own guides on
  top. Every control has a name and a role, is reachable by keyboard and
  remote, keeps contrast (text 4.5:1, large text and icons 3:1), works at
  text ×2 (SC 1.4.4), and never tells anything by colour alone.
- **MUST** — a card merged into one spoken item keeps every action inside
  it reachable (as custom actions).
- **SHOULD** — announcements are kept to what matters, merged and spaced
  out, so the screen reader is not interrupted all the time.
- Known platform limits (Narrator, Orca) are listed in ACCESSIBILITY.md;
  the app does not claim AA where one of them stands.

## 14. Completeness (完整性)

A feature is done when all of these hold, or the pull request lists what is
left in an issue:

- **SHOULD — every platform** Lumtub ships, or the feature is hidden where it
  cannot work and the reason is in the code.
- **SHOULD — every state** from section 9, and every way to reach it (menu,
  shortcut, link, remote, screen reader).
- **MUST — every language has the key**: new strings go through `tr` into
  every `assets/l10n` file with the same placeholders, so no language falls
  back to a missing text. Machine translations are marked for review on
  Weblate; people correct them there.
- **MUST — settings persist** and survive an update; a new saved field has a
  default for files written before it.
- **SHOULD — stop and clean up**: what a feature starts, it can stop; what it
  writes, it can remove (clear cache, sign out). On uninstall, Lumtub
  removes what the platform lets an uninstaller remove, and offers to
  remove the user's data where the platform asks.
- **MUST — tests** (section 20).
- **SHOULD — documentation**: README or the website when users see the
  change, release notes for the version, and these pages when a rule
  changes.

## 15. Reliability and data (可靠性和数据)

- **MUST — writes that cannot leave a half file**: a temporary file in the
  same folder, flushed, then replaced in one step (`writeFileAtomic` in
  `lib/app_directories.dart`); the database uses transactions. Tests cover a write cut off half way.
- **MUST — reading saved data fails safely**: unknown fields are kept or
  ignored, missing ones take defaults, and a file that cannot be read
  (broken, a schema from a newer version, a lost key) is kept aside
  unchanged; the app starts with defaults, says so, and offers to restore
  it.
- **MUST — migrations** keep a copy of the file as it was before, and are
  tested with files from the versions in the support window (section 18).
  Going back to an older version uses that copy.
- **SHOULD — disk full and power loss**: a write that fails leaves the old
  file, tells the user, and stops writing until there is room.
- **SHOULD — crashes** leave a log, and a dump where the platform allows it.
  The dump holds thread stacks only, not the heap, and secrets are wiped
  from memory once used (`zeroize` in Rust), because a dump cannot be
  cleaned afterwards. The user sees what a report contains before sending
  it. A crash at start twice in a row starts with safe settings.
- **SHOULD — background work survives**: downloads resume after a restart;
  a failed step is retried a bounded number of times, then shown.
- **SHOULD — export and import** for what the user builds (subscriptions,
  playlists, settings), in an open format. An export never holds secrets
  (tokens, API keys, proxy passwords). An import says whether it merges or
  replaces, and shows what it will change before it does.
- **SHOULD — backups on phones**: downloads, caches and data packs are kept
  out of iCloud and Android backups; settings, library and history are
  included.
- **MUST — temporary files** for an atomic write are in the same folder as
  the file they replace, never in a system temp folder on another volume.

What can still be lost (a failed disk, the system cleaning app storage on
a phone) is said in the FAQ, with how to back up.

## 16. Languages and regions (语言和地区)

- **SHOULD — layouts grow.** Translations of short labels can be two to three
  times the English length; long text about 30 % longer (W3C's guidance on
  text size in translation). Pseudo-localised strings (labels ×3, text
  ×1.5) are tested with text ×2, and with a real right-to-left language.
- **MUST — right-to-left** languages mirror the layout by meaning: text,
  menus and buttons follow the language; the timeline, progress and
  media transport stay left to right, as the platforms do.
- **MUST — plurals, dates, numbers and durations** come from the locale
  (CLDR), never built by joining strings. Language codes are BCP 47.
- **MUST** — fonts cover every interface language (the script font packs); a
  missing glyph in the app's own text is a bug. Titles and comments from
  YouTube use the system's fallback fonts and may hold characters no font
  has.
- **SHOULD** — content language and interface language are separate
  settings; subtitles and translations follow the user's choice.

## 17. Power and heat (耗电和发热)

- **SHOULD** — on battery, power saving or Low resource mode: no prefetch,
  no background AI jobs, fewer animations, lower preview quality.
- **SHOULD** — nothing wakes the CPU on a timer while the app is idle,
  hidden or in the tray, except what the user turned on, at a slow interval.
- **SHOULD** — a paused video renders no new video frames; the controls,
  subtitles and seek preview still draw when they change. A minimised
  window renders nothing.
- **SHOULD** — caches that are cleared to save memory when a window hides
  are measured against the cost of decoding them again when it comes back.

## 18. Compatibility, updates and distribution (兼容、更新和分发)

- **SHOULD — a platform matrix** in the README: the oldest system version,
  CPU architectures, GPU back ends and the features each platform has, and
  which of them CI tests on a real machine.
- **MUST — support window**: saved data from the last 12 months of releases
  (*project value*) opens; sample files from those releases are kept in
  `test/`. A removed setting is migrated, not dropped silently.
- **MUST — versioned interfaces**: the core's FFI version (`lumtub_core`
  version check), the database schema, data packs and settings files each
  carry a version, and the reader says what it does with an older or newer
  one.
- **MUST — updates by channel.** The GitHub builds update themselves
  (signatures, section 4). Store builds (Google Play, App Store) never
  download or replace executable code and update through the store;
  components the store forbids are left out of those builds. F-Droid and
  package managers update through their own tools.
- **SHOULD** — YouTube behaviour that changes (clients, formats,
  challenges) sits behind one module each, with a fallback, and a canary
  in CI that talks to YouTube, kept apart from the deterministic tests.

## 19. Logs and diagnostics (日志和诊断)

- **SHOULD** — log lines are in English, one event per line, with what
  failed and why. An error is logged once, where it is handled.
- **MUST — no personal data in logs**: no tokens, cookies, stream
  addresses, email addresses or search terms. A diagnostic mode the user
  turns on may log search terms and full paths, says so while on, and turns
  itself off after a day.
- **SHOULD** — logs have a size limit and rotate; the user can open, copy
  and clear them from Settings › About.

## 20. Tests (测试)

- **MUST — a bug fix comes with a test** that fails without it, unless the
  bug cannot be reproduced in a test; then the pull request says why.
- **MUST** — tests are deterministic: no real network, no wall-clock sleeps,
  no order dependence. A flaky test is fixed, never retried until green.
  The online canary runs apart from them.
- **SHOULD — fault injection**: the network failing, timeouts, 429, malformed
  JSON, a helper process dying, the GPU context lost, a broken database,
  a full disk. Each has at least one test where the code can be reached.
- **SHOULD** — parsers of untrusted input with their own logic get a fuzz
  target (SECURE-CODING rule 18); thin wrappers over a fuzzed library do not
  need one.
- **SHOULD** — pages are tested in a few combinations chosen to cover each
  size, text scale and theme at least once (pairwise), not every product of
  them: for example narrow phone + text ×2 + light, TV + dark, small window
  + text ×2 + picture skin, full HD + right to left.
- **MUST** — what CI cannot test (GPU playback, real TVs, screen readers) is
  listed in the pull request with what was checked by hand.

## 21. Dependencies, supply chain and licences (依赖、供应链和许可)

- **SHOULD — a new dependency** is weighed on security, upkeep, size and
  what it would take to write ourselves. Cryptography, protocols and
  complex formats use a maintained library, not our own code.
- **MUST** — dependencies are pinned (lockfile, hash or commit). New versions
  wait the 7-day cooldown (`cooldown.py`, Dependabot); a security fix may
  skip it, saying so in the pull request.
- **SHOULD** — each release has an SBOM (SPDX or CycloneDX, `sbom.py`) and
  signed packages built by CI from a tagged commit.
- **MUST** — code from other projects keeps its licence header and is listed
  in `NOTICE`; every licence that ships is shown in Settings › About.

## 22. Package size (安装包大小)

- **SHOULD** — a change that grows a package by more than 1 MiB or 5 % of
  it, whichever is smaller (*project value*), says by how much and why. Any
  new native library or model says why, whatever its size. Package size,
  installed size and update size are tracked separately.
- **SHOULD** — optional parts (ffmpeg, AI models, data packs, script fonts)
  download on demand where the channel allows it (section 18), with their
  size shown before the download.

## 23. AI features (AI 功能)

- **MUST** — subtitles, titles, descriptions, comments and web pages given to
  a model are data. Nothing in them can make the app call a tool, read a
  file, open a link or send anything; the model's answer is shown, never
  acted on.
- **MUST** — what is sent to an AI service, and which service, is shown
  before the first use (section 5); on-device models are preferred where
  they are good enough.

## Pull request checklist (提交前自查)

- [ ] FFI, threads and lifecycles: ownership, cancellation and release
      order are clear.
- [ ] Player events are valid for the state they arrive in.
- [ ] Security and privacy: SECURE-CODING rules; nothing new leaves the
      device unasked.
- [ ] Network: time limits, safe retries only, works offline.
- [ ] Performance: limits kept, numbers for a speed change.
- [ ] Every state that applies is designed; tokens for visual constants.
- [ ] Animations through `Motion.of`, interruptible.
- [ ] Accessible: names, focus, contrast, text ×2.
- [ ] All platforms and all languages, or the gap is in an issue.
- [ ] Saved data from the support window still opens.
- [ ] Tests, including one for each bug fixed.
- [ ] Code style checks pass (Checks › Analyze and Scripts).

## Known gaps (已知差距)

Places where Lumtub does not meet this page yet. Each is fixed in its own
change; remove the line when it is.

1. Desktop page and panel moves use `Ease.move` (320 ms), above the
   desktop range in section 10.
2. The player's state machine is spread over `AppController`'s playback
   code, not written down as one table; section 2 is checked by review.
3. The FFI functions document safety (`# Safety`) but not every one states
   which thread may call it.
4. There is no fault-injection test for a lost GPU context or a full disk.
5. No real-machine performance gates in CI; the numbers in section 3 come
   from manual runs.
6. Python is not type-checked, and Kotlin, Swift and data files (JSON,
   TSV, XML) are checked by review only (CODE-STYLE.md).
7. No diagnostic mode yet; logs follow the stricter rule.
8. Which network setting each backend honours (section 6) is not written
   down as a table yet.
9. The support-window sample files (section 18) are not collected yet.
10. Secrets are not yet wiped from memory after use, and backup exclusion
    on iOS and Android is not checked.
11. TV frame-rate matching and Bluetooth delay compensation are not built.
