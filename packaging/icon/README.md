# App icon

- `lumtub.svg`: the icon, used at 64 px and larger.
- `lumtub-small.svg`: simpler version for 48 px and smaller (fewer rays, bigger play button with a light rim, no bubbles or sparkles).

Exported files:

| Platform | File |
| --- | --- |
| Windows | `windows/runner/resources/app_icon.ico` (16–48 from the small version, 64–256 from the full one, PNG entries) |
| macOS | `macos/Runner/Assets.xcassets/AppIcon.appiconset` (824 px body on the 1024 px canvas, soft shadow; 16 and 32 from the small version) |
| Linux, AUR | `linux/runner/resources/lumtub.png`, `packaging/aur/lumtub.png` (256 px; update the sha256 in `aur/PKGBUILD` and `aur/.SRCINFO`) |
| Android | `android/app/src/main/res/mipmap-*/ic_launcher.png` (mdpi from the small version), `drawable-xhdpi/banner.png` (320×180 TV banner) |

The SVGs use filters and masks; render them with a browser (Chromium) rather than librsvg, which draws the blurs differently.
