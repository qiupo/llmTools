# Phase 3 PRD: Native Task Polish And Vision OCR

Last updated: 2026-07-04

Status: planned next phase. Phase 3 starts after Phase 2 closure work is recorded or explicitly deferred.

## 1. Objective

Phase 3 makes llmTools stronger as a task-first macOS assistant.

The phase has two product tracks:

1. Close and harden the existing translation and native text-task workflows.
2. Add a native image OCR workflow that can use local macOS OCR, a configured vision-capable model, or a hybrid of both.

The user should be able to rely on the app for everyday selected-text translation, polishing, summarization, explanation, TODO extraction, and image text extraction without guessing which model supports which input type.

This is not a broad chat feature, a browser image-translation feature, or a document indexing system. OCR starts as a native app workflow with explicit model capability checks.

## 2. Scope Summary

### 2.1 In Scope

- Finish Phase 2 translation closure tasks and fix acceptance defects.
- Improve native translation quality, run states, retry behavior, and copy/reuse paths.
- Improve polishing, summarization, explanation, and TODO extraction so they feel like first-class tasks rather than generic prompt variants.
- Add model capability metadata for text and image input.
- Detect or infer whether a configured model supports vision.
- Let the user manually override model capability when automatic detection is unavailable or wrong.
- Add a dedicated OCR model setting that only accepts vision-capable models.
- Add local OCR through Apple Vision as the privacy-preserving baseline.
- Add vision-model OCR from local image files, clipboard images, and screenshots.
- Add a hybrid OCR mode where local OCR extracts first-pass text and the model cleans, structures, or translates it.
- Add OCR output modes: plain text, structured extraction, and optional translate-after-OCR.
- Keep raw image storage off by default.
- Add automated checks for capability filtering, OCR prompt generation, task regressions, and privacy defaults.

### 2.2 Out Of Scope

- Browser image/canvas OCR inside webpage translation.
- Browser PDF viewer translation.
- Full PDF, DOCX, or multi-document understanding.
- Local multimodal LLM running unless a real local vision runner is added. Apple Vision local text recognition is in scope because it is not a local LLM runner.
- Silent cloud OCR fallback.
- Cross-device sync.
- Automatic storage of raw source images.
- General chat sessions.

## 3. Product Principles

- Task-first: every surface starts from a concrete user job, not from a blank chat box.
- Capability-aware: the app must not offer OCR through a model that is known to be text-only.
- Honest detection: when model capability cannot be proven, show the confidence and ask for an explicit user decision.
- Local-first where possible: text tasks continue to default to local models. Remote vision OCR is allowed only through an explicitly configured provider model.
- Use deterministic OCR where it helps: Apple Vision should provide fast local extraction for ordinary screenshots and scanned text; vision LLMs should add value for messy images, structure recovery, table cleanup, or translate-after-OCR.
- Privacy by default: raw images and OCR source content are not retained unless the user opts in.
- Reversible and retryable: task output should be copyable, rerunnable, and cancellable without losing input.
- Do not regress Phase 1 and Phase 2: selected-text workflows and browser translation must remain green while OCR is added.

## 3.1 External Implementation References

Phase 3 should follow current provider API shapes rather than assuming that all "OpenAI-compatible" endpoints expose the same multimodal contract.

Reference conclusions from official docs:

- OpenAI-compatible image input is commonly expressed as text plus an `image_url` content block, including data URLs for base64 images. This is the best first shared path for OpenAI, OpenRouter, Ollama, and many local OpenAI-compatible servers.
- Anthropic Messages uses provider-specific image content blocks with a source containing media type and base64 data. It should keep a separate payload encoder.
- Gemini supports multimodal image input, but the OpenAI-compatible path and the native Gemini path should not be treated as the same implementation. The current app has only an OpenAI-compatible Gemini preset, so Phase 3 should start there and leave a native Gemini runner as later work.
- OpenRouter exposes model modality metadata such as text/image support in its model data, so it can provide higher-confidence capability detection than providers that return only model IDs.
- macOS Vision text recognition is a strong local OCR baseline for the native app. It should be used for local-only OCR and can also feed a vision/text model for cleanup.

Implementation implication: do not hard-code one universal multimodal payload. Add a small capability and payload layer that can branch by provider/API style while keeping the UI model simple.

Reference links:

- OpenAI Images and Vision: `https://developers.openai.com/api/docs/guides/images-vision`
- Anthropic Vision: `https://docs.anthropic.com/en/docs/build-with-claude/vision`
- Gemini image understanding: `https://ai.google.dev/gemini-api/docs/image-understanding`
- OpenRouter multimodal capabilities: `https://openrouter.ai/docs/guides/overview/multimodal/overview`
- OpenRouter model metadata/API: `https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties`
- Ollama OpenAI compatibility: `https://docs.ollama.com/api/openai-compatibility`
- Apple Vision text recognition: `https://developer.apple.com/documentation/vision/recognizing-text-in-images`

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

