# Lumtub 前沿技术路线与顶层设计（2026-11-15）

范围：调研 7 个前沿方向的可行性，把语言学习方案（`plans/language-learning-2026-11-10.md`）并进同一套架构，给出模块划分、端侧 AI 运行时、数据存储和分阶段路线图。本文只是设计，还没有改代码。

> 证据说明：whisper.cpp 各模型体积、sherpa-onnx 支持的模型和平台、Firefox Translations 模型的 MPL-2.0 许可、Moonshine 的 MIT 许可、mpv 0.39 支持 NVIDIA/Intel 超分、iroh 已发布 1.0 这几条是查过原文或发布信息的。其余数字（速度、耗电、其他模型体积）标「估」，是根据对这些项目的了解给出的估计，动手前必须实测（第 9 节列了清单）。

## 0. 结论

1. **Lumtub 已经有一半「AI 骨架」**：AI 总结（`video_summary.dart` + core `insights.rs`）、云端语音识别生成字幕（`speech_subtitles.dart`，Groq/OpenAI 兼容接口）、AI 翻译、AI 内容过滤（`ai_filter.dart`，YouTube 标签 + 名单）、本地推荐（`taste.rs`，TF-IDF）、QuickJS（`js.rs`）、帧插值开关。缺的是**「不联网也能做」的那一层**，以及把这些功能串起来的**统一数据层**。
2. **核心原则：三层提供者，谁可用用谁**。每个 AI 能力都按「系统自带 → 下载的本地模型包 → 用户自己的云端密钥」三层接入，用户可在设置里指定。系统自带的（Apple Foundation Models、Apple SpeechAnalyzer、Android ML Kit 翻译、Windows Copilot+ PC 的端侧模型）零下载；本地包按需下载；云端沿用现有配置。这和语言学习方案「先用系统 TTS」是同一个思路。
3. **端侧运行时只选一套：ggml 家族（whisper.cpp + llama.cpp）**，做成按需下载的组件 `lumtub_ai` 动态库，不链接进 `lumtub_core`、不进安装包。它一套代码覆盖语音识别、摘要/问答、向量嵌入，GPU 走 Vulkan（Windows/Linux/Android）和 Metal（macOS/iOS），没有 GPU 回落到 CPU。翻译另配一个很小的 Bergamot 引擎（MPL-2.0，CPU 快），作为可选包。
4. **统一数据层：一个本地 SQLite 库 `lumtub.db`**（core 里用 rusqlite，带 FTS5 全文检索和向量检索），存字幕全文、摘要、章节、向量、生词本、观看记录。语义搜索、「看得懂的视频」、问这个视频、生词高亮都读同一份「视频文本索引」，不各存一份。
5. **建议顺序**：先做 **M1 统一底座**（包管理 + 数据库 + 任务调度），再做 **M2 端侧字幕**（最实用，也让语言学习工具在没有人工字幕的视频上也能用），然后 **M3 摘要/章节/问视频 + 语言学习第二档**，**M4 语义搜索和推荐**。超分、AV1/HDR 是播放器配置层面的事，成本低，可以穿插随时做。点对点同步放最后。AI 配音识别不建议自己训练检测模型，用现有信号补强即可。

## 1. 现状盘点（代码里已经有的）

| 能力 | 现有实现 | 缺口 |
|------|---------|------|
| 字幕生成 | `speech_subtitles.dart`：yt-dlp 拉最小音频流 → core 按 cluster 切块 → 发到 OpenAI 兼容 `/audio/transcriptions` → core 转 WebVTT | 只有云端，必须有密钥，音频外发 |
| AI 总结 | `video_summary.dart`：core `lumtub_summary_transcript` 切块，长视频先分段笔记再总结，带时间点 | 只有云端；不能追问；不生成章节 |
| 翻译 | Google/DeepL/Microsoft/DeepLX/百度/Libre/AI，`translation_cache.dart` 缓存 | 没有离线翻译 |
| AI 内容过滤 | YouTube「AI 制作」标签 + KillSlop/AiSList 名单 | 没有自动配音（AI 配音音轨）信号 |
| 推荐 | `taste.rs` TF-IDF 本地重排，有推荐原因 | 只看标题等文本词，不懂近义和跨语言 |
| 播放画质 | mpv：插帧、video-sync、缩放算法、硬解探测（`hw_decode.rs`）、编码偏好（`format_policy`） | 没有超分着色器；HDR 视频只有色调映射默认行为 |
| 数据 | 各种 JSON 文件（`library_store.dart` 等），原子写入 | 没有能做全文和向量检索的库 |
| 同步 | 设置导出 v2（含订阅库）、NewPipe 格式导出 | 没有设备间同步 |
| JS | `rquickjs`（yt-dlp 挑战求解） | — |

