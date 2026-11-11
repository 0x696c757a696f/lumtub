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
