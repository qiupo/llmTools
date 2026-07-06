# Phase 3 PRD: Native Task Polish And Vision OCR

Last updated: 2026-07-04

Status: implementation baseline complete as of 2026-07-04. Phase 2 closure has been recorded through the closure toolchain, with remaining acceptance limited to external browser readiness/manual smoke items; live OCR acceptance requires a configured vision-capable provider model.

## 1. Objective

Phase 3 makes llmTools stronger as a task-first macOS assistant.

The phase has two product tracks:

1. Close and harden the existing translation and native text-task workflows.
2. Add a native image OCR and image-explanation workflow powered by a configured vision-capable model.

The user should be able to rely on the app for everyday selected-text translation, polishing, summarization, explanation, TODO extraction, and image text extraction without guessing which model supports which input type.

This is not a broad chat feature, a browser image-translation feature, or a document indexing system. OCR starts as a native app workflow with explicit model capability checks.

## 1.1 Implementation Record

The 2026-07-04 implementation landed the Phase 3 baseline described by this PRD:

- Phase 2 closure commands are runnable and the packaged app is the verification target.
- Native text-task prompts were tightened for translation, polish, summarize, explain, and TODO extraction.
- Task results can be reused through follow-up actions into translate, polish, summarize, explain, and TODO extraction.
- `ModelDescriptor` persists capability metadata and older registries decode with safe defaults.
- Settings shows capability badges, source/confidence/failure details, manual vision/text-only overrides, reset-to-automatic, and an explicit OCR/vision probe.
- `OCRPreferences` is part of `AppPreferences`, with enablement, filtered OCR model selection, default OCR mode, model-recognition default, history opt-in, and stale model cleanup.
- The image workflow has file, paste, drop, and remote URL loading, local normalization, metadata stripping, size limits, preview, and redacted image descriptors.
- `VisionModelRunner` and the OpenAI-compatible runner provide the first model-vision OCR request path using normalized local image data URLs.
- OCR modes cover plain text, structured extraction, extract-then-translate, and screenshot/image explanation.
- OCR history remains opt-in and stores redacted image descriptors instead of raw image bytes, base64 payloads, or file paths.
- Automated checks cover capability migration/filtering, prompt contracts, image preprocessing, text-only OCR rejection, stub vision OCR, history redaction, and OpenAI-compatible multimodal payload encoding.
- `swift run LLMToolsLiveOCRCheck` provides the live provider gate when a real OpenAI-compatible vision model is configured. It configures/selects the OCR model, runs a vision probe, OCRs a generated fixture image, and runs image explanation.
- `node scripts/check-phase3-goal-audit.mjs --run-checks --run-live-ocr` summarizes the current end-to-end evidence and refuses to assert completion while Chrome/manual Phase 2 acceptance is still blocked.

Remaining manual acceptance is environment-bound: Chrome must load the unpacked extension from this repo for final packaged-app browser smoke, Edge acceptance needs Edge installed, and live OCR/image explanation needs a real configured vision-capable provider model.

## 2. Scope Summary

### 2.1 In Scope

- Finish Phase 2 translation closure tasks and fix acceptance defects.
- Improve native translation quality, run states, retry behavior, and copy/reuse paths.
- Improve polishing, summarization, explanation, and TODO extraction so they feel like first-class tasks rather than generic prompt variants.
- Add model capability metadata for text and image input.
- Detect or infer whether a configured model supports vision.
- Let the user manually override model capability when automatic detection is unavailable or wrong.
- Add a dedicated OCR model setting that only accepts vision-capable models.
- Add model-vision OCR from local image files, clipboard images, and screenshots.
- Add explicit model-recognition controls: a per-run button, a setting to use model recognition by default, and a configurable vision-capable model.
- Add OCR output modes: plain text, structured extraction, and optional translate-after-OCR.
- Add screenshot/image explanation as a Phase 3 vision feature, using the configured vision-capable model when visual context matters.
- Keep raw image storage off by default.
- Add automated checks for capability filtering, OCR prompt generation, task regressions, and privacy defaults.

### 2.2 Out Of Scope

- Browser image/canvas OCR inside webpage translation.
- Browser PDF viewer translation.
- Full PDF, DOCX, or multi-document understanding.
- Apple Vision, VisionKit, or any Apple-provided OCR/visual recognition path.
- Local multimodal LLM running unless a real local vision runner is added.
- Silent cloud OCR fallback.
- Cross-device sync.
- Automatic storage of raw source images.
- General chat sessions.