## 2. 设计原则

1. **安装包不变胖**：AI 运行时、模型、语言包全部按需下载，默认不装。装之前显示体积，设置里能看到占用并一键删除。
2. **默认关闭，按功能开启**：没打开的用户感觉不到它存在（语言学习方案的「学习模式」同理）。
3. **三层提供者**：系统自带 → 本地包 → 云端密钥。同一个功能在不同设备上自动选可用的那一层，界面上标明当前用的是哪一层、是否离线。
4. **隐私分级写在界面上**：「完全本地」「发给你配置的服务」两级，后者首次使用弹提示（沿用现有 AI 讲解的规定）。
5. **结果按视频缓存，算一次用多次**：同一视频的字幕、摘要、向量只算一次，存进数据库，换设备可以靠同步带过去。
6. **遵守 `docs/PERFORMANCE.md`**：AI 任务都有并发上限、后台优先级、用电池时不自动跑（第 6 节给出要加进规范的条目）。
7. **机器生成的数据要标记**：机器字幕、机器翻译、AI 摘要在界面和数据里都标「机器生成」，不和人工字幕同等对待（例如「看得懂的视频」评分里权重更低）。

## 3. 七个方向逐项调研

### 3.1 端侧字幕和翻译（优先级：最高）

**语音识别（ASR）候选**

| 方案 | 许可证 | 模型体积 | 平台 / 加速 | 适合 |
|------|--------|---------|------------|------|
| **whisper.cpp**（ggml） | MIT | tiny 75 MiB、base 142 MiB、small 466 MiB、large-v3-turbo 1.5 GiB，**turbo 的 q5_0 量化版 547 MiB** | Windows/Linux/macOS/iOS/Android；Metal、Core ML、Vulkan、CUDA、OpenVINO | 99 种语言通用，质量好；**主力方案** |
| sherpa-onnx（ONNX Runtime） | Apache-2.0 | SenseVoice-small int8 约 230 MB（估），Moonshine tiny 很小 | 同上 + HarmonyOS；有 Flutter 包 `sherpa_onnx` | SenseVoice 对中/英/日/韩/粤非常快，带标点；还自带 VAD、标点、说话人分离、TTS |
| Moonshine | MIT（旧版非英语非流式模型为非商用许可，要避开） | 从约 1 MB 的微型模型到超过 Whisper Large V3 的大模型（官方说法） | 偏移动端、流式 | 英语直播实时字幕候选 |
| Apple SpeechAnalyzer（iOS 26 / macOS 26） | 系统 | 0（系统下载） | 仅苹果 | 苹果设备上的「系统自带」层 |
| Android 系统识别 | 系统 | 0 | 主要面向麦克风输入，不方便喂文件音频 | 不采用 |

**建议**：主力用 whisper.cpp（和 llama.cpp 共用 ggml，见第 4.2 节），默认模型分档：

| 档位 | 模型 | 下载体积 | 适用设备（估） |
|------|------|---------|--------------|
| 快速 | base（q5 量化约 60 MB，估） | 约 60 MB | 手机、低配电脑 |
| 标准 | small（q5 约 190 MB，估） | 约 190 MB | 一般电脑、近两年手机 |
| 高质量 | large-v3-turbo q5_0 | 547 MiB | 有独显或 Apple Silicon 的电脑 |

配合 Silero VAD（MIT，约 2 MB）先切掉静音和音乐，减少幻觉并加速。中日韩粤视频可选 SenseVoice 包作为加速方案，但第一版只做 whisper.cpp，避免两个运行时。

**速度和耗电（估）**：large-v3-turbo 在中端独显上约 20–50 倍实时（10 分钟视频 15–30 秒），Apple M 系列 Metal 上约 10–30 倍；small 在手机 CPU 上约 2–5 倍实时。所以**不做「边播边识别」，而是「播放前整段识别、按句流式出字幕」**：先识别前 2 分钟让字幕马上出现，后面的在后台继续。直播用流式（Moonshine 或 whisper 滑窗）以后再说。

**接入方式**：完全复用现有 `speech_subtitles.dart` 的流水线：yt-dlp 拉最小音频流 → core 解码成 16 kHz 单声道（现有 ffmpeg 组件或 core 内 symphonia 解码 Opus/AAC） → `lumtub_ai` 识别 → core `insights.rs` 现有的「识别结果转 WebVTT」。只是把「发到云端」那一步换成本地调用。

**翻译候选**

