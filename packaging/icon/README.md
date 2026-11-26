# App icons

`make_icons.py` draws the three icons in code and writes them as `lumtub-classic.svg`, `lumtub-tabor.svg` and `lumtub-gold.svg`. Change the drawing there, not in the SVGs, then run

    python3 packaging/icon/make_icons.py --export

to render every file below with Chromium (Playwright for Node and Pillow are needed).

- **Classic** (default): mint tile with a dark play button.
- **Light of Tabor**: the mandorla of Transfiguration icons, darker toward the centre, with three rays from the play button.
- **Gold ground**: the gold ground of Byzantine icons with a lapis nimbus and a gold play button.

Classic is the program's own icon everywhere. The other two are chosen under Settings › Appearance › App icon (`AppearanceSettings.appIcon`).

| Platform | Classic | Light of Tabor / Gold ground |
| --- | --- | --- |
| Windows | `windows/runner/resources/app_icon.ico` (`IDI_APP_ICON`) | `app_icon_tabor.ico`, `app_icon_gold.ico` (`IDI_APP_ICON_TABOR`, `IDI_APP_ICON_GOLD`), set on the window and tray at run time |
| Linux | `linux/runner/resources/lumtub.png`, `packaging/aur/lumtub.png` | `lumtub-tabor.png`, `lumtub-gold.png` (256 px, installed to `data/`) |
| macOS | `macos/Runner/Assets.xcassets/AppIcon.appiconset` (824/1024 body with a soft shadow) | `assets/app_icons/tabor-mac.png`, `gold-mac.png`, set as the Dock icon at run time |
| iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` (square, no alpha) | – |
| Android | `mipmap-*/ic_launcher.png`, `drawable-xhdpi/banner.png` | `ic_launcher_tabor.png`, `ic_launcher_gold.png`, `banner_tabor.png`, `banner_gold.png` (launcher aliases `.TaborIcon`, `.GoldIcon`) |
| Settings preview | `assets/app_icons/classic.png` | `tabor.png`, `gold.png` (128 px) |
| Website, cards | `website/public/icon.png`, `favicon.png`, `docs/cards/icon.png` | – |

The Android alias `.SunlightIcon` is left over from an earlier optional icon. It now shows the classic icon and is turned off at start, so installs that had it chosen keep a launcher entry through the update.
