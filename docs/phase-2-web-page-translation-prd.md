# Phase 2 PRD: Web Page Translation

Last updated: 2026-07-03

Status: active Phase 2 product and engineering plan. Phase 2.0 Chrome current-page translation is complete; this document now tracks the remaining Phase 2 expansion requirements.

## 1. Objective

Phase 2 adds browser web-page translation to llmTools.

The user should be able to open an English webpage, trigger llmTools from the browser, and see the visible English text translated into Simplified Chinese directly inside the page. The page must remain usable, translation must be reversible, and page text must stay local by default.

This phase is not a separate chat product and not a cloud translation feature. It extends the existing local-model translation engine to browser pages.

## 1.1 Completed Phase 2.0 Baseline

Phase 2.0 established the Chrome current-page translation baseline:

- Chrome MV3 extension in `browser-extension/chromium`.
- Development extension ID: `jednddlgkkohaebgoejcidfppddjegij`.
- `LLMToolsNativeHost` Swift executable target for Chrome native messaging.
- `LocalAppBridgeServer` in the macOS app, bound to `127.0.0.1` and protected by an app-generated bearer token.
- Bridge state file at `~/Library/Application Support/llmTools/web-page-bridge.json`.
- `BrowserIntegrationService` for Chrome detection, native host manifest writing, extension folder discovery, and `chrome://extensions` launch.
- Settings section `网页翻译`, including Chrome bridge repair and manual unpacked-extension guidance.
- Shared webpage translation models in `WebPageTranslationTypes`.
- App-side webpage batch translation through `TaskEngine.translateWebPageSegments`.
- Browser popup controls for translate, restore, cancel, test, and cache clear.
- Content script support for visible text discovery, English-dominant filtering, skip rules, in-page overlay, pending indicators, restore, cancellation, mutation/scroll discovery, and dynamic segment enqueueing.
- Extension background support for batching, duplicate segment reuse, native messaging, context-menu toggle, translation state, and a `chrome.storage.local` translation cache.
- Focused checks through `swift run LLMToolsChecks` and `node scripts/check-browser-extension-dom.mjs`.

Do not treat these as remaining Phase 2 requirements unless a regression is found. They are the baseline that later Phase 2 work must preserve.

## 1.2 Remaining Phase 2 Scope

The remaining Phase 2 work should be organized into these requirement groups:

1. Site rules and automatic translation controls.
2. Production Chrome distribution and repair UX.
3. Additional browser support.
4. Advanced reading and translation modes.
5. Complex webpage and embedded-content support.
6. Release-grade QA, observability, and privacy controls.

The remaining work should not reopen the Phase 2.0 Chrome bridge architecture. Extend it unless a browser policy or security finding requires a change.

## 2. Product Principles

- Local-first: webpage text is processed by the local llmTools app and local model runners by default.
- Reversible: every page translation must be restorable without reloading the page.
- Permissioned: browser extension installation, enablement, and site access must follow browser-controlled permission flows.
- Visible-first: translate what the user is reading first, then continue as more text becomes visible.
- Structure-preserving: translate text nodes without breaking links, buttons, tables, forms, layout, or page JavaScript.
- Low-friction setup: Settings should provide a guided installer and repair flow, but must not pretend browsers allow fully silent consumer extension installation.
- Observable: the app and extension should show current status, model used, progress, cancellation, and actionable errors.

## 3. Target User

Primary user:

- macOS user running llmTools locally.
- Has local Qwen models already configured from Phase 1.
- Frequently reads English documentation, articles, product pages, technical blogs, and dashboards.
- Wants page content translated in place instead of copying text into a separate app.

Primary jobs:

- Read English article/documentation in Chinese without losing page navigation.
- Translate a long page gradually while scrolling.
- Restore the original English text when translation quality or layout is not acceptable.
- Install or repair the browser extension from llmTools Settings with minimal manual work.

## 4. Platform Scope

### 4.1 Phase 2.0 MVP Browser

Build the first full MVP for Google Chrome on macOS.

Reasons:

- Chrome supports content scripts for DOM inspection and mutation.
- Chrome supports native messaging between extensions and native applications.
- Chrome is the best first target for a Manifest V3 extension and Playwright-based verification.

### 4.2 Phase 2.x Additional Browsers

After Chrome MVP is stable, add support in this order:

1. Microsoft Edge, because its native messaging model is close to Chrome.
2. Brave or Arc if user priority requires it and native messaging paths are verified.
3. Safari Web Extension, because it needs a Safari-specific containing-app/distribution path and user enablement in Safari Settings.
4. Firefox, because release/beta builds require signed add-ons and Firefox-specific manifest handling.

The Settings UI should be designed as multi-browser from the beginning, even if only Chrome is implemented in Phase 2.0.

## 5. Official Platform Constraints

These constraints are product requirements, not implementation preferences.

- Browser extensions run page-side code through content scripts. Chrome documents content scripts as code that can read and modify pages through the DOM and communicate with the extension.
- For current-tab translation, prefer temporary page access through `activeTab` plus programmatic script injection instead of blanket `<all_urls>` permission.
- Extension-to-native communication should use native messaging where possible. Chrome, Edge, and Firefox document native messaging as the browser-supported way for extensions to exchange messages with a native app.
- Native messaging manifests must be installed into browser-specific locations. On macOS, Chrome user-specific manifests live under `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`; Edge has its own `Microsoft Edge` path; Firefox uses Mozilla native manifest locations.
- Browser extension installation cannot be fully silent for normal consumer distribution. Chrome Web Store installation and permissions are browser-controlled; Safari extensions are installed/enabled through App Store/Safari settings flows; Firefox release/beta extensions must be signed.
- The app may automate local bridge assets, open the correct install/enable pages, verify connectivity, and provide exact repair steps. It must not bypass user consent or browser policy.

