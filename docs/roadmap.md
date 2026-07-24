# llmTools Roadmap

Last updated: 2026-07-15

## Product Direction

llmTools is a native macOS local-model assistant. It is not primarily a chat app. Its core value is to connect small local models to high-frequency desktop workflows:

- selected-text translation, polishing, summarization, explanation, and TODO extraction
- direct web-page translation, where English text in a page can be translated into Chinese in place
- native image OCR using explicitly configured vision-capable models
- local-first media subtitles for audio, video, and desktop live playback, with direct Chinese translation
- delayed live meeting transcription with speaker-aware notes as a separate work surface from live subtitles
- local VoxCPM2 text-to-speech for ordinary copy, long text, reusable voices, and optional reviewed multi-role scripts
- a floating desktop widget that accepts pasted text and dragged files
- local model reuse through user-selected model files or model folders
- task-first interaction, with model selection hidden behind sensible defaults

The app should default to local processing. Remote provider entries can exist in the shared model registry, but browser page translation must remain local/private by default unless the user explicitly chooses a remote provider.

## Current Status

- A repository-wide code/security/runtime review and the next five optimization phases are tracked in `docs/code-audit-and-five-phase-optimization-plan.md`. Quick Action has a separate workstream and acceptance matrix in that document.

- Phase 1 native MVP is complete as of 2026-07-03.
- Phase 1 should now be treated as the stable baseline for regression checks: selected-text processing, quick action, model registry, GGUF/MLX runners, task templates, floating widget, local packaging, and recent history.
- Phase 2 implementation is complete and is now in closure/acceptance mode.
- Phase 2.0 Chrome webpage translation baseline is complete: current-page translation, native bridge, real model translation, restore, cancel, dynamic scroll translation, cache, context-menu toggle, popup, overlay, Settings entry, and packaged-app workflow.
- Phase 2.1 site/domain rules are implemented. The Chrome development extension and macOS Settings now share per-domain `ask` / `alwaysTranslate` / `neverTranslate` rules, popup rule editing, automatic translation for opted-in domains, `neverTranslate` blocking for automatic/context-menu translation, and page/site/all webpage cache controls.
- Phase 2.2 is complete as a product decision for this phase: Chrome distribution remains development-only, with visible channel/version/manifest diagnostics and stable native-manifest validation. Chrome Web Store distribution is deferred to a later release/distribution track.
- Phase 2.3 has implementation support for Microsoft Edge: Settings rows, detection, independent native manifest repair, `edge://extensions` launch, and a reusable Edge-capable browser fixture runner. Real Edge loading/native-messaging/translation acceptance remains pending until Edge is available on the test machine.
- Phase 2.4 current-page controls are implemented for replacement/bilingual/original reading modes, visible-first/full-page discovery scope, natural/literal/technical quality modes, pending translation style selection in the extension popup, current-page retranslate, and per-domain reading/quality defaults.
- Phase 2.5 complex-page baseline is implemented for SPA route reset, stale page-session rejection, virtualized rows, same-origin iframes, open shadow roots, high-frequency mutations, table-heavy pages, protected/page-PDF unsupported states, and partial-support reporting for unsupported embedded content.
- Phase 2.6 privacy, diagnostics, and release-QA baseline is implemented: redacted webpage diagnostics, explicit cache/history policy, default-off webpage Recent History, fixture matrix coverage, least-privilege manifest checks, browser runtime/console checks, and Phase 1 regression checks.
- Remaining Phase 2 work is now limited to external/manual closure tasks: real Edge acceptance when Edge is available, real Chrome packaged-app smoke after the unpacked extension is loaded from this repo, and fixing defects found by that acceptance. Production Chrome distribution, Safari/Firefox, browser PDF translation, browser image/canvas OCR translation, form-writing assistance, and broader browser expansion are later-phase product decisions.
- Phase 3 implementation baseline is complete as of 2026-07-04: native text-task prompts and follow-up actions are hardened, model capability metadata is persisted and visible, and native model-vision OCR plus screenshot/image explanation are available through a user-selected vision-capable model.
- Phase 4 product direction is now media intake and live subtitles: local audio/video transcription, translated subtitles, and desktop live subtitles from system audio and/or microphone audio. The previous file/document intake plan is retained as supporting file-ingestion scope and later document-assistant work.
- Phase 4.x language/speaker/fast-MT implementation is now in place: language-ID routing, file-scope speaker diarization, fast MT sidecar routing for subtitles/webpage translation, webpage cache v2 engine isolation, and dependency-free fixture checks.
- Phase 4.x realtime speaker diarization is explicitly out of scope for the MVP. The live speaker toggle is hard-disabled until a later spike can prove that diarization never blocks ASR partial/final subtitle output.
- Phase 4.y live meeting transcription has a separate local-only product surface with microphone, native system-audio, and local audio/video-file input. Recognition is capability-adaptive: native speaker-aware ASR (including VibeVoice) emits text/speakers/timestamps jointly; ordinary live ASR emits natural-pause transcript rows first and receives delayed local pyannote labels independently; transcript-only is the local failure fallback. Ordinary local files may still diarize first and transcribe stable speaker slices offline. This keeps live text responsive without changing the low-latency Live Subtitles contract, and includes editable grouped turns, speaker correction, recovery drafts, a 60-minute reminder, cancellable manual finalization, and after-stop chunked Chinese notes.
- Local TTS V1 is implemented as a separate VoxCPM2-only workbench. bf16 is the quality default and 4bit is the low-memory option. Single-narrator copy is the default; multi-role analysis is optional, locally reviewed, and uses deterministic explicit-role parsing or a local GGUF/MLX text model. Projects, cloned references, generated segments, recovery, playback, and WAV/M4A/SRT export remain local.

