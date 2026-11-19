# media_kit 1.2.6, patched for Lumtub

Copied from pub.dev (MIT, see LICENSE): `lib/`, `assets/` and the
pubspec without its screenshots, dev dependencies and ffigen settings.
The change, marked "Lumtub" in the code:

- `lib/src/player/native/player/real.dart`: on Linux, `audio-device-list`
  is observed only when a PipeWire server socket exists. Listing audio
  devices starts every audio output mpv has, and libmpv 0.41 as built
  against PipeWire 0.3.48 headers (the Linux AppImage's) crashes in its
  PipeWire output when no server answers: its cleanup calls
  `spa_hook_remove` on a hook never added, which those headers do not
  check. Lumtub also leaves PipeWire out of `ao` on such a system.
- `lib/src/player/native/player/real.dart`: `NativePlayer.requestLogMessages`
  changes the level of libmpv messages passed on while the player runs, so
  switching the log level to debug includes libmpv's notes without a restart.
- `lib/src/player/native/player/real.dart`: `NativePlayer.setProperty` and
  `getProperty` are asynchronous (`mpv_set_property_async`,
  `mpv_get_property_async`, the reply read with the events) and
  `observeProperty` takes the value with the event (`MPV_FORMAT_STRING`), so
  the app's main thread never waits for mpv's core lock: on iOS, where Dart
  runs on the main thread, a busy core froze the app until the system's
  watchdog killed it. Calls made while an event is being handled (observer
  callbacks, on-load hooks) stay synchronous, as events are handled one at a
  time and a reply would never be read there. Pending calls are answered
  when the player is disposed.
