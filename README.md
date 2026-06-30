# llmTranslate

Native macOS local-model assistant for quick text translation, polishing, summary, explanation, and TODO extraction.

## Build

The project uses SwiftPM and native SwiftUI/AppKit.

```sh
fish -lc 'setproxy >/dev/null; swift build'
```

`setproxy` is useful on this machine because the first dependency resolution pulls packages from GitHub.

## MLX Runtime Resource

MLX Swift needs `mlx.metallib` next to the executable at runtime. On this machine the helper script can reuse the `mlx.metallib` bundled in oMLX:

```sh
./scripts/prepare-mlx-metallib.sh
```

If the file lives somewhere else, point to it explicitly:

```sh
MLX_METALLIB_PATH=/path/to/mlx.metallib ./scripts/prepare-mlx-metallib.sh
```

## Checks

Fast core checks:

```sh
fish -lc 'setproxy >/dev/null; swift run LLMTranslateChecks'
```

Chrome extension DOM and batching checks:

```sh
node scripts/check-browser-extension-dom.mjs
```

Prepare MLX runtime resources before running MLX smoke tests from SwiftPM:

```sh
./scripts/prepare-mlx-metallib.sh
```

Real model smoke:

```sh
swift run LLMTranslateSmoke /Users/po/code/models/lmstudio-community/Qwen3.5-0.8B-GGUF "Reply with OK only."
swift run LLMTranslateSmoke /Users/po/code/models/lmstudio-community/Qwen3.5-4B-MLX-4bit "Reply with OK only."
swift run LLMTranslateSmoke /Users/po/code/models/lmstudio-community/Qwen3.5-9B-MLX-4bit "Reply with OK only."
```

## Shortcuts

- `Option + Space`: open Quick Action and try to capture selected text.
- `Option + Shift + Space`: open Quick Action with an empty input area.

Selected-text capture may require macOS Accessibility permission. If capture fails, paste text manually or grant the permission in System Settings.

## Package Local App

```sh
fish -lc 'setproxy >/dev/null; ./scripts/package-app.sh'
```

The packaged app is written to:

```text
dist/llmTranslate.app
```

## Phase 2 Web Page Translation MVP

The Chrome MVP uses a local-only bridge:

- Chrome extension: `browser-extension/chromium`
- Native messaging host: `LLMTranslateNativeHost`
- App bridge state: `~/Library/Application Support/llmTranslate/web-page-bridge.json`
- Development Chrome extension ID: `jednddlgkkohaebgoejcidfppddjegij`

Development setup:

1. Package and launch `dist/llmTranslate.app`.
2. Open Settings -> `网页翻译`.
3. Click `修复 Chrome 桥接`; the app writes Chrome's native messaging manifest and opens `chrome://extensions`.
4. In Chrome, enable Developer Mode and load the unpacked extension folder shown in Settings.

The app cannot silently install or enable browser extensions. Chrome still owns the final extension loading and permission confirmation.
Current Google Chrome also ignores command-line unpacked extension loading in this local setup, so end-to-end browser verification must use Chrome's `Load unpacked` confirmation flow or a separate Chrome for Testing/Chromium build that permits extension automation.