| 方案 | 许可证 | 体积 | 说明 |
|------|--------|------|------|
| **Bergamot / Firefox Translations** | 引擎 MPL-2.0，模型 MPL-2.0 | 每个语言对约 15–40 MB（估） | CPU 上很快，Firefox 自己在用；覆盖几十种语言，和英语互译为主，中↔日要经英语中转 |
| 系统翻译：Apple Translation 框架、Android ML Kit 翻译 | 系统 | 每语言约 30 MB（估，系统管理） | 免费、离线，苹果和安卓上的「系统自带」层 |
| 本地 LLM 翻译（llama.cpp + Qwen3 等） | Apache-2.0（Qwen3） | 1–3 GB | 质量好、能利用上下文，但慢、耗电；复用摘要模型即可，不单独下载 |
| NLLB-200 | **CC BY-NC（非商用）** | 600M 起 | Lumtub 接受赞助，**不用** |
| MADLAD-400 | Apache-2.0 | 3B 起，太大 | 不用 |

**建议**：翻译层加一个「离线翻译」服务：苹果/安卓先用系统翻译，Windows/Linux 用 Bergamot 包；已经下载了 LLM 的用户可选「本地 AI 翻译」。都接进现有 `Translator` 接口和 `TranslationCache`，界面零改动。

**隐私**：全部本地，音频和字幕不出设备。

### 3.2 AI 摘要、章节、问这个视频（优先级：高）

- **现有基础**：`summarizeTranscript` 已经做了分段笔记再汇总、带时间点。只需要把 `AiTranslator.complete` 换成「提供者」接口，就能接本地模型。
- **本地 LLM 候选**（都走 llama.cpp，GGUF 格式，MIT）：

| 模型 | 许可证 | Q4 体积（估） | 适用 |
|------|--------|-------------|------|
| Qwen3 1.7B | Apache-2.0 | 约 1.1 GB | 手机、轻薄本；摘要够用 |
| Qwen3 4B | Apache-2.0 | 约 2.5 GB | 一般电脑；章节、问答更稳 |
| Gemma 3 系列 | Gemma 使用条款（有使用限制，需核对） | 1–3 GB | 备选，许可证不如 Apache 干净 |
| Apple Foundation Models（iOS 26 / macOS 26，约 3B） | 系统 | 0 | 苹果上的系统层，免费 |
| Android ML Kit GenAI（Gemini Nano） | 系统，部分机型 | 0 | 支持的机型上的系统层 |
| Windows Copilot+ PC 端侧模型（Phi Silica） | 系统，仅 Copilot+ PC | 0 | Windows 上的系统层，覆盖面窄 |

- **章节**：YouTube 自带章节优先（已有）；没有章节的视频，让模型基于带时间点的字幕输出「时间 + 标题」列表，core 校验时间点必须落在字幕里出现过的时间上（防编造），结果作为「AI 章节」画进进度条（复用现有章节显示）。
- **问这个视频**：字幕切成约 30 秒的段，算向量（3.3 节同一个嵌入模型），问题来了取最相关的几段 + 摘要喂给模型，回答必须带 `[mm:ss]`，点击跳转。短视频（字幕少于约 1 万字）直接整段塞进去，不用检索。
- **耗电（估）**：4B 模型在电脑 GPU 上生成一份摘要约 10–30 秒；手机上 1.7B 约 30–90 秒并明显发热。所以手机默认只在用户点按钮时生成，不自动生成。
- **隐私**：本地模型或系统模型时完全本地；选云端时沿用现有提示。

### 3.3 本地语义搜索和推荐（优先级：中高）

- **做什么**：
  1. 「按意思搜我看过的」：在历史、收藏、订阅频道最近视频里，用自然语言搜（「上次那个讲量子计算机纠错的」），跨语言（中文问、英文视频也能找到）。
  2. 推荐：`taste.rs` 现在是 TF-IDF，加一路「向量相似度」信号：用户口味向量 = 近期认真看完的视频向量加权平均，候选视频按相似度加分，推荐原因写「和你看过的《…》相近」。
  3. 去重和聚类：同一事件多个频道的重复视频合并显示（可选）。
- **嵌入模型候选**（都能用 llama.cpp 跑 GGUF，或用 ONNX）：

| 模型 | 许可证 | 体积（估） | 说明 |
|------|--------|-----------|------|
| multilingual-e5-small | MIT | 约 120 MB（int8） | 多语言、轻，手机可用；**首选** |
| Qwen3-Embedding-0.6B | Apache-2.0 | 约 400 MB（Q4–Q8） | 质量更好，电脑上可选 |
| EmbeddingGemma 300M | Gemma 条款 | 约 200 MB | 备选 |
| bge-m3 | MIT | 约 600 MB | 太大，不选 |