## 6. In Scope

### 6.1 Product

- Site/domain rules: always translate, never translate, ask every time, and clear site-specific state.
- Optional auto-translate on trusted domains, off by default.
- Production Chrome extension distribution and update path.
- Multi-browser support after Chrome, starting with Edge.
- Advanced reading modes, including bilingual/original comparison and full-page pretranslation after the current visible-first path remains stable.
- Complex-page handling for SPAs, virtualized lists, accessible frames, and table-heavy pages.
- Browser PDF viewer and image/OCR translation as later Phase 2.x extensions, not part of the already completed 2.0 baseline.
- Release-grade privacy, cache, diagnostics, and browser E2E coverage.

### 6.2 Native App

- Store and expose site/domain translation preferences.
- Show production/development extension channel, extension version, browser version, last ping, and repair diagnostics.
- Support additional browser native messaging manifest paths.
- Provide explicit cache/history controls for webpage translation.
- Keep webpage diagnostics redacted by default.
- Preserve Phase 1 native workflows while webpage features expand.

### 6.3 Browser Extension

- Domain toggle and per-site status in popup and context menu.
- Optional auto-translate permission request for domains the user enables.
- Bilingual/original comparison UI without corrupting page layout.
- Retranslate current page with a different model or quality mode.
- Production extension identity, versioning, and upgrade compatibility.
- Additional Chromium browser manifests and build/distribution variants.
- More robust SPA route, iframe, virtualized list, and PDF viewer handling.

## 7. Out of Scope

- Cloud translation APIs.
- Automatic cloud fallback.
- Translating browser internal pages such as `chrome://`, extension store pages, or browser settings pages.
- Translating user-entered form text.
- Rewriting page HTML structure.
- Persisting full page text to disk by default.
- Fully automatic translation of all websites without user opt-in.
- Silent extension installation that bypasses browser confirmation.
- Enterprise managed extension deployment.
- Mobile browser support.
- Cross-device sync.
- Multi-tab bulk translation.

## 8. Success Metrics

Remaining Phase 2 work is successful when:

- Users can set per-site behavior: ask, always translate, never translate, clear cached translations, and disable auto-translate quickly.
- Chrome has a production-like install/update path with a stable production extension ID or an explicitly documented decision to stay development-only.
- Edge can use the same webpage translation feature with the same local app bridge behavior.
- Settings can show clear status across supported browsers and repair the correct native messaging manifest for each one.
- Users can choose a readable bilingual/original comparison mode without breaking links, tables, forms, or page layout.
- Complex pages such as SPAs, table-heavy pages, documentation pages, and virtualized feeds have defined supported behavior and graceful fallback.
- Webpage cache/history behavior is explicit, user-controlled, and covered by privacy checks.
- Automated browser tests cover the supported browser/page matrix, not only the local static DOM harness.

## 9. User Stories

### 9.1 Site Translation Rules

As a user, I can decide how llmTools behaves on the current website.

Acceptance:

- Popup shows the current domain and rule: `ask`, `alwaysTranslate`, or `neverTranslate`.
- The user can enable auto-translate for the current domain only after a clear browser permission prompt when extra host permission is required.
- `neverTranslate` prevents automatic translation and hides auto-translate prompts for the domain.
- Domain rules are visible and editable in Settings.
- Clearing a domain rule does not delete unrelated model or app settings.

### 9.2 Production Chrome Distribution

As a user, I can install or update the Chrome extension through a production-like path instead of relying only on load-unpacked development mode.

Acceptance:

- A production extension ID is defined, or the product explicitly documents that Phase 2 remains development-only.
- If a Chrome Web Store path is chosen, Settings opens the correct listing and writes a manifest with the production extension ID.
- Development and production extension IDs cannot be mixed silently.
- Settings shows extension version, native host path, manifest path, and last successful connection time.
- Repair tells the user exactly whether the failure is extension missing, wrong extension ID, native host missing, app not running, or permission missing.

### 9.3 Additional Browser Support

As a user, I can use webpage translation from another supported browser after Chrome.

Acceptance:

- Edge is the first additional browser target.
- Settings detects Edge and writes/repairs the correct Edge native messaging manifest path.
- The Edge extension build uses the correct extension ID and allowed origin.
- Chrome and Edge can be installed side by side without overwriting each other's manifest or status.
- Browser rows share one visual pattern but show browser-specific repair actions and paths.

### 9.4 Bilingual Reading Mode

As a user, I can compare the original English text with the Chinese translation when direct replacement is not enough.

Acceptance:

- The user can switch between `replace`, `bilingual`, and `original` for the current page session.
- Bilingual mode does not use `innerHTML` injection for source page content.
- Links, buttons, form controls, code blocks, and tables remain usable.
- Restore returns the page to the original state without leaving duplicate bilingual artifacts.
- The mode choice is per-page by default, with optional per-domain default later.

### 9.5 Complex Page Support

As a user, I can translate common modern web pages without the page becoming unstable.

Acceptance:

- SPA route changes reset or resume translation without mixing old and new page sessions.
- Virtualized lists and constantly changing nodes are skipped or handled without repeated retranslation loops.
- Table-heavy pages preserve row/column structure.
- Accessible iframes are translated only when the extension has permission and can safely inject a content script.
- Unsupported frames, PDF viewers, closed shadow DOM, canvas, and image text show a graceful unsupported/partial state.

### 9.6 Cache, History, And Privacy Controls