## 3. Product Principles

- Task-first: every surface starts from a concrete user job, not from a blank chat box.
- Capability-aware: the app must not offer OCR through a model that is known to be text-only.
- Honest detection: when model capability cannot be proven, show the confidence and ask for an explicit user decision.
- Local-first for preprocessing: images are read, downloaded, normalized, converted, size-checked, metadata-stripped, and temporarily stored by the app before model recognition. Recognition itself is performed by the configured vision-capable model.
- Model recognition is explicit and configurable: the user can trigger model recognition for a run, set model recognition as the default for image workflows, and choose the model used for that mode.
- Privacy by default: raw images and OCR source content are not retained unless the user opts in.
- Do not pass remote image URLs directly to models or providers. Download remote images into a local temporary file, normalize and strip metadata, then send only the normalized local image payload to the configured model.
- Reversible and retryable: task output should be copyable, rerunnable, and cancellable without losing input.
- Do not regress Phase 1 and Phase 2: selected-text workflows and browser translation must remain green while OCR is added.

## 3.1 External Implementation References

Phase 3 should follow current provider API shapes rather than assuming that all "OpenAI-compatible" endpoints expose the same multimodal contract.

Reference conclusions from official docs:

- OpenAI-compatible image input is commonly expressed as text plus an `image_url` content block, including data URLs for base64 images. This is the best first shared path for OpenAI, OpenRouter, Ollama, and many local OpenAI-compatible servers.
- Anthropic Messages uses provider-specific image content blocks with a source containing media type and base64 data. It should be treated as a later provider-specific extension, not the first Phase 3 OCR provider path.
- Gemini supports multimodal image input, but the OpenAI-compatible path and the native Gemini path should not be treated as the same implementation. The current app has only an OpenAI-compatible Gemini preset, so Phase 3 should start there and leave a native Gemini runner as later work.
- OpenRouter exposes model modality metadata such as text/image support in its model data, so it can provide higher-confidence capability detection than providers that return only model IDs.
- Remote image URL handling should be app-owned: fetch to a temporary local file first, enforce file type/size limits, strip metadata, then construct the provider payload from the normalized local data only when the user-selected model path requires it.

Implementation implication: do not hard-code one universal multimodal payload. Add a small capability and payload layer that can branch by provider/API style while keeping the UI model simple.

Reference links:

- OpenAI Images and Vision: `https://developers.openai.com/api/docs/guides/images-vision`
- Anthropic Vision: `https://docs.anthropic.com/en/docs/build-with-claude/vision`
- Gemini image understanding: `https://ai.google.dev/gemini-api/docs/image-understanding`
- OpenRouter multimodal capabilities: `https://openrouter.ai/docs/guides/overview/multimodal/overview`
- OpenRouter model metadata/API: `https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties`
- Ollama OpenAI compatibility: `https://docs.ollama.com/api/openai-compatibility`

## 4. User Stories

### 4.1 Translation Closure

As a user, I can complete the remaining browser-translation acceptance work and still use selected-text translation without regressions.

Acceptance:

- Phase 2 closure commands and manual acceptance keys remain documented and runnable.
- Chrome packaged-app smoke is recorded or explicitly blocked by browser-extension readiness.
- Edge acceptance is recorded when Edge is available, or explicitly skipped with a reason.
- Selected-text and quick-action translation still produce output-only translations.
- Translation failures explain the actionable cause: no model, model load failure, request failure, empty result, cancellation, or input too large.

### 4.2 Text Task Polish

As a user, I can use polish, summarize, explain, and extract-TODOs with predictable task-specific output.

Acceptance:

- Polish supports at least natural, formal, concise, conversational, and technical styles.
- Summarize produces compact key points by default and keeps action items distinct when present.
- Explain uses plain Chinese by default and can explain terms, errors, logs, code snippets, and dense paragraphs.
- TODO extraction outputs actionable bullet items and does not invent owners, dates, or priorities.
- Each task has clear empty-input, running, cancelled, failed, and completed states.
- Existing keyboard behavior in input fields remains normal for `cmd+a/c/v/x/z`.

### 4.3 Model Capability Visibility

As a user, I can see whether a model is text-only, vision-capable, unknown, or manually overridden.

Acceptance:

- Model cards show capability badges.
- Settings exposes capability source: detected, inferred, probe-passed, manual, failed-probe, or unknown.
- Settings exposes confidence and last-checked time when available.
- Local GGUF and MLX models default to text-only unless a real multimodal local runner marks them otherwise.
- Provider-backed models can be marked vision-capable through provider metadata, provider heuristics, or manual override.
- Capability changes are persisted in the model registry.
- Manual override is visible and reversible.

### 4.4 OCR Model Selection

As a user, I can configure which model is used for OCR.

Acceptance:

- OCR and image explanation require a configured vision-capable model.
- OCR model setting only lists enabled models that are vision-capable or manually marked vision-capable.
- If no vision-capable model exists, the OCR/image entry point shows a setup action instead of a broken run button.
- The default OCR model can be separate from the default text model and the webpage translation model.
- Disabling or deleting the OCR model clears the OCR preference safely.
- Provider validation failures do not silently fall back to a text-only model.

### 4.5 Native Image OCR

As a user, I can provide an image and extract text from it.

Acceptance:

- User can choose an image file from the native app.
- User can paste or drop a clipboard/screenshot image where the OCR surface is active.
- Supported initial formats: PNG, JPEG, and WebP where native decoding succeeds. HEIC can be accepted by decoding locally and converting before provider upload.
- The app shows a lightweight preview, file name when available, pixel size when known, and model to be used.
- The OCR result preserves line breaks and table/key-value structure where possible.
- If no readable text is found, the result says that no readable text was detected instead of inventing content.
- OCR can be cancelled while waiting for the provider.
- OCR output is copyable and can be sent into translate, summarize, explain, or TODO extraction as follow-up text.
- OCR output keeps raw model output and cleaned display text separate where they differ, so the user can inspect what changed.

### 4.6 Screenshot And Image Explanation

As a user, I can ask llmTools to explain a screenshot or image, not only extract text from it.

Acceptance:

- Image explanation is available from the OCR/image workflow, not the text-only task picker in the first implementation.
- The configured vision-capable model can explain the image, screenshot, chart, UI, or error dialog.
- Image explanation output is copyable and can be followed by summarize, translate, explain, polish, or TODO extraction on the produced text.
- The app does not send a remote image URL directly to a model. URL-based images are downloaded to a temporary local file first.

## 5. Model Capability Design

### 5.1 Capability Fields

Add explicit model capabilities to the registry. Suggested model:

```swift
public enum ModelInputCapability: String, Codable, Sendable, CaseIterable {
    case text
    case image
}

public enum ModelCapabilitySource: String, Codable, Sendable, CaseIterable {
    case detected
    case inferred
    case probePassed
    case failedProbe
    case manual
    case unknown
}

public struct ModelCapabilities: Codable, Hashable, Sendable {
    public var inputs: [ModelInputCapability]
    public var source: ModelCapabilitySource
    public var confidence: Double
    public var note: String?
    public var lastCheckedAt: Date?
    public var lastFailureMessage: String?
}
```

Default behavior:

- Existing registry entries without capability metadata decode as text-only with source `unknown` or `inferred` and confidence below 1.0.
- Local GGUF and MLX entries decode as text-only until a multimodal runner exists.
- Remote provider entries decode as text-capable by default and image-capable only after detection, inference, or manual override.
- Encode capability inputs in a stable sorted order. Do not rely on unordered `Set` JSON if the registry file is meant to stay reviewable and migration-friendly.

### 5.2 Detection Strategy

Capability detection should use layered evidence:

1. Provider metadata: use model-list metadata if the provider exposes input modalities or capabilities.
2. Provider presets and model-ID heuristics: infer support for known vision model families, with source `inferred`.
3. Probe request: optionally send a small non-sensitive generated image only when the user explicitly tests the model for OCR support.
4. Manual override: let the user mark a model as vision-capable or text-only.

Detection must not send the user's image during a background capability scan.

Provider-specific guidance:

| Provider family | First capability source | Confidence | Notes |
| --- | --- | --- | --- |
| OpenRouter | `/models` modality metadata when available | High / detected | Use `input_modalities` or equivalent fields when present; fallback to model-ID inference. |
| OpenAI | Known vision model families plus optional probe | Medium / inferred, high after probe | The normal model list path may not be enough to prove image support. Keep manual override. |
| Anthropic | Known Claude vision-capable families plus optional probe | Medium / inferred, high after probe | Use native Anthropic image content blocks, not OpenAI-compatible blocks. |
| Google Gemini OpenAI-compatible preset | Known Gemini multimodal families plus optional probe | Medium / inferred, high after probe | Native Gemini API support is separate and can be a later runner. |
| Ollama / LM Studio | Local server model name plus optional probe | Low to medium | Different local servers expose capability metadata inconsistently. Keep manual override and clear failure messages. |
| Custom OpenAI-compatible | Manual override or explicit probe | Unknown until user action | Do not infer broadly from unknown model IDs. |

