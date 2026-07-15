# llmTools

[![Release](https://github.com/qiupo/llmTools/actions/workflows/release.yml/badge.svg)](https://github.com/qiupo/llmTools/actions/workflows/release.yml)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)
![Chromium MV3](https://img.shields.io/badge/Chromium-MV3-4285F4?logo=googlechrome&logoColor=white)

语言：[English](README.md) | 简体中文

llmTools 是一个原生 macOS 菜单栏助手，用于对选中文本、网页、图片、音视频和桌面音频执行翻译、润色、总结、解释、TODO 提取、模型视觉 OCR、字幕和会议转写。它支持本地模型、远程 LLM Provider，并提供一个开发通道的 Chromium 扩展，通过本地 native bridge 翻译网页。

最新版本：[v0.4.1](https://github.com/qiupo/llmTools/releases/tag/v0.4.1)

## 功能亮点

- 原生 macOS SwiftUI/AppKit 菜单栏应用，支持全局 Quick Action 快捷键。
- 选中文本工作流：翻译、写作润色、总结、解释、TODO 提取。
- 本地模型支持：GGUF、MLX 文本模型，以及 MLX Swift LM 支持的 MLX 视觉语言模型目录。
- 远程 Provider 支持：OpenAI-compatible endpoint 和 Anthropic Messages API。
- Chromium 网页翻译：Manifest V3 扩展加本地 native messaging host。
- 原生图片 OCR、结构化提取、OCR 后翻译、截图/图片解释，使用显式配置的本地或远程视觉能力模型。
- 媒体字幕与桌面实时字幕：本地 ASR 转写、字幕翻译、SRT/VTT/TXT/Markdown 导出。
- Phase 4.x 本地语言/翻译辅助：fastText 语言识别路由、文件字幕说话人分离、字幕/网页 fast MT 路由，以及网页翻译 cache v2 的引擎隔离。
- 独立的本地“会议转写与纪要”窗口：支持麦克风、系统音频、本地音视频，提供文字编辑、说话人修正、中文纪要、恢复草稿和 Markdown/TXT/JSON 导出。
- Quick Action、选择操作、悬浮组件、实时字幕和会议转写窗口都可通过图钉按钮保持置顶。
- 模型能力感知设置：text-only、vision-capable、自动推断、探测结果、手动覆盖。
- 隐私友好的网页诊断：页面/域名只记录 hash，默认不记录原始网页文本。
- GitHub Actions 发布流程：打包 macOS `.app` 并发布 GitHub Release 资产。

## 当前状态

llmTools 仍在持续开发中。当前 `v0.4.1` 版本已经包含桌面 Quick Action、按文本任务选择默认模型、强化后的本地/远程模型配置、本地模型视觉 OCR、Chromium 网页翻译、媒体字幕、原生桌面实时字幕、官方 FunASR Nano + CAM++ 离线说话人管线、本地语言/fast-MT 路由、文件说话人分离，以及全本地会议转写与纪要。

会议转写与低延迟实时字幕是两条独立管线。实时会议支持麦克风或原生系统音频，本地音视频文件走离线处理；`v0.4.1` 不包含麦克风与系统音频混合的会议采集。实时字幕的说话人分离仍然硬禁用：当前 MVP 不持久化 speaker embedding，也不做跨文件说话人身份识别。

Chromium 网页翻译目前仍是开发通道功能：Chrome 和 Edge 可以加载 unpacked extension，但 Chrome Web Store 分发和生产扩展 ID 暂时有意后置。

## 功能与使用方法

| 功能 | 入口 | 使用方法 |
| --- | --- | --- |
| 选中文本 Quick Action | 在其他应用选中文字后按 `Option + Space` | 选择翻译、润色、总结、解释或提取 TODO；需要自动读取选区时授予 Accessibility 权限。 |
| 粘贴文本与文件 | 状态栏菜单 -> `打开快捷操作` 或 `打开悬浮组件` | 粘贴文本/图片或拖入支持的文件，选择任务和模型，然后复制或导出结果。 |
| 图片 OCR 与解释 | 状态栏菜单 -> `图片 OCR` | 先在“设置 -> OCR”选择有视觉能力的本地或远程模型，再粘贴、拖入或选择图片，执行 OCR、结构化提取、翻译或解释。 |
| 网页翻译 | “设置 -> 网页翻译”，然后使用 Chromium 扩展 popup | 修复本地 bridge，把 `browser-extension/chromium` 作为 unpacked extension 加载，授予站点权限，再翻译或恢复当前页。 |
| 媒体字幕 | “设置 -> 媒体”，然后打开媒体导入界面 | 选择本地文件 ASR 和健康的 runtime，导入音视频，转写并按需翻译，最后导出 SRT、VTT、TXT 或 Markdown。 |
| 桌面实时字幕 | 状态栏菜单 -> `开始实时字幕`，或已配置的全局快捷键 | 在“设置 -> 媒体”选择实时本地 ASR，选择麦克风、系统音频或两者混合，通过原生悬浮窗查看字幕。 |
| 会议转写与纪要 | 状态栏菜单 -> `会议转写与纪要` | 在“设置 -> 会议”配置本地模型，开始麦克风/系统音频采集或导入本地音视频，编辑文字与说话人，停止后最终整理、生成本地中文纪要并导出。 |
| 窗口置顶 | 支持窗口右上角的图钉按钮 | 让 Quick Action、选择操作、悬浮组件、实时字幕或会议转写窗口持续位于其他窗口上方；再次点击或退出 app 后取消。 |

## 环境要求

| 范围 | 要求 |
| --- | --- |
| 运行环境 | macOS 14 或更高版本 |
| 构建环境 | 支持 Swift 6 的 Xcode/Swift toolchain |
| 脚本 | Node.js 18 或更高版本，用于扩展检查 |
| 浏览器翻译 | Google Chrome 或 Microsoft Edge，并开启 Developer Mode |
| 本地 MLX 模型 | 打包后的 app 内包含 `mlx.metallib`，或打包时设置 `MLX_METALLIB_PATH` |
| 本地 MLX ASR 安装 | `uv`、Python 3.11 或 3.12，以及兼容的本地语音模型 |
| 选中文本捕获 | 给 llmTools 授予 macOS Accessibility 权限 |
| 实时音频采集 | macOS 麦克风权限和/或 ScreenCaptureKit 屏幕/系统音频捕获权限 |

## 从 Release 安装

1. 从最新 GitHub Release 下载 `llmTools-<version>-macos-arm64.zip`。
2. 解压后，把 `llmTools.app` 移到 `/Applications` 或其他可信目录。
3. 启动应用。如果 macOS 因为 ad-hoc 签名且未 notarize 而阻止首次启动，请使用 Finder 的 Open 流程，或在 System Settings -> Privacy & Security 中允许。
4. 如果需要选中文本捕获，请授予 Accessibility 权限。
5. 如果需要网页翻译，打开 Settings -> `网页翻译`，修复浏览器 bridge，然后按应用显示的路径加载 unpacked Chromium 扩展目录。

Release 还包含这些资产：

- `llmTools-<version>-macos-arm64.zip.sha256`
- `llmTools-<version>-chromium-extension.zip`
- `llmTools-<version>-chromium-extension.zip.sha256`

## 从源码快速开始

```sh
git clone https://github.com/qiupo/llmTools.git
cd llmTools
swift build
```

在这台开发机器上，首次解析依赖可能需要本地代理 helper：

```sh
fish -lc 'setproxy >/dev/null; swift build'
```

运行核心检查：

```sh
swift run LLMToolsChecks
```

打包本地 app：

```sh
./scripts/package-app.sh
open dist/llmTools.app
```

打包产物会写入 `dist/llmTools.app`。

## MLX 运行时资源

本地 MLX 文本模型和本地 MLX 视觉语言模型运行时都需要 `mlx.metallib` 位于可执行文件旁边。如果本机安装了默认位置的 oMLX，打包脚本可以自动复用它内置的资源。也可以显式准备资源：

```sh
./scripts/prepare-mlx-metallib.sh
```

如果资源在其他路径：

```sh
MLX_METALLIB_PATH=/path/to/mlx.metallib ./scripts/package-app.sh
```

缺少 `mlx.metallib` 时，app 仍然可以打包，但 MLX 本地模型会在运行时报错，直到补齐该资源。

本地 MLX 视觉语言模型目录需要包含 MLX-compatible 权重、tokenizer 文件、模型配置，以及 MLX Swift LM 可加载的 vision/processor 配置。应用会根据模型和 processor 文件保守识别可能的本地视觉模型；不支持的本地模型家族应标记为 text-only，或改用远程 vision-capable provider。

## 快捷键

| 快捷键 | 动作 |
| --- | --- |
| `Option + Space` | 打开 Quick Action，并尝试捕获当前选中文本 |
| `Option + Shift + Space` | 打开空输入 Quick Action |

选中文本捕获依赖 macOS Accessibility 权限和当前前台应用行为。如果捕获失败，可以手动粘贴文本，或在系统设置中补充授权。

## 模型与 Provider

Models 设置页使用统一的模型注册表。本地/远程模型、默认模型选择、Quick Action 面板、网页翻译模型选择都会读取这份注册表。

Provider API key 继续保存在 `~/Library/Application Support/llmTools` 下的本地注册表中，llmTools 不使用 macOS Keychain。应用会把该目录权限收紧为 `0700`，把注册表、历史和备份文件收紧为 `0600`；如需更强隔离，请避免共用 macOS 账户，并同步限制文件系统备份的访问权限。

支持的模型和 Provider 类型：

- 本地 GGUF 文件。
- 本地 MLX 文本模型目录。
- MLX Swift LM 支持的本地 MLX 视觉语言模型目录。
- OpenAI-compatible providers：OpenAI、SiliconFlow、DeepSeek、Google Gemini、OpenRouter、Ollama、LM Studio、Together AI、Mistral AI、DeepInfra，以及自定义 endpoint。
- Anthropic Messages API。

## 浏览器网页翻译

当前浏览器集成是本地开发通道：

| 组件 | 位置 |
| --- | --- |
| Chromium 扩展 | `browser-extension/chromium` |
| Native host 可执行文件 | 打包 app 内的 `LLMToolsNativeHost` |
| Bridge 状态 | `~/Library/Application Support/llmTools/web-page-bridge.json` |
| Chrome 开发扩展 ID | `jednddlgkkohaebgoejcidfppddjegij` |
| Edge native manifest | `~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/com.llmtools.native_host.json` |

设置流程：

1. 打包并启动 `dist/llmTools.app`。
2. 打开 Settings -> `网页翻译`。
3. 点击 Chrome 或 Edge 的修复按钮。应用会写入该浏览器的 native messaging manifest，并打开扩展页。
4. 在浏览器中开启 Developer Mode。
5. 加载 Settings 中显示的 unpacked extension 文件夹。可以用 `显示扩展文件夹` 打开准确目录。

Popup 控制包括：直接替换、双语视图、原文视图、可见内容优先或整页翻译、自然/直译/技术质量模式、pending 样式、重新翻译、清理页面/站点/全部缓存，以及站点默认规则。

浏览器诊断默认不包含原始页面 URL、域名、源文本、译文或 DOM 内容。诊断只包含 browser ID、扩展版本、翻译状态、分段数量、耗时、模型名、页面 URL hash、域名 hash、模式设置、不支持嵌入内容数量和稳定错误码。

当前范围：

- 已实现：Chrome 页面翻译、站点规则、缓存控制、阅读模式、质量模式、重新翻译、隐私诊断、Phase 1 回归检查。
- Edge 已实现：Settings 检测、native manifest 修复、打开 `edge://extensions`、可复用浏览器 fixture runner。
- Native app 已实现：文本任务 prompt 加固、输出后续操作、模型能力 badge 和覆盖、OCR 设置、OpenAI-compatible 模型视觉 OCR payload、结构化 OCR、OCR 后翻译、截图/图片解释，以及本地 MLX VLM runner 路径。
- 浏览器翻译暂不包含：Chrome Web Store 分发、生产扩展 ID、Safari/Firefox 支持、浏览器 PDF viewer 翻译、浏览器图片/canvas OCR 翻译、表单写作辅助、多标签批量翻译。

Chrome 不能被 app 静默安装、启用或确认。最终扩展加载和权限弹窗仍由浏览器控制。

原生 OCR 需要配置一个被标记为 vision-capable 的模型。OCR 可以使用支持图片输入的 OpenAI-compatible provider 模型，也可以使用 MLX Swift LM 支持的本地 MLX 视觉语言模型目录。本地 GGUF 模型仍然是 text-only。

当配置了真实 OpenAI-compatible provider API key 时，可以使用 `swift run LLMToolsLiveOCRCheck` 作为 Phase 3 OCR 的 live gate。它会复用现有 provider 配置，新增或选择 vision-capable 模型，把它设为 OCR 模型，运行视觉探测，OCR 一张生成的文字图片，并运行截图/图片解释；检查过程不会把原始源图存入历史。

## 媒体字幕与实时字幕

Phase 4 增加媒体优先的字幕工作流。Native app 可以注册 speech-capable 本地模型，分别选择实时 ASR 和文件 ASR 模型，检查本地 ASR runtime 健康状态，导入本地音频/视频文件，通过 macOS 媒体工具归一化音频，转写为带时间戳的字幕 segment，再复用现有文本翻译引擎生成译文，并导出 SRT、VTT、TXT 或 Markdown。

ASR 仅本地运行。Phase 4 没有远程 ASR 设置，也没有云端 ASR fallback。在当前 Apple Silicon 测试机上，Qwen3-ASR-0.6B bf16 通过 MLX sidecar 是中英混合实时字幕的优先候选；在打包 app 的 bridge 压测中，以 100ms PCM 传输 chunk 实时喂流，首个 partial 约 1.59s 墙钟时间出现，ASR 事件响应约为 157ms median / 203ms p90。Qwen3-ASR-0.6B 4bit 仍作为量化质量可接受时的更快 Qwen3 备选。Fun-ASR-MLT-Nano、Fun-ASR-Nano 的 MLX/GGUF 版本和 SenseVoiceSmall 继续作为低延迟或更广语言覆盖取舍下的实时候选；原版 `model.pt` Nano 保留实时字幕和文件处理，但根据实时会议 speaker 实测结果，不再进入会议采集模型。文件模式仍使用 Nano + VAD + CAM++ 组合管线。实时 partial 字幕使用测试后的模型族 partial 窗口默认值：Qwen3 1350ms、SenseVoice 1200ms、Fun-ASR 1500ms、whisper.cpp Core ML 2000ms。Settings -> Media -> Realtime ASR 提供 `Partial window` 控件，可按模型手动调节；final 字幕仍使用完整缓冲语音解码。这个控件不是模型解码器内部的底层音频切片大小；当前内置 Qwen3、SenseVoice、Fun-ASR、whisper 实时 sidecar 走的是滚动窗口重复解码，还没有按每个 PCM 切片保留 decoder state 的真增量流式解码。

VibeVoice-ASR 支持为重型 file-only rich transcription 模型，刻意不进入实时字幕模型选择。它的 runtime 如果返回带说话人归属的 segment，llmTools 会直接使用模型原生的 speaker 和 timestamp 元数据，并跳过外部 pyannote 说话人分离。其他 ASR 命令如果返回 `speaker`、`speakerID` 或 `speakerLabel`，也会被视为模型/runtime 原生说话人标签；如果没有 speaker 元数据且所选模型不是 VibeVoice-ASR，开启文件说话人分离后仍会走现有 pyannote 路径补标签。

Fun-ASR-Nano 的官方说话人分离能力来自 FunASR 组合管线：Nano 负责 ASR，FSMN-VAD 负责语音段，CAM++ 负责 speaker embedding/聚类，CT-Punc 提供标点组件，最终从 `sentence_info[].spk` 读取 speaker。llmTools 已把这套组合管线接入文件字幕和离线会议，运行阶段强制离线；如果结果没有有效 speaker，则回退到现有 pyannote/仅转写路径。Fun-ASR-Nano / Fun-ASR-MLT-Nano 的 MLX 与 GGUF 路径仍只负责 ASR，不会被误标为 Nano 权重原生说话人能力。当前三层语音架构和 runtime 矩阵见 [语音识别架构与 FunASR 接入说明](docs/speech-recognition-architecture.md)。

当前 Mac 实时 ASR 测试记录见 [Phase 4 ASR realtime latency report](docs/phase-4-asr-realtime-latency-report.md)。这份报告把实时首字延迟和离线文件吞吐分开记录，并汇总了已测试的 MLX、whisper.cpp Core ML、Apple SpeechAnalyzer、FluidAudio/Parakeet，以及已移除的 sherpa-onnx Qwen3-ASR 路线。

官方 Fun-ASR 加速路径按硬件分开：vLLM 路径面向 CUDA/NVIDIA 服务端并提供最高吞吐；llama.cpp/GGUF 路径面向 CPU/edge；Nano 的官方 Torch `demo2.py` 会在 Apple Silicon 上选择 `mps`。llmTools 的原版 Nano 常驻 sidecar 复用这条 MPS 路径，并在 M5 Pro 上完成真实 partial/final smoke；这不等同于 NVIDIA vLLM 的 RTFx 吞吐数据。

本地 ASR runtime 通过命令模板接入，避免把音频发送到设备外。可以在 Settings -> Media -> Local ASR runtime 配置命令模板，命令模板支持 `{model}`、`{audio}`、`{language}`、`{mode}`、`{isFinal}`、`{max_tokens}` 和 `{chunk_duration}`，也可以用启动时环境变量作为 fallback：

```sh
LLMTOOLS_FUN_ASR_COMMAND='your-fun-asr-command --model {model} --audio {audio} --language {language}'
LLMTOOLS_SENSEVOICE_COMMAND='your-sensevoice-command --model {model} --audio {audio}'
LLMTOOLS_QWEN3_ASR_COMMAND='your-qwen3-asr-command --model {model} --audio {audio}'
LLMTOOLS_VIBEVOICE_ASR_COMMAND='your-vibevoice-asr-command --model {model} --audio {audio}'
LLMTOOLS_ASR_COMMAND='your-generic-local-asr-command --model {model} --audio {audio}'
```

命令需要输出纯文本转写，或形如 `{"segments":[{"start":0,"end":2.5,"speakerID":"0","speakerLabel":"Speaker 1","text":"Hello"}]}` 的 JSON 字幕片段。`{audio}` 是归一化后的 16 kHz mono WAV 路径，`{model}` 是选中的本地模型目录。Settings 命令优先于环境变量。原版 Fun-ASR-Nano `model.pt` 在实时模式自动使用隔离的常驻 Torch/MPS sidecar，在文件模式使用 Nano + FSMN-VAD + CAM++ + CT-Punc；Fun-ASR GGUF 目录可在 `PATH` 存在 `llama-funasr-cli` 时自动使用。SenseVoiceSmall 也可使用兼容的 sherpa-onnx。safetensors/MLX ASR 目录通过 app 内置的 `llmtools-mlx-asr-runner.sh` 调用按模型族隔离的 runtime：Qwen3 与 mlx-community VibeVoice-ASR 共享固定版本 `mlx-audio`，SenseVoiceSmall、Fun-ASR-Nano、Fun-ASR-MLT-Nano 使用各自隔离环境。VibeVoice 的自动路径仅保留当前实际使用的 MLX runtime；原始 PyTorch 版本如仍需要，可通过显式自定义命令接入。

```sh
./scripts/install-phase4-mlx-asr-runtime.sh
./scripts/install-phase4-funasr-mlx-runtime.sh
./scripts/install-phase4-funasr-nano-mlx-runtime.sh
./scripts/install-phase4-funasr-pipeline-runtime.sh
./scripts/install-phase4-sensevoice-mlx-runtime.sh
```

健康检查会显示 runtime 来源：官方 FunASR 组合管线、Settings 命令、环境变量、测试夹具、本地 MLX runner、whisper.cpp、自动 sherpa-onnx，或未配置。对于受支持的模型目录，Settings 健康检查会在匹配 runtime 缺失时提供修复按钮。

检查当前 Mac 的 ASR runtime 状态且不修改 app 状态：

```sh
node scripts/check-phase4-local-asr-runtime.mjs
```

桌面实时字幕在原生 app 内运行，可监听系统音频、麦克风或两者混合。通过菜单项或可配置的全局快捷键打开实时字幕悬浮窗；Chromium 扩展不再包含实时字幕入口，也不再申请音频采集权限。修改扩展文件后，需要在 `chrome://extensions` reload unpacked extension。

## 会议转写与纪要

“会议转写与纪要”是独立于低延迟实时字幕的原生窗口，支持麦克风、原生系统音频和本地音频/视频离线处理。ASR、说话人分离和中文纪要都在设备本地运行，绝不回退到远程 provider。VibeVoice 一类原生说话人 ASR 可以联合输出文字、speaker 和时间戳；普通实时 ASR 会先在自然停顿处输出文字，再由本地 pyannote 独立回填 speaker 标签。说话人分离不可用时仍可继续仅转写。

使用步骤：

1. 打开“设置 -> 会议”，选择本地会议采集 ASR、本地文件 ASR、可选的本地 GGUF/MLX 纪要模型、默认输入和源语言。
2. 运行 ASR 健康检查。需要说话人标签时在“设置 -> 模型 -> 模型设置 -> Speaker Diarization”配置本地 pyannote runtime；分离 runtime 不可用只会降级为仅转写，不会阻塞文字。
3. 从状态栏菜单打开“会议转写与纪要”。实时会议选择麦克风或系统音频和讲话人数提示后开始；已有录音则直接选择本地音频或视频文件。
4. 结果出现后可以修改已完成的转写文字、重命名说话人、合并重复 speaker。界面会分别显示文字与 speaker 标签的延迟。
5. 停止采集后，根据需要分别执行“最终整理”“生成纪要”和“导出”。三个动作互相独立且可取消；导出支持 Markdown、TXT 和 JSON，默认写入 Downloads。
6. 活跃会议期间若 app 异常退出，下次启动可恢复或删除本地草稿。草稿保留转写和 speaker 编辑，但默认不保留临时音频。

`v0.4.1` 暂不支持会议中的麦克风与系统音频混合采集。原生说话人模型把自然停顿保留为逻辑讲话边界，但连续讲话每 120 秒会封装一个有界的技术推理窗口；普通 ASR 优先在自然停顿处输出，并限制连续讲话的最大等待时间。如果本地 ASR 慢于采集且已经排队 2 个推理窗口，app 会自动停止采集并完成队列，避免内存继续无界增长。正常停止时默认删除临时会议音频；异常退出后的清理只处理已终止进程拥有的音频，不会误删另一个仍在运行的 app 实例。

隐私默认保持收紧：默认不把原始音频、完整转写、字幕译文、页面标题、完整 URL 或完整媒体路径写入诊断或历史。会议工作目录仅当前用户可访问，不再逐回调落盘无用 PCM，ASR 处理后的临时归一化音频会删除。

## 开发命令

| 任务 | 命令 |
| --- | --- |
| Debug 构建 | `swift build` |
| Release 构建 | `swift build -c release` |
| 核心检查 | `swift run LLMToolsChecks` |
| 浏览器扩展检查 | `node scripts/check-browser-extension-dom.mjs` |
| Phase 4 媒体字幕检查 | `node scripts/check-phase4-media-subtitles.mjs` |
| Phase 4 本地 ASR runtime 检查 | `node scripts/check-phase4-local-asr-runtime.mjs` |
| 安装 Phase 4 本地 MLX ASR runtime，包含 Qwen3 和 mlx-community VibeVoice-ASR | `./scripts/install-phase4-mlx-asr-runtime.sh` |
| 安装 Phase 4 Fun-ASR-MLT MLX runtime | `./scripts/install-phase4-funasr-mlx-runtime.sh` |
| 安装 Phase 4 Fun-ASR-Nano MLX runtime | `./scripts/install-phase4-funasr-nano-mlx-runtime.sh` |
| 安装原版 FunASR Nano + CAM++ 离线组合 runtime | `./scripts/install-phase4-funasr-pipeline-runtime.sh` |
| 安装 Phase 4 SenseVoice MLX runtime | `./scripts/install-phase4-sensevoice-mlx-runtime.sh` |
| Phase 4 真实媒体 pipeline smoke | `swift run LLMToolsMediaSmoke --output-dir dist/phase4-media-smoke` |
| Phase 4.y 会议文件 smoke | `swift run LLMToolsMeetingSmoke --input /absolute/path/to/audio-or-video --output-dir dist/meeting-smoke` |
| 打包 app | `./scripts/package-app.sh` |
| 验证打包签名 | `codesign --verify --deep --strict --verbose=2 dist/llmTools.app` |
| Live OCR provider 检查 | `swift run LLMToolsLiveOCRCheck` |
| Phase 3 goal audit | `node scripts/check-phase3-goal-audit.mjs --run-checks --run-live-ocr` |
| Phase 2 closure gate | `./scripts/check-phase2-closure.sh` |

针对 Edge 或所有已配置 Chromium 浏览器运行 fixture 检查：

```sh
LLMTOOLS_E2E_BROWSER=edge node scripts/check-browser-extension-dom.mjs
LLMTOOLS_E2E_BROWSER=all node scripts/check-browser-extension-dom.mjs
```

如果浏览器可执行文件不在默认 macOS app 路径，可以设置 `CHROME_PATH` 或 `EDGE_PATH`。

## Phase 2 验收

closure 脚本会在 `dist/phase2-closure-reports/` 下生成带时间戳的报告，并刷新 `dist/phase2-closure-report.md`。

```sh
./scripts/check-phase2-closure.sh
node scripts/check-browser-extension-install.mjs --browser chrome --require-ready
node scripts/record-phase2-manual-check.mjs --list
```

针对最新报告记录手动验收：

```sh
node scripts/record-phase2-manual-check.mjs --pass translate-article "Chrome article translated from packaged app"
node scripts/record-phase2-manual-check.mjs --skip edge-acceptance "Microsoft Edge is not installed on this machine"
node scripts/check-phase2-acceptance-status.mjs --assert-complete
node scripts/record-phase2-manual-check.mjs --assert-complete
```

手动验收列表覆盖扩展 reload、Settings 状态、文章翻译、恢复原文、取消、阅读模式、质量/重新翻译、缓存清理、总是/永不翻译规则，以及重启后重连。

## 发布自动化

GitHub Actions 发布打包位于 `.github/workflows/release.yml`。

推送版本 tag 触发发布：

```sh
git tag v0.4.1
git push origin v0.4.1
```

也可以在 GitHub Actions 手动运行 workflow，并传入类似 `v0.4.1` 的 `version` input。

Workflow 会：

1. 在 `macos-15` arm64 GitHub-hosted runner 上运行。
2. 检查 Swift 和 Node toolchain。
3. 构建并运行 `LLMToolsChecks` 作为 Swift 回归 gate。
4. 对浏览器扩展执行语法检查和真实 DOM 行为检查。
5. 安装 Python MLX package，以定位 release bundle 需要的 `mlx.metallib`。
6. 在 CI 上限制 SwiftPM 并行度，通过 `scripts/package-app.sh` 打包 `dist/llmTools.app`。
7. 验证 app bundle 签名及 app/内嵌扩展版本。
8. 创建 release zip 和 sha256 checksum，并验证归档内的扩展版本。
9. 发布资产到匹配的 GitHub Release。

Release build 使用 ad-hoc 签名。未来如果要 notarized release，需要补充 Apple Developer 签名凭据、notarization、stapling，以及更严格的安装说明。

## 项目结构

```text
Sources/
  LLMToolsApp/          macOS app、settings UI、hotkeys、browser integration UI
  LLMToolsCore/         model registry、providers、runners、prompts、task engine
  LLMToolsNativeHost/   Chromium native messaging host
  LLMToolsChecks/       fast regression checks
  LLMToolsMeetingSmoke/ 本地会议文件 pipeline smoke 可执行程序
browser-extension/
  chromium/             用于网页翻译的 Manifest V3 扩展
scripts/                打包、诊断、浏览器检查、验收 helper
docs/                   roadmap、Phase 设计文档和版本发布说明
Resources/              app icon 资源
```

## 文档

- [Roadmap](docs/roadmap.md)
- [Phase 1 spec](docs/phase-1-spec.md)
- [Phase 2 webpage translation PRD](docs/phase-2-web-page-translation-prd.md)
- [Phase 3 native task and OCR PRD](docs/phase-3-native-task-and-ocr-prd.md)
- [Phase 4 media intake and live subtitles PRD](docs/phase-4-media-live-subtitles-prd.md)
- [Phase 4.y live meeting transcription PRD](docs/phase-4y-live-meeting-transcription-prd.md)
- [v0.4.1 发布说明与使用方法](docs/releases/v0.4.1.md)
- [v0.4.0 发布说明与使用方法](docs/releases/v0.4.0.md)
- [Phase 4 live audio subtitles research](docs/phase-4-live-audio-subtitles-research.md)
- [Phase 4 ASR realtime latency report](docs/phase-4-asr-realtime-latency-report.md)

## 贡献

提交 PR 前：

1. 保持改动聚焦，避免把产品行为变更和发布/文档整理混在一起。
2. 运行相关开发命令中的检查。
3. 如果改动影响浏览器集成，运行 `./scripts/check-phase2-closure.sh`，并记录必要的手动验收。
4. 如果改动影响发布，构建 `dist/llmTools.app` 并验证打包 app，而不是只跑 `swift build`。

## 安全与隐私

- API keys 和 provider credentials 存储在本机。
- 网页翻译诊断默认不记录原始网页内容。
- 媒体字幕诊断默认不记录原始音频、完整转写、字幕译文、完整媒体路径、页面标题或完整 URL。
- 浏览器扩展使用 optional host permissions，而不是把 `<all_urls>` 作为常规权限。
- 不要发布未经审查的日志或 closure reports，里面可能包含私有本地路径、模型名称或 provider 配置。

## License

llmTools 是开源软件，使用 [MIT License](LICENSE)。