- OCR can run in local-only, vision-model, or hybrid mode.
- OCR model setting only lists enabled models that are vision-capable or manually marked vision-capable.
- If local-only OCR is selected, no model is required.
- If vision-model or hybrid OCR is selected and no vision-capable model exists, the OCR entry point shows a setup action instead of a broken run button.
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
- OCR keeps local raw extraction and model-cleaned output separate when both exist, so the user can inspect what changed.

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

Implementation correction: do not overload `AppState.inputText` with image data. Add an OCR-specific state object for preview, normalized image data, local OCR output, model OCR output, selected OCR mode, and current OCR run status.

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

- `originalPreview`: local-only display and user confirmation.
- `localOCRImage`: format and resolution suitable for Apple Vision.
- `providerImage`: stripped, normalized, size-bounded upload payload.

### 6.3 Output Modes

Start with these OCR modes:

- Plain text: preserve reading order and line breaks.
- Structured: preserve tables, receipts, labels, key-value pairs, and form-like text as Markdown where useful.
- Extract then translate: first OCR, then translate the extracted text with the normal text-task engine.

The default mode should be plain text because it is easiest to verify and reuse.

Start with these OCR engines:

- Local: Apple Vision text recognition only. Best for privacy, speed, screenshots, and ordinary scanned text.
- Vision model: send the normalized image to the configured vision-capable model.
- Hybrid: run local OCR first, then ask the configured model to repair layout, recover structure, or translate. The model should receive the image only when the user has selected a mode that permits remote image processing.

For "extract then translate", default to OCR extraction first and then hand the extracted text to the normal default text model. Do not use the vision model for the translation step unless the user explicitly chooses that model.

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
    public var rawLocalText: String?
    public var rawModelText: String?
    public var structuredMarkdown: String?
    public var engine: OCREngineMode
    public var modelName: String?
    public var warnings: [String]
}
```

This keeps raw local extraction, model output, and final display text inspectable without storing the source image.

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
}

public enum OCREngineMode: String, Codable, Sendable, CaseIterable {
    case local
    case visionModel
    case hybrid
}
```

Add a method at the task engine level:

```swift
public func runOCR(
    image: OCRImageInput,
    mode: OCRMode,
    engineMode: OCREngineMode,
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

OpenAI-compatible and Anthropic runners should own their provider-specific image content blocks.

Rules:

- Text-only generation remains unchanged.
- OCR generation validates image capability before building a request.
- Provider payloads are constructed from normalized image data and MIME type.
- OpenAI-compatible payloads should support content arrays with text plus `image_url` data URLs.
- Anthropic payloads should support native image source blocks with `media_type` and base64 data.
- Provider-specific options such as OpenAI image detail should be optional and hidden behind provider-aware defaults.
- Provider errors are mapped to actionable app errors.
- OCR calls should have separate timeout behavior from short text tasks.
- The existing `ChatMessage.content: String?` shape is not enough for OpenAI-compatible image input. Add a codable message-content enum or separate request type for multimodal calls.

### 7.3 Local Runners

The current local GGUF and MLX runners should remain text-only.

Do not pretend local models support image input because a model name looks multimodal. Add local vision only when there is an actual image-preprocessor and runner path that can execute it.

### 7.4 Local OCR Service

Add a small local OCR service separate from `ModelRunner`.

Suggested location:

- Core if it can import Vision cleanly across `LLMToolsApp`, `LLMToolsChecks`, and smoke targets.
- App target if Vision integration introduces UI/AppKit-only dependencies.

Responsibilities:

- Decode and normalize images.
- Run Apple Vision text recognition.
- Return recognized lines, optional bounding boxes, and candidate confidence where available.
- Avoid network access and avoid writing source images to disk.

Do not mix Apple Vision OCR with local LLM runners; it is a deterministic native service, not a model registry entry.

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
- OCR engine: local, vision model, or hybrid
- OCR model picker
- OCR output mode default
- Capability status for the selected model
- Remote provider privacy notice when the OCR model is remote
- Require confirmation before remote image upload
- Test OCR support action
- Clear OCR history/cache action if OCR history is later enabled

Do not bury OCR model selection under webpage translation settings. OCR is a native task, not a webpage translation preference.

Suggested preference model:

```swift
public struct OCRPreferences: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var engineMode: OCREngineMode
    public var modelID: UUID?
    public var defaultMode: OCRMode
    public var persistHistory: Bool
    public var confirmRemoteUpload: Bool
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

