# Sunlight app icon

The optional icon under Settings › Appearance › App icon. The installed program, its shortcuts and package metadata keep the classic icon.

- `lumtub-sunlight.svg`: used at 64 px and larger.
- `lumtub-sunlight-small.svg`: simpler version for 48 px and smaller (fewer rays, bigger play button with a light rim, no bubbles or sparkles).

Exported files:

| Platform | File |
| --- | --- |
| Windows | `windows/runner/resources/app_icon_sunlight.ico` (resource `IDI_APP_ICON_SUNLIGHT`; 16–48 px from the small version, 64–256 px from the full one) |
| Linux | `linux/runner/resources/lumtub-sunlight.png` (256 px, installed to `data/`) |
| macOS | `assets/app_icons/sunlight-mac.png` (512 px, 824/1024 body with a soft shadow, set as the Dock icon at run time) |
| Android | `android/app/src/main/res/mipmap-*/ic_launcher_sunlight.png` (mdpi from the small version), `drawable-xhdpi/banner_sunlight.png` (TV banner) |
| Settings preview | `assets/app_icons/sunlight.png`, `assets/app_icons/classic.png` (128 px) |

The SVGs use filters and masks; render them with a browser (Chromium) rather than librsvg, which draws the blurs differently.
