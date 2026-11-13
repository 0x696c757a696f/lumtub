# Performance spec · 性能规范

Every change to Lumtub must keep to the rules below. A change that breaks
one needs a measured reason in its pull request (see
[Measure before and after](#measure-before-and-after-先测再改)).

Lumtub 的每一处改动都要守下面这些规则。要破例，必须在 PR 里给出实测理由（见 [先测再改](#measure-before-and-after-先测再改)）。

The rules come from the earlier performance roadmap, how comparable apps do
it (NewPipe, PipePipe, LibreTube, PiliPlus, SmartTube) and what Lumtub
already measured. Numbers in **bold** are the current limits in the code.

规则来自之前的性能路线图、同类应用（NewPipe、PipePipe、LibreTube、PiliPlus、SmartTube）的做法，以及 Lumtub 自己测过的数据。**粗体**数字是代码里现在的上限。

## 1. Work only for what is on screen 只为屏幕上的东西干活

- Lists are built lazily (slivers, builders). A page never builds every
  item it has loaded.
  列表按需构建（sliver、builder），页面不会一次构建所有已加载的条目。
- A loaded page of results is committed once, not once per item.
  一页结果加载完只提交一次，不逐条刷新。
- Panels, sheets and dialogs (comments, chat, subtitles, AI summary, cast)
  are created when opened and release their controllers, timers and
  subscriptions when closed.
  评论、聊天、字幕、AI 总结、投屏这些面板在打开时才创建，关闭时释放控制器、定时器和订阅。
- Nothing animates or polls while hidden: a closed panel, a minimised or
  tray window, a page under another. Timers stop with what they serve.
  看不见的东西不动画、不轮询：关掉的面板、最小化或在托盘里的窗口、被盖住的页面。定时器随服务对象一起停。
- Prefetch runs only for what the user is likely to open next, and never
  on battery, while a video is playing, or in Low resource mode.
  预取只针对用户很可能马上打开的内容；用电池时、正在播放时、低占用模式下都不预取。

## 2. Budgets 资源上限

| What 项目 | Limit 上限 |
| --- | --- |
| Flutter image cache 图片缓存 | **300 images / 64 MiB**; Low resource **120 / 24 MiB**; cleared when the window hides 窗口隐藏时清空 |
| One remote image 单张网络图片 | **4 MiB**, decoded at the size it is drawn 按显示尺寸解码 |
| Thumbnail downloads at once 同时下载的缩略图 | **6** |
| Home feed sources at once 首页推荐同时请求的来源 | **3** |
| Downloads at once 同时下载 | **2** |
| Player demuxer cache 播放器缓冲 | **60 s / 150 MiB**, `cache-on-disk=no`; with the playback strategy 低资源占用优先 **30 s / 64 MiB** |
| Pending video renders per output 每个画面待渲染帧 | **1**: the newest frame wins 只画最新帧 |
| Retries after a playback failure 播放失败重试 | **3 per 2 min**, recovery counts only after decoded progress 解码前进才算恢复 |
| Skin pictures 皮肤图片 | decoded at window size; none in Low resource mode 按窗口尺寸解码；低占用模式不画 |

A new feature that makes requests or starts processes joins an existing
limit or adds its own, written here. Nothing starts an unbounded number
of requests, processes or timers.

新功能发请求或起进程时，要么用现有上限，要么新增一个并写进这张表。任何东西都不能无上限地发请求、起进程或开定时器。

## 3. Keep the UI thread free 别占 UI 线程

- A frame has 16 ms at 60 Hz. Work that can take more than a few
  milliseconds (parsing large JSON, ranking a long list, reading a folder)
  runs in the Rust core or off the UI isolate. Prefer Rust.
  60 Hz 下一帧只有 16 毫秒。可能超过几毫秒的活（解析大 JSON、给长列表排序、读文件夹）放到 Rust 核心或 UI isolate 之外，优先放 Rust。
- No synchronous file system calls (`listSync`, `readAsStringSync`) on the
  UI isolate outside startup.
  除了启动阶段，UI isolate 上不做同步文件操作（`listSync`、`readAsStringSync`）。
- Rebuild the smallest widget that changed: listen to the specific
  `ValueListenable` or stream, not the whole controller.
  只重建变化的最小部件：监听具体的 `ValueListenable` 或流，不要监听整个控制器。
- No `Opacity` or `BackdropFilter` over large areas. Use an image's own
  `opacity`, `FadeTransition`, or a translucent colour.
  大面积不用 `Opacity` 和 `BackdropFilter`，改用图片自带的 `opacity`、`FadeTransition` 或半透明颜色。
- Never await player calls inside an mpv property callback.
  不在 mpv 属性回调里 await 播放器调用。

## 4. Processes, files and network 进程、文件和网络

- Every yt-dlp, ffmpeg or helper process belongs to the process tree in the
  Rust core, so closing Lumtub ends it. Its output is read with a size cap.
  每个 yt-dlp、ffmpeg 或辅助进程都挂在 Rust 核心的进程树下，Lumtub 关闭时一起结束；读取它的输出要有大小上限。
- Settings and state files are written atomically (temporary file, then
  rename).
  设置和状态文件原子写入（先写临时文件再改名）。
- Responses are read with a size cap. Redirects follow the same host rules
  as the first request.
  读取网络响应要有大小上限；跳转要遵守和第一次请求相同的主机规则。
- Retries are bounded and back off. A permanent failure shows a retry
  button; it doesn't loop in the background.
  重试有次数上限并逐步拉长间隔。永久性失败显示重试按钮，不在后台反复重试。
- Stream addresses expire, so they are never stored on disk.
  视频流地址会过期，不写入磁盘。

## 5. Every device 各设备

- Phones, tablets and TVs follow the same budgets. Low resource mode is
  the lever for weak devices and must stay correct: same features, no
  pictures or decorations, smaller caches.
  手机、平板、电视用同一套上限。低占用模式是弱设备的开关，必须一直可用：功能不少，只是不画图片和装饰、缓存更小。
- Touch targets are at least 44 dp on touch screens; a TV shows focus on
  every control a remote can reach.
  触屏上的点按区域至少 44 dp；电视上遥控器能到的每个控件都要显示焦点。
- Honour the system's reduce-motion setting (`Motion.reduced`).
  遵守系统的“减少动态效果”设置（`Motion.reduced`）。

## Measure before and after 先测再改

A change made for speed or memory compares a baseline and the change on
the same video, network, display mode and quality, and puts the numbers in
the pull request:

为速度或内存做的改动，要在同一视频、同一网络、同一显示模式和画质下对比改前改后，并把数字写进 PR：

| Scenario 场景 | Measure 测量 |
| --- | --- |
| 1080p H.264, hardware decode 硬解 | first frame, dropped frames, CPU, memory (private, working set, GPU) 首帧、丢帧、CPU、内存 |
| 1440p VP9, hardware and software decode 硬解和软解 | the same, plus GPU 3D, video decode, the picked height and codec 另加 GPU、解码占用、实际分辨率和编码 |
| Resize, full screen, mini player, loop 反复切换窗口大小、全屏、小窗 | memory trend, black frames, render queue 内存趋势、黑帧、渲染队列 |
| Long scroll of home and search 首页和搜索长列表滚动 | frame build and raster time, items loaded, image cache size, requests in flight 帧构建和光栅时间、已加载条目、图片缓存、在途请求 |

Lumtub logs most of these already (Settings › About › Error log, the
player's statistics overlay). CI cannot measure GPU playback; those numbers
come from a real machine and are reported as such.

这些数据 Lumtub 大多已经记在日志里（设置 › 关于 › 错误日志、播放器的统计信息浮层）。CI 测不了 GPU 播放，这部分数字要在真机上测，并注明是真机数据。

## Pull request checklist 提交前自查

- [ ] Lists stay lazy; results commit once per page. 列表仍是按需构建，每页只提交一次。
- [ ] New requests, processes and timers have a limit, and stop when their screen goes. 新的请求、进程、定时器都有上限，页面离开就停。
- [ ] No slow work or synchronous file access on the UI isolate. UI isolate 上没有慢操作或同步文件读写。
- [ ] Panels release what they hold when closed. 面板关闭时释放占用的资源。
- [ ] Low resource mode and reduce-motion still work. 低占用模式和减少动态效果仍然有效。
- [ ] For a speed or memory change: before and after numbers. 速度或内存相关改动附上前后数据。

## Known gaps 已知差距

Places where the code does not yet meet this spec, most important first.
Each is fixed in its own change; remove the line when it is.

代码里还没达到本规范的地方，按重要程度排列。逐条单独修，修完就删掉对应行。

1. Storyboards read whole response bodies; playlist covers and hover frames bypass the thumbnail cache and its limits (`lib/storyboard.dart`, `lib/ui/pages/library_pages.dart`).
   故事板预览图整段读取响应；播放列表封面和悬停预览帧绕过了缩略图缓存及其上限。
2. Thumbnails keep loading for cards scrolled off screen.
   卡片滑出屏幕后缩略图仍在继续加载。
3. Redirects are not checked against the host rules in the Rust core (`relay.rs`, `http.rs`).
   Rust 核心里的网络跳转没有按主机规则检查。
4. The player cache defaults (60 s / 100 MiB, 64 MiB on Android) and `demuxer-hysteresis` are untested against a 96 MiB budget; the Windows bridge still calls `glFinish` every frame. Both need measurements first.
   播放器缓冲默认值（60 秒 / 100 MiB，Android 64 MiB）和 `demuxer-hysteresis` 还没按 96 MiB 的目标测过；Windows 渲染桥每帧仍调用 `glFinish`。两项都要先实测。
