# llmTools

[![Release](https://github.com/qiupo/llmTools/actions/workflows/release.yml/badge.svg)](https://github.com/qiupo/llmTools/actions/workflows/release.yml)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)
![Chromium MV3](https://img.shields.io/badge/Chromium-MV3-4285F4?logo=googlechrome&logoColor=white)

llmTools is a native macOS menu-bar assistant for translating, polishing, summarizing, explaining, extracting TODOs, and running model-vision OCR on selected text, webpages, images, and screenshots. It supports local models, remote LLM providers, and a development Chromium extension for page translation through a local native bridge.

## Highlights

- Native macOS SwiftUI/AppKit app with global quick-action shortcuts.
- Selected-text workflows for translation, writing polish, summaries, explanations, and TODO extraction.
- Local model support for GGUF and MLX model folders.
- Remote provider support for OpenAI-compatible endpoints and Anthropic Messages API.
- Chromium webpage translation via Manifest V3 extension plus local native messaging host.
- Native image OCR, structured extraction, translate-after-OCR, and screenshot/image explanation through explicitly configured vision-capable models.
- Capability-aware model settings with text-only, vision-capable, inferred, probed, and manual override states.
- Privacy-oriented webpage diagnostics: hashed page/domain identifiers, no raw page text in diagnostics by default.
- Release workflow that packages a macOS `.app` bundle and publishes GitHub Release assets.

## Status

llmTools is under active development. The desktop quick-action flow, local/remote model registry, capability-aware model settings, and native model-vision OCR workflow are usable. Chromium webpage translation is currently a development-channel feature: Chrome and Edge can load the unpacked extension, but Chrome Web Store distribution and production extension IDs are intentionally deferred.

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

MLX Swift needs `mlx.metallib` next to the executable at runtime. If oMLX is installed in the default location, the package script can reuse its bundled resource automatically. To prepare the resource explicitly:

```sh
./scripts/prepare-mlx-metallib.sh
```

If the file is elsewhere:

```sh
MLX_METALLIB_PATH=/path/to/mlx.metallib ./scripts/package-app.sh
```

When `mlx.metallib` is missing, the app still packages, but MLX-backed local models will fail until the resource is added.

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
- Local MLX model folders.
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

Native OCR requires a configured model that is marked vision-capable. Local GGUF and MLX runners remain text-only until a real multimodal local runner exists, so OCR uses provider models that accept image input through the implemented vision runner path.

When a real OpenAI-compatible provider API key is configured, `swift run LLMToolsLiveOCRCheck` can be used as the live Phase 3 OCR gate. It reuses the existing provider configuration, adds or selects a vision-capable model, sets it as the OCR model, runs a vision probe, OCRs a generated text image, and runs screenshot/image explanation without storing raw source images in history.

## Development Commands

| Task | Command |
| --- | --- |
| Build debug | `swift build` |
| Build release | `swift build -c release` |
| Core checks | `swift run LLMToolsChecks` |
| Browser extension checks | `node scripts/check-browser-extension-dom.mjs` |
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

## Contributing

Before opening a pull request:

1. Keep changes focused and avoid mixing product behavior changes with release/documentation churn.
2. Run the relevant checks from the Development Commands section.
3. For browser integration changes, run `./scripts/check-phase2-closure.sh` and record any required manual acceptance.
4. For release-impacting changes, build `dist/llmTools.app` and verify the packaged app, not only `swift build`.

## Security And Privacy

- API keys and provider credentials are stored locally.
- Webpage translation diagnostics are designed to avoid raw page content by default.
- Browser extension host access uses optional host permissions rather than global `<all_urls>` normal permissions.
- Do not publish logs or closure reports containing private local paths, model names, or provider configuration unless they have been reviewed.

## License

llmTools is open source software licensed under the [MIT License](LICENSE).