As a user, I can understand and control what webpage translation data is stored locally.

Acceptance:

- Settings explains whether page translations are session-only or persisted in local extension storage.
- The user can clear current-page cache, current-domain cache, and all webpage translation cache.
- Cache entries are capped and pruned.
- Recent history remains off for webpage translation unless the user explicitly enables it.
- Logs and diagnostics use hashes/counts/error codes by default, not raw page text.

## 10. UX Requirements

### 10.1 Native Settings Panel

Extend the existing Settings section named `网页翻译`.

The section should contain:

- Master toggle: `启用网页翻译`.
- Browser integration table.
- One primary button per browser.
- `全部检测` action.
- `修复本地桥接` action when host manifest is missing or invalid.
- Production/development channel indicator.
- Extension version and last successful ping time.
- Domain rules table.
- Cache controls: clear current domain, clear all webpage cache, and reset domain rules.
- Privacy note that matches the chosen cache/history policy.
- Advanced disclosure for development mode install steps.

Browser row fields:

- Browser name.
- Browser path.
- Distribution channel.
- Extension ID.
- Extension version.
- Extension status.
- Native host status.
- Pairing status.
- Last successful ping time.
- Last error.
- Primary action.

Primary actions:

- `安装扩展`: open browser install flow and install native host manifest.
- `启用扩展`: open browser extension settings.
- `修复`: rewrite native host manifest and retest.
- `配对`: start pairing challenge.
- `测试连接`: ping extension/native app.
- `打开当前浏览器`: launch browser.

Domain rule fields:

- Domain.
- Rule: `ask`, `alwaysTranslate`, `neverTranslate`.
- Auto-translate permission state.
- Cached entry count.
- Last translated time.
- Actions: edit, clear cache, reset rule.

### 10.2 Browser Extension Popup

Popup states:

- `Not ready`: native app missing, extension not paired, or no model configured.
- `Ready`: current tab can be translated.
- `Translating`: show progress, current batch, cancel.
- `Partially translated`: some nodes translated and some failed/skipped.
- `Translated`: restore and retranslate actions.
- `Unsupported page`: browser page cannot be scripted.

Popup controls:

- `翻译当前页`
- `取消`
- `恢复原文`
- `重新翻译`
- Mode selector: `替换`, `双语`, `原文`.
- Domain toggle: `此网站自动翻译` off by default.
- Domain rule selector: `每次询问`, `总是翻译`, `永不翻译`.
- `清除此页缓存`
- Link/button to open llmTools Settings.

### 10.3 In-Page Overlay

Provide a small nonintrusive overlay during translation.

Requirements:

- Fixed position, bottom-right by default.
- Shows percent or translated/total segment count.
- Has cancel during active translation.
- Has restore after translation.
- Can be minimized.
- Must not cover selected text while user is editing.
- Must not inject global CSS that affects the host page.

## 11. Architecture

### 11.1 Component Diagram

```mermaid
flowchart LR
  User["User"]
  Browser["Chrome"]
  Popup["Extension Popup"]
  Content["Content Script"]
  SW["Extension Service Worker"]
  Host["LLMToolsNativeHost"]
  AppBridge["Local App Bridge"]
  App["llmTools App"]
  Engine["TaskEngine"]
  Runner["GGUF / MLX Runner"]

  User --> Browser
  Browser --> Popup
  Browser --> Content
  Popup --> SW
  Content --> SW
  SW --> Host
  Host --> AppBridge
  AppBridge --> App
  App --> Engine
  Engine --> Runner
```

### 11.2 Required Native Components

- `BrowserIntegrationService`: detects browsers, writes native host manifests, runs health checks, owns browser status.
- `BrowserIntegrationView`: Settings UI section.
- `WebPageTranslationService`: app-side queue, batching, cancellation, and bridge requests.
- `WebPageTranslationTypes`: shared request/response models.
- `LLMToolsNativeHost`: executable target launched by the browser through native messaging.
- `LocalAppBridge`: local-only IPC between `LLMToolsNativeHost` and the running app.

### 11.3 Required Extension Components

- `manifest.json`: MV3 manifest.
- `background.ts`: service worker, native messaging, tab job coordination.
- `popup.html` / `popup.ts`: user controls and status.
- `contentScript.ts`: content script entry.
- `domScanner.ts`: visible text-node discovery and skip rules.
- `domMutator.ts`: replacement, marker, restore.
- `language.ts`: English-dominant heuristics.
- `cache.ts`: session translation cache.
- `protocol.ts`: typed message contracts.

### 11.4 IPC Decision

Chosen MVP path:

1. Browser extension talks to `LLMToolsNativeHost` through native messaging.
2. `LLMToolsNativeHost` talks to the running app through a local-only loopback HTTP bridge.
3. The app bridge binds to `127.0.0.1`, uses a random port, and requires a bearer token written by the running app to the user-private bridge state file.

Current implementation:

- Native messaging from extension to helper is implemented by `Sources/LLMToolsNativeHost/main.swift`.
- Loopback HTTP from helper to app is implemented by `Sources/LLMToolsApp/LocalAppBridgeServer.swift`.
- Bridge state is written to `~/Library/Application Support/llmTools/web-page-bridge.json`.
- The helper reads the bridge state, checks the app PID, and forwards `getStatus`, `translateSegments`, and `cancelJob`.
- The app bridge exposes `GET /status`, `POST /translateSegments`, and `POST /cancelJob`.
- Do not expose the loopback token to the extension or page.
- Bind only to `127.0.0.1`.
- Reject all bridge requests unless they include the bearer token.

Rationale:

