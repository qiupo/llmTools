# llmTools Roadmap

Last updated: 2026-07-03

## Product Direction

llmTools is a native macOS local-model assistant. It is not primarily a chat app. Its core value is to connect small local models to high-frequency desktop workflows:

- selected-text translation, polishing, summarization, explanation, and TODO extraction
- direct web-page translation, where English text in a page can be translated into Chinese in place
- a floating desktop widget that accepts pasted text and dragged files
- local model reuse through user-selected model files or model folders
- task-first interaction, with model selection hidden behind sensible defaults

The app should default to local processing. Remote provider entries can exist in the shared model registry, but browser page translation must remain local/private by default unless the user explicitly chooses a remote provider.

## Current Status

- Phase 1 native MVP is complete as of 2026-07-03.
- Phase 1 should now be treated as the stable baseline for regression checks: selected-text processing, quick action, model registry, GGUF/MLX runners, task templates, floating widget, local packaging, and recent history.
- Phase 2 is the active next product phase.
- Phase 2.0 Chrome webpage translation baseline is complete: current-page translation, native bridge, real model translation, restore, cancel, dynamic scroll translation, cache, context-menu toggle, popup, overlay, Settings entry, and packaged-app workflow.
- Remaining Phase 2 work should focus on product expansion that was deferred in the original plan: site/domain rules, production distribution, additional browsers, advanced reading modes, complex-page support, and release-grade QA/privacy controls.

## Confirmed Decisions

- Phase 1 native MVP is complete and frozen as the baseline for future regression checks.
- Platform: native macOS app using SwiftUI/AppKit.
- Minimum platform target: macOS 14 or newer, with development and verification on the current newer macOS environment.
- Model source: users can reuse already downloaded local models by selecting model files or model folders.
- Model management: the app manages model registration, status, routing, and runner lifecycle.
- Text replacement: copying results is required; replacing original selected text is optional and controlled by a setting.
- Floating window: a desktop widget is required; it appears on all Spaces by default and can auto-collapse at the screen edge.
- Phase 1 model support: multiple model registrations are supported from the beginning.
- Phase 1 runtime support: GGUF and MLX inference must both fully work before Phase 1 is complete.
- Initial user model set: Qwen 0.8B, Qwen 4B, and Qwen 9B.
- Default model roles: Qwen 0.8B is fast mode, Qwen 4B is default mode, and Qwen 9B is quality mode.
- Observed model formats: GGUF models and MLX-4bit model folders.
- Early distribution: Phase 1 should be packaged as a local `.app` for realistic permission, shortcut, and floating-window testing.
- Recent history: keep the latest 20 local results and provide a one-click clear action.
- Translation default: Chinese input translates to English, and non-Chinese input translates to Chinese.
- Web-page translation should reuse the local translation engine through a local bridge. Page text must not be sent to cloud services by default.
- Web-page translation default: translate visible English page text into Chinese while preserving page structure and allowing the user to restore the original text.
- Browser extension installation cannot be silent on normal consumer browsers. The app should provide a guided installer in Settings that opens the correct browser or extension settings page, installs local bridge assets, and verifies the extension after the user confirms browser permissions.
- Phase 2.0 starts with Google Chrome on macOS.
- Phase 2.0 uses a Chrome extension, native messaging host, and a local `127.0.0.1` app bridge protected by an app-generated token.
- Development Chrome extension ID: `jednddlgkkohaebgoejcidfppddjegij`.
- Phase 2.0 Chrome baseline is complete. Later Phase 2 work should not relitigate the Chrome MVP architecture unless a regression or browser policy change requires it.

## Phase 1: Native MVP - Completed

Goal: ship a usable menu-bar macOS app that can process selected or pasted text with local models.

Core capabilities:

- menu-bar app
- global shortcut for selected-text processing
- quick action panel
- local model registry
- multiple configured models
- one active model at a time
- working GGUF and MLX model inference
- translation, polishing, summarization, explanation, and TODO extraction
- result copy
- optional original-text replacement setting, disabled by default
- floating desktop widget MVP with edge auto-collapse
- recent history capped at 20 entries with one-click clear
- local `.app` packaging for Phase 1 testing

Primary acceptance:

- A user can register Qwen 0.8B, Qwen 4B, and Qwen 9B from existing local folders.
- A user can run real inference with both a GGUF model and an MLX model.
- A user can select text in another app, press a shortcut, process it, and copy the result.
- A user can paste text into the floating widget and process it.
- A user can clear recent results with one action.

