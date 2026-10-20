# YTPlus

[简体中文](README.md) · English

YTPlus is a lightweight YouTube client for Windows, built with Flutter, [media_kit](https://github.com/media-kit/media-kit) (libmpv) and [yt-dlp](https://github.com/yt-dlp/yt-dlp). It uses neither Electron nor a web player. Its interface follows [PiliNara](https://github.com/Starfallan/PiliNara), a third-party Bilibili client.

## Features

**Browsing**
- Home: continue watching, recently watched, and a "For you" feed worked out on your computer. It mixes long-term interests, recent interests, exploration, and popular and new videos; it scrolls endlessly, each card says why it was suggested, and any video can be marked "Not interested".
- Explore: video and live halves split into categories, Bilibili style, each with sub-categories. Browse by For you, Popular, Latest, Hidden gems or Long videos, filter by length and quality (1080p, 4K, HDR), and see upcoming streams and replays. Categories can be added, hidden, pinned and reordered.
- Religion & faith: its own entry in Explore, with Traditions, Study, Culture & art and Live tabs. Christianity is split into Catholic, Eastern Orthodox, Protestant and Oriental Orthodox, and Catholic further into the Pope's words, Mass, sacraments, lives of the saints and more. Filter by type and viewpoint; clickbait is left out and each channel shows at most three videos.
- Search: suggestions and history, sort order, upload date and length filters, and videos, Shorts, live streams, channels or playlists only.
- Channel pages: videos, Shorts, live, playlists, podcasts and community posts, with search inside the channel. A post's comments open on the right.
- Subscriptions, history, local playlists and favorites. Alt+← or the mouse back button returns to the previous page.

**Playback**
- libmpv playback with hardware decoding, video and audio quality, speed, subtitles (including automatic and translated captions), chapters, fullscreen and keyboard shortcuts.
- Streams come through Piped by default (the fastest public server is picked automatically), falling back to YouTube directly.
- Optional SponsorBlock, off by default.
- Comments, related videos and descriptions.

**Google account (optional)**
- Sync subscriptions and playlists, like or dislike videos, post comments and replies, save to YouTube playlists, and subscribe on YouTube when following a channel.
- Needs your own Google OAuth client (see below). Credentials are kept on your computer, encrypted with Windows DPAPI.

**Other**
- Interface languages: 简体中文, 繁體中文 and English, under Settings › Appearance › Language.
- Proxy: follow the system, none, or a manual HTTP / SOCKS5 proxy.
- Light and dark themes, accent colours, fonts, card size and more.
- Settings can be exported, imported and reset.

**Blocking**
- Block controversial religious groups (on by default, each can be unticked): videos and channels about Falun Gong, the Church of Almighty God, Shincheonji, the Unification Church, Scientology and others stay out of recommendations, Explore, related videos, search and suggestions. Only a search for a channel's exact name, letter case included, finds that channel.
- Block a channel, or stop recommending one: add it in settings by link or full name, or from the menu on a video card, channel page or the watch page. Channels not recommended still show in searches and follows.

## Privacy

Recommendations, history, searches and "Not interested" stay on your computer and are never uploaded. YTPlus does not read browser cookies. When Piped is used, the Piped server knows which video you watch; to avoid that, choose a direct YouTube connection under Settings › Playback.

## Install and use

1. Download `YTPlus-Windows-x64` from the **Build YTPlus Windows** GitHub Actions workflow, or the installer from Releases.
2. Unzip and run `ytplus.exe`; no administrator rights are needed.
3. The first start downloads yt-dlp and Deno and needs access to GitHub. Updates are checked at most once a day and apply after a restart.

Data lives in the `config`, `data`, `cache`, `components` and `logs` folders under `%LOCALAPPDATA%\YTPlus`. The log is `logs\ytplus.log`; Settings › About can copy diagnostics.

### Google sign-in

1. In Google Cloud Console, create an OAuth client of type "Desktop app" and enable YouTube Data API v3.
2. Enter its client ID and secret under Settings › Google account and sign in. They can also be built in through the repository secrets `YTPLUS_GOOGLE_CLIENT_ID` and `YTPLUS_GOOGLE_CLIENT_SECRET`.
3. A client you create yourself is not reviewed by Google, so sign-in may warn that the app is unverified; continue past it.

## Building

The Windows build runs on GitHub Actions (`.github/workflows/windows.yml`) for pushes and pull requests to `main`, or by hand from the Actions page. It verifies and bundles the latest shinchiro x86_64-v3 `libmpv-2.dll`, runs `flutter analyze` and the unit tests, builds a release and uploads `YTPlus-Windows-x64`. Pushing a `v*` tag (such as `v0.2.0`) also publishes a GitHub release with an Inno Setup installer.

Building locally needs Flutter 3.47 and Visual Studio with the C++ desktop workload:

```powershell
flutter pub get
flutter test
flutter build windows --release
```

### Translations

Interface text is written in simplified Chinese in the code and wrapped in `tr('…')`; English and traditional Chinese live in `lib/l10n/strings_en.dart` and `lib/l10n/strings_zh_hant.dart`. `test/l10n_test.dart` checks that every string has an English translation.

## Known limits

- Windows x64 only, with the x86_64-v3 libmpv build; there is no fallback for older CPUs yet.
- Search or playback can break when YouTube changes; an updated yt-dlp usually fixes it.
- The official API cannot like or comment on community posts.

## License and attribution

YTPlus is licensed under the GNU General Public License, version 3 or later (`GPL-3.0-or-later`).

The settings tiles in `lib/widgets/pilinara_settings_tiles.dart` are adapted from [PiliNara](https://github.com/Starfallan/PiliNara), copyright its contributors, and remain under GPL-3.0-or-later. `vendor/pilinara-settings/` and `vendor/pilinara-player/` are unmodified PiliNara source snapshots kept for reference; they are not built. `vendor/media_kit_video/` is a copy of media_kit_video with one Windows fix (see its `YTPLUS.md`).

The bundled Noto Sans SC font is under the SIL Open Font License 1.1 (`assets/fonts/OFL.txt`). Other packages and runtime components keep their own licenses; review `NOTICE` before redistributing.