## Confirmed Decisions

- Phase 1 native MVP is complete and frozen as the baseline for future regression checks.
- Platform: native macOS app using SwiftUI/AppKit.
- Minimum platform target: macOS 14 or newer, with development and verification on the current newer macOS environment.
- Model source: users can reuse already downloaded local models by selecting model files or model folders.
- Model management: the app manages model registration, status, routing, and runner lifecycle.
- Provider API keys remain in the existing local model registry. llmTools does not use macOS Keychain; the legacy Keychain account field is decode-only compatibility data and is never queried.
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
- Phase 3 OCR starts in the native app, not inside browser page translation. Browser image/canvas OCR remains a later browser feature after native model-vision OCR and normal DOM translation are stable.
- Phase 3 does not use Apple Vision, VisionKit, or Apple-provided OCR/visual recognition APIs. Image recognition is performed by the configured vision-capable model.
- OCR models must be chosen from models marked as vision-capable. When provider APIs cannot prove vision support, the app should expose confidence and allow a clear manual override instead of silently assuming support.
- Local text-only GGUF and MLX models should remain unavailable for OCR until a real multimodal local runner exists.
- Phase 4 changes the main line from generic file/document intake to media intake and subtitles. TXT/Markdown/image drag-and-drop can remain as supporting workflow, but PDF/DOCX and reusable document understanding stay later-phase work.
- Phase 4 does not consider remote ASR. Speech recognition must run locally by default and should not include a cloud fallback path in MVP requirements.
- Phase 4 keeps ASR model, local runtime, and speaker processing as separate layers. Fun-ASR-MLT-Nano remains the broad-language initial realtime preference, Fun-ASR-Nano is the Chinese/English/Japanese option, and the currently benchmarked Qwen3-ASR-0.6B bf16 MLX route remains the preferred mixed Chinese/English candidate on Apple Silicon. The UI exposes actual family/mode/speaker capability instead of presenting one universal best model.
- Phase 4 translated subtitles reuse llmTools' existing text translation engine after ASR; ASR models should produce transcripts, not final Chinese translations.
- Phase 4.x file subtitle diarization is file-scope only. Cross-file speaker identity and speaker embedding persistence are rejected for the MVP.
- Phase 4.x fast MT has a global killswitch (`fastTranslation.forceLLM`) and must fall back to LLM when configured to do so. Webpage translation cache keys must include source language, target language, engine id, engine model id, domain, and text hash so LLM and fast MT outputs do not mix.
- Phase 4.x realtime diarization status is tracked in `docs/phase-4x-realtime-diarization-spike.md`; no 4.x.6 implementation should start until that spike passes the latency gate.
- Phase 4.y live meeting transcription is tracked in `docs/phase-4y-live-meeting-transcription-prd.md`; it is allowed to lag and should not be implemented by simply enabling speaker labels in the live subtitle overlay.
- Local TTS V1 is tracked in `docs/local-tts-voxcpm2-v1-prd.md`; it uses VoxCPM2 bf16/4bit only, keeps multi-role as an optional mode, rejects cloud fallback, and unloads text/TTS models between stages.

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

