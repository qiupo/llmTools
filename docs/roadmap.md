# llmTranslate Roadmap

Last updated: 2026-06-30

## Product Direction

llmTranslate is a native macOS local-model assistant. It is not primarily a chat app. Its core value is to connect small local models to high-frequency desktop workflows:

- selected-text translation, polishing, summarization, explanation, and TODO extraction
- direct web-page translation, where English text in a page can be translated into Chinese in place
- a floating desktop widget that accepts pasted text and dragged files
- local model reuse through user-selected model files or model folders
- task-first interaction, with model selection hidden behind sensible defaults

The app should default to local processing. Cloud APIs are not part of the initial product scope.

## Confirmed Decisions

- Phase 1 native MVP is complete.
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

See `docs/phase-1-spec.md` for the detailed spec.

## Phase 2: Web Page Translation

Goal: provide the existing local translation capability to webpages, so a user can translate English content in the current page directly into Chinese without copying text out of the browser.

Detailed PRD: `docs/phase-2-web-page-translation-prd.md`.

Core capabilities:

- browser extension MVP connected to the native app
- Settings-page browser integration panel
- guided extension installer for supported browsers
- local bridge between the extension and llmTranslate
- one-click "translate this page" action for the current tab
- visible-text extraction from the page DOM
- English-to-Chinese translation in place
- original-text restore action
- per-page and per-domain enable/disable controls
- progress, cancellation, and error display for large pages
- batching, rate limiting, and incremental translation
- lightweight translation cache for repeated text segments
- dynamic-page handling for text that appears after scroll or navigation
- local-only privacy boundary by default

Implementation direction:

- Start with a browser extension because webpage DOM replacement needs browser-side code.
- If no browser priority is specified, build the first MVP for the user's primary Chromium-based browser, then add Safari Web Extension support after the bridge and DOM translation behavior are stable.
- Do not design for silent extension installation. Chrome, Safari, Firefox, and similar browsers require user confirmation, store distribution, enabling, or browser-controlled permission prompts outside the app's direct control.
- The Settings installer should be a one-click guided flow: detect installed supported browsers, show extension status, open the correct install or enable page, install or repair native messaging bridge assets, pair the extension with the app, run a test ping, and then offer "Translate current page" when ready.
- The extension owns browser permissions, page text discovery, DOM replacement, restore behavior, and page-level controls.
- The native macOS app owns model selection, prompt templates, runner lifecycle, task execution, logging, and local privacy controls.
- Connect the extension to the app through a local-only bridge, such as a loopback HTTP/WebSocket service or native messaging host.
- Protect the local bridge with an app-generated token or pairing flow so random webpages cannot call the local model endpoint.
- Add a `webPageTranslate` task path in the app layer instead of treating webpage translation as generic pasted text.
- Translate text nodes in batches, preserve links and layout, and avoid rewriting HTML structure unless required.
- Keep page translation cancellable. Closing the tab, navigating away, or pressing cancel should stop queued work.

Settings installer behavior:

- Show browser rows for installed supported browsers, with statuses such as "not installed", "installed but disabled", "needs permission", "bridge missing", "paired", and "ready".
- For Chromium-based browsers, prefer a published extension flow for normal use. The app may open the extension's store listing or managed install instructions, but the user must confirm installation and permissions in the browser.
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

Suggested scope:

- Start with manual current-tab translation.
- Start with English-to-Chinese only.
- Start with ordinary article, documentation, blog, and product pages.
- Translate the initially visible page first, then translate additional visible content as the user scrolls.
- Defer full-page pretranslation, bilingual side-by-side view, image/OCR translation, PDF-in-browser translation, form-writing assistance, and complex web-app mutation handling until the MVP is stable.

Primary acceptance:

- A user can open an English article or documentation page, trigger llmTranslate, and see the English text replaced by readable Chinese in the page.
- The page remains usable: links still work, layout does not collapse, and buttons/forms are not corrupted.
- The user can restore the original English text without reloading the page.
- The user can cancel a long translation and see a clear partial/failed state.
- Page text stays local by default, and the app shows which local model handled the webpage translation.
- Repeated text on the same page is not translated redundantly.

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
