# llmTools

[![Release](https://github.com/qiupo/llmTools/actions/workflows/release.yml/badge.svg)](https://github.com/qiupo/llmTools/actions/workflows/release.yml)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)
![Chromium MV3](https://img.shields.io/badge/Chromium-MV3-4285F4?logo=googlechrome&logoColor=white)

Languages: English | [简体中文](README.zh-CN.md)

llmTools is a native macOS menu-bar assistant for translating, polishing, summarizing, explaining, extracting TODOs, and running model-vision OCR on selected text, webpages, images, and screenshots. It supports local models, remote LLM providers, and a development Chromium extension for page translation through a local native bridge.

Latest release: [v0.3.0](https://github.com/qiupo/llmTools/releases/tag/v0.3.0)

## Highlights

- Native macOS SwiftUI/AppKit app with global quick-action shortcuts.
- Selected-text workflows for translation, writing polish, summaries, explanations, and TODO extraction.
- Local model support for GGUF, MLX text models, and MLX vision-language model folders supported by MLX Swift LM.
- Remote provider support for OpenAI-compatible endpoints and Anthropic Messages API.
- Chromium webpage translation via Manifest V3 extension plus local native messaging host.
- Native image OCR, structured extraction, translate-after-OCR, and screenshot/image explanation through explicitly configured vision-capable local or remote models.
- Capability-aware model settings with text-only, vision-capable, inferred, probed, and manual override states.
- Privacy-oriented webpage diagnostics: hashed page/domain identifiers, no raw page text in diagnostics by default.
- Release workflow that packages a macOS `.app` bundle and publishes GitHub Release assets.

## Status

llmTools is under active development. The desktop quick-action flow, local/remote model registry, capability-aware model settings, local MLX vision-language runner path, and native model-vision OCR workflow are usable in the current `v0.3.0` release. Chromium webpage translation is currently a development-channel feature: Chrome and Edge can load the unpacked extension, but Chrome Web Store distribution and production extension IDs are intentionally deferred.

## Requirements

| Area | Requirement |
| --- | --- |
| Runtime | macOS 14 or later |
| Build | Xcode/Swift toolchain with Swift 6 support |
| Scripts | Node.js 18 or later for extension checks |
| Browser translation | Google Chrome or Microsoft Edge with Developer Mode enabled |
| Local MLX models | `mlx.metallib` copied into the packaged app, or `MLX_METALLIB_PATH` during packaging |
| Selected-text capture | macOS Accessibility permission for llmTools |

## Install From Releases

1. Download `llmTools-<version>-macos-arm64.zip` from the latest GitHub Release.
2. Unzip it and move `llmTools.app` to `/Applications` or another trusted location.
3. Launch the app. If macOS blocks the first launch because the app is ad-hoc signed and not notarized, use Finder's Open flow or System Settings -> Privacy & Security.
4. Grant Accessibility permission when selected-text capture is needed.
5. For webpage translation, open Settings -> `网页翻译`, repair the browser bridge, and load the unpacked Chromium extension folder shown by the app.

Release assets also include:

- `llmTools-<version>-macos-arm64.zip.sha256`
- `llmTools-<version>-chromium-extension.zip`
- `llmTools-<version>-chromium-extension.zip.sha256`

## Quick Start From Source

```sh
git clone https://github.com/qiupo/llmTools.git
cd llmTools
swift build
```

On this development machine, the first dependency resolution may need the local proxy helper:

```sh
fish -lc 'setproxy >/dev/null; swift build'
```

Run the core checks:

```sh
swift run LLMToolsChecks
```

Package the local app:

```sh
./scripts/package-app.sh
open dist/llmTools.app
```

The packaged bundle is written to `dist/llmTools.app`.

## MLX Runtime Resource

MLX Swift needs `mlx.metallib` next to the executable at runtime for local MLX text models and local MLX vision-language models. If oMLX is installed in the default location, the package script can reuse its bundled resource automatically. To prepare the resource explicitly:

```sh
./scripts/prepare-mlx-metallib.sh
```

If the file is elsewhere:

```sh
MLX_METALLIB_PATH=/path/to/mlx.metallib ./scripts/package-app.sh
```

When `mlx.metallib` is missing, the app still packages, but MLX-backed local models will fail until the resource is added.

Local MLX vision-language model folders must include MLX-compatible weights, tokenizer files, model configuration, and vision/processor configuration that MLX Swift LM can load. The app detects likely local vision models conservatively from the model and processor files; unsupported local model families should be marked text-only or run through a remote vision-capable provider instead.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| `Option + Space` | Open Quick Action and try to capture the current selected text |
| `Option + Shift + Space` | Open Quick Action with an empty input area |

Selected-text capture depends on macOS Accessibility permission and the behavior of the focused app. If capture fails, paste text manually or grant permission in System Settings.

## Providers

The Models settings page uses one shared registry for local and remote models. The default model picker, quick-action panel, and webpage translation model picker all read from that registry.

Supported model/provider families:

- Local GGUF files.
- Local MLX text model folders.
- Local MLX vision-language model folders supported by MLX Swift LM.
- OpenAI-compatible providers: OpenAI, SiliconFlow, DeepSeek, Google Gemini, OpenRouter, Ollama, LM Studio, Together AI, Mistral AI, DeepInfra, and custom endpoints.
- Anthropic Messages API.

## Browser Page Translation

The current browser integration is a local-only development channel:

| Component | Location |
| --- | --- |
| Chromium extension | `browser-extension/chromium` |
| Native host executable | `LLMToolsNativeHost` inside the packaged app |
| Bridge state | `~/Library/Application Support/llmTools/web-page-bridge.json` |
| Chrome development extension ID | `jednddlgkkohaebgoejcidfppddjegij` |
| Edge native manifest | `~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/com.llmtools.native_host.json` |

Setup flow:

1. Package and launch `dist/llmTools.app`.
2. Open Settings -> `网页翻译`.
3. Click the repair button for Chrome or Edge. The app writes that browser's native messaging manifest and opens its extensions page.
4. Enable Developer Mode in the browser.
5. Load the unpacked extension folder shown in Settings. Use `显示扩展文件夹` to reveal the exact folder.

Popup controls include inline replacement, bilingual view, original view, visible-first or full-page translation scope, natural/literal/technical quality modes, pending-style selection, retranslate, page/site/all cache clearing, and site defaults.

Browser diagnostics intentionally avoid raw page URLs, domains, source text, translated text, and DOM content. They include browser ID, extension version, translation status, segment counts, elapsed time, model name, page URL hash, domain hash, mode settings, unsupported embedded-content counts, and stable error codes.

Current scope:

- Implemented: Chrome page translation, site rules, cache controls, reading modes, quality modes, retranslate, privacy diagnostics, and Phase 1 regression checks.
- Implemented for Edge: Settings detection, native manifest repair, `edge://extensions` launch, and reusable browser fixture runner.
- Implemented in the native app: text-task prompt hardening, output follow-up actions, model capability badges and overrides, OCR settings, OpenAI-compatible model-vision OCR payloads, structured OCR, translate-after-OCR, and screenshot/image explanation.
- Deferred from browser translation: Chrome Web Store distribution, production extension ID, Safari/Firefox support, browser PDF viewer translation, browser image/canvas OCR translation, form-writing assistance, and multi-tab bulk translation.

Chrome cannot be silently installed, enabled, or confirmed by the app. Final extension loading and permission prompts stay under browser control.

Native OCR requires a configured model that is marked vision-capable. OCR can use OpenAI-compatible provider models that accept image input or local MLX vision-language model folders supported by MLX Swift LM. Local GGUF models remain text-only.

When a real OpenAI-compatible provider API key is configured, `swift run LLMToolsLiveOCRCheck` can be used as the live Phase 3 OCR gate. It reuses the existing provider configuration, adds or selects a vision-capable model, sets it as the OCR model, runs a vision probe, OCRs a generated text image, and runs screenshot/image explanation without storing raw source images in history.

## Media Subtitles And Live Captions

Phase 4 adds media-first subtitle workflows. The native app can register speech-capable local models, pick separate realtime and file ASR models, check local ASR runtime health, import local audio/video files, normalize audio through macOS media tools, transcribe into timestamped subtitle segments, translate those segments through the existing text translation engine, and export SRT, VTT, TXT, or Markdown.

ASR is local-only. There is no remote ASR setting and no cloud fallback. On the current Apple Silicon test machine, Qwen3-ASR-0.6B bf16 through the MLX sidecar is the preferred mixed Chinese/English realtime candidate; in the packaged-app bridge benchmark with 100 ms realtime PCM transport chunks, the first partial appeared at about 1.59 s wall time and ASR-event responses measured about 157 ms median / 203 ms p90. Qwen3-ASR-0.6B 4bit remains the faster Qwen3 alternative when its quantized quality is acceptable. Fun-ASR-MLT-Nano, Fun-ASR-Nano, and SenseVoiceSmall remain supported realtime candidates with lower-latency or broader-language tradeoffs. Realtime partial subtitles use tested family-specific partial-window defaults: Qwen3 1350 ms, SenseVoice 1200 ms, Fun-ASR 1500 ms, and whisper.cpp Core ML 2000 ms. Settings -> Media -> Realtime ASR exposes a `Partial window` control for per-model manual tuning, while final subtitles still decode the complete buffered utterance. This control is not the model decoder's low-level audio-slice size; the bundled Qwen3, SenseVoice, Fun-ASR, and whisper realtime sidecars currently re-decode rolling windows instead of maintaining an incremental decoder state for every PCM slice.

VibeVoice-ASR is supported as a heavy file-only rich transcription model. It is intentionally excluded from realtime/live-caption pickers. When its runtime returns speaker-attributed segments, llmTools uses the native speaker and timestamp metadata directly and skips external pyannote diarization. Other ASR commands can also return speaker metadata; any JSON segment with `speaker`, `speakerID`, or `speakerLabel` is treated as model/runtime-native speaker labeling. If no speaker metadata is returned and the selected model is not VibeVoice-ASR, the existing file-scope pyannote diarization path can still add speaker labels when enabled.

The current Mac realtime ASR benchmark notes are kept in [Phase 4 ASR realtime latency report](docs/phase-4-asr-realtime-latency-report.md). That report separates live first-subtitle latency from offline file throughput and records the tested MLX, whisper.cpp Core ML, Apple SpeechAnalyzer, FluidAudio/Parakeet, and removed sherpa-onnx Qwen3-ASR paths.

Official Fun-ASR acceleration paths split by hardware. The vLLM path targets CUDA/NVIDIA servers and provides the highest throughput/streaming service. The llama.cpp/GGUF path targets CPU/edge/on-device use with a single `llama-funasr-cli` binary and built-in FSMN-VAD when compatible GGUF files are present. The checked Fun-ASR GitHub docs do not document Apple MPS/Metal as a supported acceleration path, so llmTools does not assume `device="mps"` for Fun-ASR runtimes.

Local ASR runtime integration is command-based so the app can work with installed local sidecars without sending audio off-device. Configure command templates in Settings -> Media -> Local ASR runtime. Command templates can use `{model}`, `{audio}`, `{language}`, `{mode}`, and `{isFinal}`. Environment variables are still supported as a launch-time fallback:

```sh
LLMTOOLS_FUN_ASR_COMMAND='your-fun-asr-command --model {model} --audio {audio} --language {language}'
LLMTOOLS_SENSEVOICE_COMMAND='your-sensevoice-command --model {model} --audio {audio}'
LLMTOOLS_QWEN3_ASR_COMMAND='your-qwen3-asr-command --model {model} --audio {audio}'
LLMTOOLS_VIBEVOICE_ASR_COMMAND='your-vibevoice-asr-command --model {model} --audio {audio}'
LLMTOOLS_ASR_COMMAND='your-generic-local-asr-command --model {model} --audio {audio}'
```

The command must print either plain transcript text or JSON subtitle segments such as `{"segments":[{"start":0,"end":2.5,"speakerID":"0","speakerLabel":"Speaker 1","text":"Hello"}]}`. `{audio}` is the normalized 16 kHz mono WAV path and `{model}` is the selected local model folder. Settings commands take priority over environment variables. Fun-ASR GGUF folders can be detected automatically when `llama-funasr-cli` is in `PATH` and the selected model folder contains compatible Fun-ASR encoder and Qwen3 decoder GGUF files. SenseVoiceSmall can also use `sherpa-onnx-offline` from `PATH` when the selected model folder contains `model.onnx` and `tokens.txt`. safetensors/MLX ASR folders use the bundled `llmtools-mlx-asr-runner.sh` with family-specific isolated runtimes: pinned `mlx-audio` for Qwen3, patched `mlx-audio` for SenseVoiceSmall and Fun-ASR-Nano, and `mlx-audio-plus` for Fun-ASR-MLT-Nano. VibeVoice-ASR folders use `scripts/llmtools-vibevoice-asr-runner.py` with a separate Python runtime and preserve the model's rich transcription speaker/timestamp fields.

```sh
./scripts/install-phase4-mlx-asr-runtime.sh
./scripts/install-phase4-funasr-mlx-runtime.sh
./scripts/install-phase4-funasr-nano-mlx-runtime.sh
./scripts/install-phase4-sensevoice-mlx-runtime.sh
./scripts/install-phase4-vibevoice-asr-runtime.sh
```

Health checks show the runtime source: Settings command, environment variable, fixture transcript, local MLX runner, automatic sherpa-onnx, or unavailable. The Settings health check can offer a repair button for supported safetensors/MLX model folders when the matching local runtime is missing.

To inspect the current Mac's ASR setup without changing app state:

```sh
node scripts/check-phase4-local-asr-runtime.mjs
```

Desktop live subtitles run in the native app and can listen to system audio, microphone audio, or both. Use the menu item or the configurable global shortcut to open the floating subtitle window; the Chromium extension no longer contains live-subtitle controls or audio-capture permissions. After changing extension files, reload the unpacked extension in `chrome://extensions`.

Privacy defaults stay restrictive: raw audio, full transcripts, translated subtitles, page titles, full URLs, and full media paths are not written to diagnostics or history by default. Temporary normalized audio is deleted after ASR processing.

## Development Commands

| Task | Command |
| --- | --- |
| Build debug | `swift build` |
| Build release | `swift build -c release` |
| Core checks | `swift run LLMToolsChecks` |
| Browser extension checks | `node scripts/check-browser-extension-dom.mjs` |
| Phase 4 media subtitle checks | `node scripts/check-phase4-media-subtitles.mjs` |
| Phase 4 local ASR runtime check | `node scripts/check-phase4-local-asr-runtime.mjs` |
| Install Phase 4 local MLX ASR runtime | `./scripts/install-phase4-mlx-asr-runtime.sh` |
| Install Phase 4 Fun-ASR-MLT MLX runtime | `./scripts/install-phase4-funasr-mlx-runtime.sh` |
| Install Phase 4 Fun-ASR-Nano MLX runtime | `./scripts/install-phase4-funasr-nano-mlx-runtime.sh` |
| Install Phase 4 SenseVoice MLX runtime | `./scripts/install-phase4-sensevoice-mlx-runtime.sh` |
| Install Phase 4 VibeVoice-ASR runtime | `./scripts/install-phase4-vibevoice-asr-runtime.sh` |
| Phase 4 real media pipeline smoke | `swift run LLMToolsMediaSmoke --output-dir dist/phase4-media-smoke` |
| Package app | `./scripts/package-app.sh` |
| Verify packaged code signature | `codesign --verify --deep --strict --verbose=2 dist/llmTools.app` |
| Live OCR provider check | `swift run LLMToolsLiveOCRCheck` |
| Phase 3 goal audit | `node scripts/check-phase3-goal-audit.mjs --run-checks --run-live-ocr` |
| Phase 2 closure gate | `./scripts/check-phase2-closure.sh` |

Run browser fixture checks against Edge or all configured Chromium browsers:

```sh
LLMTOOLS_E2E_BROWSER=edge node scripts/check-browser-extension-dom.mjs
LLMTOOLS_E2E_BROWSER=all node scripts/check-browser-extension-dom.mjs
```

If browser executables are not in the default macOS app paths, set `CHROME_PATH` or `EDGE_PATH`.

## Phase 2 Acceptance

The closure script produces a timestamped report under `dist/phase2-closure-reports/` and refreshes `dist/phase2-closure-report.md`.

```sh
./scripts/check-phase2-closure.sh
node scripts/check-browser-extension-install.mjs --browser chrome --require-ready
node scripts/record-phase2-manual-check.mjs --list
```

Record manual acceptance against the latest report:

```sh
node scripts/record-phase2-manual-check.mjs --pass translate-article "Chrome article translated from packaged app"
node scripts/record-phase2-manual-check.mjs --skip edge-acceptance "Microsoft Edge is not installed on this machine"
node scripts/check-phase2-acceptance-status.mjs --assert-complete
node scripts/record-phase2-manual-check.mjs --assert-complete
```

The manual acceptance list covers extension reload, Settings status, article translation, restore, cancellation, reading modes, quality/retranslate, cache clearing, auto/never-translate rules, and restart reconnect.

## Release Automation

GitHub Actions release packaging lives in `.github/workflows/release.yml`.

Trigger a release by pushing a version tag:

```sh
git tag v0.3.0
git push origin v0.3.0
```

The same workflow can be run manually from GitHub Actions with a `version` input such as `v0.3.0`.

The workflow:

1. Runs on `macos-15` arm64 GitHub-hosted runners.
2. Checks the Swift and Node toolchains.
3. Builds `LLMToolsChecks` as a Swift compile gate.
4. Runs syntax checks for the browser extension scripts.
5. Installs the Python MLX package to locate `mlx.metallib` for the release bundle.
6. Packages `dist/llmTools.app` through `scripts/package-app.sh` with limited SwiftPM parallelism on CI.
7. Verifies the app bundle signature.
8. Creates release zip files and sha256 checksums.
9. Publishes the assets to the matching GitHub Release.

Release builds are ad-hoc signed. A future notarized release should add Apple Developer signing credentials, notarization, stapling, and a stricter install guide.

## Project Layout

```text
Sources/
  LLMToolsApp/          macOS app, settings UI, hotkeys, browser integration UI
  LLMToolsCore/         model registry, providers, runners, prompts, task engine
  LLMToolsNativeHost/   Chromium native messaging host
  LLMToolsChecks/       fast regression checks
browser-extension/
  chromium/             Manifest V3 extension for webpage translation
scripts/                packaging, diagnostics, browser checks, acceptance helpers
docs/                   roadmap and Phase 2 design notes
Resources/              app icon assets
```

## Documentation

- [Roadmap](docs/roadmap.md)
- [Phase 1 spec](docs/phase-1-spec.md)
- [Phase 2 webpage translation PRD](docs/phase-2-web-page-translation-prd.md)
- [Phase 3 native task and OCR PRD](docs/phase-3-native-task-and-ocr-prd.md)
- [Phase 4 media intake and live subtitles PRD](docs/phase-4-media-live-subtitles-prd.md)
- [Phase 4 live audio subtitles research](docs/phase-4-live-audio-subtitles-research.md)
- [Phase 4 ASR realtime latency report](docs/phase-4-asr-realtime-latency-report.md)

## Contributing

Before opening a pull request:

1. Keep changes focused and avoid mixing product behavior changes with release/documentation churn.
2. Run the relevant checks from the Development Commands section.
3. For browser integration changes, run `./scripts/check-phase2-closure.sh` and record any required manual acceptance.
4. For release-impacting changes, build `dist/llmTools.app` and verify the packaged app, not only `swift build`.

## Security And Privacy

- API keys and provider credentials are stored locally.
- Webpage translation diagnostics are designed to avoid raw page content by default.
- Media subtitle diagnostics are designed to avoid raw audio, transcript text, translated subtitle text, full media paths, page titles, and full URLs by default.
- Browser extension host access uses optional host permissions rather than global `<all_urls>` normal permissions.
- Do not publish logs or closure reports containing private local paths, model names, or provider configuration unless they have been reviewed.

## License

llmTools is open source software licensed under the [MIT License](LICENSE).