### 5.3 Failure Semantics

- If the model is text-only, OCR cannot start.
- If capability is unknown, OCR can start only after the user chooses to treat the model as vision-capable.
- If a provider rejects image input, record the failure on that model and suggest changing capability or choosing another OCR model.
- If a model previously worked for OCR but later fails, do not remove the capability automatically; show the latest failure.
- A successful text-only provider connectivity test does not prove OCR support. Add a separate vision/OCR test action.

## 6. OCR Workflow

### 6.1 Entry Points

Initial entry points:

- Quick Action window: OCR mode or image drop/paste state.
- Menu-bar action: "OCR Image" or localized equivalent.
- Floating widget image drop can be enabled if the existing widget surface is ready enough; otherwise it belongs to Phase 4 file intake.

Do not add OCR to browser page translation in Phase 3.

Implementation correction: do not overload `AppState.inputText` with image data. Add an OCR-specific state object for preview, normalized image data, model OCR output, selected OCR mode, and current OCR run status.

### 6.2 Input Handling

The OCR surface should normalize images before sending them to a model:

- Decode through native macOS image APIs.
- Enforce a maximum image byte size and pixel count.
- Convert unsupported but decodable formats to PNG or JPEG internally.
- Preserve enough resolution for small text while enforcing provider-specific upload limits.
- Normalize orientation before OCR.
- Strip unnecessary metadata before provider upload.
- Compute a local hash for diagnostics without storing the raw image.
- Show user-facing errors for unsupported format, too large, decode failure, and empty clipboard.

Keep separate image variants:

- `originalPreview`: local display and user confirmation.
- `providerImage`: stripped, normalized, size-bounded upload payload.

### 6.3 Output Modes

Start with these OCR modes:

- Plain text: preserve reading order and line breaks.
- Structured: preserve tables, receipts, labels, key-value pairs, and form-like text as Markdown where useful.
- Extract then translate: first OCR, then translate the extracted text with the normal text-task engine.

The default mode should be plain text because it is easiest to verify and reuse.

The OCR engine is model vision recognition:

- The app sends the normalized local image payload to the configured vision-capable model.
- The same model-recognition path powers OCR, structured extraction, and image explanation.
- Remote image URLs are downloaded locally first; the model receives local normalized image bytes, not the original URL.

For "extract then translate", default to OCR extraction first and then hand the extracted text to the normal default text model. Do not use the vision model for the translation step unless the user explicitly chooses that model.

Add an image explanation mode alongside OCR modes:

- Explain image: explain the visible screenshot/image content, UI, chart, error state, or document image.

### 6.4 Prompt Contract

OCR prompts should be strict:

- Extract visible text only.
- Preserve original language.
- Preserve line breaks, table rows, numbers, punctuation, and labels where possible.
- Do not describe the image unless a short note is required to explain no readable text.
- If no readable text exists, output "No readable text detected." or the localized equivalent.
- For structured mode, use Markdown tables only when the table structure is clear.

The app should keep provider-specific multimodal payload construction inside runners, not inside generic prompt code.

Recommended OCR result shape:

```swift
public struct OCRTaskResult: Sendable, Hashable {
    public var text: String
    public var rawModelText: String?
    public var structuredMarkdown: String?
    public var modelName: String?
    public var warnings: [String]
}
```

This keeps raw model output and final display text inspectable without storing the source image.

## 7. Runner Architecture

### 7.1 Request Types

Do not force image OCR through the existing text-only `TaskRequest` shape. Add a multimodal request type or extend the engine with an OCR-specific method.

Suggested shape:

```swift
public struct OCRImageInput: Sendable, Hashable {
    public var data: Data
    public var mimeType: String
    public var fileName: String?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var contentHash: String
}

public enum OCRMode: String, Codable, Sendable, CaseIterable {
    case plainText
    case structured
    case extractThenTranslate
    case explainImage
}
```

Add a method at the task engine level:

```swift
public func runOCR(
    image: OCRImageInput,
    mode: OCRMode,
    modelID: UUID? = nil,
    persistHistory: Bool = false
) async throws -> TaskResult
```

Add a separate vision runner protocol instead of forcing every existing text runner to understand images:

```swift
public protocol VisionModelRunner: ModelRunner {
    func generateOCR(
        request: OCRTaskRequest,
        preferences: AppPreferences
    ) async throws -> OCRTaskResult
}
```

`TaskEngine.runOCR` can resolve the model, check its image capability, load the normal runner, then downcast to `VisionModelRunner` for model OCR. Text-only runners stay unchanged and should fail before any provider call.

### 7.2 Provider Runners

OpenAI-compatible runners should own the first Phase 3 model-recognition image payload path. Anthropic should remain a documented later extension because its native Messages image blocks require a separate encoder.

Rules:

- Text-only generation remains unchanged.
- OCR generation validates image capability before building a request.
- Provider payloads are constructed from normalized image data and MIME type.
- OpenAI-compatible payloads should support content arrays with text plus `image_url` data URLs.
- Anthropic payloads should be added later with native image source blocks containing `media_type` and base64 data.
- Provider-specific options such as OpenAI image detail should be optional and hidden behind provider-aware defaults.
- Provider errors are mapped to actionable app errors.
- OCR calls should have separate timeout behavior from short text tasks.
- The existing `ChatMessage.content: String?` shape is not enough for OpenAI-compatible image input. Add a codable message-content enum or separate request type for multimodal calls.
- Never pass external image URLs as provider `image_url` values. Build `image_url` data URLs from normalized local data so the app controls download, metadata stripping, size limits, and diagnostics.

### 7.3 Local Runners

The current local GGUF and MLX runners should remain text-only.

Do not pretend local models support image input because a model name looks multimodal. Add local vision only when there is an actual image-preprocessor and runner path that can execute it.

### 7.4 Image Preprocessing Service

Add a small image preprocessing service separate from `ModelRunner`.

Suggested location:

- Core defines data structures and protocol boundaries.
- App target owns macOS file picker, clipboard/drop handling, image decoding, temporary-file downloads, and image conversion.

Responsibilities:

- Decode and normalize images.
- Download remote image URLs into a temporary local directory.
- Strip metadata.
- Convert to provider-safe PNG/JPEG when needed.
- Return pixel size, byte size, MIME type, content hash, and local temporary path when applicable.
- Avoid writing persistent source images to disk.
- Delete temporary files after the run.

Do not add Apple Vision or other Apple-provided OCR APIs. The preprocessing layer prepares images; the configured model recognizes them.

## 8. Settings UX

### 8.1 Model Cards

Model cards should show compact badges:

- Text
- Vision
- Unknown
- Manual

The card should expose the source of the capability in a details area, not as noisy primary text.

### 8.2 OCR Settings

Add an OCR settings section:

- Enable OCR
- Use model recognition by default
- OCR model picker
- OCR output mode default
- Image explanation mode
- Capability status for the selected model
- Remote provider privacy notice when the OCR model is remote
- Test OCR support action
- Clear OCR history/cache action if OCR history is later enabled

Do not bury OCR model selection under webpage translation settings. OCR is a native task, not a webpage translation preference.

Suggested preference model:

```swift
public struct OCRPreferences: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var modelID: UUID?
    public var defaultMode: OCRMode
    public var persistHistory: Bool
    public var useModelRecognitionByDefault: Bool
    public var maximumImageBytes: Int
    public var maximumPixelCount: Int
}
```

Add `ocr: OCRPreferences` to `AppPreferences`. Decode older preference files with defaults. When a model is removed, disabled, or marked text-only, clear `ocr.modelID` just like `webPageTranslation.modelID` is cleared today.

### 8.3 Manual Override

Manual override should require an explicit action:

- Mark as vision-capable
- Mark as text-only
- Reset to automatic

When a manual override exists, the model card should show that the capability is manually controlled.

## 9. History And Privacy

Default history behavior:

- Store OCR result preview only if normal recent history is enabled for OCR.
- Do not store raw images in recent history.
- Do not store base64 image payloads in logs, diagnostics, or closure reports.
- Diagnostics may include image byte size, pixel size, MIME type, content hash prefix, model name, elapsed time, and error code.

Remote provider OCR behavior:

- The app must indicate when the configured model is a hosted remote provider.
- No automatic cloud fallback.
- No background OCR upload during capability detection.
- Provider API keys stay in the existing provider credential path.
- Do not show a per-image upload confirmation in the normal OCR loop; model recognition is already an explicit mode/default chosen by the user.
- If the input is a remote image URL, download it into a local temporary directory first, delete it after the run, and never give the provider the original URL.
- If the selected configured model is a hosted remote provider, the normalized local image payload is sent to that provider as part of the user-configured model-recognition path.

History model correction:

- If OCR results enter recent history, add `TaskKind.ocr` or a dedicated history origin field.
- Do not add OCR to `TaskKind.interactiveCases` until the UI actually supports image input in the same task picker.
- `HistoryItem.inputPreview` for OCR should be a redacted image descriptor such as `Image 1280x720 PNG`, not base64 or file path.

## 10. Test Plan

### 10.1 Swift Checks

Add focused checks for:

- Existing `TaskKind.interactiveCases` still covers translate, polish, summarize, explain, and extract TODOs.
- Capability metadata decodes older registries safely.
- Local GGUF/MLX models default to text-only.
- `OCRPreferences` decodes older registries and clears missing model IDs.
- OCR model picker excludes text-only models.
- Removing or disabling the OCR model clears the preference.
- OCR prompt rules include "visible text only" and no-invention behavior.
- OCR result history does not persist raw image data.
- OpenAI-compatible multimodal request encoding can produce text plus image content without changing text-only requests.
- Anthropic multimodal request encoding is a later extension and should not be required for first Phase 3 completion.
- Image preprocessing service can decode generated fixture images, normalize them, and clean temporary files without network access.

### 10.2 Runner Tests

Use stub runners for deterministic checks:

- Vision-capable stub returns OCR text.
- Text-only stub rejects OCR before any provider call.
- Provider rejection maps to a clear unsupported-vision error.
- Cancellation stops the in-flight OCR task and leaves the UI reusable.

### 10.3 Manual Acceptance

Manual acceptance should cover:

- Trigger OCR/image recognition with the model-recognition button.
- Set model recognition as the default and choose the model used for that mode.
- Configure a provider model and mark or detect it as vision-capable.
- Select it as the OCR model.
- OCR a screenshot with mixed Chinese and English.
- OCR a receipt/table-like image in structured mode.
- Explain a screenshot/image through the configured vision-capable model.
- OCR an image with no text and confirm no hallucinated content.
- Confirm raw source image is not saved in recent history by default.
- Confirm remote image URL input is downloaded to a temporary local file and the provider never receives the original URL.
- Confirm Phase 1 selected-text tasks and Phase 2 Chrome page translation still work from packaged `dist/llmTools.app`.

## 11. Implementation Order

### 11.1 Phase 3.0 Translation Closure

- Refresh Phase 2 closure report.
- Record Chrome packaged-app smoke or preserve the explicit browser-readiness blocker.
- Run Edge acceptance if Edge is available.
- Fix only acceptance defects.

### 11.2 Phase 3.1 Text Task Polish

- Tighten prompt contracts for polish, summarize, explain, and TODO extraction.
- Improve empty/running/cancelled/failed UI states.
- Add focused regression checks for all native text tasks.
- Keep `cmd+a/c/v/x/z` behavior in text inputs.
- Add follow-up actions from any task result where useful: translate, polish, summarize, explain, and extract TODOs from the current output.

### 11.3 Phase 3.2 Model Capabilities

- Add capability metadata to `ModelDescriptor`.
- Add `OCRPreferences` to `AppPreferences`.
- Decode old registries safely.
- Add capability badges and manual override UI.
- Add OCR model preference.
- Add provider-specific detection/probe strategy and explicit unsupported-vision errors.
- Add tests for capability filtering and migration.

### 11.4 Phase 3.3 Image Input And Preprocessing

- Add OCR request/input/result types.
- Add image import, paste, drop, preview, and normalized variants.
- Add temporary remote-image download and cleanup.
- Add image metadata stripping, size limits, orientation normalization, and provider-safe conversion.
- Add privacy and history checks.

### 11.5 Phase 3.4 Vision Model OCR

- Add OCR execution path for at least one remote vision-capable provider style.
- Add OpenAI-compatible multimodal payload support.
- Add strict OCR prompts and output display.
- Add copy and follow-up task actions.
- Add explicit model-recognition toggle/default behavior and failure taxonomy.