- **索引内容**：标题 + 简介前 500 字 + 字幕（若已有）切段。只给「用户接触过的视频」建索引（看过、收藏、稍后看、订阅频道近期），规模几万条，向量 384 维 × 4 字节 ≈ 1.5 KB/条，**5 万条约 75 MB**，可量化到 int8 再降到约 20 MB。
- **检索**：几万条直接暴力点积就够快（毫秒级，Rust SIMD），不需要专门的向量数据库；若要放进 SQLite 统一管理，可用 sqlite-vec 扩展（MIT/Apache，体积小）。全文关键词用 SQLite FTS5，结果和向量结果混合排序。
- **耗电**：建索引是增量的，每看一个视频算几条向量（小模型 CPU 上几十毫秒）；首次给历史补索引只在接电源且空闲时跑。
- **隐私**：完全本地，不需要任何账号。这正是 Lumtub「推荐不被算法绑架」卖点的技术底座。

### 3.4 超分和插帧（优先级：中，成本低）

- **着色器超分**（全部平台，libmpv 的 `glsl-shaders` 选项，media_kit 的渲染路径可用）：
  - Anime4K（MIT）：动画专用，效果最明显。
  - FSRCNNX / ArtCNN / RAVU：真人视频的轻量超分。
  - AMD FSR 的 mpv 着色器移植：通用、开销低。
  - 做法：着色器文件作为一个很小的可选包（几百 KB），设置里给「画质增强」三档：关 / 轻（FSR）/ 强（ArtCNN 或 Anime4K，按视频分类自动选动画或真人）。
- **显卡驱动超分**：mpv 0.39 起支持通过 `d3d11vpp` 滤镜调用 **NVIDIA RTX Video Super Resolution 和 Intel VSR**，效果好、开销由驱动优化。只在 Windows + 支持的显卡上提供，需要实测在 Lumtub 的 d3d11va + ANGLE 零拷贝路径上能不能用（第 9 节）。
- **插帧**：已有 mpv `interpolation` + `display-resample`（是平滑运动，不是生成新帧）。AI 插帧（RIFE、SVP 走 VapourSynth）要额外 Python/VapourSynth 运行时，耗电大，**不做**。
- **耗电**：着色器超分会让 GPU 负载明显上升（估 +10–40%），和「低资源占用优先」策略冲突。规则：用电池时自动关闭，低占用模式下不提供，只对低于屏幕分辨率的视频启用。
- **平台**：手机上只开「轻」档；TV 盒子性能不够，默认不提供。

### 3.5 AI 配音识别和过滤（优先级：低，不建议自研模型）

- **可靠信号（建议做）**：
  1. YouTube 自动配音音轨：yt-dlp 的格式信息会标出自动配音的音轨，语言筛选里排除「AI 配音」直接用它（语言学习线程第 2 项也要它）。
  2. YouTube「经过修改或合成内容」标签：已有（`ai_label`）。
  3. 名单：已有 KillSlop / AiSList。
  4. 用户举报：本地「这是 AI 内容」按钮，把频道加进自己的屏蔽名单（复用屏蔽名单机制）。
- **音频检测模型（不建议现在做）**：学术上的语音伪造检测模型（AASIST 等）在真实 YouTube 音频（背景音乐、压缩、混音）上误报率高，新 TTS 迭代快，模型很快过时；误杀真人频道的代价大于收益。
- **可选的弱信号**：端侧字幕已经算出来时，顺带用 LLM 判断「文案是否像批量生成」作为提示（不自动屏蔽，只标记）。放到很后面。

### 3.6 AV1 硬解和 HDR 色调映射（优先级：中，主要是配置）

- **AV1**：已有硬解探测和「禁用编码」策略。补齐：
  1. 硬解探测结果决定默认偏好：有 AV1 硬解（RTX 30+、RX 6000+、Intel Arc / 11 代以后核显、Apple M3+/A17 Pro+、近年安卓旗舰）就优先 AV1（同画质码率更低，省流量），没有就避开 AV1（dav1d 软解 4K 很耗电）。
  2. 「省电」策略里把这条写成显式规则，设置页显示「本机 AV1：硬件解码 / 软件解码」。
- **HDR**：
  1. **色调映射（建议做）**：Lumtub 的画面经 Flutter 纹理输出，是 8 位 SDR，所以 HDR 视频要在 mpv 里映射到 SDR。打开 `vo=libmpv` 下可用的高质量色调映射（`tone-mapping`、`hdr-compute-peak`）并实测；格式策略里加「HDR 视频：自动 / 优先 SDR 版本」，默认在 SDR 屏幕上优先 SDR 版（YouTube 通常两种都有）。
  2. **真正的 HDR 输出（暂不做）**：需要绕开 Flutter 纹理，让 mpv 直接画到原生子窗口（HDR10 交换链），是播放器架构级改动，且字幕、弹幕叠加都要重做。等 Flutter 引擎支持 HDR 表面再评估。
- **耗电**：AV1 硬解比 VP9 软解省电很多；HDR 色调映射开销小。

### 3.7 点对点同步（优先级：低，放最后）

