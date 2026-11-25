# Which platforms CI builds

`.github/workflows/build.yml` builds only the packages a change needs. The
first job, "Reuse an earlier build", decides which ones and prints its
reasons in the log.

## Pull requests

A pull request gets the quick checks (`checks.yml`) on every push. It builds
packages only when asked:

| In the newest commit message, or on the PR | What builds |
| --- | --- |
| nothing | no packages, quick checks only |
| `[full]`, or the label `full build` | the platforms whose files that push changed |
| `[ios]`, `[android]`, `[macos]`, `[linux]` or `[windows]` | that platform alone, whatever changed (`[ios] [windows]`: those two) |
| `[all]` or `[showcase]` | every platform |

"Whose files that push changed" comes from `.github/scripts/build_platforms.py`:

- a platform's own folder (`ios/`, `android/`, `macos/`, `linux/`, `windows/`)
  or a vendored package's platform folder (`vendor/media_kit_video/ios/`,
  `vendor/media_kit_libs_ios_video/`) builds that platform;
  `vendor/**/darwin/` builds macOS and iOS;
- release notes, Markdown, `docs/`, `website/`, `packaging/`, other workflows
  and `.github/scripts/` build nothing;
- everything else (`lib/`, `native/`, `assets/`, `pubspec.*`, `build.yml`
  ...) is shared and builds every platform.

A push that merges `main` into the branch usually touches shared files, so
it builds everything: while debugging one platform, name it (`[ios]`).

## main, manual runs, releases

- A push to `main` builds the platforms its files need, as above.
- A manual run (Actions › Build › Run workflow) has a `platforms` choice:
  `all` or one platform.
- The daily run and release tags (`v*`) always build every platform; a
  release publishes only a build with every package.
- Each AppImage carries `gh-releases-zsync` update information, and the
  release publishes a `.zsync` beside it, so AppImageUpdate, AppImageLauncher
  and Gear Lever update it by downloading only the changed blocks.

One build runs at a time: a newer run waits for older ones, and a newer push
to a pull request cancels its older run.

A run that finds a passed build of the same files reuses its packages
instead of building again (a release signs that build's packages). Only a
push or daily run on `main`, or a pull request from this repository, counts,
and only when the commit it ran for has exactly those files, `build.yml`
included. A pull request that was behind `main` when it built has other
files than the merge, so `main` builds it again.

## Heavy dependencies are built elsewhere

Nothing that takes long to compile is compiled in this repository's CI.
[lumtub-media-builds](https://github.com/0x696c757a696f/lumtub-media-builds)
builds it on a daily schedule and publishes a release; `build.yml` downloads
the release pinned in `.github/pins.env` and checks its SHA-256. The weekly
upstream run (`.github/scripts/upstream.py`) moves the pins to newer releases.

| Dependency | Built by | Release name | Pins |
| --- | --- | --- | --- |
| libmpv for Linux (x86_64, x86_64-v3, aarch64) | `libmpv.yml` | `libmpv-<date>-<mpv commit>` | `MPV_*` |
| libmpv for iOS (picture in picture patch) | `libmpv-ios.yml`, recipe read from `vendor/media_kit_libs_ios_video/ios` | `libmpv-ios-<MPVKit release>-<recipe hash>` | `IOS_LIBMPV_*` |
| ANGLE for Windows on Arm | `angle-windows-arm64.yml` (vcpkg) | `angle-arm64-windows-<port version>` | `ANGLE_ARM64_*` |

Where a trustworthy ready-made build already exists, it is used directly
instead: libmpv for Windows and Android, MPVKit's other libraries for iOS,
the LGPL FFmpeg for macOS (dfloresc/ffmpeg-macos-builds).

Rules:

- A new heavy dependency gets a workflow in lumtub-media-builds and a pin
  here, never a build step in `build.yml`.
- A dependency whose recipe lives in this repository (the iOS libmpv) is
  named after a hash of the recipe. A change that edits the recipe builds it
  locally once (cached by that hash); after merging, media-builds publishes
  it the next day and the upstream run pins it.
- A pin of `none` means "no release yet": `build.yml` falls back to
  building it here.
- The tools the jobs download (the Flutter SDK, `rustup-init`, `7zr.exe`,
  vcpkg's commit, the Windows libmpv) are pinned in `pins.env` too and
  checked by SHA-256. `lockfiles.yml` moves the Flutter sums with
  `.flutter-version`; the upstream run moves the Windows libmpv.