Current Phase 2.1 implementation:

- macOS Settings exposes auto-translate and never-translate domain lists.
- Chrome development extension reads domain rules from the native app status and writes popup changes back through native messaging.
- Popup shows the current domain and lets the user choose manual translation, auto-translate this site, or never translate this site.
- `alwaysTranslate` triggers page translation when a matching HTTP/HTTPS page finishes loading.
- `neverTranslate` prevents automatic translation and context-menu translation for the domain; the popup translate button remains an explicit manual override.
- Popup can clear cached webpage translations for the current page, current site, or all sites.
- Page overlay shows short-lived notices for site-rule changes, never-translate blocking, and cache clearing without injecting text into the page DOM.
- The Chrome extension uses optional HTTP/HTTPS host permissions. Selecting auto-translate for a site from the popup requests that site's permission before saving `alwaysTranslate`; background auto-translate refuses to run without that permission.
- Settings shows Chrome diagnostics including extension ID, extension version, Native Host path, native manifest path, last error code, and last local check; Chrome native host manifest repair now validates host path, manifest type, and allowed extension ID with stable diagnostic codes.
- `node scripts/check-browser-extension-dom.mjs` covers native domain-rule sync, default domain state, optional permission request/denial, auto-translate permission gating, never-translate blocking, manual override, page/site/all cache clearing, overlay notices, the existing translation/cache/restore path, and a real-browser multi-page navigation smoke for article/docs fixtures.

Current Phase 2.2 distribution state:

- Chrome is explicitly development-only for Phase 2; production extension ID and Chrome Web Store distribution are deferred to a later release/distribution decision.
- Settings shows the Chrome extension channel, the development extension ID, version, Native Host path, manifest path, last error code, and last local check.
- Settings gives a development install guide, opens `chrome://extensions`, reveals the unpacked extension folder, and repairs only the development native messaging manifest.
- The app does not claim silent extension installation; Chrome still owns extension loading, enablement, and site permission prompts.
- Browser regression checks derive the development extension ID from `manifest.key` and fail if it no longer matches `jednddlgkkohaebgoejcidfppddjegij`, so development native manifests cannot silently drift from the unpacked extension.

Current Phase 2.3 Edge support state:

- Settings now treats browser integration as a browser list instead of a single Chrome-only row.
- Microsoft Edge is listed with its own app detection, status badge, extension channel, shared development extension ID, extension version, Native Host path, manifest path, last error code, and last local check.
- Edge native messaging repair writes `~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/com.llmtools.native_host.json` and opens `edge://extensions`.
- Chrome and Edge manifest repair paths are independent and do not overwrite each other.
- `scripts/check-browser-extension-dom.mjs` can now run the same real-browser content-script fixture suite against Chrome or Edge through `LLMTOOLS_E2E_BROWSER=chrome|edge|all`, with `CHROME_PATH` / `EDGE_PATH` overrides for non-standard executable locations.

Current Phase 2.4 reading-mode state:

- The popup exposes current-page reading modes: replacement, bilingual, and original.
- The popup exposes current-page discovery scope: visible-first remains the default, while full-page pretranslation explicitly discovers offscreen page text up to a bounded per-session cap.
- The popup exposes current-page translation quality modes: natural, literal, and technical terminology.
- The popup exposes pending translation style selection: Loading, flip-text, and no pending style. The value persists through native llmTools webpage preferences.
- Reading mode is stored in tab state and passed to the content script when a page session starts.
- Discovery scope is stored in tab state, passed to the content script when a page session starts, reset to visible-first on navigation, and covered by long-page DOM regression checks.
- Translation quality is stored in tab state, sent to the native webpage translation request, reflected in the prompt, and included in the extension cache key so different quality modes do not reuse incompatible cached translations.
- The content script keeps translated segment data in memory and can switch replacement/bilingual/original DOM views without reloading or calling the model again.
- Bilingual rendering uses DOM nodes and textContent, not raw HTML injection, and restore clears bilingual artifacts.
- The popup has a current-page retranslate action that clears current-page cached translations, restores the DOM, and translates again with the current webpage translation model and quality mode.
- The popup can save the selected reading mode or translation quality as the current site's default. These defaults are stored in native llmTools preferences, returned through the native bridge status, applied on future page sessions for the domain, and visible/removable from Settings.