- **同步什么**：订阅和分组、收藏/稍后看/自建列表、观看进度和历史、生词本、设置（可选），以及可选的「算好的结果」（字幕、摘要，省得另一台设备再算一遍）。
- **传输**：**iroh**（Rust，MIT/Apache，已发布 1.0）：用公钥连设备，自动打洞，打不通时走中继（中继只转加密流量，看不到内容；可用官方中继或自建）。同一局域网直接连。配对用二维码（扫一下交换公钥），不需要账号和服务器。
- **合并**：数据都在 `lumtub.db`。每张表记录变更日志（行 id + 混合逻辑时钟 + 设备 id），同步时交换对方没有的变更，**按字段「后写者赢」**，删除用墓碑。收藏列表顺序这种少数需要合并的，用简单的有序列表规则。现阶段不需要完整的 CRDT 库（Automerge、Loro），数据量和冲突都小。
- **隐私**：数据只在用户自己的设备之间流动，端到端加密；和语言学习方案「生词本不上云」的承诺一致。
- **平台**：iroh 支持全部五个平台；手机后台同步受系统限制，只在打开应用时同步。

## 4. 顶层架构

### 4.1 分层

```
┌──────────────────────── Flutter UI（lib/ui）────────────────────────┐
│ 播放页 · 字幕菜单 · 字幕列表 · 学习面板 · 摘要/章节/问答面板 · 搜索 · 设置 │
└───────────────┬──────────────────────────────────────┬───────────────┘
                │ 服务层（lib/app、lib/*）              │
   ┌────────────┴───────────┐  ┌───────────────────────┴──────────────┐
   │ IntelligenceService     │  │ LearnService（语言学习）              │
   │  能力：transcribe /     │  │  每句暂停·跟读录音·点词查词·生词本·   │
   │  translate / complete / │  │  Anki 导出·看得懂的视频评分           │
   │  embed                  │  └──────────────────────────────────────┘
   │  提供者：系统 / 本地 / 云│  ┌──────────────────────────────────────┐
   └────────────┬───────────┘  │ PackManager（扩展 ToolManager）       │
                │               │  运行时·模型·语言包·着色器包的下载/校验│
                │               └──────────────────────────────────────┘
───────────────── FFI（native_core.dart，JSON 进出，长任务走 isolate + 端口）──
┌──────────────────────────── lumtub_core（Rust，常驻）────────────────────┐
│ 现有：innertube · resolved · relay · cast · danmaku · taste · insights · │
│       subtitles · process_tree · js(QuickJS) · vault · update ...        │
│ 新增：store（SQLite + FTS5 + 向量）· jobs（AI 任务队列/优先级/预算）     │
│       learn（分词·词典·注音·词频）· index（视频文本索引）· sync（iroh）  │
│       audio（解码重采样 16 kHz）· packs（manifest 校验/签名）            │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ dlopen（按需，组件不存在就整组功能置灰）
┌───────────────────────────────┴──────────────────────────────────────────┐
│ lumtub_ai（按需下载的动态库）：whisper.cpp + llama.cpp（共用 ggml）       │
│   后端：Vulkan（Win/Linux/Android）· Metal（mac/iOS）· CPU 回落            │
│ lumtub_mt（可选）：Bergamot 翻译引擎                                       │
│ 系统层（原生壳里的小桥）：Apple Foundation Models / SpeechAnalyzer /       │
│   Translation · Android ML Kit 翻译 / GenAI · Windows 端侧模型             │
└──────────────────────────────────────────────────────────────────────────┘
```

### 4.2 为什么运行时选 ggml，且做成单独的动态库

- **一套覆盖三种能力**：whisper.cpp（识别）和 llama.cpp（生成 + 嵌入）同源，共用 ggml 的 GPU 后端，构建一次、维护一份。ONNX Runtime 也能覆盖，但要再加 LLM 引擎，两套运行时更重。
- **GPU 覆盖面最好**：Vulkan 一个后端覆盖 NVIDIA/AMD/Intel 和大多数安卓 GPU，Metal 覆盖苹果，无需 CUDA（CUDA 运行库动辄几百 MB）。
- **不进安装包**：`lumtub_ai` 预计每平台 10–30 MB（估，含 Vulkan 后端），和 ffmpeg 一样是「首次使用时下载」的组件，按 CPU 指令集分 x64 / x64-v3 / arm64（沿用现有分包方式）。iOS 不能下载可执行代码，**iOS 只能把它编进应用**或只用系统层，这是唯一的平台例外。
- **崩溃隔离**：模型推理在桌面端放进子进程（`lumtub_ai` 带一个小可执行文件，挂进现有 `process_tree`），出错或内存爆掉不拖垮播放器；手机端同进程但跑在独立线程，限制线程数。
- **Rust 绑定**：通过 C API 用 `dlopen` 调用（与 core 现在 dlopen Python.framework 的方式一致），不在 core 里静态链接，core 的体积和编译时间不变。

