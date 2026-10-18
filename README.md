# YTPlus for Windows

YTPlus is a lightweight, non-Electron YouTube search and playback app built with Flutter, `media_kit`/libmpv, and `yt-dlp`.

## Features

- Search YouTube and show video cards with channel and duration.
- Play search results or HTTPS YouTube video links in the app.
- Keep the 60 most recent videos in local history.
- Bundle the latest shinchiro x86_64-v3 `libmpv-2.dll` in the Windows release. The GitHub build replaces media_kit's DLL with this single file.
- Download current `yt-dlp` and Deno releases into versioned app-support folders. SHA-256 digests from GitHub Releases are checked before activation.
- Check `yt-dlp` and Deno for updates in the background no more than once every 24 hours, or from the update button. New versions take effect after restarting YTPlus.

## Build on GitHub

The `.github/workflows/windows.yml` workflow runs on pushes to `main` and can also be started from **Actions → Build YTPlus Windows → Run workflow**. On a Windows GitHub runner it verifies the latest shinchiro x86_64-v3 libmpv release, replaces the old bundled DLL with only `libmpv-2.dll`, analyzes the Flutter sources, runs the unit tests, builds a release version, and uploads the `YTPlus-Windows-x64` artifact. On first launch, YTPlus downloads `yt-dlp` and Deno.

## First launch

First launch needs internet access to download `yt-dlp` and Deno. The current libmpv DLL is included in the release ZIP; newer libmpv builds arrive with a new Windows artifact. A firewall or network restrictions may prevent setup or video playback.

## Limits

- This first version has no Google sign-in, subscription sync, playlist import, or SponsorBlock.
- Search or playback may fail when YouTube changes its extraction requirements or asks for additional verification.
- The app currently targets Windows x64 and the x86_64-v3 libmpv build. There is no baseline x64 fallback yet.
- This is a prototype. The GitHub workflow provides a real Windows build and component-feed check, but video playback still needs a smoke test on a Windows machine.

The interface is original Flutter UI, broadly inspired by PiliNara's usability; no PiliNara source code is included. External packages and runtime assets retain their upstream licenses. Review bundled notices before redistributing the executable.

Upstream components:

- [media_kit](https://github.com/media-kit/media-kit)
- [shinchiro Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [Deno](https://github.com/denoland/deno)
