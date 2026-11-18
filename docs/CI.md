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
| `[ios]`, `[android]`, `[macos]`, `[linux]` or `[windows]` | that platform alone, whatever changed |
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

One build runs at a time: a newer run waits for older ones, and a newer push
to a pull request cancels its older run.