### 4.3 统一能力接口（Dart 侧）

```dart
abstract class Intelligence {
  Future<Transcript> transcribe(AudioSource audio, {String? language, void Function(TranscriptPart)? onPart});
  Future<String> translate(List<String> lines, String from, String to);
  Stream<String> complete(String system, String prompt, {int maxTokens});
  Future<List<Float32List>> embed(List<String> texts);
}
```

- 每个能力有一张「提供者表」：`system`、`local`、`cloud`，各自报告 `available`、`offline`、`quality` 档位；按用户设置的顺序挑第一个可用的。
- 现有 `SpeechRecognizer`、`AiTranslator.complete`、各翻译服务改成 `cloud` 提供者，行为不变。
- 结果统一带 `origin`（human / youtube-auto / machine-local / machine-cloud），界面和语言学习评分据此区分。

### 4.4 包管理（模型包和语言包共用）

扩展现有 `ToolManager`，统一叫「组件与数据包」：

| 类型 | 例子 | 内容 |
|------|------|------|
| runtime | `lumtub_ai`、`lumtub_mt` | 动态库（按平台和指令集） |
| model | `asr-whisper-small`、`llm-qwen3-4b`、`embed-e5-small`、`mt-en-zh` | GGUF / Bergamot 模型文件 |
| language | `learn-zh`、`learn-ja` | 词典、分词词典、词频（语言学习方案第 4 节） |
| shader | `shaders-upscale` | GLSL 着色器 |

- `manifest.json`：id、版本、类型、`min_app_version`、每个文件的 sha256 和大小、来源 URL、许可证与署名文本、适用平台。
- manifest 用现有发布签名（ML-DSA + Ed25519 的混合签名）校验；数据包不含可执行代码，运行时包只从 Lumtub 自己的 release 下载。
- 模型文件优先放 Lumtub 自己的 release / `ytplus-media-builds`（可控、可签名），过大的模型（> 2 GB，GitHub 单文件上限）从 Hugging Face 原始地址下载但 sha256 写死在签名 manifest 里。
- 下载支持断点续传、国内镜像开关（沿用现有 GitHub 下载重试）。
- 存放：用户数据目录 `packs/<id>/<版本>/`。设置 ›「组件与数据包」统一列出体积、来源、许可证、删除按钮。
- 设备推荐：首次开启某功能时，按探测到的显卡/内存/平台推荐档位（例如 8 GB 内存以下不推荐 4B 模型）。

### 4.5 数据存储：`lumtub.db`

core 新增 `store` 模块（rusqlite，SQLite 静态编进 core，约 1 MB），WAL 模式，所有写入在 core 的后台线程。现有 JSON 文件**不一次性迁移**：新功能先用数据库，旧数据按需搬（历史和进度第一批搬，因为语义搜索要用）。

| 表 | 主要字段 | 用途 |
|----|---------|------|
| `video` | id, title, channel, duration, lang, fetched_at | 视频元数据缓存 |
| `transcript` | video_id, lang, origin, cues（压缩）, model, created_at | 人工/自动/机器字幕全文 |
| `segment` + `segment_fts` | video_id, start_ms, end_ms, text | 字幕切段，FTS5 全文检索 |
| `vector` | owner(video/segment), id, model, dim, data(int8) | 向量，一个模型一份 |
| `summary` / `chapter` | video_id, lang, provider, text / start_ms, title | 摘要和 AI 章节缓存 |
| `watch` | video_id, position, fraction, at | 进度与历史（从现有文件迁来） |
| `vocab` | lang, lemma, reading, status(new/learning/known), example_video, example_ms, added_at | 生词本 |
| `vocab_seen` | lang, lemma, video_id, count | 「看得懂的视频」评分用 |
| `change_log` | table, row, field, hlc, device | 同步用变更日志 |

**视频文本索引（`index` 模块）** 是枢纽：一个视频的字幕（不管来源）进来，就一次性完成切段 → 全文索引 → 向量 → 分词统计（学习模式开着时），供语义搜索、问这个视频、看得懂的视频、生词高亮共同使用。

### 4.6 任务调度（`jobs` 模块）

- 一个全局 AI 任务队列，**同时只跑 1 个重任务**（识别、生成），嵌入这种轻任务另一个队列，最多 1 个。
- 优先级：用户正在看的视频 > 用户点了按钮的 > 后台补索引。
- 播放时把识别线程设为低优先级（沿用 `process_priority.dart`），保证不掉帧；检测到掉帧（`picture_health.dart` 已有数据）就暂停后台任务。
- 用电池、低占用模式、省电模式：后台任务全部暂停，只跑用户主动点的。
- 每个任务可取消，结果增量写库，断了下次接着算。

