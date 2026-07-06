# llmTools

[![Release](https://github.com/qiupo/llmTools/actions/workflows/release.yml/badge.svg)](https://github.com/qiupo/llmTools/actions/workflows/release.yml)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)
![Chromium MV3](https://img.shields.io/badge/Chromium-MV3-4285F4?logo=googlechrome&logoColor=white)

语言：[English](README.md) | 简体中文

llmTools 是一个原生 macOS 菜单栏助手，用于对选中文本、网页、图片和截图执行翻译、润色、总结、解释、TODO 提取和模型视觉 OCR。它支持本地模型、远程 LLM Provider，并提供一个开发通道的 Chromium 扩展，通过本地 native bridge 翻译网页。

最新版本：[v0.3.0](https://github.com/qiupo/llmTools/releases/tag/v0.3.0)

## 功能亮点

- 原生 macOS SwiftUI/AppKit 菜单栏应用，支持全局 Quick Action 快捷键。
- 选中文本工作流：翻译、写作润色、总结、解释、TODO 提取。
- 本地模型支持：GGUF、MLX 文本模型，以及 MLX Swift LM 支持的 MLX 视觉语言模型目录。
- 远程 Provider 支持：OpenAI-compatible endpoint 和 Anthropic Messages API。
- Chromium 网页翻译：Manifest V3 扩展加本地 native messaging host。
- 原生图片 OCR、结构化提取、OCR 后翻译、截图/图片解释，使用显式配置的本地或远程视觉能力模型。
- 模型能力感知设置：text-only、vision-capable、自动推断、探测结果、手动覆盖。
- 隐私友好的网页诊断：页面/域名只记录 hash，默认不记录原始网页文本。
- GitHub Actions 发布流程：打包 macOS `.app` 并发布 GitHub Release 资产。

## 当前状态

llmTools 仍在持续开发中。当前 `v0.3.0` 版本中，桌面 Quick Action、本地/远程模型注册表、模型能力设置、本地 MLX 视觉语言模型 runner 路径，以及原生模型视觉 OCR 工作流已经可用。

Chromium 网页翻译目前仍是开发通道功能：Chrome 和 Edge 可以加载 unpacked extension，但 Chrome Web Store 分发和生产扩展 ID 暂时有意后置。

## 环境要求

| 范围 | 要求 |
| --- | --- |
| 运行环境 | macOS 14 或更高版本 |
| 构建环境 | 支持 Swift 6 的 Xcode/Swift toolchain |
| 脚本 | Node.js 18 或更高版本，用于扩展检查 |
| 浏览器翻译 | Google Chrome 或 Microsoft Edge，并开启 Developer Mode |
| 本地 MLX 模型 | 打包后的 app 内包含 `mlx.metallib`，或打包时设置 `MLX_METALLIB_PATH` |
| 选中文本捕获 | 给 llmTools 授予 macOS Accessibility 权限 |

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

## 开发命令

| 任务 | 命令 |
| --- | --- |
| Debug 构建 | `swift build` |
| Release 构建 | `swift build -c release` |
| 核心检查 | `swift run LLMToolsChecks` |
| 浏览器扩展检查 | `node scripts/check-browser-extension-dom.mjs` |
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
git tag v0.3.0
git push origin v0.3.0
```

也可以在 GitHub Actions 手动运行 workflow，并传入类似 `v0.3.0` 的 `version` input。

Workflow 会：

1. 在 `macos-15` arm64 GitHub-hosted runner 上运行。
2. 检查 Swift 和 Node toolchain。
3. 把 `LLMToolsChecks` 作为 Swift 编译 gate。
4. 对浏览器扩展脚本做语法检查。
5. 安装 Python MLX package，以定位 release bundle 需要的 `mlx.metallib`。
6. 在 CI 上限制 SwiftPM 并行度，通过 `scripts/package-app.sh` 打包 `dist/llmTools.app`。
7. 验证 app bundle 签名。
8. 创建 release zip 和 sha256 checksum。
9. 发布资产到匹配的 GitHub Release。

Release build 使用 ad-hoc 签名。未来如果要 notarized release，需要补充 Apple Developer 签名凭据、notarization、stapling，以及更严格的安装说明。

## 项目结构

```text
Sources/
  LLMToolsApp/          macOS app、settings UI、hotkeys、browser integration UI
  LLMToolsCore/         model registry、providers、runners、prompts、task engine
  LLMToolsNativeHost/   Chromium native messaging host
  LLMToolsChecks/       fast regression checks
browser-extension/
  chromium/             用于网页翻译的 Manifest V3 扩展
scripts/                打包、诊断、浏览器检查、验收 helper
docs/                   roadmap 和 Phase 设计文档
Resources/              app icon 资源
```

## 文档

- [Roadmap](docs/roadmap.md)
- [Phase 1 spec](docs/phase-1-spec.md)
- [Phase 2 webpage translation PRD](docs/phase-2-web-page-translation-prd.md)
- [Phase 3 native task and OCR PRD](docs/phase-3-native-task-and-ocr-prd.md)
- [Phase 4 live audio subtitles research](docs/phase-4-live-audio-subtitles-research.md)

## 贡献

提交 PR 前：

1. 保持改动聚焦，避免把产品行为变更和发布/文档整理混在一起。
2. 运行相关开发命令中的检查。
3. 如果改动影响浏览器集成，运行 `./scripts/check-phase2-closure.sh`，并记录必要的手动验收。
4. 如果改动影响发布，构建 `dist/llmTools.app` 并验证打包 app，而不是只跑 `swift build`。

## 安全与隐私

- API keys 和 provider credentials 存储在本机。
- 网页翻译诊断默认不记录原始网页内容。
- 浏览器扩展使用 optional host permissions，而不是把 `<all_urls>` 作为常规权限。
- 不要发布未经审查的日志或 closure reports，里面可能包含私有本地路径、模型名称或 provider 配置。

## License

llmTools 是开源软件，使用 [MIT License](LICENSE)。