- Native messaging is the browser-supported extension/native boundary.
- The helper avoids giving webpages direct access to app endpoints.
- The app can keep using existing `TaskEngine` and model runners.
- Loopback HTTP is simpler to debug than a custom binary IPC during MVP.

## 12. Browser Integration Installer

### 12.1 Browser Detection

Chrome MVP detection:

- Check `/Applications/Google Chrome.app`.
- Verify bundle id `com.google.Chrome` when possible.
- Determine if Chrome is running.
- Determine expected user native host manifest path:
  `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.llmtools.native_host.json`

Future browser configs should be data-driven:

```json
{
  "id": "chrome",
  "name": "Google Chrome",
  "bundleID": "com.google.Chrome",
  "appPaths": ["/Applications/Google Chrome.app"],
  "nativeHostManifestPath": "~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.llmtools.native_host.json",
  "extensionInstallURL": "https://chromewebstore.google.com/detail/<extension-id>",
  "extensionSettingsURL": "chrome://extensions/?id=<extension-id>"
}
```

### 12.2 Native Host Manifest

Manifest name:

```text
com.llmtools.native_host
```

Chrome user-specific manifest path:

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.llmtools.native_host.json
```

Manifest shape:

```json
{
  "name": "com.llmtools.native_host",
  "description": "llmTools native messaging host",
  "path": "/absolute/path/to/LLMToolsNativeHost",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://<chrome-extension-id>/"
  ]
}
```

Rules:

- `path` must be absolute.
- `allowed_origins` must include only known production/dev extension IDs.
- File permissions should be user-readable and user-writable only where possible.
- Rewriting the manifest should be idempotent.
- Repair must validate that the executable exists and is runnable.

### 12.3 Install Flow

Production Chrome flow:

1. User clicks `安装扩展` in llmTools Settings.
2. App writes/repairs native host manifest.
3. App opens Chrome Web Store listing.
4. User clicks `Add to Chrome` and accepts permissions in Chrome.
5. Extension starts and sends `hello` through native messaging.
6. App verifies helper path, host manifest, extension ID, and pairing.
7. Settings row becomes `ready`.

Development Chrome flow:

1. User clicks `安装开发版扩展`.
2. App writes/repairs native host manifest with dev extension ID.
3. App opens `chrome://extensions`.
4. Settings shows exact local extension folder path.
5. User enables Developer Mode and loads unpacked extension.
6. Extension sends `hello`.
7. Settings row becomes `ready`.

Important:

- The app should automate everything outside Chrome's confirmation boundary.
- The app should not promise that Chrome will install or enable the extension without user confirmation.

### 12.4 Pairing Flow

Use pairing to make accidental extension/native connections visible.

Recommended MVP:

- Native app generates a short-lived pairing nonce when user clicks `配对`.
- Extension requests pairing through native messaging.
- App shows or validates the nonce.
- On success, app stores extension ID, browser ID, and pairing timestamp.

If using native messaging with strict `allowed_origins`, pairing can be lightweight. The main value is user visibility and repair diagnostics.

## 13. Extension Permissions

Chrome MVP manifest permissions:

```json
{
  "manifest_version": 3,
  "name": "llmTools",
  "permissions": [
    "activeTab",
    "scripting",
    "storage",
    "nativeMessaging"
  ],
  "host_permissions": [],
  "background": {
    "service_worker": "background.js"
  },
  "action": {
    "default_popup": "popup.html"
  }
}
```

Rules:

- Use `activeTab` for manual current-tab translation.
- Use `chrome.scripting.executeScript` to inject content script after user action.
- Do not request `<all_urls>` in the MVP.
- Request optional per-domain host permissions only when adding auto-translate for a domain.
- Do not use remote code.
- Keep extension storage minimal and avoid storing page text persistently.

## 14. DOM Translation Requirements

### 14.1 Text Discovery

Use `TreeWalker` to discover text nodes under `document.body`.

Include a text node only when:

- It has non-empty normalized text.
- It is inside a visible element.
- It is not in a skipped element.
- It is English-dominant.
- It has not already been processed in the current page session.

Skip elements:

- `script`
- `style`
- `noscript`
- `template`
- `svg`
- `canvas`
- `code`
- `pre`
- `kbd`
- `samp`
- `textarea`
- `input`
- `select`
- `option`
- editable elements
- elements with `aria-hidden="true"`
- elements hidden by CSS

Visibility checks:

- `display !== "none"`
- `visibility !== "hidden"`
- `opacity !== "0"`
- element has visible client rects
- text node is inside current or near-future viewport for visible-first mode

### 14.2 English-Dominant Heuristic

Translate only English-dominant text by default.

Suggested heuristic:

- Normalize whitespace.
- Skip if fewer than 3 Latin letters.
- Skip if text is mostly digits, punctuation, URL, email, hash, UUID, or code-like token.
- Translate if Latin letters are at least 60% of all letters.
- Skip if CJK characters are already at least 25% of all letters.
- Skip very short all-caps labels unless surrounded by sentence-like context.

This heuristic should live in the extension and be unit-tested with examples.

### 14.3 Segmentation

Segment at text-node level, but batch multiple segments per native request.

Segment fields:

- `segmentID`
- `nodeID`
- `frameID`
- `text`
- `tagName`
- `blockContext`
- `priority`
- `textHash`

Batch limits:

- Max 20 segments per batch.
- Max 2,000 source characters per batch for MVP.
- Max 200 batches queued per tab before requiring user confirmation.
- Retry individual segments when a batch response cannot be parsed safely.

Rationale:

- Small local models are more reliable with small batches.
- Native messaging message-size limits make smaller batches safer.
- Per-segment retry avoids losing a whole page because one model response is malformed.

### 14.4 Replacement

Replacement rules:

- Replace only `Text.nodeValue`.
- Do not assign `innerHTML`.
- Do not remove or recreate host elements.
- Add markers through WeakMap/session state first. Use DOM attributes only on host elements if needed for restore/debug.
- Preserve leading/trailing whitespace around the text node.
- If translated text is empty or identical after normalization, keep original.
- If applying translation throws because node detached, mark segment as `stale` and skip.

### 14.5 Restore

Restore rules:

- Store original `nodeValue` in memory before first replacement.
- Restore only nodes replaced by llmTools.
- If node no longer exists, ignore.
- If page has changed a translated node after replacement, do not overwrite by default. Mark as `changedAfterTranslation`.
- Clear observers, pending queue, and in-page overlay after restore.

### 14.6 Dynamic Content

Use:

- `IntersectionObserver` for visible/newly visible candidates.
- `MutationObserver` for DOM changes.
- Debounced queueing after scroll and mutations.

Rules:

- Initial pass translates visible viewport plus a small prefetch margin.
- Newly visible untranslated nodes are queued if page session is active.
- Do not retranslate nodes whose original text hash has already been translated.
- Use exponential backoff on pages that constantly mutate the same nodes.

## 15. Translation Behavior

### 15.1 Task Type

Add a webpage-specific task path.

Implementation options:

- Add `TaskKind.webPageTranslate`, or
- Keep `TaskKind.translate` and add `TranslationOrigin.webPage`.

Recommended:

- Add explicit webpage request/response types in `LLMToolsCore`.
- Internally reuse prompt generation and runner execution.
- Keep webpage translation out of normal recent history unless user opts in.

### 15.2 Prompt

System prompt:

```text
You are a webpage translation engine. Translate English webpage text to Simplified Chinese.
Preserve meaning, numbers, names, URLs, product names, code-like tokens, and UI intent.
Return only valid JSON that follows the requested schema.
Do not explain.
```

Batch user prompt:

```text
Translate each item to Simplified Chinese.
Return a JSON array with objects in the same order:
[
  {"id":"...", "translation":"..."}
]

Rules:
- Preserve links, numbers, product names, keyboard shortcuts, and code-like tokens.
- For buttons and short UI labels, use concise Chinese.
- For paragraphs, use natural Chinese.
- Do not add commentary.

Items:
[
  {"id":"s1","text":"..."},
  {"id":"s2","text":"..."}
]
```

Fallback:

- If JSON parsing fails, retry the batch once with stricter prompt.
- If retry fails, translate segments individually with plain-text output.
- If individual translation fails, mark that segment failed and continue.

### 15.3 Model Routing

MVP:

- Use the existing default model from Phase 1.
- Allow user to choose a webpage translation model in advanced settings later.
- Show model name in extension status and app Settings.

Future:

- 0.8B for language detection and simple UI labels.
- 4B default for ordinary pages.
- 9B for long/technical pages or quality mode.

## 16. Protocol

### 16.1 Native Messaging Envelope

Every request:

```json
{
  "protocolVersion": 1,
  "requestID": "uuid",
  "type": "translateSegments",
  "browserID": "chrome",
  "extensionVersion": "0.1.0",
  "tabID": 123,
  "pageSessionID": "uuid",
  "sentAt": "2026-06-30T12:00:00Z",
  "payload": {}
}
```

Every response:

```json
{
  "protocolVersion": 1,
  "requestID": "uuid",
  "type": "translateSegments.result",
  "status": "ok",
  "payload": {},
  "error": null
}
```

### 16.2 Message Types

- `hello`: extension/native handshake.
- `getStatus`: app, model, bridge, and pairing status.
- `startPairing`: start pairing challenge.
- `confirmPairing`: complete pairing.
- `translateSegments`: translate a batch.
- `cancelJob`: cancel queued/running work for a page session.
- `openSettings`: ask native app to open Settings to browser integration section.
- `diagnostics`: redacted setup details for troubleshooting.

### 16.3 Translate Segments Request

```json
{
  "jobID": "uuid",
  "sourceLanguage": "en",
  "targetLanguage": "zh-Hans",
  "urlHash": "sha256-url",
  "title": "optional page title",
  "segments": [
    {
      "segmentID": "s1",
      "text": "The quick brown fox.",
      "tagName": "P",
      "blockContext": "article",
      "priority": 10,
      "textHash": "sha256-text"
    }
  ]
}
```

### 16.4 Translate Segments Response

```json
{
  "jobID": "uuid",
  "modelName": "Qwen 4B MLX 4bit",
  "translations": [
    {
      "segmentID": "s1",
      "translation": "敏捷的棕色狐狸。",
      "status": "translated"
    }
  ],
  "usage": {
    "sourceCharacters": 20,
    "targetCharacters": 9
  }
}
```

### 16.5 Error Codes

- `app_not_running`
- `native_host_missing`
- `native_host_invalid`
- `extension_not_paired`
- `extension_not_allowed`
- `model_not_configured`
- `model_not_ready`
- `model_load_failed`
- `translation_failed`
- `payload_too_large`
- `timeout`
- `cancelled`
- `permission_missing`
- `unsupported_page`
- `tab_changed`
- `page_session_expired`
- `rate_limited`
- `internal_error`

Every error must include:

- machine-readable code
- user-facing Chinese message
- repair action when available
- redacted diagnostic detail

## 17. State Machines

### 17.1 Browser Integration Status