### 11.6 Phase 3.5 Structured OCR And Image Explanation

- Add structured output mode for receipts, tables, forms, and key-value screenshots.
- Add extract-then-translate using the normal text model by default.
- Add screenshot/image explanation mode.
- Keep raw model output and cleaned display output inspectable.

### 11.7 Phase 3.6 QA And Packaging

- Run `swift run LLMToolsChecks`.
- Package with `./scripts/package-app.sh`.
- Relaunch `dist/llmTools.app` and verify the running packaged path.
- Manually test OCR and existing translation workflows.
- Update README with OCR setup once implementation exists.

## 12. Open Decisions

The following decisions are now fixed for Phase 3:

- OCR starts as a separate image workflow. It can be integrated into the text task picker later after the image state and history model are stable.
- OCR is model-vision only. Do not use Apple Vision, VisionKit, or any Apple-provided visual/OCR recognition API.
- The OCR surface must provide a model-recognition button, plus settings to use model recognition by default and choose the model for that mode.
- Model recognition sends the normalized local image payload to the configured model.
- Translate-after-OCR uses the normal default text model by default.
- OCR history is independent opt-in and defaults off.
- Capability detection is conservative and includes a user-triggered OCR/vision probe.
- First model OCR provider path is OpenAI-compatible.
- Supported first image formats are PNG, JPEG, WebP where decodable, and HEIC through local decode-and-convert.
- No built-in screenshot selection tool in the first OCR release. Support file picker, drag/drop, and clipboard images first.
- Core defines OCR protocols and data structures; App target provides macOS clipboard/image decoding, temporary downloads, and image conversion implementation.
- Screenshot/image explanation is in Phase 3 scope.
- Remote image URLs are never passed directly to models/providers; they are downloaded to a temporary local file first.

## 13. Implementation Self-Review

The first draft of this plan had several likely implementation mistakes. These should be considered resolved constraints for Phase 3:

1. OCR should now be model-vision-only by product decision. Do not add Apple Vision or VisionKit recognition even though it would be locally available.
2. The existing `TaskRequest` and `ModelRunner.generate` are text-only. Do not cram images into `inputText`; add OCR request/result types and a `VisionModelRunner` protocol.
3. `ChatMessage.content` is currently a string. OpenAI-compatible image input needs content arrays. Anthropic later needs separate image blocks, but it is not the first Phase 3 provider path.
4. Capability detection cannot be universally automatic. Some providers expose explicit modality metadata, others expose only model IDs. Store capability source, confidence, last check, and failure state.
5. Registry JSON should stay migration-friendly. Prefer stable sorted arrays for capability inputs instead of unordered sets.
6. `AppPreferences` currently has no OCR preference surface. Add `OCRPreferences`, decode older registries safely, and clear OCR model IDs when models are deleted, disabled, or marked text-only.
7. Quick Action is text-first today. Add OCR-specific UI state and image drop/paste handling instead of overloading the existing text input.
8. Recent history cannot store raw images. If OCR history is added, use `TaskKind.ocr` or a redacted origin and store only result previews plus redacted image descriptors.
9. A normal provider connectivity test proves text chat only. Add an explicit OCR/vision test with a generated non-sensitive image.
10. Translate-after-OCR should hand extracted text to the normal text pipeline by default. It should not automatically use the expensive vision model for text translation.
11. Browser page image/canvas OCR remains out of Phase 3. Native OCR can later power a browser feature, but the browser DOM translation phase should not be reopened for this.
12. CI should not depend on live provider OCR. Use generated image fixtures and stub vision runners for automated tests; keep real provider OCR in manual packaged-app acceptance.
13. Image explanation is useful enough to include in Phase 3, but it should live in the image/OCR workflow rather than turning llmTools into a general chat product.
14. Remote image URL handling must stay app-owned. Download to temp, normalize, strip metadata, and delete after use.

## 14. Complete Phase 3 Implementation Checklist

### 14.1 Translation Closure

- Done: Phase 2 closure reports are refreshed by `./scripts/check-phase2-closure.sh`.
- Done: Chrome packaged-app smoke is machine-checked where possible; browser-readiness blockers remain explicit when Chrome has not loaded the unpacked extension from this repo.
- Done: Edge acceptance is skipped with an explicit reason when Edge is unavailable on the test machine.
- Done: no Phase 2 source defect was found by the closure gate before Phase 3 implementation.
- Done: Phase 1 selected-text and quick-action regressions remain covered by `swift run LLMToolsChecks`.