- The app must indicate when an image will be sent to a remote provider.
- No automatic cloud fallback.
- No background OCR upload during capability detection.
- Provider API keys stay in the existing provider credential path.
- In hybrid mode, remote upload requires the same confirmation as vision-model mode.

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
- Anthropic multimodal request encoding uses native image content blocks and leaves text-only requests unchanged.
- Local OCR service can process generated fixture images without network access.

### 10.2 Runner Tests

Use stub runners for deterministic checks:

- Vision-capable stub returns OCR text.
- Text-only stub rejects OCR before any provider call.
- Provider rejection maps to a clear unsupported-vision error.
- Cancellation stops the in-flight OCR task and leaves the UI reusable.

### 10.3 Manual Acceptance

Manual acceptance should cover:

- Local-only OCR on a screenshot without any remote model configured.
- Configure a provider model and mark or detect it as vision-capable.
- Select it as the OCR model.
- OCR a screenshot with mixed Chinese and English.
- OCR a receipt/table-like image in structured mode.
- OCR an image with no text and confirm no hallucinated content.
- Hybrid mode: local extraction remains inspectable and model-cleaned output is visibly separate.
- Confirm raw source image is not saved in recent history by default.
- Confirm remote upload confirmation appears before sending images to a remote provider.
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

### 11.4 Phase 3.3 Local OCR MVP

- Add OCR request/input/result types.
- Add image import, paste, drop, preview, and normalized variants.
- Add Apple Vision local OCR service.
- Add plain-text OCR display and copy.
- Add local-only privacy and history checks.

### 11.5 Phase 3.4 Vision Model OCR

- Add OCR execution path for at least one remote vision-capable provider style.
- Add OpenAI-compatible multimodal payload support.
- Add Anthropic multimodal payload support if the configured provider is Anthropic.
- Add strict OCR prompts and output display.
- Add copy and follow-up task actions.
- Add remote upload confirmation and failure taxonomy.

### 11.6 Phase 3.5 Hybrid OCR And Structured Output

- Add hybrid local-plus-model mode.
- Add structured output mode for receipts, tables, forms, and key-value screenshots.
- Add extract-then-translate using the normal text model by default.
- Keep raw local OCR and model-cleaned output inspectable.

### 11.7 Phase 3.6 QA And Packaging

- Run `swift run LLMToolsChecks`.
- Package with `./scripts/package-app.sh`.
- Relaunch `dist/llmTools.app` and verify the running packaged path.
- Manually test OCR and existing translation workflows.
- Update README with OCR setup once implementation exists.

## 12. Open Decisions

- Whether OCR should appear as a sixth top-level task beside translate/polish/summarize/explain/TODO, or as a separate image workflow.
- Whether "extract then translate" should use the OCR model for both steps or hand off to the normal default text model after OCR.
- Whether OCR history should be opt-in separately from normal recent history.
- Whether screenshot capture should use a built-in screen picker in Phase 3 or rely on clipboard/file input first.
- Whether to support HEIC in the first OCR release.
- Which provider capability metadata sources are reliable enough to mark as `detected` rather than `inferred`.

Current recommended decisions after implementation self-review:

- Treat OCR as a separate image workflow initially, not as another text-only task in `TaskKind.interactiveCases`.
- Use the normal default text model for translate-after-OCR unless the user explicitly chooses otherwise.
- Make OCR history opt-in separately from normal recent history.
- Start with file, paste, and drop input; add a built-in screenshot picker only after the base OCR loop is stable.
- Accept HEIC only through local decode-and-convert, not direct provider upload.
- Treat provider metadata as `detected` only when the provider returns explicit modality fields. Treat model-name allowlists as `inferred`.

## 13. Implementation Self-Review

The first draft of this plan had several likely implementation mistakes. These should be considered resolved constraints for Phase 3:

1. OCR should not be model-only. A pure vision-model OCR plan is slower, costlier, and less private than necessary. Add Apple Vision local OCR as the default local baseline, then use vision models for cleanup, structure, and hard images.
2. The existing `TaskRequest` and `ModelRunner.generate` are text-only. Do not cram images into `inputText`; add OCR request/result types and a `VisionModelRunner` protocol.
3. `ChatMessage.content` is currently a string. OpenAI-compatible image input needs content arrays, and Anthropic needs separate image blocks. Add provider-specific multimodal payload encoders.
4. Capability detection cannot be universally automatic. Some providers expose explicit modality metadata, others expose only model IDs. Store capability source, confidence, last check, and failure state.
5. Registry JSON should stay migration-friendly. Prefer stable sorted arrays for capability inputs instead of unordered sets.
6. `AppPreferences` currently has no OCR preference surface. Add `OCRPreferences`, decode older registries safely, and clear OCR model IDs when models are deleted, disabled, or marked text-only.
7. Quick Action is text-first today. Add OCR-specific UI state and image drop/paste handling instead of overloading the existing text input.
8. Recent history cannot store raw images. If OCR history is added, use `TaskKind.ocr` or a redacted origin and store only result previews plus redacted image descriptors.
9. A normal provider connectivity test proves text chat only. Add an explicit OCR/vision test with a generated non-sensitive image.
10. Translate-after-OCR should hand extracted text to the normal text pipeline by default. It should not automatically use the expensive vision model for text translation.
11. Browser page image/canvas OCR remains out of Phase 3. Native OCR can later power a browser feature, but the browser DOM translation phase should not be reopened for this.
12. CI should not depend on live provider OCR. Use generated image fixtures and stub vision runners for automated tests; keep real provider OCR in manual packaged-app acceptance.

