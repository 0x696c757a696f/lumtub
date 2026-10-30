<div align="center">

# ▶ Lumtub

### YouTube, native on Windows.

**No browser. No Electron. No web player.** Just Flutter, libmpv and yt-dlp, running on your own PC.

[![Build](https://github.com/0x696c757a696f/lumtub/actions/workflows/build.yml/badge.svg)](https://github.com/0x696c757a696f/lumtub/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/0x696c757a696f/lumtub?include_prereleases&label=release)](https://github.com/0x696c757a696f/lumtub/releases)
![Windows](https://img.shields.io/badge/Windows-x64%20%7C%20x64--v3%20%7C%20ARM64-0078D4?logo=windows)
![Flutter](https://img.shields.io/badge/Flutter-UI-02569B?logo=flutter)
![Rust](https://img.shields.io/badge/Rust-core-B7410E?logo=rust)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-EA4AAA?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/0x696c757a696f)

[Why Lumtub](#why-lumtub) · [Features](#features) · [Install](#install) · [Privacy](#privacy) · [Building](#building) · [Support](#support) · [License](#license-and-attribution)

</div>

---

## Why Lumtub

| | |
|---|---|
| 🎞️ **Real player** | libmpv with hardware decoding, not a browser tab. Smooth 4K and HDR, low CPU. |
| 🪶 **Light** | A native app with no Chromium inside. Starts fast and stays out of the way. |
| 🧠 **Your feed, your PC** | The "For you" feed is worked out locally. Nothing about what you watch is uploaded. |
| 🛠️ **Keeps itself working** | yt-dlp and libmpv update themselves, are checked by SHA-256, and roll back if a new one breaks. |
| 📦 **Portable or installed** | Unzip and run, or use the installer. No administrator rights either way. |

> Lumtub was called **YTPlus** until October 2026. Updating keeps your settings, library and sign-in: the data folder is renamed on first launch.

## Features

### 🏠 Browse
- **Home:** continue watching, recently watched, and an endless "For you" feed mixing long-term interests, recent interests, exploration, and popular and new videos. Every card says why it was suggested; any video can be marked "Not interested".
- **Explore:** video and live split into Bilibili-style categories with sub-categories. Sort by For you, Popular, Latest, Hidden gems or Long videos; filter by length, quality (1080p, 4K, HDR), region and language. Categories can be added, hidden, pinned and reordered.
- **Languages:** English and simplified Chinese, following the Windows language. Help translate Lumtub on [Weblate](https://hosted.weblate.org/engage/lumtub/).
- **Search:** suggestions and history, sort order, upload date and length filters, and videos, Shorts, live, channels or playlists only.
- **Channels:** videos, Shorts, live, playlists, podcasts and community posts, with search inside the channel.
- **AI filter (off by default):** hides videos YouTube labels as made with AI and, if you choose, channels on the AI channel lists of [KillSlop](https://killslop.app) (CC BY-SA 4.0) and [AiSList](https://github.com/Override92/AiSList) (CC BY-NC 4.0), downloaded at runtime and not shipped with Lumtub. Subscribed channels are never hidden.
- **Library:** subscriptions, history, local playlists, favorites, watch later and a play queue.

### 🎬 Watch
- Hardware-decoded playback with quality, speed, subtitles (automatic and translated captions too), chapters, fullscreen and keyboard shortcuts.
- Playback strategies: smart, best quality, or lowest resource use, with codecs you can switch off.
- Mini player, borderless picture-in-picture, theater mode, storyboard previews, the "most replayed" heatmap and screenshots.
- Cast to DLNA and Chromecast devices.
- Live chat during broadcasts and replays.
- Windows media controls and a tray icon.
- Optional SponsorBlock, Return YouTube Dislike and DeArrow, all off by default.

### ⬇️ Download
- Downloads through yt-dlp, choosing from the formats the video really has. Video and audio are joined without re-encoding.
- FFmpeg is optional and only downloaded the first time a download needs it.

### 👤 Google account (optional)
- Sync subscriptions and playlists, like or dislike, comment and reply, save to YouTube playlists, and subscribe on YouTube when you follow a channel.
- Uses your own Google OAuth client (see [Google sign-in](#google-sign-in)). Credentials stay on your PC, encrypted with Windows DPAPI.

### ⚙️ And more
- Proxy: follow the system, none, or a manual HTTP / SOCKS5 proxy.
- Light and dark themes, accent colours, fonts and card sizes.
- Optional channel block lists: block a channel, or just stop it being recommended.
- Settings can be exported, imported and reset.

## Install

1. Get the portable ZIP or the installer from [Releases](https://github.com/0x696c757a696f/lumtub/releases), or from the latest **Build** run on the Actions page:

   | Package | For |
   |---|---|
   | `x64-v3` | CPUs with AVX2, most from 2015 on |
   | `x64` | Older x64 CPUs |
   | `arm64` | Windows on ARM |

2. Unzip and run `lumtub.exe`, or run the installer.
3. The first start downloads yt-dlp and Deno, so it needs access to GitHub. Updates are checked at most once a day and apply after a restart.

**Where data lives:** `%LOCALAPPDATA%\Lumtub` for the installed app; the `userdata` folder next to `lumtub.exe` for the portable ZIP. Delete `portable.txt` to make a portable copy use `%LOCALAPPDATA%` instead; a copy in a folder it cannot write to does so by itself. The log is `logs\lumtub.log`, and Settings › About can copy diagnostics.

### Google sign-in

1. In Google Cloud Console, create an OAuth client of type "Desktop app" and enable YouTube Data API v3.
2. Enter its client ID and secret under Settings › Google account and sign in. To build them in instead, set the repository secrets `YTPLUS_GOOGLE_CLIENT_ID` and `YTPLUS_GOOGLE_CLIENT_SECRET`.
3. A client you create yourself is not reviewed by Google, so sign-in may warn that the app is unverified; continue past it.

## Privacy

🔒 Recommendations, history, searches and "Not interested" never leave your PC. Lumtub never reads your browser's cookies or profiles. The optional cookie sign-in (for liking, voting and commenting on community posts) opens a separate temporary browser window, keeps only the youtube.com cookies, encrypts them on your PC and deletes that window's data. Videos play straight from YouTube by default. If you choose a Piped or Invidious server under Settings › Playback, or Lumtub falls back to one because YouTube refused, that server knows which video you watch.

## Building

Every push and pull request to `main` builds on GitHub Actions (`.github/workflows/build.yml`). For each of x64, x64-v3 and arm64 it:

- bundles a verified libmpv for that CPU;
- builds and tests the Rust core in `native/lumtub_core` (fat LTO, one codegen unit, `target-cpu=x86-64-v3` for x64-v3);
- runs `flutter analyze` and the unit tests;
- uploads a portable ZIP and an Inno Setup installer.

Pushing a `v*` tag (such as `v0.2.0`) also publishes them as a GitHub release.

`lumtub_core.dll` is optional at run time. Without it Lumtub still works, minus what it adds (for now: stopping yt-dlp also stops the ffmpeg and Deno it started, and none of them outlive Lumtub).

Building locally needs Flutter 3.47, Visual Studio with the C++ desktop workload, and Rust:

```powershell
flutter pub get
flutter test
flutter build windows --release
cargo build --release --manifest-path native/lumtub_core/Cargo.toml
```

### Translations

[![Translation status](https://hosted.weblate.org/widget/lumtub/svg-badge.svg)](https://hosted.weblate.org/engage/lumtub/)

Lumtub is translated on [Weblate](https://hosted.weblate.org/engage/lumtub/), which offers free hosting to open-source projects. Source strings are written in simplified Chinese and wrapped in `tr('…')`; translations live in `assets/l10n`. See [TRANSLATING.md](TRANSLATING.md).

## Known limits

- Windows only for now; macOS and Linux are planned.
- YouTube changes can break search or playback until yt-dlp catches up, usually within days.
- Liking, voting and commenting on community posts need the optional cookie sign-in; the official API cannot do them.

## Support

<div align="center">

**Lumtub is free, open source, ad-free and collects nothing.**<br>
If it saves you time, sponsoring keeps it updated: development time, test devices and a code-signing certificate.

<a href="https://github.com/sponsors/0x696c757a696f"><img src="https://img.shields.io/badge/Sponsor_on_GitHub-%E2%9D%A4-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor on GitHub" height="40"></a>

Monthly or one-time, any amount. The same page is under Settings › About › Support development in the app.

</div>

<details>
<summary><b>Crypto</b> (check that the coin and network match the address; funds sent on the wrong chain cannot be recovered)</summary>

| Coin | Network | Address |
|---|---|---|
| ETH · USDC · USDT | Any EVM chain (Ethereum, Arbitrum, Base, Optimism, Polygon, BNB Chain…) | `0x619FeeF5986b9ed8E75D7CFD67AdB575355b9F80` |
| BTC | Taproot | `bc1p7jf7pzep76cld4pd6xmtfjckpn6qamdqc2rhjus64re2cvuc72sqdwszqc` |
| BTC | Native SegWit | `bc1q4rp3ag5lmnyy8eqwjm9s4xx62uulfr6n43ycvc` |
| BTC | Nested SegWit | `3Lu1yzQYfNZLpvh2dt6T6NuRbtwQkJHmT6` |
| BTC | Legacy | `123mpbi91xQitVkh9oosY4VczFqJB9kjDQ` |
| USDT | Tron (TRC-20) | `TBHXcP2ReM5sqpRDTyrL1UWtcSmYeyrmnB` |
| USDT | Solana (SPL) | `4s6uaauKCgwSNVzb5Lq1kxUe9dpm8V64D6FPw7hTwrQ6` |

</details>

Not spending money helps too: ⭐ star the repository, [report a bug or suggest an idea](https://github.com/0x696c757a696f/lumtub/issues), or [translate Lumtub on Weblate](https://hosted.weblate.org/engage/lumtub/).

## License and attribution

Lumtub is licensed under the GNU General Public License, version 3 or later (`GPL-3.0-or-later`).

The settings tiles in `lib/widgets/pilinara_settings_tiles.dart` are adapted from [PiliNara](https://github.com/Starfallan/PiliNara), copyright its contributors, and remain under GPL-3.0-or-later. Lumtub's interface follows PiliNara's design. `vendor/pilinara-settings/` and `vendor/pilinara-player/` are unmodified PiliNara source snapshots kept for reference; they are not built. `vendor/media_kit_video/` is a copy of media_kit_video with one Windows fix (see its `LUMTUB.md`).

Built on [media_kit](https://github.com/media-kit/media-kit), [mpv](https://mpv.io), [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [FFmpeg](https://ffmpeg.org). The bundled Noto Sans SC font is under the SIL Open Font License 1.1 (`assets/fonts/OFL.txt`); the Phosphor icon fonts are under the MIT License (`assets/fonts/phosphor/LICENSE`). Other packages and runtime components keep their own licenses; review `NOTICE` before redistributing.