Current Phase 2.5 complex-page state:

- The content script detects same-document SPA route changes through `history.pushState`, `history.replaceState`, `popstate`, and `hashchange`.
- On SPA route change, the content script restores current llmTools translations, clears the page session, disconnects old discovery observers, and notifies the background page.
- The background page handles route-change notifications by cancelling the tab job and resetting translated state so old page sessions are not mixed into the new route.
- Reused text nodes in virtualized rows are tracked by current text hash instead of node identity alone, so changed English text can be discovered once without re-queuing unchanged translated text; detached/reattached row pools and larger reusable scroll-window feed updates are covered by the same regression fixture.
- Accessible same-origin iframe bodies are included in initial text discovery, mutation observation, translation application, and restore.
- Open shadow roots are included in initial text discovery, mutation observation, translation application, and restore for supported web components.
- Dynamic text discovery uses a 250 ms debounce plus a 1000 ms max wait, so high-frequency DOM mutations still flush periodically instead of postponing discovery forever.
- Table cells are discovered and translated, and bilingual mode uses a table-cell-specific block layout so translation/original comparison does not replace the table structure.
- Large dashboard table fixtures verify bounded full-page discovery across hundreds of sticky-header table rows, table-cell bilingual layout, and restore.
- Protected browser pages and content-script injection failures return an `unsupportedPage` state with actionable popup copy and stable diagnostics error codes instead of raw browser errors.
- Top-level PDF/browser PDF viewer URLs return an `unsupportedPage` state with a `browser_pdf_page` diagnostics code; actual PDF translation remains out of scope for the normal DOM path.
- Unsupported embedded content detection reports cross-origin or restricted frames, closed Shadow DOM/component content, canvas text candidates, image-text candidates, and PDF/embed counts in page state.
- The popup/background state appends a short partial-support notice when a translated page also contains unsupported embedded content.
- `node scripts/check-browser-extension-dom.mjs` covers background route reset, stale page-session dynamic discovery, translation application, and state update rejection, a real-browser `history.pushState` route-change smoke, reused virtualized text-node discovery, detached/reattached row pools, reusable virtual scroll-window pressure, same-origin iframe translation/restore, open shadow root translation/restore, closed Shadow DOM/component heuristics, high-frequency mutation flushing, table-cell bilingual layout/restore, unsupported embedded-content detection, and the background popup notice.

Current Phase 2.6 release-QA/privacy state:

- The extension background state generates redacted webpage diagnostics with browser ID, extension version, status, segment counts, elapsed time, model name, page URL hash, domain hash, mode settings, unsupported embedded-content counts, and error code.
- The popup displays the diagnostics summary without raw page URL, raw domain, source text, translated text, or DOM content.
- Settings exposes webpage cache/history policy, keeps webpage translation out of Recent History by default, and provides an explicit opt-in for saving webpage translation batches to Recent History.
- Browser E2E fixtures now include article, docs/code, product page, shadow components page, form/editor page, long page, table-heavy page, dashboard table stress page, iframe page, unsupported embedded-content page, and SPA/virtualized page routes.
- `swift run LLMToolsChecks` covers default-off webpage history and explicit opt-in history persistence; `node scripts/check-browser-extension-dom.mjs` covers redacted diagnostics generation, verifies non-translation native messages do not carry page text, intercepts page-side fetch/XHR/beacon calls and asserts the content script does not send page text through JS network requests, fails on real-browser runtime exceptions or console errors, can execute the content-script fixture suite in Chrome or Edge, and covers popup rendering, product button/link preservation, cancel/late-translation guarding, stale page-session dynamic discovery, translation application, and state update rejection, open shadow root translation/restore, closed Shadow DOM/component heuristics, form/editor skip behavior, long-page visible-first discovery plus scroll discovery, table-cell bilingual layout, large dashboard table full-page discovery/restore, same-origin iframe translation/restore, protected/injection-blocked page reporting, top-level PDF unsupported reporting, unsupported embedded-content reporting, SPA route reset, virtualized text-node reuse, detached/reattached virtualized row pools, and high-frequency mutation flushing.