### 4.7 语言学习如何嵌进来

| 语言学习功能（方案第 10 节排序） | 依赖的底座 |
|------------------------------|-----------|
| 1. 精听/跟读（每句暂停、单句循环、遮住翻译、跟读录音并排回放） | 只依赖字幕时间轴；**有了端侧字幕后，没有人工字幕的视频也能用** |
| 2. 看得懂的视频（人工字幕、排除 AI 配音、认识词占比） | 3.5 节的自动配音信号；`vocab` + `vocab_seen` + `index` 分词统计 |
| 3. 点词查词 + 生词本 + CSV | `learn` 模块（分词/词典，语言包走 4.4 的包管理）；`vocab` 表 |
| 4. AnkiConnect 加卡（配音 + 截图） | 现有 mpv 截图 + ffmpeg 切音频 |
| 5. TTS 朗读、AI 讲解 | 系统 TTS；AI 讲解走 `Intelligence.complete`，**有本地模型时可以完全离线讲解**，不再是唯一外发的功能 |

额外收益：
- 端侧识别可以输出**词级时间戳**（whisper.cpp 支持），精听时可以逐词高亮、点词从那个词开始重播。
- 生词本走点对点同步，手机上看视频收的词，电脑上导出到 Anki。
- 机器字幕标 `origin=machine-local`，「看得懂」评分对其降权（语言学习线程的提醒）。

## 5. 隐私分级

| 功能 | 完全本地 | 可能外发（仅当用户选云端提供者） |
|------|---------|------------------------------|
| 端侧字幕 / 离线翻译 / 本地摘要 / 本地问答 | ✓ | — |
| 系统提供者（Apple/Android/Windows 端侧模型） | ✓（系统端侧） | Apple Private Cloud Compute 等系统云端回落需核实，界面注明 |
| 语义搜索、推荐、生词本 | ✓ | — |
| 云端识别 / 云端 AI 摘要 / AI 讲解（云） | — | 音频或字幕发给用户配置的服务，首次使用提示 |
| 点对点同步 | ✓（端到端加密） | 中继只转加密流量 |
| 包下载 | 只请求固定静态地址，不带用户标识 | — |

## 6. 性能与耗电预算（拟加入 `docs/PERFORMANCE.md`）

| 项目 | 上限（拟） |
|------|-----------|
| 同时运行的重 AI 任务（识别、生成） | **1** |
| 同时运行的嵌入任务 | **1** |
| AI 推理线程数 | 播放时 **物理核数 / 2**，不播放时 **物理核数 − 1** |
| LLM 上下文 | 手机 **4k tokens**，电脑 **16k tokens** |
| 模型常驻内存 | 用完 **60 秒** 后卸载；低占用模式用完立即卸载 |
| 后台补索引 | 只在接电源、窗口空闲且不播放时 |
| 着色器超分 | 用电池时关闭；低占用模式不可用 |
| 包下载同时数 | **1**（与组件更新共用队列） |

## 7. 分阶段路线图

每个阶段都能单独发布、单独停下。

| 阶段 | 内容 | 依赖 | 体量（估） |
|------|------|------|-----------|
| **M0 速赢**（随时穿插） | 自动配音音轨信号接入语言筛选和 AI 过滤；AV1 按硬解自动偏好 + 设置页显示；HDR 视频优先 SDR 版 + 色调映射参数实测；着色器超分包（FSR / ArtCNN / Anime4K 三档）；Windows 上实测 RTX/Intel VSR；语言学习第一档（每句暂停、单句循环、遮住翻译、跟读录音） | 无 | 小 |
| **M1 统一底座** | `PackManager`（扩展 ToolManager，manifest + 签名 + 设置页）；`store`（lumtub.db，先放字幕和进度）；`jobs` 队列；`Intelligence` 接口，把现有云端识别/AI 总结/AI 翻译改成 `cloud` 提供者（行为不变） | 无 | 中 |
| **M2 端侧字幕** | `lumtub_ai` 组件（whisper.cpp，CI 四平台构建 + Vulkan/Metal）；三档 Whisper 模型包 + Silero VAD；流水线换成本地；词级时间戳；Bergamot 离线翻译包；苹果/安卓系统翻译提供者 | M1 | 大 |
| **M3 摘要与学习** | llama.cpp 加进 `lumtub_ai`；本地摘要、AI 章节（时间点校验）、问这个视频；Apple Foundation Models 提供者；语言学习第二、三档（`learn` 模块，中文包 → 日语包，生词本、CSV、AnkiConnect） | M2 | 大 |
| **M4 语义搜索与推荐** | 嵌入模型包；`index` 模块；「按意思搜我看过的」；`taste.rs` 加向量信号；看得懂的视频评分（认识词占比） | M3（共用运行时和索引） | 中 |
| **M5 点对点同步** | `sync` 模块（iroh + 二维码配对 + 变更日志）；同步订阅、进度、生词本，可选同步字幕和摘要缓存 | M1 的 `store` | 中 |
| 以后 | 直播实时字幕（流式识别）；SenseVoice 加速包；神经网络 TTS；文案批量生成的弱提示；HDR 原生输出 | — | — |