## 14. Complete Phase 3 Implementation Checklist

### 14.1 Translation Closure

- Refresh Phase 2 closure reports.
- Verify Chrome packaged-app smoke or keep the browser-readiness blocker explicit.
- Verify Edge acceptance when Edge is available.
- Fix only defects found by closure/acceptance gates.
- Confirm Phase 1 selected-text and quick-action flows still work.

### 14.2 Native Text Task Polish

- Revisit translate, polish, summarize, explain, and TODO prompts.
- Add task-specific mode controls where they are useful and bounded.
- Add follow-up actions from output text.
- Improve empty/running/cancelled/failed states.
- Keep text input keyboard shortcuts normal.
- Add regression coverage for every native text task.

### 14.3 Capability Registry

- Add capability fields to `ModelDescriptor`.
- Add stable old-registry migration.
- Add capability inference for local, OpenAI-compatible, Anthropic, OpenRouter, Gemini, Ollama, LM Studio, and custom providers.
- Add manual override and reset-to-automatic actions.
- Add explicit OCR/vision probe action.
- Show capability badges, source, confidence, last check, and last failure.

### 14.4 OCR Preferences

- Add `OCRPreferences`.
- Add OCR enablement.
- Add OCR engine mode: local, vision model, hybrid.
- Add OCR model picker filtered by image capability.
- Add OCR output mode default.
- Add separate OCR history opt-in.
- Add remote upload confirmation preference.
- Clear stale OCR model IDs when model state changes.

### 14.5 Image Input And Local OCR

- Add image file picker, paste, and drop.
- Support PNG, JPEG, WebP where decodable, and HEIC via local conversion if practical.
- Strip metadata and normalize orientation.
- Enforce size and pixel limits.
- Add preview and redacted diagnostics.
- Add Apple Vision local OCR service.
- Display copyable plain-text OCR output.

### 14.6 Vision Model OCR

- Add `VisionModelRunner`.
- Add OpenAI-compatible image payload support.
- Add Anthropic image payload support.
- Map provider errors to actionable OCR errors.
- Require vision capability before provider call.
- Require confirmation before remote image upload when configured.
- Keep text-only generation untouched.

### 14.7 Hybrid And Structured OCR

- Run local OCR first.
- Send image and/or local OCR text to model only when mode allows remote processing.
- Keep local OCR and model-cleaned output inspectable.
- Add structured Markdown extraction for tables, receipts, labels, and key-value screenshots.
- Add translate-after-OCR through normal text model by default.

### 14.8 Privacy, History, And Diagnostics

- Do not store raw images by default.
- Never log base64 image payloads.
- Keep OCR diagnostics redacted.
- Add OCR history preview only when explicitly enabled.
- Include model name, engine mode, elapsed time, MIME type, pixel size, byte size, hash prefix, and error code in diagnostics.

### 14.9 Automated And Manual Verification

- Run Swift checks.
- Add generated OCR image fixtures.
- Add stub local OCR and stub vision runner tests.
- Add request-encoding tests for OpenAI-compatible and Anthropic image payloads.
- Package and relaunch `dist/llmTools.app`.
- Manually test local OCR, vision-model OCR, hybrid OCR, no-text image, structured receipt/table image, remote confirmation, and existing translation workflows.

## 15. Definition Of Done

Phase 3 is done when:

- Phase 2 closure state is recorded and no untriaged acceptance blocker remains.
- Native text tasks have clear task-specific prompts, states, and regression coverage.
- The model registry stores capability metadata and survives old-registry migration.
- Settings shows model capability badges and an OCR model picker filtered to vision-capable models.
- The app can OCR PNG/JPEG/WebP or clipboard images locally, with a configured vision-capable model, and in hybrid mode.
- OCR does not store raw images by default.
- Text-only models cannot be used for OCR.
- Packaged `dist/llmTools.app` is rebuilt, relaunched, and manually verified for OCR plus existing translation workflows.
