# Window transparency

What 窗口透明 (Settings › Style › Window transparency) promises, and how
it keeps that promise. Code: `lib/window_glass.dart`,
`lib/ui/glass_look.dart`, the `setDesktopGlass` call in
`windows/runner/window_frame.cpp`, `linux/runner/linux_shell.cc`,
`macos/Runner/MainFlutterWindow.swift` and
`android/.../MainActivity.kt`. Tests: `test/window_glass_test.dart`. CI:
the window glass check in `.github/workflows/build.yml`.

## Promise

With it on, the **desktop** (on a phone or tablet, the wallpaper) shows
through the window, blurred where the system can blur, the way Windows
Vista and 7 showed it through their glass. It works with every skin and
both brightnesses; it is not a skin. Every word on the window stays as
readable as without it, at every setting.

It is not the skins' own glass look (the 玻璃 slider on some skins),
which only lets the skin's own background show through its bars.

## Settings

All in `AppearanceSettings`, shown on the Skins page under Window
transparency when `WindowGlass.possible`:

- `windowGlass` (off by default): on or off.
- `windowGlassClarity` (0.7): how much shows through, 0 to 1. 1 is the
  clearest the skin allows (see Floors), 0 is solid.
- `windowGlassWhole` (off): **Frame only** lets the desktop through the
  title bar, menu bar, top bar, side rail, tabs and status bar, the pages
  stay solid; **Whole window** lets it through the pages too.
- `windowGlassBlur` (on): ask the system to blur what lies behind.

## Platforms

| Platform | Through the window | Blur |
| --- | --- | --- |
| Windows 11 22H2+ | DWM frame over the whole client area | `DWMWA_SYSTEMBACKDROP_TYPE` acrylic |
| Windows 10 1803+ | same | `SetWindowCompositionAttribute` acrylic accent frosted with three quarters of the skin's page colour (its blur is weak) (as the system's own acrylic), plain blur behind while moved or sized (acrylic lags) |
| Windows older | same | DWM blur behind |
| Linux X11 | RGBA visual chosen before the window is realized | KDE: `_KDE_NET_WM_BLUR_BEHIND_REGION` |
| Linux Wayland | RGBA surface | `ext_background_effect_v1` (KDE Plasma 6.7+, GNOME 51+, COSMIC, niri, Hyprland 0.56+), else KDE's `org_kde_kwin_blur` |
| macOS | clear window over an `NSVisualEffectView` | the view's behind-window blur (none: the view is hidden) |
| Android phones and tablets | `BackgroundMode.transparent` + `FLAG_SHOW_WALLPAPER` | Android 12+: `setBackgroundBlurRadius` when cross-window blur is on |

Without blur, Windows 8 and later draw the extended frame solid, so the
window also takes a clear accent (`ACCENT_ENABLE_TRANSPARENTGRADIENT`
with no colour). With Transparency effects off on Windows (Settings ›
Personalisation › Colours) or Reduce transparency on macOS, the system
would draw its blur as a solid colour, so the glass stays clear and
unblurred instead.

Not TVs (no wallpaper behind apps) nor iOS. On Android the transparent
background must be chosen when the activity starts, so a change takes
effect at the next start and the setting says so (`restart`). On Linux
without a compositor nothing shows through and the setting says so.

The runner answers `{shown, blurred, restart}`; the setting shows what
was managed, never what was only asked.

## Readability

The app lays its own tint over what the system lets through
(`withGlass`, `GlassBackdrop`): the skin's page colour at an alpha,
with a faint sheen. Over a desktop that can be any colour, words keep
their contrast in two ways.

**Plates.** Every word and icon on the frame sits on a `GlassPlate`: a
soft halo of the bar's own colour that follows the shapes of the letters
and icons, like the glow behind window titles on Windows 7. The strokes
are widened by 4 px (`GlassPlate.spread`) and blurred (sigma 1.25), so
the halo covers 99% (`GlassPlate.coverage`) one pixel from the ink, 94%
two pixels out, and is gone about 8 px out. It is never a box round the
words: a box over a busy desktop reads as a hard-edged patch. Items
whose surface already has its own face (buttons, selected items) get
none.

**Floors.** `glassFloor(theme, whole:)` is the clearest alpha at which
every writing of the skin (`glassWritings`) keeps its contrast (4.5:1,
3:1 for large) over each of `desktopColors`: greys every 15 steps and
the six pure colours. Clarity 1 is that floor, never below
`glassClearest` (0.3). The frame floor is about 0.3 for most skins; the
pages in whole-window mode have no plates, so their floor is far higher
(0.75 to 1.0) and some skins show little desktop there. That is the
price of readable pages.

Tests check every skin in both brightnesses at clarity 0, 0.5 and 1 in
both modes, and measure the halo round rendered letters: whole next to
them, clear 10 px away.

## Why the first try failed

PR #59 added see-through only to skins with a glass look, and laid the
skin's tint (about 70%) and a veil (about 70%) over the desktop: about
91% opaque, with the bars opaque too, so nothing of the desktop could be
seen. It was never checked on a real desktop.

## CI check

`LUMTUB_GLASS_CHECK=1` (`runGlassCheck` in `lib/app/smoke_check.dart`)
takes six pictures with a magenta window behind Lumtub: glass off,
frame, whole (Aero light, clarity 1, no blur), frame with the system's
blur, and off and frame in Obsidian dark.
`packaging/glass_measure.py` measures magenta ((R + B) / 2 − G) at the
bottom of the side rail and in the middle of the pages, and fails unless
the frame took on magenta (+12), the pages took on none in frame
mode (at most 8 more than without glass, since thumbnails bring magenta
of their own) and took it on in whole mode (+6).
CI machines have no graphics card, and Windows and macOS draw their blur
solid there, so the blurred picture is reported but not required; the
blur itself needs checking on a real machine. Before each picture on Linux, a small window is shown and closed in a
corner so picom draws the whole screen anew (it can show a window one
change late), and the app draws a frame after every runner answer. The
log also shows a coarse map of each picture. Scripts:
`windows/packaging/glass-check.ps1`, `linux/packaging/glass-check.sh`
(picom), `macos/packaging/glass-check.sh`. The pictures are uploaded as
`glass-*` artifacts.
