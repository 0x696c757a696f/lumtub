# Engineering requirements

What every change to Lumtub has to meet, beyond working. Each section is
short and points to the detailed page where there is one. When two rules
meet, the order is: [SECURE-CODING.md](SECURE-CODING.md), then this page,
then [PERFORMANCE.md](PERFORMANCE.md), [ACCESSIBILITY.md](ACCESSIBILITY.md)
and the style pages ([CODE-STYLE.md](CODE-STYLE.md),
[RUST-STYLE.md](RUST-STYLE.md)).

A change that cannot meet a rule says so in its pull request, with the
reason, and adds the gap to the list at the end of the page it breaks.

Contents:

1. [Performance](#1-performance-性能)
2. [Security and privacy](#2-security-and-privacy-安全和隐私)
3. [Network](#3-network-网络)
4. [Complexity](#4-complexity-复杂度)
5. [Design](#5-design-设计)
6. [UI and UX](#6-ui-and-ux-界面和体验)
7. [Animation](#7-animation-动画)
8. [Usability](#8-usability-可用性)
9. [Human factors](#9-human-factors-人因工程)
10. [Accessibility](#10-accessibility-无障碍)
11. [Completeness](#11-completeness-完整性)
12. [Reliability and data](#12-reliability-and-data-可靠性和数据)
13. [Languages and regions](#13-languages-and-regions-语言和地区)
14. [Power and heat](#14-power-and-heat-耗电和发热)
15. [Compatibility and updates](#15-compatibility-and-updates-兼容和更新)
16. [Logs and diagnostics](#16-logs-and-diagnostics-日志和诊断)
17. [Tests](#17-tests-测试)
18. [Dependencies and licences](#18-dependencies-and-licences-依赖和许可)
19. [Package size and install](#19-package-size-and-install-安装包)
20. [Pull request checklist](#pull-request-checklist-提交前自查)

## 1. Performance (性能)

[PERFORMANCE.md](PERFORMANCE.md) has the budgets and how to measure.

- Work only for what is on screen; nothing polls or animates while hidden.
- Every request, process, timer and cache has a limit written in
  PERFORMANCE.md.
- Nothing slow on the UI thread: a frame is 16 ms at 60 Hz (8 ms at
  120 Hz). Heavy work goes to the Rust core.
- A speed or memory change shows numbers from before and after.

## 2. Security and privacy (安全和隐私)

[SECURE-CODING.md](SECURE-CODING.md) has the rules; these are the
promises they serve.

- **Nothing about the user leaves the device** unless they turned on the
  feature that needs it (sign-in, AI services, translation, sync), and the
  setting says what is sent where. No analytics or tracking.
- Browser cookies are never read. Sign-in uses the user's own account, kept
  in the system's secure store, and only for the calls that need it.
- Secrets (tokens, keys, cookies) never appear in logs, crash dumps,
  screenshots, error text or files outside the secure store.
- Outside data (YouTube, devices on the LAN, files, plugins, Dart over the
  FFI) is untrusted: checked, size-limited, and never executed.
- Downloads of tools and updates are verified by signature or checksum
  before use.

## 3. Network (网络)

- **Every request has a timeout**, and connecting has its own shorter one.
  Nothing waits forever.
- **Retries are bounded and back off** (with jitter for anything that
  repeats). 429 and bot checks back off longer and are reported, never
  hammered.
- **Leaving a screen cancels its requests.** A reply for a screen that is
  gone is dropped, not applied.
- **No network is a normal state.** Pages show what is saved (library,
  history, downloads) and say plainly that they are offline; nothing spins
  without end. Coming back online retries what failed.
- **The user's network settings are honoured everywhere**: proxy (system,
  HTTP, SOCKS5), IPv4 only, encrypted DNS, certificate roots. A new
  connection path goes through the core's HTTP client or the same settings,
  never around them.
- **Metered and slow networks**: no prefetch, previews or large downloads
  on a metered connection unless the user allows it; quality follows the
  playback strategy.
- Replies are read with a size limit (SECURE-CODING rule 13) and parsed off
  the UI thread.
- Fallbacks (Piped, Invidious, quick start) are tried in a fixed, logged
  order, and the user can see which one served the video.

## 4. Complexity (复杂度)

**Algorithms.** Anything that grows with outside data (lists, comments,
chat, subtitles, history, the library) states its complexity in a comment
and stays linear or `n log n`. Quadratic work needs a small fixed bound and
says so. Long lists are windowed, not rebuilt.

**Code.**

- One subject per file, named after it. Split a file when a newcomer can no
  longer find their way in it (as `AppController` was split into part
  files), not by line count alone.
- A function does one thing that its name says. Deep nesting is flattened
  with early returns.
- State has one owner. Another place that needs it asks the owner or
  listens; it does not keep its own copy.
- No speculative generality: no option, parameter or layer without a
  present use.
- New logic that is not UI goes into the Rust core (SECURE-CODING rule 17).

**Product.** A new setting has to earn its place: first try a good default
that needs no setting. Settings that interact are explained where they are
set.

## 5. Design (设计)

Lumtub's look is flat and calm: content first, chrome quiet.

- **Tokens only.** Gaps and paddings come from `Space` (2 to 48 px), corner
  radii from `Radii` and `AppStyle`, colours from the theme and the palette
  (`lib/ui/palettes.dart`), type from the theme's text styles. No literal
  sizes or colours in widgets.
- **Hairline borders, not shadows**, for separation. The accent marks only
  what is chosen or on (switches, selection, the current tab), never large
  areas or body text.
- A shape inside another one less than 32 px from its edge uses
  `Radii.inner` so both curves run parallel.
- **Every palette and skin, light and dark**, keeps the contrast in
  ACCESSIBILITY.md (`skin_theme_contrast_test`). A new surface is checked in
  both modes and in a skin with a picture.
- Icons come from `AppIcons`, one style, at the sizes the theme sets.
- Platform manners are kept where users expect them: window controls,
  menus, shortcuts (Ctrl on Windows and Linux, Cmd on macOS), the back
  gesture on Android, the TV remote's focus.

## 6. UI and UX (界面和体验)

- **Every screen has all its states designed**: loading, loaded, empty,
  error, offline, signed out, and partly loaded. An empty state says why it
  is empty and what to do.
- **Feedback for every action.** A press shows at once (pressed state
  within one frame); a result within 1 s, or a progress mark that says what
  is happening.
- **Errors say what happened and what to do** (`friendlyError`), in the
  user's language, with a retry where retrying can help. The technical
  detail goes to the log.
- **Consistency**: the same thing looks and acts the same everywhere (a
  video card, a channel link, a menu of actions). A new pattern replaces the
  old one everywhere or is not added.
- **Respect the user's place**: back returns to where they were, with the
  scroll position and focus; reopening the app restores the page and the
  video's position.
- **Nothing moves under the pointer**: content that loads later does not
  push what the user is about to press. Reserve the space.
- **No surprises**: autoplay, sounds, full screen and opening other apps
  happen only on the user's action or a setting they chose.

## 7. Animation (动画)

- **Motion has a purpose**: show where something came from or went, show a
  change of state, or keep the eye on what moved. No decoration that loops.
- **Lengths and curves from `lib/ui/motion.dart`**: `Ease.press` (120 ms)
  for presses, `Ease.fade` (200 ms) for appearing and fading, `Ease.move`
  (320 ms) for movement; `Ease.curve` or `Ease.out`. Every duration goes
  through `Motion.of`, so the system's reduce-motion setting, Appearance ›
  Motion and frame pressure turn it off.
- **Never block input**: a user can press, scroll or go back while
  something animates; the animation jumps to its end.
- **Only transform and opacity on large areas**, never layout or blur, and
  nothing animates behind playing video.
- **60 fps or nothing**: an animation that drops frames on the slowest
  supported device is shortened or removed (`FramePressure` already does it
  at run time).
- No flashing more than three times a second (WCAG 2.3.1).

## 8. Usability (可用性)

- **Good defaults**: a new user gets a working app with no setup. Every
  setting has a default that suits most people.
- **Undo over confirm**: removing from history, a playlist or the queue is
  undone from the snackbar. A confirmation dialog only for what cannot be
  undone (deleting files, signing out, clearing all), and it names the thing
  and the button says the action ("Delete 12 files"), never "OK".
- **Recognition over recall**: actions are visible or one menu away; a
  shortcut is a second way, never the only way.
- **Forgiving input**: search accepts typos, links of every YouTube form,
  and pasted text with spaces; a wrong value in a field says what is
  expected.
- **Interruptions are safe**: closing the window, losing the network or the
  computer sleeping never loses a download, a half-written comment or a
  setting.
- **Words the user knows**: labels name what the user wants ("Watch later"),
  not how it works ("Queue entry"). No codes or English error names in the
  interface.

## 9. Human factors (人因工程)

- **Targets**: at least 44 × 44 dp on touch screens and 24 × 24 px with a
  pointer (WCAG 2.5.8), with space between them. Often used controls are
  larger and near where the hand or pointer already is; destructive ones are
  apart from them.
- **Response times** (the 0.1 / 1 / 10 s limits): within 0.1 s the press
  shows; within 1 s the result or a progress mark; beyond 10 s a progress
  bar with what is left, and a way to cancel.
- **Choices**: a menu shows the common choices first and keeps rare ones
  under "More". No more than about seven items in a group before it is
  split.
- **Reading**: body text at least 14 px at 100 % (TV: readable from
  3 m), lines no longer than about 80 characters in prose, enough line
  height for CJK and scripts with marks.
- **Viewing distance**: the TV layout is for a remote and a sofa (the
  "10-foot" interface): one clear focus, large type, no hover-only actions.
- **Long sessions**: eye care and dark schedules work as set; nothing
  flickers; the player's controls get out of the way and come back on the
  smallest movement.
- **Attention**: the app does not steal focus, notify, or make sound except
  for what the user asked (a finished download, a live that starts).
- **Errors of habit**: two actions that look alike never sit next to each
  other if one destroys data. Repeated presses do not repeat a one-time
  action (debounce submit, like and subscribe).

## 10. Accessibility (无障碍)

[ACCESSIBILITY.md](ACCESSIBILITY.md) is the full page: WCAG 2.2 AA on every
platform, the rules for new code and the manual checks before a release.
The short form: every control has a name and a role, is reachable by
keyboard and remote, keeps contrast in every palette, works at text ×2, and
never tells anything by colour alone.

## 11. Completeness (完整性)

A feature is done when all of these hold, or the pull request lists what is
left:

- **Every platform** Lumtub ships (Windows, macOS, Linux, Android, Android
  TV, iOS), or the feature is hidden where it cannot work and the reason is
  in the code.
- **Every state** from section 6, and every way to reach it (menu, shortcut,
  link, remote, screen reader).
- **Every language**: strings through `tr`, translated into every
  `assets/l10n` file in the same change.
- **Settings persist** and survive an update; a new saved field has a
  default for files written before it.
- **Undo, cancel and clean-up**: what the feature starts, it can stop; what
  it writes, it can remove (clear cache, sign out, uninstall).
- **Tests** for the logic and for any bug it fixes (section 17).
- **Documentation**: README or the website when users see it, release notes
  for the version, and these pages when a rule changes.

## 12. Reliability and data (可靠性和数据)

- **The user's data is never lost**: library, history, settings, downloads
  and sign-in. Files are written atomically (temporary file, then rename);
  the database uses transactions.
- **Reading old data never fails**: unknown fields are kept or ignored,
  missing ones take defaults, a broken file is set aside (renamed, not
  deleted) and the app starts with defaults and says so.
- **Migrations go one way and are tested** with a file from the previous
  version.
- **Crashes**: a crash leaves a dump and a log the user can attach; the next
  start offers to report it and starts cleanly. A crash loop at start falls
  back to safe settings.
- **Background work survives**: downloads resume after a restart; a failed
  step is retried a bounded number of times and then shown.
- Export and import for what the user builds (subscriptions, playlists,
  settings), in an open format.

## 13. Languages and regions (语言和地区)

- **Layouts grow**: translated text can be 40 % longer than English and CJK
  lines taller. Nothing is clipped at text ×2 in any language.
- **Right-to-left** languages mirror the layout (`Directionality`), except
  media controls and timelines, which stay left to right.
- **Plurals, dates, numbers and durations** come from the locale, never
  built by joining strings.
- Fonts cover every interface language (the script font packs); a missing
  glyph is a bug.
- Content language and interface language are separate settings; subtitles
  and translations follow the user's choice, not the interface's.

## 14. Power and heat (耗电和发热)

- On battery, power saving or Low resource mode: no prefetch, no background
  AI jobs, fewer animations, lower preview quality (PERFORMANCE.md).
- Hardware decoding first; software decoding only when the hardware cannot,
  and the reason is logged.
- Nothing wakes the CPU on a timer while the app is idle, hidden or in the
  tray, except what the user turned on (subscription checks), at a slow
  interval.
- Paused video draws nothing new; a minimised window renders nothing.

## 15. Compatibility and updates (兼容和更新)

- The oldest supported system version of each platform is listed in the
  README and tested in CI where CI can.
- **Updates never break the user's setup**: saved data from any earlier
  release opens (section 12); a removed setting is migrated, not dropped
  silently.
- The self-updater checks the signature, keeps the old version until the
  new one starts, and can be turned off.
- yt-dlp, Deno and other tools update on their own schedule; the app keeps
  working with the previous version when a new one fails its check.
- Behaviour that YouTube may change (clients, formats, challenges) is
  isolated behind one module each, with a fallback and a canary in CI.

## 16. Logs and diagnostics (日志和诊断)

- Log lines are in English, one event per line, with what failed and why.
- **No personal data in logs**: no tokens, cookies, email addresses, full
  file paths in the user's home where a relative one will do, or search
  terms beyond what a bug report needs.
- Logs have a size limit and rotate; the user can open, copy and clear them
  from Settings › About.
- Errors are logged once, where they are handled, not at every level they
  pass.

## 17. Tests (测试)

- **Every bug fix comes with a test** that fails without the fix, unless the
  bug cannot be reproduced in a test; then the pull request says why.
- Logic is tested where it lives: Rust with `#[test]`, Dart with
  `flutter test`. Parsers of outside data also get a fuzz target.
- Pages are tested at phone, tablet, TV, small window and full HD sizes,
  at text ×2, light and dark.
- Tests are deterministic: no real network, no wall-clock sleeps, no order
  dependence. A flaky test is fixed, never retried until green.
- What CI cannot test (GPU playback, real TVs, screen readers) is listed in
  the pull request with what was checked by hand.

## 18. Dependencies and licences (依赖和许可)

- A new dependency needs a reason a small amount of our own code could not
  meet, is maintained, has a compatible licence, and is pinned (lockfile,
  hash or commit). New versions wait the cooldown week (`cooldown.py`,
  Dependabot).
- Code taken from other projects (PiliNara, mpv shaders, vendored plugins)
  keeps its licence header and is listed in `NOTICE`.
- Every third-party licence that ships in a package is shown in Settings ›
  About.

## 19. Package size and install (安装包)

- A change that grows a package by more than 1 MB says by how much and why
  in its pull request.
- Optional parts (ffmpeg, AI models, data packs, script fonts) download on
  demand, with their size shown before the download.
- Install, update and uninstall need no administrator rights where the
  platform allows; uninstall offers to remove the user's data and removes
  everything else.

## Pull request checklist (提交前自查)

- [ ] Performance: limits kept, nothing slow on the UI thread, numbers for a
      speed change.
- [ ] Security and privacy: SECURE-CODING rules; nothing new leaves the
      device unasked.
- [ ] Network: timeouts, bounded retries, cancelled on leave, works offline.
- [ ] Every state of every screen it touches is designed.
- [ ] Design tokens only; checked light, dark and with a skin.
- [ ] Animations through `Motion.of`; nothing blocks input.
- [ ] Accessible: names, focus, contrast, text ×2.
- [ ] All platforms and all languages, or the gap is listed.
- [ ] Saved data from the last release still opens.
- [ ] Tests, including one for each bug fixed.
- [ ] Code style checks pass (Checks › Analyze and Scripts).