Completion record:

- Accepted as complete on 2026-07-03.
- Future work in this area should be treated as maintenance, polish, or regression repair unless a new phase explicitly changes scope.
- Phase 1 verification should continue to use the packaged app path `dist/llmTools.app`, not only `swift build`.

See `docs/phase-1-spec.md` for the detailed spec.

## Phase 2: Web Page Translation

Goal: provide the existing local translation capability to webpages, so a user can translate English content in the current page directly into Chinese without copying text out of the browser.

Detailed PRD: `docs/phase-2-web-page-translation-prd.md`.

Completed Phase 2.0 baseline:

- Chrome MV3 extension in `browser-extension/chromium`.
- Native messaging executable target `LLMToolsNativeHost`.
- Local bridge server in the native app, with bridge state at `~/Library/Application Support/llmTools/web-page-bridge.json`.
- Settings UI section `网页翻译` with Chrome bridge repair and extension-folder guidance.
- Webpage-specific translation request/response types and `TaskEngine.translateWebPageSegments`.
- DOM text discovery, English-dominant filtering, skip rules, overlay, restore, cancel, dynamic discovery, context-menu toggle, and translation cache logic in the extension.
- Packaged-app workflow for the Chrome development extension.
- Focused checks through `swift run LLMToolsChecks` and `node scripts/check-browser-extension-dom.mjs`.

Completed Phase 2.0 capabilities:

- Chrome browser extension connected to the native app
- Settings-page browser integration panel
- Chrome development bridge repair flow
- native messaging host and local app bridge
- one-click current-tab translation
- visible-text extraction from the page DOM
- English-to-Chinese translation in place
- original-text restore
- cancellation
- progress and error display
- batching, rate limiting, and incremental translation
- persistent local translation cache for repeated text segments
- dynamic-page handling for text that appears after scroll or navigation
- context-menu toggle
- local-only bridge boundary

Remaining implementation direction:

- Preserve the Chrome 2.0 architecture as the baseline.
- Add site/domain rules and optional auto-translation before adding broad browser or content-type scope.
- Add production Chrome distribution if the user wants non-development installation.
- Add Edge before Safari or Firefox unless user priority changes.
- Add bilingual/original reading mode after site rules are stable.
- Add complex-page and embedded-content support incrementally, with graceful unsupported states.
- Do not design for silent extension installation. Chrome, Safari, Firefox, and similar browsers require user confirmation, store distribution, enabling, or browser-controlled permission prompts outside the app's direct control.
- Keep the extension responsible for browser permissions, page text discovery, DOM replacement, restore behavior, site rules, and page-level controls.
- Keep the native macOS app responsible for model selection, prompt templates, runner lifecycle, task execution, logging, diagnostics, and local privacy controls.

Remaining Settings behavior:

- Show browser rows for installed supported browsers, with statuses such as "not installed", "installed but disabled", "needs permission", "bridge missing", "paired", and "ready".
- Show development/production extension channel, extension ID, version, native host path, manifest path, and last successful ping.
- Show domain rules and cache controls.
- For Chromium-based browsers, prefer a published extension flow for normal use once production distribution is selected. The app may open the extension's store listing or managed install instructions, but the user must confirm installation and permissions in the browser.
- For Safari, package the Safari Web Extension with a containing app target when that becomes the chosen distribution path. The Settings button may open Safari's extension preferences, but the user must enable the extension in Safari.
- For Firefox, support a signed add-on flow and native messaging manifest installation. The user must install or approve the add-on through Firefox's controlled flow.
- Provide a local development mode only for developer builds, such as opening `chrome://extensions` with load-unpacked instructions or Safari unsigned-extension instructions. Do not treat development install flows as the normal user path.
- After browser confirmation, the app should automatically verify extension connectivity through a local ping and explain the exact remaining step if verification fails.
- If the current browser cannot be detected or supported, fall back to copying a clear install link and showing manual steps.

DOM translation rules:

- Translate visible user-facing text nodes.
- Skip `script`, `style`, `noscript`, `code`, `pre`, form inputs, textareas, editable regions, hidden elements, and user-entered content.
- Preserve links, buttons, headings, lists, tables, and inline formatting as much as possible.
- Store enough original text in the page session to restore the page without a reload.
- Avoid permanent storage of full page content unless the user explicitly enables history for webpage translation.

Remaining suggested scope:

- Add site rules and auto-translate first.
- Add production Chrome distribution second.
- Add Edge third.
- Add bilingual/original reading mode after domain behavior is stable.
- Add full-page pretranslation, browser PDF viewer translation, image/OCR translation, form-writing assistance, and complex web-app mutation handling only after the normal DOM path remains stable.

Remaining primary acceptance:

- A user can set per-site rules and auto-translate trusted domains.
- A user can use a production-like Chrome install path or see a clear development-only decision.
- A user can translate pages in Edge with the same privacy boundary as Chrome.
- A user can switch between replacement, bilingual, and original modes without reloading.
- Complex pages fail gracefully when they cannot be safely translated.
- Webpage cache/history behavior is visible, clearable, and documented.

Remaining Phase 2 requirement groups:

1. Site rules and auto-translation: per-site enable/disable, ask-every-time, optional auto-translate for trusted domains, domain cache controls, and clear UI state in popup/overlay/Settings.
2. Production Chrome distribution: production extension ID, Chrome Web Store listed/unlisted decision, production install/repair flow, version reporting, upgrade/repair diagnostics, and release notes.
3. Additional browsers: Edge first, then Brave/Arc if needed, then Safari Web Extension once Chromium behavior is stable, with Firefox deferred unless it becomes a priority.
4. Advanced reading modes: optional full-page pretranslation, bilingual/original comparison mode, retranslate current page with a different model, and page-level translation quality controls.
5. Complex content support: SPA route changes, virtualized lists, accessible iframes, table-heavy pages, browser PDF viewer translation, and image/canvas/OCR text only after the normal DOM path remains stable.
6. Release-grade QA and privacy: browser E2E coverage, permission/privacy checks, cache/history policy documentation, and regression checks for Phase 1 native flows.

## Phase 3: Floating File Drop Workflow

Goal: make the floating widget a natural file-processing entry point.

Core capabilities:

- always-available floating widget
- drag-to-process interaction
- screen-edge docking and auto-collapse
- TXT and Markdown file ingestion
- PDF ingestion after text extraction is stable
- automatic task suggestion based on file content
- file summary
- key point extraction
- action item extraction
- recent result history
- clear running/error states

Suggested scope:

- Start with TXT/Markdown because they are predictable and allow the model pipeline to be hardened first.
- Add PDF only after text chunking, page extraction, and progress reporting are reliable.
- Treat DOCX as a later extension unless it becomes an explicit priority.

Primary acceptance:

- A user can drag a supported file onto the floating widget and receive a structured result.
- The widget remains unobtrusive when docked to the side of the screen.
- Large-file failures produce understandable messages instead of silent hangs.

## Phase 4: Local Document Assistant

Goal: move from single-shot processing to reusable local document understanding.

Core capabilities:

- import files and folders
- local document index
- searchable processing history
- document-level question answering
- multi-document summary
- project or folder digest
- local metadata storage
- tags and lightweight organization

Suggested scope:

- Keep all data local by default.
- Add indexing only for user-selected folders.
- Make index status visible, including "not indexed", "indexing", "ready", and "failed".

Primary acceptance:

- A user can add a folder and ask questions against its indexed documents.
- A user can summarize a set of files without manually opening each file.
- The app clearly separates raw files, extracted text, generated summaries, and vector/index data.

## Phase 5: Model Routing and Automation

Goal: make multiple small models cooperate behind simple task workflows.

Core capabilities:

- task classification
- automatic model routing
- speed/quality mode
- 0.8B model for lightweight classification and short tasks
- 4B model for default everyday tasks
- 9B model for higher-quality or longer-context tasks
- prompt template management
- custom workflows
- developer utilities: log explanation, error analysis, diff summary, commit message drafting

Suggested scope:

- Keep routing observable. The user should be able to see which model was used and why.
- Allow users to override model choice per task.
- Store prompt templates locally.

Primary acceptance:

- The app can choose a reasonable model based on task type, text length, and user quality preference.
- The user can define custom actions without editing code.
- Developer workflows are useful but do not dominate the general product experience.

## Cross-Phase Principles

- Local-first by default.
- Explicit model paths, no hidden model downloads in early phases.
- Native macOS interactions should feel first-class.
- Failures must be visible and actionable.
- Long-running model work should never freeze the UI.
- Model runners should be isolated enough that a backend crash does not crash the whole app.
- Privacy-sensitive data should not be retained unless the user opts in.
- Browser integration must be permissioned, reversible, and scoped to the current page or domain.