Phase 2 closure direction:

- Preserve the Chrome 2.0 architecture as the baseline.
- Treat Chrome production distribution as a later release/distribution decision rather than a remaining Phase 2 implementation requirement.
- Add production Chrome distribution only if the user wants non-development installation in a later release track.
- Verify Edge extension loading and translation before Safari or Firefox unless user priority changes.
- Keep broader page-level controls bounded and explicit; full-page pretranslation is now current-page only and should not become a site default without a separate product decision.
- Add complex-page and embedded-content support incrementally; keep unsupported states explicit while adding actual embedded-content translation only where safe.
- Do not design for silent extension installation. Chrome, Safari, Firefox, and similar browsers require user confirmation, store distribution, enabling, or browser-controlled permission prompts outside the app's direct control.
- Keep the extension responsible for browser permissions, page text discovery, DOM replacement, restore behavior, site rules, and page-level controls.
- Keep the native macOS app responsible for model selection, prompt templates, runner lifecycle, task execution, logging, diagnostics, and local privacy controls.

Settings behavior contract:

- Show browser rows for Chrome and Edge, with statuses such as "not installed", "installed but disabled", "needs permission", "bridge missing", "paired", and "ready".
- Show extension channel, extension ID, version, native host path, manifest path, last error code, and last local check.
- Show domain rules, site defaults, cache controls, and webpage history/privacy controls.
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

Reorganized Phase 2 remaining scope:

1. Edge acceptance: install or load the Chromium extension in Microsoft Edge, repair the Edge native messaging manifest, run `LLMTOOLS_E2E_BROWSER=edge node scripts/check-browser-extension-dom.mjs`, and manually verify page translation through the packaged app.
2. Release smoke: run `./scripts/check-phase2-closure.sh`, run the Chrome development extension against representative real pages, verify app/browser restart recovery, and confirm no Phase 1 workflows regressed.
3. Acceptance bug fixing: only fix defects found during Edge acceptance, release smoke, privacy checks, or Phase 1 regression checks.
4. Documentation handoff: keep README, roadmap, and PRD aligned around the development-only Chrome decision, Edge acceptance status, cache/history policy, and known unsupported content.

Practical closure order:

1. Refresh the automated closure report with `./scripts/check-phase2-closure.sh`.
2. Load or reload the Chrome unpacked extension from `browser-extension/chromium`, then require `node scripts/check-browser-extension-install.mjs --browser chrome --require-ready` to pass.
3. Record the Chrome manual acceptance keys in the latest report with `node scripts/record-phase2-manual-check.mjs --pass <key> "<evidence>"`; the `reading-modes` key also covers the popup pending-style selector.
4. Run `node scripts/check-phase2-acceptance-status.mjs --assert-complete` and `node scripts/record-phase2-manual-check.mjs --assert-complete`.
5. If Edge becomes available, rerun closure with `LLMTOOLS_E2E_BROWSER=edge` and record real Edge acceptance instead of relying on the unavailable-browser skip.

Deferred out of the current Phase 2 closure:

- Chrome Web Store listed/unlisted production distribution and a production extension ID.
- Brave, Arc, Safari, and Firefox support.
- Actual browser PDF viewer translation.
- Browser image/canvas OCR translation; native image OCR belongs to Phase 3.
- Form-writing assistance or user-input rewriting.
- Multi-tab bulk translation and cross-device sync.
- Enterprise managed extension deployment.

Phase 2 completion checklist:

1. Chrome development flow remains usable from packaged `dist/llmTools.app`.
2. Edge either passes real browser acceptance or is explicitly deferred because Edge is unavailable in the release environment.
3. Existing Chrome behavior for domain rules, cache controls, reading modes, quality modes, retranslate, complex pages, diagnostics, and privacy remains covered by automated checks.
4. Manual smoke confirms representative real pages can translate, restore, cancel, and recover after app/browser restart.
5. Phase 1 selected-text, quick action, model registry, floating widget, recent history, and packaging regressions remain green.
6. All intentionally unsupported content shows graceful unsupported or partial-support states.

## Phase 3: Native Task Polish And Vision OCR

Goal: turn the current task-first macOS assistant into a reliable everyday tool by closing translation acceptance, improving the existing text workflows, and adding native OCR and screenshot/image explanation through explicitly configured vision-capable models.