```text
notInstalled
extensionMissing
extensionInstalledDisabled
permissionMissing
nativeHostMissing
nativeHostInvalid
appNotRunning
pairingRequired
ready
failed
```

### 17.2 Page Translation Status

```text
idle
unsupportedPage
discovering
waitingForModel
translating
applying
partiallyTranslated
translated
cancelling
cancelled
restoring
restored
failed
```

### 17.3 Segment Status

```text
pending
skipped
queued
translating
translated
applied
failed
stale
restored
changedAfterTranslation
```

## 18. Data Model

### 18.1 App Preferences Additions

Proposed additions to `AppPreferences` or a dedicated registry section:

```swift
public struct WebPageTranslationPreferences: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var defaultTargetLanguage: String
    public var translateVisibleOnly: Bool
    public var autoTranslateDomains: [String]
    public var disabledDomains: [String]
    public var persistWebHistory: Bool
    public var maxSegmentsPerBatch: Int
    public var maxCharactersPerBatch: Int
}
```

Defaults:

- `enabled = true`
- `defaultTargetLanguage = "zh-Hans"`
- `translateVisibleOnly = true`
- `autoTranslateDomains = []`
- `disabledDomains = []`
- `persistWebHistory = false`
- `maxSegmentsPerBatch = 20`
- `maxCharactersPerBatch = 2000`

### 18.2 Browser Integration State

```swift
public struct BrowserIntegrationState: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var bundleID: String
    public var appPath: String?
    public var extensionID: String?
    public var extensionVersion: String?
    public var nativeHostManifestPath: String?
    public var status: BrowserIntegrationStatus
    public var pairedAt: Date?
    public var lastPingAt: Date?
    public var lastErrorCode: String?
    public var lastErrorMessage: String?
}
```

### 18.3 History Policy

Default:

- Do not save source text or translated webpage text to existing recent history.
- Do not persist full page content.
- Store only redacted diagnostics: timestamp, browser, domain hash, segment count, model, status, error code.

Optional future setting:

- User can opt into webpage translation history.
- If enabled, store title, URL, source preview, translation preview, and model.

## 19. Caching

### 19.1 Session Cache

Extension keeps an in-memory session cache:

```text
cacheKey = sha256(promptVersion + targetLanguage + normalizedSourceText)
```

Cache value:

- translated text
- model name
- timestamp

Rules:

- Use cache within the current page session.
- Do not persist page text to disk.
- Clear cache on restore, tab close, extension reload, or user clear.

Current implementation note:

- The extension also has a `chrome.storage.local` cache keyed by target language, URL hash, and text hash.
- Cached entries include source text, translated text, target language, URL hash, text hash, model name, and update time.
- The popup includes a current-page cache clear action.
- Remaining Phase 2 work should formalize this as a product feature by exposing the policy in Settings/README, adding domain/all-cache clearing, enforcing caps, and testing that cached content remains local.

Persistent cache product requirements:

- Keep storage local to the extension.
- Cap entries and prune deterministically.
- Add a visible clear-cache action.
- Document that page source snippets and translations can be retained locally.
- Add automated checks that no cache data is sent remotely.

### 19.2 App Cache

MVP:

- No persistent app-side webpage text cache.

Future:

- Optional encrypted local cache with explicit user setting.
- Cache key includes model ID and prompt version.

## 20. Performance Requirements

- First visible translation should start applying within 10 seconds on a normal article page after model is warm.
- Initial DOM scan should not block the page for more than 50 ms chunks.
- DOM application should run in chunks using `requestAnimationFrame` or micro-batched time slicing.
- Only one active translation batch per tab in MVP.
- App should serialize model generation globally unless the runner layer later supports safe parallelism.
- Extension should pause queueing when tab is hidden.
- Large pages should show confirmation when more than 200 batches are estimated.
- Batch timeout default: 90 seconds.
- Segment retry limit: 1 batch retry and 1 individual retry.

## 21. Privacy And Security Requirements

- Page text is local-only by default.
- Extension must not send page text to remote servers.
- Extension must not load remote scripts.
- Extension must use least-privilege permissions.
- Native host must accept messages only from configured extension IDs.
- App bridge must bind to `127.0.0.1` only if loopback HTTP is used.
- App bridge must require a random bearer token.
- Bridge token must be stored in a user-private app support file.
- Logs must redact segment text by default.
- Diagnostics can include text hashes, counts, timing, model name, browser, and error codes.
- User can clear browser integration pairing and caches from Settings.
- Random webpages must not be able to call the translation API directly.
- Cross-origin frames should be translated only when the extension has permission and content script access.

## 22. Unsupported And Edge Cases

The extension must detect or safely handle:

- `chrome://`, `edge://`, `about:`, extension store pages, and browser settings pages.
- Pages where content scripts cannot be injected.
- Pages with strict frames or inaccessible cross-origin iframes.
- Closed Shadow DOM.
- Canvas/image/video text.
- Browser PDF viewers.
- Pages that replace DOM nodes continuously.
- Virtualized lists that detach nodes while translating.
- Single-page apps that change route without full reload.
- Pages with mixed Chinese/English content.
- Code documentation pages where code blocks must be skipped.
- Forms, editors, and contenteditable areas.
- Sites that already run machine translation.
- Very long legal/license pages.
- Model unavailable, loading, or failed.
- App quits during translation.
- Browser restarts during pairing.

Expected behavior:

- Never corrupt page structure.
- Prefer skipping uncertain nodes over translating risky nodes.
- Show partial success when some segments fail.
- Restore should remain available after partial success.

## 23. Remaining Implementation Plan

### Phase 2.0: Chrome Current-Page Translation - Done

The Chrome baseline is complete and is now the compatibility contract for later Phase 2 work:

- Development Chrome extension.
- Native messaging host.
- Local app bridge.
- Current-page translation.
- Restore original.
- Cancel translation.
- Dynamic scroll translation.
- Repeated-text cache.
- Context-menu toggle.
- Popup and in-page overlay.
- Settings entry and bridge repair flow.
- Packaged-app workflow.

### Phase 2.1: Site Rules And Auto-Translate

Goal: make webpage translation behave predictably per website instead of being only a manual per-page action.

Requirements:

- Add domain rule states: `ask`, `alwaysTranslate`, `neverTranslate`.
- Show current domain and rule in the popup.
- Add a domain rule table in Settings.
- Support optional auto-translate for a domain after explicit user opt-in.
- Request optional host permissions only when needed for auto-translate.
- Allow clearing current-page, current-domain, and all webpage translation cache.
- Keep `neverTranslate` stronger than auto-translate and context-menu actions.
- Make route changes and newly opened pages respect the domain rule.

Exit criteria:

- User can set `alwaysTranslate` on a documentation site and future pages on that domain translate automatically.
- User can set `neverTranslate` on a site and no automatic translation runs there.
- User can clear a domain's cached translations and rule independently.
- No global all-sites auto-translation is enabled by default.

### Phase 2.2: Production Chrome Distribution

Goal: move Chrome support from development-only loading toward a reproducible production-like install/update path.

Requirements:

- Decide production distribution: Chrome Web Store listed, Chrome Web Store unlisted, or development-only for now.
- If production distribution is chosen, define the production extension ID and keep it separate from `jednddlgkkohaebgoejcidfppddjegij`.
- Generate or maintain manifests for both development and production extension IDs.
- Settings should show extension channel, extension ID, version, native host path, manifest path, and last ping.
- Repair should detect stale/wrong manifest, wrong extension ID, missing host executable, and app-not-running states.
- README should document production and development install flows separately.

Exit criteria:

- The app can repair the native messaging manifest for the selected Chrome extension channel.
- The user can tell whether the loaded extension is development or production.
- Extension updates do not silently break allowed origins.

### Phase 2.3: Additional Browser Support

Goal: reuse the proven Chrome architecture in other desktop browsers without weakening the permission model.

Priority:

1. Microsoft Edge.
2. Brave or Arc if the user explicitly prioritizes them.
3. Safari Web Extension after Chromium behavior is stable.
4. Firefox only if it becomes a clear priority.

Requirements:

- Add browser config objects for each supported browser: bundle id, app paths, native messaging manifest path, extension ID, install URL, settings URL.
- Add Settings rows for installed supported browsers.
- Add manifest repair for Edge first.
- Keep browser-specific manifests independent.
- Ensure one browser's repair action never overwrites another browser's manifest.
- For Safari, plan the containing-app and Safari extension enablement flow separately.

Exit criteria:

- Edge can translate pages through llmTools with the same local privacy boundary as Chrome.
- Chrome and Edge can coexist with correct manifests and status.
- Unsupported browsers show clear manual or unsupported state.

### Phase 2.4: Advanced Reading Modes

Goal: give the user more control over how translations appear on the page.

Requirements:

- Add page mode selector: `replace`, `bilingual`, `original`.
- Bilingual mode should preserve layout and avoid unsafe HTML injection.
- Add `retranslate` with the selected webpage translation model or quality mode.
- Add page-level translation quality controls such as simpler wording, more literal translation, or technical translation after the core mode switch is stable.
- Preserve restore behavior across mode changes.

Exit criteria:

- User can switch between Chinese-only replacement, bilingual view, and original text without reloading.
- Bilingual mode does not break links, forms, tables, or code blocks.
- Retranslation replaces prior llmTools translations without duplicating artifacts.

### Phase 2.5: Complex Pages And Embedded Content

Goal: expand from normal articles/docs pages to harder but common web content.

Requirements:

- Handle SPA route changes cleanly.
- Avoid infinite translation loops on virtualized lists and constantly mutating DOM.
- Improve table-heavy page behavior.
- Translate accessible same-origin iframes when content script injection is allowed.
- Detect and explain unsupported frames, closed shadow DOM, canvas/image text, browser PDF viewers, and pages that block injection.
- Add browser PDF viewer translation only after ordinary DOM and iframe handling remain stable.
- Add image/canvas/OCR translation only after PDF/browser embedding is stable.

Exit criteria:

- SPA route changes do not mix old and new translations.
- Virtualized feeds do not repeatedly retranslate the same content.
- Table layout remains usable after translation.
- Unsupported embedded content produces a clear partial state instead of silent failure.

### Phase 2.6: Release-Grade QA, Privacy, And Diagnostics

Goal: make the expanded Phase 2 surface maintainable.

Requirements:

- Add browser E2E fixtures for article, docs/code, product page, table-heavy page, SPA route, virtualized list, form/editor page, iframe page, and unsupported PDF/canvas page.
- Add diagnostics that expose counts, timings, browser, extension version, model, and error codes without raw page text by default.
- Document webpage cache and history policy in README and Settings.
- Keep Phase 1 regression checks in the acceptance path.
- Keep `swift run LLMToolsChecks` and `node scripts/check-browser-extension-dom.mjs` passing.
- Package `dist/llmTools.app` for release-grade checks when browser integration changes.

Exit criteria:

- New browser/page support has automated coverage.
- Privacy behavior is explicit and testable.
- Debug output is useful without leaking raw page content.

## 24. Test Plan

### 24.1 Unit Tests

Native:

- browser detection config
- native host manifest generation
- manifest path expansion
- bridge token generation
- protocol request/response decoding
- error mapping
- webpage prompt fallback behavior
- domain rule persistence and precedence
- multi-browser manifest path generation
- production/development extension ID selection
- cache/history preference migration

Extension:

- English-dominant heuristic
- skip element rules
- visible element detection
- segmentation limits
- cache key normalization
- restore behavior for detached/changed nodes
- protocol envelope validation
- domain rule matching
- auto-translate permission gating
- mode switching between replace, bilingual, and original
- cache clear by page/domain/all

### 24.2 Integration Tests

- Native host starts and responds to `hello`.
- Native host rejects unknown extension origin.
- App bridge rejects missing/invalid token.
- App bridge returns `model_not_configured` when no model exists.
- Translation batch returns expected schema.
- Cancel request cancels queued batches.
- Domain rules are shared correctly between Settings and extension behavior.
- Chrome and Edge manifests can coexist.
- Production and development Chrome extension IDs do not overwrite each other.

### 24.3 Browser E2E Tests

Use Playwright or an equivalent browser automation path where possible. Keep the existing DOM harness for fast extension logic checks.

Test pages:

- article page with headings, paragraphs, links
- documentation page with code/pre blocks
- product page with buttons and cards
- table-heavy page
- long page with 500+ segments
- SPA page with route change
- dynamic page appending content after scroll
- form page with inputs/contenteditable
- page with iframes
- SPA route-change page
- virtualized list page
- unsupported PDF/canvas fixture

Assertions:

- visible English text becomes Chinese
- skipped elements remain unchanged
- links still navigate
- buttons still click
- restore returns original text
- cancel prevents further replacements
- no console errors from extension
- no remote network requests containing page text
- domain rules drive auto/manual behavior correctly
- bilingual mode can switch back to original without duplicates
- cache clearing removes the intended scope only
- Chrome and Edge behavior match where both are supported

### 24.4 Manual Acceptance Tests

Run against:

- English blog article.
- English technical documentation page.
- GitHub README page with code blocks.
- Product marketing page.
- Long news article.
- A multi-page documentation site with per-domain auto-translate enabled.
- A SPA documentation/product site.
- A table-heavy dashboard or docs page.
- Edge after browser support is added.

Manual checks:

- Translation readability.
- Layout stability.
- Link/button usability.
- Restore correctness.
- Extension/app status clarity.
- App restart and browser restart recovery.
- Domain rule clarity.
- Production/development extension channel clarity.
- Cache/history privacy controls.

## 25. Definition Of Done

Remaining Phase 2 is done when:

- Phase 2.1 site rules and auto-translate are implemented with explicit user opt-in.
- Phase 2.2 has either a production Chrome distribution path or a documented decision to remain development-only.
- Phase 2.3 supports Edge or records a product decision to defer additional browsers.
- Phase 2.4 provides a stable bilingual/original comparison mode.
- Phase 2.5 defines and implements the supported behavior for complex pages, with graceful unsupported states.
- Phase 2.6 test/privacy/diagnostic requirements are satisfied.
- Page text is not persisted beyond the accepted local cache/history policy.
- Cache/history behavior is visible, clearable, and documented.
- Logs and diagnostics are redacted by default.
- Automated tests cover domain rules, cache scope, browser manifests, mode switching, DOM skip rules, protocol, and supported browser E2E flows.
- Packaged app verification uses `./scripts/package-app.sh`, launches `dist/llmTools.app`, and verifies the running app path before final acceptance of browser-integration changes.

## 26. Open Decisions

Resolve while executing the remaining Phase 2 requirement groups:

- Cache policy: keep the current `chrome.storage.local` persistent extension cache as a formal product feature, or restrict persistence to domain/page metadata only?
- Production extension distribution path: Chrome Web Store listed, Chrome Web Store unlisted, or development-only until later?
- Exact Chrome production extension ID. Development ID is currently `jednddlgkkohaebgoejcidfppddjegij`.
- Whether app sandboxing or App Store distribution is planned soon. This affects native host manifest installation.
- First additional browser is recommended to be Edge, but user priority can override this.
- Whether browser PDF viewer translation belongs in Phase 2.5 or should move to a later document/PDF phase.
- Whether image/canvas/OCR translation belongs in Phase 2.5 or should remain out of scope until a dedicated OCR phase.

Recommended defaults:

- Treat persistent extension cache as accepted only if Settings and README clearly expose and clear it.
- Chrome Web Store unlisted extension for production-like testing once the user wants non-development installation.
- Native messaging helper plus loopback HTTP bridge is the current MVP implementation.
- Edge as second Chromium browser.
- Safari after Chrome/Edge behavior is stable.

## 27. Reference Links

- Chrome content scripts: https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts
- Chrome activeTab permission: https://developer.chrome.com/docs/extensions/develop/concepts/activeTab
- Chrome scripting API: https://developer.chrome.com/docs/extensions/reference/api/scripting
- Chrome native messaging: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
- Chrome alternative extension installation: https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions
- Chrome Web Store install user flow: https://support.google.com/chrome_webstore/answer/2664769
- Safari Web Extensions: https://developer.apple.com/documentation/safariservices/safari-web-extensions
- Safari extension enablement: https://support.apple.com/en-us/102343
- Safari extension preferences API: https://developer.apple.com/documentation/safariservices/sfsafariapplication/showpreferencesforextension%28withidentifier%3Acompletionhandler%3A%29
- Firefox native messaging: https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging
- Firefox native manifests: https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_manifests
- Firefox signing and distribution: https://extensionworkshop.com/documentation/publish/signing-and-distribution-overview/