建议的起点：**M0 中的语言学习第一档 + M1**，然后 M2。M1 本身对用户不可见，但没有它，M2 以后的每个功能都要各自造一遍下载、缓存和存储。

## 8. 风险

| 风险 | 应对 |
|------|------|
| 模型包很大（几百 MB 到几 GB），用户流量和磁盘 | 默认最小档；下载前显示体积；一键删除；不同功能共用同一个模型 |
| Whisper 幻觉（静音、音乐处编造文字） | Silero VAD 先切静音；结果标「机器生成」；低置信度句子不进生词统计 |
| iOS 不能下载可执行代码 | iOS 只用系统层（SpeechAnalyzer、Foundation Models、Translation），或把 `lumtub_ai` 编进 IPA（体积 +20 MB 左右，估） |
| 手机发热和耗电 | 手机默认只在用户点击时运行；后台只在充电时跑；模型用完卸载 |
| Vulkan 驱动兼容性（老显卡、部分安卓 GPU） | 首次运行做 5 秒自检，失败回落 CPU 并记住 |
| 许可证（NC 模型、Gemma 条款） | 只收 MIT / Apache / MPL / BSD 模型；manifest 写明许可证，CI 校验白名单 |
| 维护负担 | ggml 一套运行时；SQLite 一个库；包管理一套机制；每阶段可停 |

## 9. 动手前要实测和核实的事项

- whisper.cpp base/small 的 q5 量化体积、在 Windows Vulkan、Apple Metal、安卓 Vulkan 上的实时倍率和功耗；Vulkan 后端打包后的体积。
- llama.cpp 与 whisper.cpp 同一份 ggml 合并构建是否可行（版本对齐），还是要两个库。
- Qwen3 1.7B / 4B 的 Q4 GGUF 实际体积和摘要质量（中英日各测几个视频）。
- multilingual-e5-small 的 GGUF/ONNX 体积、中日英跨语言检索质量。
- Bergamot 各语言对的模型体积，中文、日语是否有直连模型。
- mpv `d3d11vpp` 的 NVIDIA/Intel 超分在 Lumtub（libmpv 渲染 API + ANGLE + d3d11va 零拷贝）路径下是否生效。
- Anime4K、ArtCNN、FSR 着色器的许可证文件和在 ANGLE（Windows）、Metal 转译（macOS）、GLES（安卓）上的兼容性。
- yt-dlp 对 YouTube 自动配音音轨的标记字段。
- Apple Foundation Models / SpeechAnalyzer 的最低系统版本与 Flutter 原生桥接方式；Android ML Kit GenAI 支持的机型范围。
- iroh 1.x 在 Android/iOS 上的体积和后台行为；默认中继的使用条款。
- 语言学习方案第 8 节的全部核实项。

## 参考

- whisper.cpp 模型列表和体积：https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md
- whisper.cpp（Metal、Core ML、Vulkan、OpenVINO、iOS/Android 示例）：https://github.com/ggml-org/whisper.cpp
- sherpa-onnx（SenseVoice、Moonshine、Whisper、VAD、平台表）：https://github.com/k2-fsa/sherpa-onnx ；Flutter 包：https://pub.dev/packages/sherpa_onnx
- Moonshine（MIT，旧版非英语模型为非商用许可）：https://github.com/moonshine-ai/moonshine
- Firefox Translations 模型（MPL-2.0）：https://github.com/mozilla/firefox-translations-models ；Bergamot：https://github.com/mozilla/bergamot-translator
- mpv 0.39 支持 NVIDIA RTX 与 Intel VSR：https://www.linuxtoday.com/blog/mpv-0-39-0-released-with-nvidia-rtx-and-intel-vsr-scaling-support/ ；相关 PR：https://github.com/mpv-player/mpv/pull/14155
- Apple Foundation Models 框架：https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/ ；SpeechAnalyzer：https://dev.to/arshtechpro/wwdc-2025-the-next-evolution-of-speech-to-text-using-speechanalyzer-6lo
- iroh 1.0：https://docs.rs/crate/iroh/latest ；https://iroh.computer/blog/the-road-to-iroh-1-0
- 语言学习方案：项目文件 `plans/language-learning-2026-11-10.md`