### 14.2 Native Text Task Polish

- Done: revisit translate, polish, summarize, explain, and TODO prompts.
- Add task-specific mode controls where they are useful and bounded.
- Done: add follow-up actions from output text.
- Done: improve empty/running/cancelled/failed states.
- Done: keep text input keyboard shortcuts normal.
- Done: add regression coverage for native text prompt contracts.

### 14.3 Capability Registry

- Done: add capability fields to `ModelDescriptor`.
- Done: add stable old-registry migration.
- Done: add capability inference for local and OpenAI-compatible provider families first, including OpenAI, OpenRouter, Gemini OpenAI-compatible, Ollama, LM Studio, and custom providers. Anthropic image payload support remains a later provider-specific extension.
- Done: add manual override and reset-to-automatic actions.
- Done: add explicit OCR/vision probe action.
- Done: show capability badges, source, confidence, last check, and last failure.

### 14.4 OCR Preferences

- Done: add `OCRPreferences`.
- Done: add OCR enablement.
- Done: add OCR model picker filtered by image capability.
- Done: add OCR output mode default.
- Done: add separate OCR history opt-in.
- Done: add model-recognition default toggle.
- Done: clear stale OCR model IDs when model state changes.

### 14.5 Image Input And Preprocessing

- Done: add image file picker, paste, and drop.
- Done: support PNG, JPEG, WebP where decodable, and HEIC via local conversion where native decoding succeeds.
- Done: strip metadata and normalize provider payloads.
- Done: enforce size and pixel limits.
- Done: add preview and redacted diagnostics.
- Done: download remote image URLs to temporary local files and clean them after normalization.

### 14.6 Vision Model OCR

- Done: add `VisionModelRunner`.
- Done: add OpenAI-compatible image payload support.
- Done: map provider and validation errors to actionable OCR errors.
- Done: require vision capability before provider call.
- Done: prevent direct remote image URL passthrough; all URL inputs are downloaded to a temporary local file first.
- Done: keep text-only generation untouched.

### 14.7 Structured OCR And Image Explanation

- Done: add structured Markdown extraction for tables, receipts, labels, and key-value screenshots.
- Done: add translate-after-OCR through normal text model by default.
- Done: add screenshot/image explanation through the image workflow.
- Done: keep raw model output and cleaned display output inspectable.

### 14.8 Privacy, History, And Diagnostics

- Done: do not store raw images by default.
- Done: avoid logging base64 image payloads.
- Done: keep OCR diagnostics redacted.
- Done: add OCR history preview only when explicitly enabled.
- Done: include model name, elapsed time, MIME type, pixel size, byte size, hash prefix, and error code in OCR result metadata.
- Done: delete temporary files created for remote image URL inputs after normalization.

### 14.9 Automated And Manual Verification

- Done: run Swift checks.
- Done: add generated OCR image fixtures.
- Done: add image preprocessing tests and stub vision runner tests.
- Done: add request-encoding tests for OpenAI-compatible image payloads.
- Done: add temporary-download cleanup coverage through image preprocessing checks.
- Done: add `LLMToolsLiveOCRCheck` for live provider OCR and image-explanation verification.
- Done: add `check-phase3-goal-audit.mjs` so completion claims are derived from current evidence rather than manual interpretation.
- Done: package and relaunch `dist/llmTools.app` as the final verification target.
- Manual/provider-bound: test model-recognition OCR, no-text image, structured receipt/table image, image explanation, remote URL temp download, and existing translation workflows with a real configured vision-capable model and browser extension loaded from this repo.

## 15. Definition Of Done

Phase 3 is done when:

- Phase 2 closure state is recorded and no untriaged acceptance blocker remains.
- Native text tasks have clear task-specific prompts, states, and regression coverage.
- The model registry stores capability metadata and survives old-registry migration.
- Settings shows model capability badges and an OCR model picker filtered to vision-capable models.
- The app can OCR PNG/JPEG/WebP or clipboard images with a configured vision-capable model.
- The app can explain a screenshot/image through the image workflow when a vision-capable model is configured.
- Remote image URL inputs are downloaded to a temporary local file and cleaned up after recognition.
- OCR does not store raw images by default.
- Text-only models cannot be used for OCR.
- Packaged `dist/llmTools.app` is rebuilt, relaunched, and manually verified for OCR plus existing translation workflows.
