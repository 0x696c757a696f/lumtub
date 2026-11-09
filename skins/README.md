# Lumtub skins · Lumtub 皮肤

A skin changes how Lumtub looks: colours, shapes, the window frame, the menu
bar, cards, buttons, the player and decorations such as bubbles or a neon
grid. A skin is one text file, `skin.jsonc`, plus any fonts or pictures it
uses. Anyone can make one, and no programming is needed.

皮肤决定 Lumtub 的样子：颜色、形状、窗口边框、菜单栏、卡片、按钮、播放器，还有泡泡、霓虹网格这类装饰。
一套皮肤就是一个文本文件 `skin.jsonc`，外加它用到的字体或图片。谁都可以做，不需要会编程。

## Contents 目录

- [Use a skin 使用皮肤](#use-a-skin-使用皮肤)
- [Make a skin 制作皮肤](#make-a-skin-制作皮肤)
- [The file 文件结构](#the-file-文件结构)
- [Avoid these 避坑](#avoid-these-避坑)
- [Check a skin 检查皮肤](#check-a-skin-检查皮肤)
- [Phones, tablets and TVs 手机、平板和电视](#phones-tablets-and-tvs-手机平板和电视)
- [Share a skin 分享皮肤](#share-a-skin-分享皮肤)
- [Built-in skins 内置皮肤](#built-in-skins-内置皮肤)

## Use a skin 使用皮肤

Settings › Appearance › Skins. Pick one; **Standard** goes back to Lumtub's
own look. Choosing a colour scheme or app theme also goes back to Standard.

设置 › 外观 › 皮肤，点一个即可；选 **标准** 回到 Lumtub 原本的样子。选配色方案或应用主题时也会回到标准。

To install someone else's skin, put its folder into your skins folder
(the **Open skins folder** button), so that you have
`skins/<their-skin>/skin.jsonc`. It shows up at once.

装别人做的皮肤：把它的文件夹放进你的皮肤文件夹（点 **打开皮肤文件夹**），变成
`skins/<皮肤名>/skin.jsonc`，马上就会出现。

| System 系统 | Skins folder 皮肤文件夹 |
| --- | --- |
| Windows | `%LOCALAPPDATA%\Lumtub\skins` |
| macOS | `~/Library/Application Support/Lumtub/skins` |
| Linux | `~/.local/share/lumtub/skins` |

Skins that draw their own title bar replace the system's window frame on
computers. **Use the system title bar** on the same page turns that off.
Minimize, maximize and close are always there, on the right; on Windows 11
pointing at maximize still shows the snap layouts.

会自己画标题栏的皮肤，在电脑上会替换系统的窗口边框。同一页的 **使用系统标题栏** 可以关掉它。
最小化、最大化、关闭三个按钮一直都在右上角；Windows 11 上把鼠标放到最大化按钮上照样会出现贴靠布局。

## Make a skin 制作皮肤

1. Settings › Appearance › Skins › **New skin**. Lumtub copies
   [`template/skin.jsonc`](template/skin.jsonc) into a new folder in your
   skins folder and opens it.
   点 **新建皮肤**，Lumtub 会把样板复制到皮肤文件夹里的新文件夹并打开它。
2. Open `skin.jsonc` in any text editor. VS Code is a good choice: thanks to
   the `"$schema"` line it completes names and underlines mistakes.
   用任何文本编辑器打开 `skin.jsonc`。推荐 VS Code：有 `"$schema"` 这一行，它能自动补全、标出错误。
3. Change `"id"`, `"name"` and colours, and save. Lumtub shows every change
   the moment you save, so keep it open next to the editor.
   改 `"id"`、`"name"` 和颜色，保存。每次保存 Lumtub 立刻显示效果，可以开着它边改边看。
4. Look under **Problems found** at the bottom of the Skins page.
   看皮肤页最下面的 **发现的问题**。

The template explains every field in English and Chinese. Start from it, or
from a built-in skin in this folder that is close to what you want.

样板里每个字段都有中英文说明。可以从样板开始，也可以从这个文件夹里风格接近的内置皮肤改起。

## The file 文件结构

`skin.jsonc` is JSON that allows `//` and `/* */` comments and trailing
commas. Only `lumtubSkin`, `id`, `name` and `brightness` are required; leave
anything else out and Lumtub draws it the usual way.

`skin.jsonc` 是允许 `//`、`/* */` 注释和结尾逗号的 JSON。必填的只有 `lumtubSkin`、`id`、`name`、
`brightness`，其余不写就按默认样子画。

| Part 部分 | What it is 是什么 |
| --- | --- |
| `brightness` | `light`, `dark`, or `auto` to follow light/dark mode with `overrides.dark`. 浅色、深色，或 `auto` 跟随模式。 |
| `colors` | Page, text, muted text, accent, borders, cards, selection, `chrome` for the bars. 底色、文字、强调色、顶栏侧栏底色等。 |
| `text` | `font`, `displayFont` (headings, logo), `monoFont` (times). 字体。 |
| `fonts` | Font files in the skin folder: `{ "My Font": "fonts/my.ttf" }`. 自带字体文件。 |
| `shape` | Corner radius of cards, controls and thumbnails. 圆角。 |
| `window.background` | One paint or a list: colours, gradients, a picture, patterns. 窗口背景。 |
| `window.decorations` | `bubbles`, `sparkles`, `perspectiveGrid`, `beam`, `pattern`. 装饰。 |
| `window.titleBar` | The window frame drawn by Lumtub (computers only). 标题栏（仅电脑）。 |
| `window.menuBar` | File, View, Play, Help with Alt keys (computers only). 菜单栏（仅电脑）。 |
| `window.topBar`, `sideBar`, `statusBar` | The search row, navigation, status line; `topBarText` and `statusBarText` colour what is on them. 顶栏、侧栏、状态栏及其文字颜色。 |
| `controls` | Buttons, the main button, chips, fields, navigation. 按钮、标签、输入框、导航。 |
| `cards` | Video cards, panels, the duration badge. 视频卡片、面板、时长角标。 |
| `logo` | The word mark: text, font, gradient, outline, glow, badge. 标志。 |
| `player` | Frame, progress bar; `"style": "lcd"` for a 90s media player display. 播放器。 |
| `overrides` | Changes for `desktop`, `mobile`, `tablet` or `tv`. 按设备覆盖。 |

Colours are `#RGB`, `#RRGGBB` or `#RRGGBBAA` with alpha **last**, as in CSS.
A *surface* (anything boxed) has `fill`, `border`, `bevel`, `radius`,
`shadow`, `gloss`, `glow`, and `hover`, `pressed` and `focused` versions of
itself. The template's header lists every value form.

颜色写 `#RGB`、`#RRGGBB` 或 `#RRGGBBAA`，透明度在**最后**，和 CSS 一样。
*表面*（所有带框的东西）有 `fill`、`border`、`bevel`、`radius`、`shadow`、`gloss`、`glow`，
以及 `hover`、`pressed`、`focused` 三种状态。所有值的写法见样板开头。

[`skin.schema.json`](skin.schema.json) describes the whole format for
editors and checkers.

[`skin.schema.json`](skin.schema.json) 给编辑器和检查工具描述了完整格式。

## Avoid these 避坑

1. **Contrast is checked in pairs.** Lumtub measures every text and icon
   colour against the surface it is really drawn on, every stop of a
   gradient included: text needs 4.5:1, icons and the accent 3:1. A colour
   that fails is replaced by black or white and listed under Problems
   found. So a white label on a gradient that starts light fails, even if
   it ends dark. Pairs to watch: `colors.text`/`colors.page`,
   `buttonText`/`button`, `primaryButtonText`/`primaryButton`,
   `chipSelectedText`/`chipSelected`, `navText`/`sideBar`,
   `titleBar.text`/`titleBar.surface`, `titleBar.buttons.icon`, `topBarText`/`topBar`, `statusBarText`/`statusBar`,
   `menuBar.text`/`menuBar.surface`.

   **对比度按「一对」检查。** Lumtub 会拿每个文字、图标颜色去比它实际所在的底色，渐变的每一段都算：
   文字要 4.5:1，图标和强调色要 3:1。不合格的会换成黑或白，并列在「发现的问题」里。
   所以浅色开头的渐变上放白字，即使结尾是深色也不合格。

2. **Dark skins: give every surface a foreground.** Icons disappear when a
   light, half-transparent fill lies over a light picture, or when you make
   a background dark but leave its text at the default. Keep translucent
   fills dark in a dark skin, and set the text colour next to each surface
   you add.

   **深色皮肤：每个表面都配好前景色。** 图标看不见，通常是浅色半透明填充叠在浅色图片上，
   或者背景改深了文字却还是默认色。深色皮肤里的半透明填充要保持深色，每加一个表面就写上它的文字颜色。

3. **Warm light (护眼暖色) tints skins too.** It multiplies every colour by
   a warm tint, so blue drops the most and red not at all. Never tell two
   states apart by blue alone; change brightness or shape as well.

   **护眼暖色同样作用于皮肤。** 它给所有颜色乘上暖色，蓝色降得最多，红色不变。
   不要只靠蓝色区分两种状态，同时改亮度或形状。

4. **Low resource mode drops decorations.** `window.decorations` are left
   out to save power. Never put anything the user needs in one.

   **低占用模式不画装饰。** 为了省电会去掉 `window.decorations`，有用的信息不要只放在装饰里。

5. **A picture needs a colour under it.** Always set a solid
   `colors.page`; it shows while the picture loads and if it is missing.

   **图片背景下要有纯色兜底。** 一定要写纯色的 `colors.page`，图片加载中或丢失时会显示它。

6. **Pixel fonts are for big text.** Use them as `displayFont` or for the
   logo and numbers. Body text should stay in the user's font: pixel fonts
   are unreadable at 12 px and most have no Chinese.

   **像素字体只给大字用。** 用作 `displayFont`、logo 或数字。正文保持用户字体：
   12 像素的像素字读不清，而且大多没有中文。

7. **Keep it light.** Blur is not supported, on purpose; gradients, glows
   and a few decorations cost almost nothing. Keep pictures under a few
   megabytes.

   **保持轻量。** 有意不支持实时模糊；渐变、光晕和少量装饰几乎不耗性能。图片尽量控制在几 MB 以内。

8. **Era-inspired, not copied.** Don't copy another product's artwork,
   logos or trademarked look; draw your own take on the era.

   **致敬年代风格，不要照抄。** 不要复制别的产品的图片、标志或商标外观，画你自己的版本。

## Check a skin 检查皮肤

The Skins page lists every warning. From a copy of the source code you can
also run:

皮肤页会列出所有警告。有源代码的话也可以运行：

```sh
SKIN=path/to/your-skin flutter test test/skin_check_test.dart
```

It reads the skin as a computer, phone, tablet and TV would, and fails on
any warning. Every built-in skin passes the same check in CI
(`test/skins_test.dart`).

它会按电脑、手机、平板、电视分别读取皮肤，有任何警告就失败。所有内置皮肤在 CI 里都要通过同样的检查。

## Phones, tablets and TVs 手机、平板和电视

One file serves every device. Lumtub on a phone, tablet or TV ignores
`titleBar`, `menuBar` and window edges, and uses everything else. For what
should differ, add `overrides`:

一份文件通用于所有设备。手机、平板、电视会忽略 `titleBar`、`menuBar` 和窗口边缘，其余照用。
需要按设备区分的，写 `overrides`：

```jsonc
"overrides": {
  "tv": {
    "shape": { "cardRadius": 20 },
    "cards": { "video": { "focused": { "border": { "color": "#0873ad", "width": 4 }, "glow": "#0873ad" } } }
  },
  "mobile": { "cards": { "padding": 4 } }
}
```

Each override is merged into the skin key by key. On TVs there is no
pointer, only a remote, so give cards, buttons and chips a clear
`"focused"` look.

覆盖会逐项合并进皮肤。电视上没有鼠标只有遥控器，所以要给卡片、按钮、标签写明显的 `"focused"` 样式。

## Share a skin 分享皮肤

Zip the skin's folder and share it anywhere. To add it to Lumtub itself,
open a pull request that adds `skins/<id>/` with:

把皮肤文件夹打包成 zip 就能分享。想收进 Lumtub 自带的皮肤，提交一个 PR，添加 `skins/<id>/`，并且：

- `"author"` and a `"license"` that lets us ship it (CC0-1.0 or CC-BY-4.0
  for the skin; fonts under the SIL Open Font License with their licence
  file). 写上作者和允许我们分发的许可证；字体要带 OFL 许可文件。
- No warnings (`test/skins_test.dart` passes). 没有任何警告。
- Names in at least English, and Chinese if you can (`names`,
  `descriptions`). 至少有英文名称，能写中文更好。
- The id added to `builtInIds` in `lib/skins/skin_library.dart` and the
  folder to `assets` in `pubspec.yaml`. 把 id 加进内置列表，文件夹加进 `pubspec.yaml`。

## Built-in skins 内置皮肤

**Colour schemes 配色方案** follow light and dark mode and keep Lumtub's
own shapes; only the colours change. 跟随浅色/深色模式，保留 Lumtub 原本的形状，只换颜色：
`rice-paper` 宣纸, `candlelight` 烛光, `ink-bamboo` 墨竹, `rime` 雾凇, `pine-soot` 松烟,
`night-voyage` 夜航, `dusk-hills` 暮山, `falling-petals` 樱落, `sandstone` 砂岩,
`high-contrast` 高对比.

**Era skins 年代皮肤**:

| id | Name | 名称 | Era 年代 |
| --- | --- | --- | --- |
| `aero` | Bubble Gel | 泡泡凝胶 | glossy aqua and green, 2006–2010 |
| `chrome` | Chrome Cyber | 镀铬赛博 | chrome, neon, perspective grid, ~2000 |
| `candy` | Candy Shell | 糖果壳 | translucent coloured plastic, 1998–2001 |
| `disc` | Disc Menu | 光碟菜单 | DVD and game console menus, ~2002 |
| `messenger` | Millennium Chat | 千禧聊天 | instant messengers, ~2003 |
| `player` | Millennium Player | 千禧播放器 | skinnable media players with an LCD, ~1999 |
| `desktop` | Millennium Desktop | 千禧桌面 | grey bevelled desktops, 1995–2000 |
| `sixteen` | Sixteen Colours | 十六色 | 16-colour desktops, ~1990 |
| `onebit` | One Bit | 黑白点阵 | black and white bitmap screens, ~1984 |
| `platinum` | Platinum | 白金灰 | late-90s platinum grey |
| `handheld` | Handheld | 点阵掌机 | green dot-matrix handhelds, ~1989 |

Fonts in [`fonts/`](fonts/) are under the SIL Open Font License 1.1; each
licence is next to its font.

[`fonts/`](fonts/) 里的字体使用 SIL Open Font License 1.1，许可文件和字体放在一起。