Detailed PRD: `docs/phase-3-native-task-and-ocr-prd.md`.

Implementation record:

- Text tasks now have stricter task-specific prompt contracts for translation, polish, summarize, explain, and TODO extraction.
- Settings exposes model capability state, source, confidence, failure detail, manual vision/text-only overrides, reset-to-automatic, and an explicit OCR/vision probe action.
- OCR settings expose enablement, filtered OCR model selection, default OCR mode, model-recognition default, and OCR history opt-in.
- The image workflow accepts file, paste, drop, and remote URL inputs, normalizes local image payloads, strips metadata, enforces size limits, and avoids passing remote URLs directly to providers.
- OpenAI-compatible providers have the first implemented multimodal request path for OCR, structured extraction, translate-after-OCR, and image explanation.
- Automated checks cover old-registry migration, prompt contracts, image preprocessing, capability filtering, text-only rejection before provider calls, stub vision execution, OCR history redaction, and OpenAI-compatible image payload encoding.

Core capabilities:

- Phase 2 translation closure and acceptance bug fixing
- selected-text and quick-action translation quality hardening
- task-specific improvements for polishing, summarization, explanation, and TODO extraction
- clearer run/cancel/retry/error states across all native text tasks
- model capability metadata for text-only and vision-capable models
- capability detection through provider metadata where available, provider/model heuristics where necessary, and user-visible manual override when automatic detection is uncertain
- OCR model preference that only accepts vision-capable models
- per-run model-recognition button, plus settings to make model recognition the default and choose the model used for it
- native image OCR from image files, clipboard images, and screenshots
- OCR output modes for plain text, key-value/table preservation, and optional translate-after-OCR
- screenshot/image explanation using the configured vision-capable model
- privacy controls that make remote OCR opt-in and avoid storing raw images by default
- focused regression coverage for existing Phase 1 and Phase 2 behavior

Suggested scope:

- Finish Phase 2 acceptance before broadening browser translation.
- Improve existing text tasks before adding new document-assistant surfaces.
- Start OCR in the native app with PNG, JPEG, WebP where decodable, and clipboard/screenshot input.
- Use configured vision-capable models for OCR, structured extraction, and screenshot/image explanation; local preprocessing only handles decode, conversion, metadata stripping, temporary downloads, and size limits.
- Keep browser image/canvas OCR, PDF translation, and document indexing out of this phase unless explicitly reprioritized.

Primary acceptance:

- A user can complete Phase 2 browser-translation closure without regressing Phase 1 native tasks.
- A user can run translate, polish, summarize, explain, and extract TODOs with task-specific output that is copyable, retryable, and predictable.
- Settings clearly shows which models are text-only, vision-capable, unknown, or manually overridden.
- A non-vision model cannot be selected as the OCR model.
- A user can trigger model recognition from the image workflow and choose a vision-capable model as the default recognition model.
- A user can drop or paste an image and get extracted text with preserved line/table structure where possible.
- A user can ask llmTools to explain a screenshot/image when a vision-capable model is configured.
- OCR failures explain whether the blocker is missing vision support, provider configuration, input format, network/API failure, or no readable text.

## Phase 4: Media Intake And Live Subtitles

Goal: make llmTools process audio, video, and desktop live audio into original and translated subtitles, with Simplified Chinese as the default target language and local ASR as a hard product boundary.

Detailed PRD: `docs/phase-4-media-live-subtitles-prd.md`.

Phase 4.x enhancement PRD: `docs/phase-4x-language-speaker-fast-mt-prd.md`.

Phase 4.y live meeting transcription PRD: `docs/phase-4y-live-meeting-transcription-prd.md`.

Implementation status as of 2026-07-06:

- Implemented in the native app: speech-capable model metadata, media subtitle preferences, realtime/file ASR pickers, local ASR health checks, file media intake, macOS audio extraction/normalization, subtitle segment model, subtitle translation coordinator, SRT/VTT/TXT/Markdown export, media quick-action mode, and redacted diagnostics.
- Implemented for local ASR runtime integration: Fun-ASR-Nano and Fun-ASR-MLT-Nano realtime/file capability detection, SenseVoiceSmall realtime/file capability detection, Qwen3-ASR-0.6B file/realtime capability detection, Settings-configurable command templates for local sidecars, runtime-source health labels, ASR source-language hints, launch-time environment variable fallback through `LLMTOOLS_FUN_ASR_COMMAND`, `LLMTOOLS_SENSEVOICE_COMMAND`, `LLMTOOLS_QWEN3_ASR_COMMAND`, or `LLMTOOLS_ASR_COMMAND`, automatic `llama-funasr-cli` GGUF detection for compatible Fun-ASR folders, automatic bundled MLX runner use for supported safetensors/MLX ASR folders when the matching isolated venv is installed, plus automatic `sherpa-onnx-offline` use for SenseVoiceSmall ONNX folders where available.
- Implemented for ASR organization: Settings and Quick Action use stable model-family names and show mode/speaker capability; Settings exposes the three-layer speech pipeline and registered-model overview; custom ASR command templates remain available in one advanced disclosure. The Fun-ASR MLX/GGUF routes remain ASR-only.
- Implemented for official FunASR: the original Fun-ASR-Nano `model.pt` uses a persistent Torch/MPS sidecar for realtime subtitles, while file transcription composes Nano, FSMN-VAD, CAM++, and CT-Punc and maps `sentence_info[].spk` into existing contracts. Based on realtime meeting tests, the original Nano is excluded from meeting capture; meeting speaker quality takes priority over adding another model option.
- Implemented in the native app for desktop live subtitles: ScreenCaptureKit system-audio capture, microphone capture, mixed audio source selection, floating subtitle window, configurable global shortcut, VAD gating, partial/final/translated event plumbing, and local ASR command execution over temporary live-audio WAV windows.
- Implemented checks: `swift run LLMToolsChecks`, `swift run LLMToolsMediaSmoke --output-dir dist/phase4-media-smoke`, `node scripts/check-phase4-media-subtitles.mjs`, `node scripts/check-phase4-local-asr-runtime.mjs`, extension JavaScript syntax checks, and the existing browser DOM regression suite with browser live-subtitle permissions removed.
- Runtime dependency: real file transcription and real desktop live subtitles require a local Fun-ASR, SenseVoiceSmall, Qwen3-ASR, Whisper, or VibeVoice runtime/model on the user's Mac. Supported safetensors/MLX folders use the bundled `llmtools-mlx-asr-runner.sh`; original Fun-ASR-Nano realtime and file transcription share the isolated runtime installed by `scripts/install-phase4-funasr-pipeline-runtime.sh`; whisper.cpp keeps its own root. No path falls back to remote ASR.

Core capabilities:

- audio and video file intake
- local audio extraction and normalization to the ASR runtime format
- non-realtime transcription for recordings and videos
- timestamped subtitle generation
- subtitle translation through the existing llmTools translation engine
- SRT, VTT, TXT, and Markdown export
- Desktop live subtitles after explicit user action
- original, translated, and bilingual subtitle modes
- Fun-ASR-MLT-Nano realtime ASR runner for broad-language live subtitles
- Fun-ASR-Nano optional low-latency runner for Chinese/English/Japanese live subtitles
- SenseVoiceSmall fallback short-window ASR runner
- Qwen3-ASR-0.6B optional ASR runner for file transcription quality and experimental realtime subtitles
- VAD-based speech segmentation and silence handling
- source-language detection with confidence and low-confidence states
- model capability metadata for speech-capable models
- redacted diagnostics that do not store raw audio, transcripts, translated subtitles, page titles, or full URLs by default
- cancellation, stop, retry, and clear running/error states
- local-only ASR; no remote ASR fallback or provider mode in Phase 4

Supporting file-intake capabilities:

- always-available floating widget
- drag-to-process interaction for supported media and text/image files
- screen-edge docking and auto-collapse
- TXT and Markdown file ingestion as lightweight supporting workflows
- image file OCR handoff to the Phase 3 OCR engine
- automatic task suggestion based on file content
- file summary
- key point extraction
- action item extraction
- recent result history

Suggested scope:

- Start with file transcription before live browser subtitles: file input has clearer progress, retry, and export semantics.
- Use Fun-ASR-MLT-Nano through a local streaming runtime for broad-language realtime subtitles; use Fun-ASR-Nano where lower-latency Chinese/English/Japanese realtime matters most.
- Keep SenseVoiceSmall as a supported short-window ASR runtime where users already have a working sidecar.
- Provide Qwen3-ASR-0.6B for file transcription and optional realtime subtitles where slower but potentially higher-quality or broader Chinese-dialect support is acceptable.
- Keep live subtitles desktop-native through user-triggered system-audio and/or microphone capture. Browser-extension-hosted live subtitles, always-on microphone dictation, and meeting bots are out of scope.
- Keep ASR local-only. Remote ASR, automatic cloud fallback, and cloud live translation are not part of Phase 4.
- Translate ASR output with the existing text translation engine so target-language behavior stays consistent with selected-text and webpage translation.
- Keep PDF, DOCX, reusable document indexing, and multi-document QA in Phase 5 unless explicitly reprioritized.

Primary acceptance:

- A user can drop a supported audio or video file, generate original subtitles, translate them into Simplified Chinese, and export SRT/VTT/TXT/Markdown.
- A user can choose Fun-ASR-MLT-Nano for broad-language realtime subtitles, Fun-ASR-Nano for lower-latency Chinese/English/Japanese realtime subtitles, SenseVoiceSmall for existing short-window ASR setups, and Qwen3-ASR-0.6B for file transcription or experimental realtime subtitles.
- A user can open desktop live subtitles from the menu or global shortcut, listen to system audio and/or microphone audio, and stop capture from the floating subtitle window.
- Live subtitles can show original-only, translated-only, or bilingual modes without mutating source app or page content.
- Chinese and English are required acceptance languages. Cantonese, Japanese, Korean, Spanish, French, and German form the first multilingual smoke set.
- Low-confidence language detection shows an unknown or low-confidence state instead of fabricating certainty.
- Raw audio, transcript text, translated subtitle text, page title, and full URL are not written to diagnostics or history by default.
- Existing Phase 1 selected-text tasks, Phase 2 webpage translation, and Phase 3 OCR workflows remain unaffected.

## Phase 4.x: Language Routing, Speaker Intelligence, And Fast Local MT

Goal: strengthen Phase 2 webpage translation and Phase 4 media/live subtitles with small local infrastructure models: ultra-small text language identification, speaker diarization/embedding support, and dedicated high-speed local machine translation for webpage and subtitle workloads.

Detailed PRD: `docs/phase-4x-language-speaker-fast-mt-prd.md`.

Core capabilities:

- local text language identification for selected text, webpage segments, OCR output, and ASR transcript segments
- low-confidence and short-text language behavior for routing instead of over-confident automatic decisions
- source-language metadata on finalized subtitle segments
- speaker diarization for file subtitles, with optional speaker labels in SRT/VTT/TXT/Markdown exports
- session-local speaker labels and speaker embedding policy, with persistent speaker embeddings off by default
- optional realtime speaker-label spike that must not delay first readable subtitle text
- fast local MT runtime layer for webpage translation and subtitle translation
- task-specific engine selection: default LLM, fast local MT, or automatic routing
- structured fallback from unsupported fast-MT language pairs to the configured LLM translation engine
- redacted diagnostics for language detector, speaker diarization, and translation engine choice

Suggested scope:

- Start with language ID because it improves routing across text, OCR, webpage translation, and subtitles with very small model cost.
- Add speaker diarization to file subtitles before attempting realtime speaker labels.
- Add fast local MT to subtitles first, then webpage translation, because subtitle segment order/timing gives a smaller validation surface.
- Keep ASR local-only and keep remote/cloud ASR out of this phase.
- Keep fast MT optional. The existing LLM translation path remains the default quality path unless the user selects speed mode or automatic routing.
- Keep browser permissions unchanged; webpage fast MT should reuse the existing native bridge and DOM translation pipeline.

Primary acceptance:

- A user can enable automatic language detection and see high-confidence source-language routing across text, OCR, webpage, and finalized subtitle segments.
- A user can generate file subtitles with stable local speaker labels and export those labels.
- A user can translate subtitle segments through a local fast-MT engine without rerunning ASR and can retry with the LLM quality path.
- A user can translate a webpage through local fast MT while preserving restore, cache controls, reading modes, site rules, and privacy diagnostics.
- Unsupported or low-confidence language pairs fall back according to the user's visible preference instead of silently producing wrong output.
- Existing Phase 4 live subtitle first-text latency is not regressed by speaker diarization or fast-MT work.

## Phase 5: Local Document Assistant

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

## Phase 6: Model Routing and Automation

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
