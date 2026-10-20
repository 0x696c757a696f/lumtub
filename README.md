# YTPlus

简体中文 · [English](README.en.md)

YTPlus 是一个轻量的 Windows YouTube 客户端，用 Flutter、[media_kit](https://github.com/media-kit/media-kit)（libmpv）和 [yt-dlp](https://github.com/yt-dlp/yt-dlp) 写成。它不用 Electron，也不用网页播放器。界面参考了 B 站第三方客户端 [PiliNara](https://github.com/Starfallan/PiliNara)。

## 功能

**浏览**
- 首页：继续观看、最近观看，以及在本机算出的“为你推荐”。推荐结合长期兴趣、近期兴趣、兴趣探索、热门与新视频四路内容，可以无限滚动，每张卡片都写明推荐原因，可以标记“不感兴趣”。
- 探索：按 B 站分区的方式分成视频和直播两部分，每个分区有二级分类（包括宗教信仰、天主教、弥撒、玫瑰经等）。可按为你推荐、热门、最新、冷门宝藏、长视频浏览，也可按时长和画质（1080p、4K、HDR）筛选。分区可以自己添加、隐藏、置顶和排序。
- 搜索：搜索建议和搜索记录，可按排序方式、上传时间、时长筛选，可以只看视频、Shorts、直播、频道或播放列表。
- 频道页：视频、Shorts、直播、播放列表、播客和社区帖子，可以在频道内搜索。帖子的评论显示在右侧。
- 订阅、历史、本地播放列表和收藏。Alt+← 或鼠标侧键可以返回上一页。

**播放**
- 用 libmpv 播放，支持硬件解码、画质与音质选择、倍速、字幕（包括自动生成和自动翻译的字幕）、章节、全屏和键盘快捷键。
- 默认通过 Piped 服务器取视频地址（自动选择最快的公共服务器），失败时直接连接 YouTube。
- 可选空降助手（SponsorBlock），默认关闭。
- 视频评论、相关视频、视频简介。

**Google 账号（可选）**
- 登录后可以同步订阅和播放列表，给视频点赞或点踩、发评论和回复、保存到 YouTube 播放列表，关注频道时同时在 YouTube 订阅。
- 需要你自己的 Google OAuth 客户端（见下文）。凭据用 Windows DPAPI 加密保存在本机。

**其它**
- 界面语言：简体中文、繁體中文、English，可在 设置 › 外观设置 › 语言 切换。
- 代理：跟随系统、不使用代理，或手动填写 HTTP / SOCKS5 代理。
- 浅色和深色主题、强调色、字体、卡片大小等外观设置。
- 设置可以导出、导入和重置。

## 隐私

推荐、历史、搜索记录和“不感兴趣”都只保存在本机，不会上传。YTPlus 不读取浏览器 Cookie。使用 Piped 时，Piped 服务器会知道你在看哪个视频；不想这样可以在 设置 › 播放 里改为直接连接 YouTube。

## 安装和使用

1. 从 GitHub Actions 的 **Build YTPlus Windows** 下载 `YTPlus-Windows-x64`，或从 Releases 下载安装包。
2. 解压后运行 `ytplus.exe`，不需要管理员权限。
3. 第一次启动时会下载 yt-dlp 和 Deno，需要能连上 GitHub。之后每天最多检查一次更新，新版本在重启后生效。

数据保存在 `%LOCALAPPDATA%\YTPlus` 下的 `config`、`data`、`cache`、`components` 和 `logs` 文件夹中。日志在 `logs\ytplus.log`，可以在 设置 › 关于 里复制诊断信息。

### Google 登录

1. 在 Google Cloud Console 创建一个“桌面应用”类型的 OAuth 客户端，并启用 YouTube Data API v3。
2. 在 设置 › Google 账号 里填入客户端 ID 和密钥后登录。也可以在构建时通过仓库 Secrets `YTPLUS_GOOGLE_CLIENT_ID` 和 `YTPLUS_GOOGLE_CLIENT_SECRET` 内置。
3. 自己创建的客户端未经 Google 审核，登录时可能出现“应用未经验证”的提示，选择继续即可。

## 构建

Windows 版本由 GitHub Actions（`.github/workflows/windows.yml`）构建：推送或向 `main` 提交 PR 时运行，也可以在 Actions 页面手动运行。它会校验并打包最新的 shinchiro x86_64-v3 `libmpv-2.dll`，运行 `flutter analyze` 和单元测试，构建发布版并上传 `YTPlus-Windows-x64`。推送 `v*` 标签（如 `v0.2.0`）会同时发布 GitHub Release，附带 Inno Setup 安装包。

在本机构建需要 Flutter 3.47 和 Visual Studio 的 C++ 桌面开发组件：

```powershell
flutter pub get
flutter test
flutter build windows --release
```

### 翻译

界面文字在代码里用简体中文写成，并用 `tr('…')` 包起来；英文和繁体中文在 `lib/l10n/strings_en.dart` 和 `lib/l10n/strings_zh_hant.dart`。新增文字后，`test/l10n_test.dart` 会检查每一条都有英文翻译。

## 已知限制

- 只支持 Windows x64，libmpv 为 x86_64-v3 版本，较老的 CPU 暂无备用版本。
- YouTube 更改接口时，搜索或播放可能失效，通常更新 yt-dlp 后恢复。
- 官方 API 不支持给社区帖子点赞或评论。

## 许可和致谢

YTPlus 以 GNU 通用公共许可证第 3 版或更新版本（`GPL-3.0-or-later`）发布。

`lib/widgets/pilinara_settings_tiles.dart` 中的设置组件改编自 [PiliNara](https://github.com/Starfallan/PiliNara)，版权归其贡献者，同样以 GPL-3.0-or-later 授权。`vendor/pilinara-settings/` 和 `vendor/pilinara-player/` 是未修改的 PiliNara 源码快照，便于对照，不参与构建。`vendor/media_kit_video/` 是带一处 Windows 修复的 media_kit_video 副本（见其中的 `YTPLUS.md`）。

内置字体 Noto Sans SC 以 SIL Open Font License 1.1 授权（`assets/fonts/OFL.txt`）。其它依赖和运行时组件遵循各自的许可证，再分发前请查看 `NOTICE`。
