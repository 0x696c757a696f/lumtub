# YTPlus for Windows

YTPlus is a lightweight, non-Electron YouTube search and playback app built with Flutter, `media_kit`/libmpv, and `yt-dlp`.

## Features

- Search YouTube and show video cards with channel and duration.
- Play search results or HTTPS YouTube video links in the app.
- Keep the 60 most recent videos in local history.
- On first start, create user-writable `config`, `data`, `cache`, `components`, and `logs` folders under `%LOCALAPPDATA%\\YTPlus`; no administrator rights are required.
- Bundle the latest shinchiro x86_64-v3 `libmpv-2.dll` in the Windows release. The GitHub build replaces media_kit's DLL with this single file.
- Download current `yt-dlp` and Deno releases into versioned app-support folders. SHA-256 digests from GitHub Releases are checked before activation.
- Check `yt-dlp` and Deno for updates in the background no more than once every 24 hours, or from the update button. New versions take effect after restarting YTPlus.

## Build on GitHub

The `.github/workflows/windows.yml` workflow runs on pushes to `main` and can also be started from **Actions → Build YTPlus Windows → Run workflow**. On a Windows GitHub runner it verifies the latest shinchiro x86_64-v3 libmpv release, replaces the old bundled DLL with only `libmpv-2.dll`, analyzes the Flutter sources, runs the unit tests, builds a release version, and uploads the `YTPlus-Windows-x64` artifact. On first launch, YTPlus downloads `yt-dlp` and Deno.

## First launch

First launch creates the YTPlus LocalAppData folders and needs internet access to download `yt-dlp`; it also attempts to install Deno for YouTube JavaScript challenge paths. The current libmpv DLL is included in the release ZIP; newer libmpv builds arrive with a new Windows artifact. A firewall or network restrictions may prevent setup or video playback.

## Limits

- This first version has no Google sign-in, subscription sync, playlist import, or SponsorBlock.
- Search or playback may fail when YouTube changes its extraction requirements or asks for additional verification.
- The app currently targets Windows x64 and the x86_64-v3 libmpv build. There is no baseline x64 fallback yet.
- This is a prototype. The GitHub workflow provides a real Windows build and component-feed check, but video playback still needs a smoke test on a Windows machine.

## License and attribution

YTPlus is licensed under the GNU General Public License, version 3 or later
(`GPL-3.0-or-later`).  The reusable settings tiles in
`lib/widgets/pilinara_settings_tiles.dart` are adapted from
[PiliNara](https://github.com/Starfallan/PiliNara), copyright its contributors,
and remain available under GPL-3.0-or-later.  They have been connected to
YTPlus's existing settings store; no PiliNara Bilibili client, data source, or
storage framework is included.

For traceable, incremental adaptation, `vendor/pilinara-settings/` contains an
unmodified GPLv3 source snapshot of PiliNara's settings module. It is not a
YTPlus build dependency; only adapted components moved into `lib/` are built.

External packages and runtime assets retain their upstream licenses. Review
bundled notices before redistributing the executable.

Upstream components:

- [media_kit](https://github.com/media-kit/media-kit)
- [shinchiro Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [Deno](https://github.com/denoland/deno)
