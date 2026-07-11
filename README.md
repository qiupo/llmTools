# llmTools

[![Release](https://github.com/qiupo/llmTools/actions/workflows/release.yml/badge.svg)](https://github.com/qiupo/llmTools/actions/workflows/release.yml)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)
![Chromium MV3](https://img.shields.io/badge/Chromium-MV3-4285F4?logo=googlechrome&logoColor=white)

Languages: English | [简体中文](README.zh-CN.md)

llmTools is a native macOS menu-bar assistant for translating, polishing, summarizing, explaining, extracting TODOs, running model-vision OCR, creating local media subtitles, and transcribing meetings. It supports local models, remote LLM providers, and a development Chromium extension for page translation through a local native bridge.

Latest release: [v0.4.0](https://github.com/qiupo/llmTools/releases/tag/v0.4.0)

## Highlights

- Native macOS SwiftUI/AppKit app with global quick-action shortcuts.
- Selected-text workflows for translation, writing polish, summaries, explanations, and TODO extraction.
- Local model support for GGUF, MLX text models, and MLX vision-language model folders supported by MLX Swift LM.
- Remote provider support for OpenAI-compatible endpoints and Anthropic Messages API.
- Chromium webpage translation via Manifest V3 extension plus local native messaging host.
- Native image OCR, structured extraction, translate-after-OCR, and screenshot/image explanation through explicitly configured vision-capable local or remote models.
- Local media subtitles and desktop live captions with separate realtime/file ASR selection, translation, and SRT/VTT/TXT/Markdown export.
- Local language routing, file-scope speaker diarization, fast MT routing, and engine-isolated webpage translation cache.
- A separate local-only Meeting Transcription & Notes window for microphone, system audio, and offline audio/video input, with editable transcript rows, speaker correction, Chinese notes, recovery drafts, and Markdown/TXT/JSON export.
- Pin controls for Quick Action, selection actions, the floating widget, Live Subtitles, and Meeting Transcription windows.
- Capability-aware model settings with text-only, vision-capable, inferred, probed, and manual override states.
- Privacy-oriented webpage diagnostics: hashed page/domain identifiers, no raw page text in diagnostics by default.
- Release workflow that packages a macOS `.app` bundle and publishes GitHub Release assets.

## Status

llmTools is under active development. The current `v0.4.0` release includes the desktop Quick Action flow, local/remote model registry, capability-aware model settings, local model-vision OCR, Chromium webpage translation, media subtitles, native desktop live captions, local language/fast-MT routing, file speaker diarization, and local-only meeting transcription and notes.

Meeting transcription is independent from the low-latency Live Subtitles overlay. Live meetings can use microphone or native system audio; local audio/video files use offline processing. Microphone+system mixed meeting capture is not included in v0.4.0. Chromium webpage translation remains a development-channel feature: Chrome and Edge can load the unpacked extension, but Chrome Web Store distribution and production extension IDs are intentionally deferred.

## Features And Usage

| Feature | Entry | How to use it |
| --- | --- | --- |
| Selected-text Quick Action | Select text in another app, then press `Option + Space` | Choose Translate, Polish, Summarize, Explain, or Extract TODOs. Grant Accessibility permission if automatic selection capture is needed. |
| Pasted text and files | Status menu -> `Open Quick Action` or `Open Floating Widget` | Paste text, paste an image, or drag a supported file, choose a task/model, then copy or export the result. |
| Image OCR and explanation | Status menu -> `Image OCR` | In Settings -> `OCR`, select a vision-capable local or remote model, then paste, drag, or choose an image and run OCR, structured extraction, translation, or explanation. |
| Webpage translation | Settings -> `Web Page Translation`, then the Chromium extension popup | Repair the local browser bridge, load `browser-extension/chromium` as an unpacked extension, grant site access, and translate/restore the current page from the popup. |
| Media subtitles | Settings -> `Media`, then the media intake UI | Select a local file ASR model and healthy runtime, import audio/video, transcribe and optionally translate, then export SRT, VTT, TXT, or Markdown. |
| Desktop Live Subtitles | Status menu -> `Start Live Subtitles`, or the configured global shortcut | Select a realtime local ASR model in Settings -> `Media`, choose microphone, system audio, or both, then read the native floating overlay. |
| Meeting Transcription & Notes | Status menu -> `会议转写与纪要` | Configure local meeting models in Settings -> `Meeting`, start microphone/system capture or import a local audio/video file, edit transcript/speakers, stop, optionally finalize, generate local Chinese notes, and export. |
| Window pinning | Pin icon in a supported tool window | Keep Quick Action, selection actions, the floating widget, Live Subtitles, or Meeting Transcription above other windows until unpinned or the app exits. |

## Requirements

| Area | Requirement |
| --- | --- |
| Runtime | macOS 14 or later |
| Build | Xcode/Swift toolchain with Swift 6 support |
| Scripts | Node.js 18 or later for extension checks |
| Browser translation | Google Chrome or Microsoft Edge with Developer Mode enabled |
| Local MLX models | `mlx.metallib` copied into the packaged app, or `MLX_METALLIB_PATH` during packaging |
| Local MLX ASR setup | `uv`, Python 3.11 or 3.12, and a compatible local speech model |
| Selected-text capture | macOS Accessibility permission for llmTools |
| Live audio capture | macOS Microphone permission and/or ScreenCaptureKit screen/system-audio permission |

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

Local ASR runtime integration is command-based so the app can work with installed local sidecars without sending audio off-device. Configure command templates in Settings -> Media -> Local ASR runtime. Command templates can use `{model}`, `{audio}`, `{language}`, `{mode}`, `{isFinal}`, `{max_tokens}`, and `{chunk_duration}`. Environment variables are still supported as a launch-time fallback:

```sh
LLMTOOLS_FUN_ASR_COMMAND='your-fun-asr-command --model {model} --audio {audio} --language {language}'
LLMTOOLS_SENSEVOICE_COMMAND='your-sensevoice-command --model {model} --audio {audio}'
LLMTOOLS_QWEN3_ASR_COMMAND='your-qwen3-asr-command --model {model} --audio {audio}'
LLMTOOLS_VIBEVOICE_ASR_COMMAND='your-vibevoice-asr-command --model {model} --audio {audio}'
LLMTOOLS_ASR_COMMAND='your-generic-local-asr-command --model {model} --audio {audio}'
```

The command must print either plain transcript text or JSON subtitle segments such as `{"segments":[{"start":0,"end":2.5,"speakerID":"0","speakerLabel":"Speaker 1","text":"Hello"}]}`. `{audio}` is the normalized 16 kHz mono WAV path and `{model}` is the selected local model folder. Settings commands take priority over environment variables. Fun-ASR GGUF folders can be detected automatically when `llama-funasr-cli` is in `PATH` and the selected model folder contains compatible Fun-ASR encoder and Qwen3 decoder GGUF files. SenseVoiceSmall can also use `sherpa-onnx-offline` from `PATH` when the selected model folder contains `model.onnx` and `tokens.txt`. safetensors/MLX ASR folders use the bundled `llmtools-mlx-asr-runner.sh` with family-specific isolated runtimes: pinned `mlx-audio` for Qwen3 and mlx-community VibeVoice-ASR, patched `mlx-audio` for SenseVoiceSmall and Fun-ASR-Nano, and `mlx-audio-plus` for Fun-ASR-MLT-Nano. mlx-community VibeVoice-ASR also needs a local Qwen2.5 tokenizer sidecar, installed by `install-phase4-mlx-asr-runtime.sh` under `~/Library/Application Support/llmTools/asr-runtime/qwen2.5-tokenizer` or overridden with `LLMTOOLS_VIBEVOICE_TOKENIZER_DIR`. Original PyTorch VibeVoice-ASR runtimes can still use `scripts/llmtools-vibevoice-asr-runner.py` or a custom command to preserve rich transcription speaker/timestamp fields.

```sh
./scripts/install-phase4-mlx-asr-runtime.sh
./scripts/install-phase4-funasr-mlx-runtime.sh
./scripts/install-phase4-funasr-nano-mlx-runtime.sh
./scripts/install-phase4-sensevoice-mlx-runtime.sh
./scripts/install-phase4-vibevoice-asr-runtime.sh # legacy/original PyTorch VibeVoice-ASR
```

Health checks show the runtime source: Settings command, environment variable, fixture transcript, local MLX runner, automatic sherpa-onnx, or unavailable. The Settings health check can offer a repair button for supported safetensors/MLX model folders when the matching local runtime is missing.

To inspect the current Mac's ASR setup without changing app state:

```sh
node scripts/check-phase4-local-asr-runtime.mjs
```

Desktop live subtitles run in the native app and can listen to system audio, microphone audio, or both. Use the menu item or the configurable global shortcut to open the floating subtitle window; the Chromium extension no longer contains live-subtitle controls or audio-capture permissions. After changing extension files, reload the unpacked extension in `chrome://extensions`.

## Meeting Transcription And Notes

The separate Meeting Transcription & Notes window supports microphone, native system audio, and offline local audio/video input. ASR, diarization, and Chinese note generation stay on-device and never fall back to a remote provider. VibeVoice-style speaker-aware ASR can emit transcript, speaker, and timestamps together. Ordinary live ASR emits text at natural pauses while local diarization independently backfills speaker labels; if diarization is unavailable, transcript-only mode remains usable. This pipeline does not change or block the low-latency Live Subtitles overlay.

Use the meeting workflow as follows:

1. Open Settings -> `Meeting`. Select a local meeting-capture ASR model, a local file ASR model, an optional local GGUF/MLX text model for Chinese notes, the default input, and the source-language hint.
2. Run the ASR health checks. Configure the local pyannote runtime under Settings -> `Models` -> `Model Settings` -> `Speaker Diarization` if speaker labels are needed; an unavailable diarization runtime degrades to transcript-only instead of blocking transcription.
3. Open the status menu -> `会议转写与纪要`. Choose microphone or system audio and a speaker-count hint, then start capture. To process a recording, choose a local audio or video file instead.
4. While results arrive, edit finalized transcript text, rename speakers, or merge duplicate speaker labels. The app shows transcript and speaker-label lag separately.
5. Stop capture. Use `Finalize` when transcript cleanup is wanted, `Generate Notes` to create local Chinese meeting notes, and `Export` to write Markdown, TXT, or JSON to Downloads. These are separate, cancellable actions.
6. If the app exits abnormally during an active session, restore or delete the local recovery draft at the next launch. Recovery drafts keep transcript/speaker edits but do not retain temporary audio by default.

Meeting capture intentionally does not mix microphone and system audio in v0.4.0. A speaker-aware capture model keeps natural pauses as logical turn boundaries, but seals a bounded technical inference window every 120 seconds during uninterrupted speech. Ordinary ASR prefers natural pauses and enforces a bounded continuous-speech delay. If two inference windows are already queued because local ASR is slower than capture, the app automatically stops capture and finishes the queue instead of allowing memory use to grow without bound. Normal stop deletes temporary session audio by default; crash recovery removes audio owned by the terminated process without touching another live app instance.

Privacy defaults stay restrictive: raw audio, full transcripts, translated subtitles, page titles, full URLs, and full media paths are not written to diagnostics or history by default. Meeting workspaces are owner-only, unused per-callback PCM chunks are not persisted, and temporary normalized audio is deleted after ASR processing.

## Development Commands

| Task | Command |
| --- | --- |
| Build debug | `swift build` |
| Build release | `swift build -c release` |
| Core checks | `swift run LLMToolsChecks` |
| Browser extension checks | `node scripts/check-browser-extension-dom.mjs` |
| Phase 4 media subtitle checks | `node scripts/check-phase4-media-subtitles.mjs` |
| Phase 4 local ASR runtime check | `node scripts/check-phase4-local-asr-runtime.mjs` |
| Install Phase 4 local MLX ASR runtime, including Qwen3 and mlx-community VibeVoice-ASR | `./scripts/install-phase4-mlx-asr-runtime.sh` |
| Install Phase 4 Fun-ASR-MLT MLX runtime | `./scripts/install-phase4-funasr-mlx-runtime.sh` |
| Install Phase 4 Fun-ASR-Nano MLX runtime | `./scripts/install-phase4-funasr-nano-mlx-runtime.sh` |
| Install Phase 4 SenseVoice MLX runtime | `./scripts/install-phase4-sensevoice-mlx-runtime.sh` |
| Install legacy/original PyTorch VibeVoice-ASR runtime | `./scripts/install-phase4-vibevoice-asr-runtime.sh` |
| Phase 4 real media pipeline smoke | `swift run LLMToolsMediaSmoke --output-dir dist/phase4-media-smoke` |
| Phase 4.y meeting file smoke | `swift run LLMToolsMeetingSmoke --input /absolute/path/to/audio-or-video --output-dir dist/meeting-smoke` |
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
git tag v0.4.0
git push origin v0.4.0
```

The same workflow can be run manually from GitHub Actions with a `version` input such as `v0.4.0`.

The workflow:

1. Runs on `macos-15` arm64 GitHub-hosted runners.
2. Checks the Swift and Node toolchains.
3. Builds and runs `LLMToolsChecks` as the Swift regression gate.
4. Runs browser-extension syntax and real DOM behavior checks.
5. Installs the Python MLX package to locate `mlx.metallib` for the release bundle.
6. Packages `dist/llmTools.app` through `scripts/package-app.sh` with limited SwiftPM parallelism on CI.
7. Verifies the app bundle signature and the app/embedded-extension versions.
8. Creates release zip files and sha256 checksums, then verifies the archived extension version.
9. Publishes the assets to the matching GitHub Release.

Release builds are ad-hoc signed. A future notarized release should add Apple Developer signing credentials, notarization, stapling, and a stricter install guide.

## Project Layout

```text
Sources/
  LLMToolsApp/          macOS app, settings UI, hotkeys, browser integration UI
  LLMToolsCore/         model registry, providers, runners, prompts, task engine
  LLMToolsNativeHost/   Chromium native messaging host
  LLMToolsChecks/       fast regression checks
  LLMToolsMeetingSmoke/ local meeting-file pipeline smoke executable
browser-extension/
  chromium/             Manifest V3 extension for webpage translation
scripts/                packaging, diagnostics, browser checks, acceptance helpers
docs/                   roadmap, phase specifications, and release notes
Resources/              app icon assets
```

## Documentation

- [Roadmap](docs/roadmap.md)
- [Phase 1 spec](docs/phase-1-spec.md)
- [Phase 2 webpage translation PRD](docs/phase-2-web-page-translation-prd.md)
- [Phase 3 native task and OCR PRD](docs/phase-3-native-task-and-ocr-prd.md)
- [Phase 4 media intake and live subtitles PRD](docs/phase-4-media-live-subtitles-prd.md)
- [Phase 4.y live meeting transcription PRD](docs/phase-4y-live-meeting-transcription-prd.md)
- [v0.4.0 release notes and usage](docs/releases/v0.4.0.md)
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
