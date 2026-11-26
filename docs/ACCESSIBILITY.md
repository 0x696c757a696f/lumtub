# Accessibility

Lumtub aims at WCAG 2.2 AA on every platform it ships on (Windows, macOS,
Linux, Android, Android TV, iOS), with the platform guides on top. Flutter
turns the app's semantics tree into each system's own interface: UI
Automation on Windows (Narrator, NVDA, JAWS), NSAccessibility on macOS and
UIAccessibility on iOS (VoiceOver, Switch Control), AccessibilityNodeInfo on
Android (TalkBack, Switch Access, Voice Access) and ATK/AT-SPI on Linux
(Orca). What the app labels is what those tools get.

## What is in place

| Need | How |
| --- | --- |
| Screen readers | Video cards, rows and tiles are one stop each (`SpokenAs`): title, live/upcoming, members only, channel, views, age, length, how much was watched, why it is recommended. The card menu is a custom action. Page and section titles are headers. Errors, empty states, loading, seek/speed/volume feedback are live regions. Settings switches read their title with their state. |
| Player controls | Bars do not hide while a screen reader runs (`Accessibility.screenReader`), while the keyboard focus is in them, or ever when 播放控件显示时间 is set to Never hide. The play button is named by what a press does now. The progress bar is a slider (±5 s). |
| Subtitles | Size, font, colour, opacity, outline, background, bold and position. Read subtitles aloud makes the screen reader say each new line (announcement where supported, a live region on Android); subtitles drawn by libmpv are pixels it cannot read otherwise. |
| Audio description | Described sound tracks (yt-dlp `language` `xx-desc`) are listed in the audio track menu as “(audio description)”. The Audio description setting, or Android 13's system setting, plays them first when a video has one, in the same yt-dlp call. |
| Keyboard and remote | Every control is reachable; Tab walks the top bar, the rail and the page each as a group. Shortcuts can be rebound. Opening a video from a card and coming back gives the card the focus again. The focus ring keeps 3:1 against the page in every palette and skin. |
| Text size | 80–200 % in Appearance, on top of the system's size where Flutter passes it (Windows, Linux/GNOME, Android, iOS; macOS passes none, so the app's own setting is the way there). Layouts that switch at a width switch sooner with larger text (`textGrowth`). |
| Contrast | `skin_theme_contrast_test` checks every built-in skin, light and dark: text 4.5:1, icons and focus 3:1. High Contrast palette, and the system's high contrast mode picks the high contrast theme. |
| Motion | Windows' “Show animations”, the platform's reduce-motion setting, or Appearance › Motion turn animations off everywhere (`Motion.of`). |
| Colour | Live, members-only, chosen items and errors say so in words or shape too, never by colour alone. |

## Rules for new code

1. A control drawn by hand (`GestureDetector`, `CustomPaint`) gets a role and a
   name: `Semantics(button: true, label: …, onTap: …)`, and keyboard focus
   (`FocusableActionDetector` or `InkWell`) when it does something.
2. Every `IconButton` has a `tooltip`; it is also its spoken name. A button
   that toggles is named by what a press does now.
3. A list item that shows several pieces of text is one stop: wrap it in
   `SpokenAs` with the sentence the eye reads. It also keeps the semantics tree
   of a long list small.
4. Something that appears without the user moving to it (an error, a result,
   a state change) is a live region or goes through `Accessibility.announce`.
   Never announce playback time every second.
5. No fixed heights or widths for text: size from `MediaQuery.textScalerOf`,
   `cardTextScale` or `textGrowth`. `narrow_layout_sweep_test` and
   `accessibility_test` run pages at text ×2 on phone, tablet, TV, small window
   and full HD sizes.
6. Text colours come from the theme (`onSurface`, `onSurfaceVariant`,
   `outline`, `linkColor`), not the accent, unless the contrast test covers the
   pair.
7. Animations take their length from `Motion.of`.
8. New strings go through `tr` and into every `assets/l10n` file.

Semantics cost nothing until an assistive tool turns them on; keep it that way
(no work in `build` only for semantics beyond joining a few strings).

## Before a release: manual checks

Automated tests cannot hear a screen reader. Check these by hand on real
devices when the player, cards or settings change:

| Platform / tool | Text size | Focus | Announcements | Subtitles aloud | Playback |
| --- | --- | --- | --- | --- | --- |
| Windows · Narrator | | | | | |
| Windows · NVDA | | | | | |
| Windows · JAWS | | | | | |
| macOS · VoiceOver | | | | | |
| Linux · Orca | | | | | |
| Android · TalkBack | | | | | |
| iOS · VoiceOver | | | | | |
| Android TV · TalkBack | | | | | |
| Android TV · remote only | | | | | |

Known limits: Narrator does not set Windows' screen reader flag, so with
Narrator the controls hide unless 播放控件显示时间 is Never hide. Orca gets
announcements only with ATK 2.46 or newer and no live regions. There is no
tvOS build.
