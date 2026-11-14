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
| `window.decorations` | `bubbles`, `sparkles`, `perspectiveGrid`, `beam`, `waves` (glossy ribbons, `position` 0–1), `pattern`. 装饰。 |
| `window.titleBar` | The window frame drawn by Lumtub (computers only). 标题栏（仅电脑）。 |
| `window.menuBar` | File, View, Play, Help with Alt keys (computers only); `position: "top"` puts it above the title bar, `appMenu` adds a bold app menu first. 菜单栏（仅电脑）；`position: "top"` 放到标题栏上面，`appMenu` 在最前面加粗体应用菜单。 |
| `window.topBar`, `sideBar`, `statusBar` | The search row, navigation, status line; `topBarText` and `statusBarText` colour what is on them. 顶栏、侧栏、状态栏及其文字颜色。 |
| `window.decorations` `scene` | A whole painted landscape behind everything: `meadow`, `sky`, `underwater`, `aurora`, `city`, `collage`; `"night": true` for the night version. 整幅背景景色：草原、蓝天、水下、极光、未来城、千禧拼贴；`"night": true` 是夜晚版。 |
| `window.veil` | 0–0.9 of the page colour laid over the backdrop under the pages, so text reads over a busy picture; it thins when the glass is clearer than `glass.min`. 在页面下面垫一层页面底色，景色再花文字也看得清；玻璃比 `glass.min` 更透明时它会变淡。 |
| `window.glass` | `true` (or `{"min": 0.6}`, the clearest glass at which all text still reads) lets users make the bars, rail, cards and panels clearer, down to 30%, so the background shows through; text must read on the background too. `true` 时用户可以把栏、侧栏、卡片、面板的不透明度调低到 30%，透出背景；`min` 是文字仍然都看得清的最透明程度。 |
| `window.tabs` | Tabs for the pages on a phone or in a narrow window, at the bottom or under the top bar (`position`), with `selected`, `indicator`, `labels: "text"` and `caps`. 手机或窄窗口的页面标签栏，在底部或顶栏下面（`position`），可设 `selected`、`indicator`、`labels: "text"`、`caps`。 |
| `controls` | Buttons, the main button, chips, fields, navigation. 按钮、标签、输入框、导航。 |
| `cards` | Video cards, panels, the duration badge. 视频卡片、面板、时长角标。 |
| `logo` | The word mark: text, font, gradient, outline, glow, badge. 标志。 |
| `icons` | `style`: `regular`/`fill`; `effect`: `none`, `emboss`, `engrave`, `gel`, `glow`. 图标实心与拟物效果。 |
| `controls.press` | `wash`, `ripple` or `glow`: what a click looks like. 点击效果：变暗、水波纹、发光。 |
| `player` | Frame, progress bar; `"style": "lcd"` for a 90s media player display; `"style": "deck"` with `deck` for a player body of its own under the picture (shape capsule, slab, wave, boombox or oval; body colours, screen, gel buttons; the screen text and button signs are checked for contrast). 播放器；`deck` 是画面下方的播放器机身。 |
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
   `chipText`/`chip` (the page where the chip is see-through), `chipSelectedText`/`chipSelected`, `navText`/`sideBar`,
   `titleBar.text`/`titleBar.surface`, `titleBar.buttons.icon`, `topBarText`/`topBar`, `statusBarText`/`statusBar`,
   `menuBar.text`/`menuBar.surface`, `tabs.text`/`tabs.surface`, `tabs.selectedText`/`tabs.selected`.

   **对比度按「一对」检查。** Lumtub 会拿每个文字、图标颜色去比它实际所在的底色，渐变的每一段都算：
   文字要 4.5:1，图标和强调色要 3:1。不合格的会换成黑或白，并列在「发现的问题」里。
   所以浅色开头的渐变上放白字，即使结尾是深色也不合格。

   Links and times in descriptions and comments are text, so they need
   nearly the contrast of `colors.text`, not the accent's 3:1. They take
   `colors.accent` only where it has that on the page and on cards; on a
   skin with a picture behind a veil, or with a dark accent on a dark page,
   they take `colors.text`, underlined in the accent. Pick an accent light
   enough on dark skins (dark enough on light ones) if you want links in it.

   描述和评论里的链接、时间点也是要读的文字，对比度要接近 `colors.text`，不是强调色的 3:1。
   只有强调色在页面和卡片上都够清楚时，链接才用强调色；背景是图片加遮罩的皮肤，
   或者深色页面配深色强调色时，链接改用 `colors.text`，再加一条强调色的下划线。
   想让链接显示强调色，深色皮肤的强调色要够亮，浅色皮肤的要够深。

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
`titleBar`, `menuBar` and window edges, and uses everything else. The
check in [Check a skin](#check-a-skin-检查皮肤) reads the skin as each
device would, so a skin that passes it works on all of them; the points
below are what the check cannot see.

一份文件通用于所有设备。手机、平板、电视会忽略 `titleBar`、`menuBar` 和窗口边缘，其余照用。
[检查皮肤](#check-a-skin-检查皮肤) 会按每种设备读一遍皮肤，通过了就能在各设备上用；下面几条是检查看不出来的。

**Phones 手机**

- The pages are four tabs along the bottom (or under the top bar with
  `"position": "top"`): Home, Explore, Subscriptions and Library. Long
  words are shrunk or scrolled, never cut, but short ones look best.
  页面是底部的四个标签（`"position": "top"` 时在顶栏下）：首页、探索、订阅、媒体库。
  长词会缩小或滚动，不会被截断，但短一点更好看。
- A phone held upright shows only a narrow middle slice of a wide picture,
  because `"fit": "cover"` crops it to fill the screen. Keep what matters
  in the middle third, or say where it is with `"focus": [x, y]` (0 to 1
  from the top left), or give an upright picture just for phones in
  `overrides.mobile`.
  竖着拿手机时，宽图只露出中间窄窄一条，因为 `"fit": "cover"` 会裁切铺满。重要的内容放在中间三分之一，
  或用 `"focus": [x, y]`（0 到 1，从左上角算）指定要保留的位置，或者在 `overrides.mobile` 里给手机单独一张竖图。
- Lists and settings lie straight on `window.background`, under `veil` of
  the page colour. A plain-colour background is checked like any other
  pair; a picture cannot be, so a busy one needs `"veil"` of about 0.5 to
  0.8.
  列表和设置直接画在 `window.background` 上，上面盖一层 `veil` 的页面色。纯色背景会像其他配色一样检查对比度；
  图片没法检查，花哨的图片要把 `"veil"` 设到 0.5 到 0.8 左右。

**Tablets 平板**

- From 720 logical pixels wide the side rail comes back, as on a computer;
  narrower, the phone's tabs. Turning the tablet switches between them, so
  give both `sideBar` and `window.tabs` a look that fits the skin.
  宽度到 720 逻辑像素就改用侧边导航栏（和电脑一样），更窄就用手机的标签栏。平板一转就会切换，所以
  `sideBar` 和 `window.tabs` 都要配好。

**TVs 电视**

- There is no pointer, only a remote, so the focused item is the only
  thing that says where you are. Give cards, buttons, chips and the rail
  a clear `"focused"` look: a 3 to 4 pixel border or a glow in the accent.
  Where a skin gives none, Lumtub adds an accent ring.
  电视没有鼠标只有遥控器，焦点是唯一的位置提示。给卡片、按钮、标签、侧边栏写明显的 `"focused"` 样式：
  3 到 4 像素的边框或强调色光晕。皮肤没写的，Lumtub 会自动加一圈强调色。
- TVs are watched from a sofa. Lines of 1 pixel and small grey text
  disappear; use `overrides.tv` for thicker borders, larger radii and
  stronger contrast.
  电视是坐在沙发上看的，1 像素的线和小号灰字会看不见；用 `overrides.tv` 加粗边框、加大圆角、提高对比度。
- Lumtub keeps the edges of the screen clear itself, for TVs that crop
  them. Don't add your own margin.
  Lumtub 会自己在屏幕四周留出安全边距（有些电视会裁掉边缘），不用再自己加。

**Pictures and fonts on every device 各设备上的图片和字体**

- Lumtub decodes a picture at the size it is drawn, so a large file costs
  only loading time, not memory. 2560 pixels on the long side is plenty.
  Lumtub 按实际显示大小解码图片，大文件只多花加载时间，不多占内存。长边 2560 像素就够了。
- Low resource mode (Settings › Appearance) draws a skin without its
  pictures and decorations. A skin must still read well that way.
  低占用模式（设置 › 外观）下皮肤不画图片和装饰，这时也要能看清。

For what should differ by device, add `overrides`:

需要按设备区分的，写 `overrides`：

```jsonc
"overrides": {
  "mobile": {
    "window": { "background": [{ "image": "pictures/upright.webp", "focus": [0.5, 0.3] }] },
    "cards": { "padding": 4 }
  },
  "tv": {
    "shape": { "cardRadius": 20 },
    "cards": { "video": { "focused": { "border": { "color": "#0873ad", "width": 4 }, "glow": "#0873ad" } } }
  }
}
```

Each override is merged into the skin key by key. The devices are
`desktop`, `mobile`, `tablet` and `tv`.

覆盖会逐项合并进皮肤。设备名是 `desktop`、`mobile`、`tablet`、`tv`。

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
| `ocean` | Ocean Glass | 海洋玻璃 | teal water glass, bubbles and waves |
| `meadow` | Sunny Meadow | 晴空草原 | blue sky, green grass, lens glints |
| `city` | Green Tomorrow | 绿色未来城 | glass towers with terrace gardens, wind turbines and a train over green hills |
| `aurora` | Aurora Glass | 极光玻璃 | dark glass under northern lights |
| `chrome` | Chrome Cyber | 镀铬赛博 | chrome, neon, perspective grid, ~2000 |
| `candy` | Candy Shell | 糖果壳 | translucent coloured plastic, 1998–2001 |
| `disc` | Disc Menu | 光碟菜单 | DVD and game console menus, ~2002 |
| `messenger` | Millennium Chat | 千禧聊天 | instant messengers, ~2003 |
| `player` | Millennium Player | 千禧播放器 | skinnable media players with an LCD, ~1999 |
| `desktop` | Millennium Desktop | 千禧桌面 | grey bevelled desktops, 1995–2000 |
| `sixteen` | Sixteen Colours | 十六色 | 16-colour desktops, ~1990 |
| `onebit` | One Bit | 黑白点阵 | black and white bitmap screens, ~1984 |
| `platinum` | Platinum | 白金灰 | late-90s platinum grey |
| `pinstripe` | Pinstripe Gel | 细条纹凝胶 | early-2000s pinstripes and gel, menus along the top |
| `silver` | Brushed Silver | 银色一体 | late-2000s grey bars joined into one, light menu bar on top, blue-grey sidebar |
| `metal` | Brushed Metal | 金属拟物 | first touch phones: steel, gloss, orange glow |
| `holo` | Ice Neon | 冰蓝霓虹 | dark panels and ice-blue lines, ~2012 phones |
| `paper` | Paper Cards | 纸片阴影 | paper cards, coloured bar and ripples, ~2015 phones |
| `linen` | Linen & Leather | 亚麻皮革 | linen, stitched leather and glass buttons |
| `shelf` | Wooden Shelf | 木纹书架 | wood grain, cream paper, a metal slider |
| `handheld` | Handheld | 点阵掌机 | green dot-matrix handhelds, ~1989 |
| `scholar` | Star Atlas | 学术星图 | star charts, a wireframe globe and gold rules, late-90s encyclopedia discs |
| `softclub` | Soft Club | 柔光俱乐部 | pale teal and lilac haze, the calm side of the late 90s |
| `obsidian` | Obsidian Glass | 黑曜玻璃 | glossy black glass with blue edges, late-2000s media players |
| `hexatron` | Honeycomb Data | 蜂巢数据 | glowing hexagon grids, cyan lines, orange selection, mid-2000s |
| `bento` | Bento | 便当格 | rounded boxes fitted side by side, today's product pages |
| `livingroom` | Living Room | 白色客厅 | white and light grey rounded tiles, late-2000s game consoles |
| `silkwave` | Silk Waves | 丝绸波浪 | a silky wave across a calm colour, late-2000s console menus |
| `flourish` | Flourish | 花藤剪影 | vines, flowers and butterflies from the corners, mid-2000s wallpapers |
| `homepage` | Homepage | 个人主页 | rainbow text, stars and pop-up windows, 2000s personal pages |
| `cassette` | Cassette Future | 磁带未来 | beige hardware, amber terminal text, 1970s–80s visions of the future |
| `clay` | Clay | 软陶 | soft puffy clay shapes, ~2021 |
| `brutal` | Neo-Brutal | 新粗野 | thick black outlines, flat clashing colours, square corners |

Fonts in [`fonts/`](fonts/) are under the SIL Open Font License 1.1; each
licence is next to its font.

[`fonts/`](fonts/) 里的字体使用 SIL Open Font License 1.1，许可文件和字体放在一起。
