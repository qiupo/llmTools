# Phase 4 PRD: Media Intake And Live Subtitles

Last updated: 2026-07-06

Status: product direction confirmed and first local product implementation landed. This document replaces the earlier Phase 4 file-drop-only plan with a media-first requirement. The previous live-audio research report remains as background research at `docs/phase-4-live-audio-subtitles-research.md`.

## 1. Objective

Phase 4 makes llmTools useful for audio, video, and live browser playback.

The user should be able to:

1. Drop a recording or video file into llmTools and generate timestamped subtitles.
2. Translate generated subtitles directly into Simplified Chinese by default.
3. Start live subtitles for the current Chrome tab while a video or live stream is playing.
4. See original, translated, or bilingual subtitles without copying text out of the media surface.

Speech recognition is local-only for Phase 4. Remote ASR is not part of the MVP and should not be added as an automatic fallback. Subtitle translation reuses the existing llmTools text translation engine; if the user has configured a remote translation model, that is a translation-provider decision, not an ASR decision.

## 1.1 Confirmed Product Decisions

- Phase 4 main line is media intake and live subtitles, not generic document intake.
- TXT/Markdown/image drag-and-drop can remain as supporting workflow where it naturally fits the floating widget.
- PDF, DOCX, reusable indexing, and multi-document QA belong to the later document-assistant phase unless explicitly reprioritized.
- Remote ASR is out of scope for Phase 4.
- Realtime subtitles prefer Fun-ASR-MLT-Nano when a local Fun-ASR streaming runtime is configured; Fun-ASR-Nano is the lower-latency Chinese/English/Japanese option when available.
- SenseVoiceSmall remains supported as a short-window low-latency ASR runtime. Qwen3-ASR-0.6B is offered for audio/video file transcription and as an optional experimental realtime ASR model through a local vLLM/streaming runtime.
- Translation to Simplified Chinese is the default subtitle target.
- Desktop live subtitles use native system-audio and/or microphone capture, started only by explicit user action.

## 1.2 Implementation Status As Of 2026-07-06

Implemented:

- `ModelInputCapability.speech`, `ModelFormat.speech`, and speech metadata for Fun-ASR-Nano, Fun-ASR-MLT-Nano, SenseVoiceSmall, Qwen3-ASR-0.6B, and custom local ASR.
- Media subtitle preferences in `AppPreferences`, including separate realtime/file ASR model IDs, ASR source-language hint, local ASR command templates, default `zh-Hans` target language, default bilingual mode, and transcript/subtitle history opt-ins defaulting off.
- Settings UI for media subtitles, realtime/file ASR pickers, source-language hint, local ASR command templates, local ASR health checks with runtime-source labels, Fun-ASR realtime labeling, SenseVoiceSmall fallback labeling, and Qwen3-ASR experimental realtime labeling.
- File intake for local audio/video, macOS `avconvert`/`afconvert` extraction and normalization to 16 kHz mono WAV, subtitle segment modeling, local ASR sidecar execution, subtitle translation through the existing text engine, and SRT/VTT/TXT/Markdown export.
- Local ASR health diagnostics for missing model path, incompatible model, missing runtime, ready states, and runtime source: Settings command, environment variable, fixture transcript, local MLX runner, automatic Fun-ASR GGUF, automatic sherpa-onnx, or unavailable. The UI and diagnostics do not offer remote ASR or cloud fallback.
- Desktop live subtitle chain in the native app: ScreenCaptureKit system-audio capture, microphone capture, mixed audio source selection, floating subtitle window, configurable global shortcut, native live session bridge, VAD gating, and partial/final/translation events. When a local ASR command runtime is ready, live chunks are buffered into temporary WAV windows for partial/final ASR and deleted after processing. The Chromium extension no longer hosts live-subtitle controls or audio capture permissions.
- Privacy defaults: no raw audio, full transcript, translated subtitle, page title, full URL, or full media path in diagnostics/history by default; temporary normalized audio is deleted after ASR processing.
- Automated checks through `swift run LLMToolsChecks`, `node scripts/check-phase4-media-subtitles.mjs`, `node scripts/check-phase4-local-asr-runtime.mjs`, extension JS syntax checks, and the existing browser DOM regression suite.

Runtime boundary:

- Real ASR requires a local Fun-ASR/SenseVoiceSmall/Qwen3-ASR runtime and model installed on the Mac. The app can call sidecar commands configured in Settings, falls back to `LLMTOOLS_FUN_ASR_COMMAND`, `LLMTOOLS_SENSEVOICE_COMMAND`, `LLMTOOLS_QWEN3_ASR_COMMAND`, or `LLMTOOLS_ASR_COMMAND`, can auto-use `llama-funasr-cli` for compatible Fun-ASR GGUF folders, can auto-use `sherpa-onnx-offline` for SenseVoiceSmall ONNX folders with `model.onnx` and `tokens.txt`, and can auto-use the bundled `llmtools-mlx-asr-runner.sh` for supported ASR folders when the matching isolated runtime is installed. Qwen3 uses `scripts/install-phase4-mlx-asr-runtime.sh`; Fun-ASR-MLT-Nano uses `scripts/install-phase4-funasr-mlx-runtime.sh`; Fun-ASR-Nano uses `scripts/install-phase4-funasr-nano-mlx-runtime.sh`; SenseVoiceSmall uses `scripts/install-phase4-sensevoice-mlx-runtime.sh`.
- Current Swift MLX dependencies do not include native in-process implementations for the ASR config model types. safetensors/MLX ASR folders therefore use the bundled local MLX command runner rather than remote ASR.
- If no local runtime/model is present, file transcription and desktop live subtitles fail with explicit local runtime/model errors. This is intentional and must not be replaced with remote ASR fallback.

## 2. Scope Summary

### 2.1 In Scope

- Audio and video file intake.
- Local audio extraction and normalization for ASR.
- Non-realtime file transcription.
- Timestamped subtitle generation.
- Subtitle translation through the existing llmTools translation engine.
- Subtitle export as SRT, VTT, TXT, and Markdown.
- Desktop live subtitles from system audio and/or microphone audio.
- Original-only, translated-only, and bilingual floating subtitle modes.
- SenseVoiceSmall local realtime ASR.
- Qwen3-ASR-0.6B local file ASR and experimental realtime ASR option.
- VAD-based speech segmentation for realtime sessions.
- Speech-capable model metadata and settings.
- Redacted media diagnostics.
- Local privacy defaults: no raw audio, full transcripts, or translated subtitles persisted unless the user explicitly opts in.
- Cancellation, stop, retry, and error-state handling.
- Regression protection for Phase 1 selected-text tasks, Phase 2 webpage translation, and Phase 3 OCR.

### 2.2 Out Of Scope

- Remote ASR providers.
- Automatic cloud ASR fallback.
- Background always-on system audio monitoring.
- General-purpose microphone dictation outside live subtitles.
- Meeting bots or conference-call joining.
- Speaker diarization.
- Word-perfect timestamps.
- Speech-to-speech translation.
- Burning subtitles into video files.
- Always-on audio monitoring.
- Browser-extension-hosted live-subtitle implementation in the MVP.
- DRM/protected-media guarantees.
- Browser PDF translation.
- DOCX/PDF document understanding and multi-document QA.

## 3. Product Principles

- Local-first ASR: audio must stay on the device for speech recognition in Phase 4.
- Media-first: audio/video subtitles are the main line; generic document intake should not dilute the phase.
- Chinese-first quality: Simplified Chinese output and Chinese-language media quality matter more than claiming universal language coverage.
- Runtime honesty: show which ASR model is running and whether it is realtime-capable or file-only.
- No silent fallback: if the selected local ASR model is unavailable or too slow, show the blocker instead of switching to cloud ASR.
- Reuse translation: after ASR produces text, use the existing llmTools translation engine and prompt discipline.
- Reversible UI: live subtitle windows must be removable and must not mutate source app or browser page content.
- Privacy by default: diagnostics and history must not capture raw audio or raw subtitle text unless the user opts in.

## 4. User Stories

### 4.1 Audio Or Video File To Subtitles

As a user, I can drop a recording or video file into llmTools and generate subtitles.

Acceptance:

- Supported initial inputs include common local audio/video files such as WAV, MP3, M4A, MP4, MOV, and WebM where local extraction succeeds.
- The app extracts audio locally and normalizes it for the selected ASR runtime.
- The app shows file name, duration when known, selected ASR model, target language, and processing state.
- The run can be cancelled.
- Failure messages distinguish unsupported file format, extraction failure, missing ASR model, ASR runtime failure, translation failure, and export failure.
- The user can export original subtitles as SRT and VTT.

### 4.2 File Subtitle Translation

As a user, I can translate generated subtitles into Simplified Chinese.

Acceptance:

- Target language defaults to Simplified Chinese.
- The user can produce original-only, translated-only, or bilingual subtitle output.
- Translation preserves subtitle segment order and timing.
- Translation uses a dedicated subtitle prompt that favors concise, readable subtitles over literal long-form prose.
- Exported bilingual text is available in Markdown/TXT, and timed translated subtitles are available in SRT/VTT.
- Translation can be retried without rerunning ASR when transcript segments already exist.

### 4.3 Non-Realtime Quality Model

As a user, I can choose a slower file-transcription model when quality matters more than latency.

Acceptance:

- Qwen3-ASR-0.6B appears as a file-transcription ASR option and an experimental realtime ASR option when installed or configured.
- Qwen3-ASR-0.6B is not forced as the default live-subtitle model when SenseVoiceSmall is already configured.
- The UI clearly labels Qwen3 realtime behavior as experimental/conservative.
- If Qwen3-ASR-0.6B requires a local sidecar or runtime process, the app exposes setup/health state before running.
- The app can fall back from Qwen3-ASR-0.6B to SenseVoiceSmall for a file task only after the user explicitly chooses another local model.

### 4.4 Chrome Current-Tab Live Subtitles

As a user watching a video or live stream in Chrome, I can start llmTools live subtitles for the current tab.

Acceptance:

- Starting live subtitles requires an explicit user action from the extension popup, command, or context menu.
- The extension captures only the current tab.
- Captured tab audio continues playing to the user.
- The user can stop subtitles and release audio capture within one second.
- The overlay supports original-only, translated-only, and bilingual modes.
- The overlay uses an isolated container and does not mutate page text.
- Navigation, stop, extension unload, or app disconnect ends the live session cleanly.
- Unsupported pages show a clear unsupported state.

### 4.5 Realtime Chinese Translation

As a user, I can watch non-Chinese media and see Chinese translated subtitles.

Acceptance:

- The live pipeline emits partial original transcript when possible.
- Final transcript segments are translated into Simplified Chinese.
- The UI distinguishes partial and final subtitle states.
- Translation lag is visible when the local machine or selected model cannot keep up.
- Low-confidence language detection shows an unknown or low-confidence state instead of a confident wrong language.

### 4.6 Privacy And Diagnostics

As a privacy-sensitive user, I can confirm audio recognition is local and that diagnostics are redacted.

Acceptance:

- ASR mode is visibly local.
- There is no remote ASR setting or fallback in Phase 4 UI.
- Raw input audio is not persisted. Temporary normalized audio may be written for local ASR and must be deleted after processing.
- Transcript and translated subtitle history are off by default.
- Diagnostics do not include raw audio, transcript text, translated text, full page URL, page title, or media file path.
- Diagnostics can include redacted fields such as file type, duration bucket, sample rate, ASR model ID, target language, elapsed time, segment counts, error code, and URL/domain hashes for browser sessions.

## 5. Model Strategy

### 5.1 Realtime ASR: Fun-ASR-MLT-Nano And Fun-ASR-Nano

Fun-ASR-MLT-Nano is the preferred broad-language realtime ASR model for Phase 4 when a local Fun-ASR streaming runtime is configured. Fun-ASR-Nano remains the lower-latency Chinese/English/Japanese option when available.

Expected role:

- Desktop live subtitles.
- Short audio/video file transcription where speed matters.
- Broad-language realtime subtitles with Fun-ASR-MLT-Nano; Chinese, English, and Japanese first-pass low latency with Fun-ASR-Nano.
- Language detection or language hint where the runtime exposes it.

Integration guidance:

- Prefer a local runtime path that can be packaged or guided clearly for macOS.
- A Fun-ASR streaming sidecar is the primary integration boundary. Compatible GGUF folders can use `llama-funasr-cli` automatically when present.
- The runtime must expose health checks: installed, missing files, incompatible model files, load failure, and inference failure.
- The app must not silently download ASR models unless model download management becomes an explicit product decision.

### 5.1a Fallback Short-Window ASR: SenseVoiceSmall

SenseVoiceSmall remains supported for users who already have a working local SenseVoice sidecar or sherpa-onnx setup.

### 5.2 File And Experimental Realtime ASR: Qwen3-ASR-0.6B

Qwen3-ASR-0.6B is an optional quality-oriented file transcription model and can be selected for experimental realtime subtitles.

Expected role:

- Audio/video file transcription.
- Conservative final-transcript realtime subtitles when the user selects Qwen3-ASR.
- Long recordings where waiting is acceptable.
- Chinese and Chinese-dialect heavy recordings where quality may justify slower runtime.
- Batch subtitle generation.

Constraints:

- Do not use it as the default live-subtitle model in Phase 4.
- Treat the runtime as local-only. If it requires Python, Transformers, vLLM, MLX conversion, or a local sidecar, the setup state must be explicit.
- The first implementation may mark it as experimental until local packaging, performance, and memory behavior are verified.

### 5.3 VAD

Realtime ASR must use VAD.

Recommended behavior:

- Convert captured audio to 16 kHz mono PCM unless the selected runtime requires a different format.
- Process short frames for speech activity.
- Start partial caption generation after speech begins.
- Finalize a segment after a silence threshold.
- Avoid sending long stretches of silence or music to ASR.

### 5.4 Translation Model

ASR models produce transcripts. They do not own final target-language translation.

Translation requirements:

- Use existing llmTools translation routing and model preferences.
- Add a subtitle translation prompt tuned for concise timing-bound text.
- Preserve segment ordering and timing.
- Allow retrying translation without rerunning ASR.
- Keep translation provider disclosure consistent with existing llmTools provider UI.

## 6. Capability And Settings Design

### 6.1 Model Capabilities

Extend model capability metadata to include speech support.

Suggested inputs:

```swift
public enum ModelInputCapability: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case speech
}
```

Add ASR-specific metadata without overloading text/vision capability:

```swift
public enum SpeechRuntimeMode: String, Codable, Sendable, CaseIterable {
    case realtime
    case fileOnly
}

public enum SpeechModelFamily: String, Codable, Sendable, CaseIterable {
    case senseVoiceSmall
    case qwen3ASR06B
    case customLocal
}

public struct SpeechModelCapabilities: Codable, Hashable, Sendable {
    public var family: SpeechModelFamily
    public var modes: [SpeechRuntimeMode]
    public var supportedLanguageHints: [String]
    public var requiresLocalSidecar: Bool
    public var source: ModelCapabilitySource
    public var confidence: Double
    public var note: String?
    public var lastCheckedAt: Date?
    public var lastFailureMessage: String?
}
```

### 6.2 Preferences

Add media subtitle preferences to `AppPreferences`.

Suggested shape:

```swift
public struct MediaSubtitlePreferences: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var realtimeASRModelID: UUID?
    public var fileASRModelID: UUID?
    public var defaultTargetLanguage: String
    public var defaultSubtitleMode: SubtitleDisplayMode
    public var saveTranscriptHistory: Bool
    public var saveTranslatedSubtitleHistory: Bool
    public var senseVoiceCommandTemplate: String
    public var qwen3ASRCommandTemplate: String
    public var genericASRCommandTemplate: String
    public var exportDirectoryBookmark: Data?
}

public enum SubtitleDisplayMode: String, Codable, Sendable, CaseIterable {
    case original
    case translated
    case bilingual
}
```

Defaults:

- `isEnabled`: true after the feature ships.
- `realtimeASRModelID`: SenseVoiceSmall when configured.
- `fileASRModelID`: first configured file-capable ASR model; users can choose Qwen3-ASR-0.6B for file transcription.
- `sourceLanguageHint`: auto by default; users can choose Chinese, Cantonese, English, Japanese, or Korean to reduce wrong source-language detection on short realtime segments.
- `defaultTargetLanguage`: Simplified Chinese.
- `defaultSubtitleMode`: bilingual for file preview, translated for live overlay if user chooses translation.
- `saveTranscriptHistory`: false.
- `saveTranslatedSubtitleHistory`: false.
- ASR command templates: empty by default; empty values fall back to launch-time environment variables or detected local runtime.

### 6.3 Settings UI

Settings should include a media subtitles section:

- Realtime ASR model picker.
- File ASR model picker.
- Source-language hint picker.
- Local ASR command templates for Fun-ASR, SenseVoice, Qwen3-ASR, and generic fallback sidecars.
- Model status and health-check action.
- Default target language.
- Default subtitle display mode.
- Transcript/subtitle history opt-in.
- Diagnostics privacy explanation.
- Chrome live-subtitle setup status after browser support is implemented.

Rules:

- Realtime model picker only lists local speech models marked `realtime`.
- File ASR model picker can list `realtime` and `fileOnly` local speech models.
- Fun-ASR-MLT-Nano should be preferred for realtime when configured; Fun-ASR-Nano should rank ahead of SenseVoiceSmall and Qwen3-ASR for low-latency realtime.
- Qwen3-ASR-0.6B must be labeled experimental realtime and should use conservative realtime segmentation until real-runtime latency proves a faster strategy.
- There is no remote ASR provider picker in Phase 4.

## 7. Architecture

### 7.1 File Subtitle Pipeline

```text
File drop / picker
-> Media intake validator
-> Local audio extractor
-> Audio normalizer
-> ASR session
-> Transcript segments
-> Subtitle segment store
-> Optional translation coordinator
-> Preview
-> Export SRT / VTT / TXT / Markdown
```

Implementation components:

- `MediaIntakeService`
- `AudioExtractionService`
- `AudioNormalizer`
- `ASRModelRegistry` or speech extension of the existing model registry
- `ASRRunner`
- `SenseVoiceASRRunner`
- `QwenASRFileRunner`
- `SubtitleSegmentStore`
- `SubtitleTranslationCoordinator`
- `SubtitleExporter`

### 7.2 Desktop Live Pipeline

```text
Menu or global shortcut
-> Native floating subtitle window
-> ScreenCaptureKit system audio and/or AVAudioEngine microphone capture
-> PCM16 chunks
-> Native live-audio session
-> VAD
-> SenseVoiceSmall ASR
-> Partial/final transcript events
-> Translation coordinator
-> Subtitle events
-> Content-script overlay
```

Implementation components:

- Native menu/global shortcut live-subtitle controls.
- Native live-subtitle session coordinator.
- ScreenCaptureKit system-audio capture.
- AVAudioEngine microphone capture.
- Native live-audio bridge.
- `LiveAudioSessionManager`
- `LiveSubtitleSession`
- `VADRunner`
- `SenseVoiceRealtimeRunner`
- `LiveSubtitleOverlay`

### 7.3 Bridge Protocol

File transcription can stay in the native app. Browser live subtitles need a session protocol.

Suggested native bridge events:

- `createLiveSubtitleSession`
- `appendAudioChunk`
- `stopLiveSubtitleSession`
- `cancelLiveSubtitleSession`
- `partialTranscript`
- `finalTranscript`
- `partialTranslation`
- `finalTranslation`
- `languageDetected`
- `warning`
- `error`
- `stopped`

For transport:

- A persistent native messaging port or WebSocket-like local bridge is preferred for live sessions.
- HTTP chunk posts are acceptable for an early spike only if latency and backpressure remain manageable.
- Every chunk must include sequence number, sample rate, channel count, encoding, and session ID.
- The bridge must apply backpressure instead of unbounded buffering.

### 7.4 Subtitle Segment Model

Suggested data model:

```swift
public struct SubtitleSegment: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var index: Int
    public var startTime: TimeInterval
    public var endTime: TimeInterval?
    public var originalText: String
    public var translatedText: String?
    public var sourceLanguage: String?
    public var languageConfidence: Double?
    public var isFinal: Bool
    public var asrModelID: String
    public var translationModelID: String?
}
```

Persistence rules:

- In-memory by default for live sessions.
- File task segments can be kept in memory until export.
- Persist transcript/subtitle history only when the user opts in.
- Never persist raw audio by default.

## 8. UX Requirements

### 8.1 Native File Workflow

Entry points:

- Floating widget file drop.
- Native file picker.
- Drag file into a media-subtitles surface.

Required controls:

- ASR model picker.
- Target language picker.
- Subtitle mode segmented control: original, translated, bilingual.
- Start/cancel/retry buttons.
- Export menu: SRT, VTT, TXT, Markdown.

States:

- Empty.
- File selected.
- Extracting audio.
- Transcribing.
- Translating.
- Completed.
- Cancelled.
- Failed.

### 8.2 Browser Live Workflow

Popup controls:

- Start live subtitles.
- Stop.
- Subtitle mode.
- Target language.
- Optional overlay position and font size controls.
- Model/status summary.

Overlay behavior:

- Fixed bottom placement by default.
- Shadow DOM isolation.
- No source-page text mutation.
- Partial text appears visually distinct from final text.
- Stop clears or collapses the overlay.
- Errors show in extension UI and overlay only when useful.

### 8.3 Copy And Export

The user can:

- Copy original transcript.
- Copy translated transcript.
- Copy bilingual transcript.
- Export original subtitles.
- Export translated subtitles.
- Export bilingual Markdown/TXT.

## 9. Privacy And Security

- No remote ASR in Phase 4.
- Raw input audio is not persisted.
- Temporary audio extraction/normalization files are deleted after the run.
- Full transcript and translated subtitle history are opt-in.
- Diagnostics are redacted.
- Desktop live-subtitle sessions require explicit user action.
- Capture source is user-selected system audio, microphone audio, or mixed audio.
- Unsupported capture contexts and missing permissions must fail clearly.
- The browser extension must not capture live-subtitle audio or send captured audio through page-side fetch/XHR/beacon.
- The native bridge must reject unauthenticated live-audio sessions using the existing local bridge token pattern or a stronger session token.

## 10. Milestones

### Phase 4.0: Speech Model And File Subtitle Foundation

Build:

- Speech capability metadata.
- Media subtitle preferences.
- SenseVoiceSmall local runtime health check.
- Audio extraction and normalization.
- File transcription with SenseVoiceSmall.
- Basic transcript segment model.

Exit criteria:

- A local audio file can be transcribed with SenseVoiceSmall.
- Cancellation works.
- Missing model/runtime errors are actionable.
- No raw audio or transcript history is persisted by default.

### Phase 4.1: File Translation And Export

Build:

- Subtitle translation coordinator.
- Subtitle-specific translation prompt.
- SRT/VTT/TXT/Markdown export.
- Qwen3-ASR-0.6B file model option.
- Retry translation without rerunning ASR.

Exit criteria:

- A user can create original and translated SRT/VTT from a supported file.
- Qwen3-ASR-0.6B remains available for file transcription.
- Chinese and English file fixtures pass.

### Phase 4.2: Desktop Live Subtitle Technical Spike

Build:

- ScreenCaptureKit system-audio capture.
- AVAudioEngine microphone capture.
- Mixed audio source selection.
- Floating subtitle window and global shortcut.
- Native session creation and chunk stats.

Exit criteria:

- Capture starts only after user action.
- System audio continues playing while capture is active.
- Stop releases capture within one second.
- App stop, app quit, and permission failures clean up the session.

### Phase 4.3: Desktop Live ASR And Floating Window

Build:

- Live native audio session.
- VAD runner.
- SenseVoiceSmall realtime ASR events and optional Qwen3-ASR final-transcript realtime events.
- Floating subtitle window rendering.
- Original-only live subtitles.

Exit criteria:

- English and Chinese desktop audio fixtures produce readable original live subtitles.
- Silence and music do not continuously trigger ASR.
- Subtitle window can start, update, stop, and clear without mutating source app content.

### Phase 4.4: Live Translation And Quality Pass

Build:

- Live subtitle translation.
- Bilingual and translated-only subtitle window modes.
- Language confidence display.
- Latency and CPU diagnostics.
- Multilingual smoke fixture set.

Exit criteria:

- English-to-Chinese and Chinese original subtitles work end to end.
- Cantonese, Japanese, Korean, Spanish, French, and German smoke cases are recorded.
- Low-confidence language detection is shown honestly.
- Existing Phase 1, Phase 2, and Phase 3 regression checks remain green.

## 11. Test Plan

Automated checks:

- `swift run LLMToolsChecks` for speech capability defaults, model picker filtering, subtitle translation coordinator, export formatting, and privacy defaults.
- `swift run LLMToolsChecks` also covers a fixture local-command file pipeline: generated WAV file, audio normalization, ASR command transcript, subtitle translation, SRT/VTT/TXT/Markdown export, and no default history persistence.
- `node scripts/check-phase4-media-subtitles.mjs` for desktop live-subtitle structure, browser-extension live-subtitle removal, native bridge routes, and no cloud-ASR hints.
- `node scripts/check-phase4-local-asr-runtime.mjs` for current-Mac ASR runtime diagnostics, including registered speech models, command-template/env readiness, local mlx-audio readiness, sherpa-onnx eligibility, and runtime blockers.
- `swift run LLMToolsMediaSmoke --output-dir dist/phase4-media-smoke` for a real local media pipeline smoke: generated speech audio, Qwen3-ASR or configured file ASR, subtitle translation through a local text model, and SRT/VTT/TXT/Markdown export.
- Extension JavaScript syntax checks for background, content script, and popup files.
- Speech capability decode/migration.
- Realtime model picker includes realtime-capable Qwen3-ASR-0.6B when configured.
- File model picker includes Qwen3-ASR-0.6B when configured.
- Subtitle translation prompt contract.
- SRT and VTT export formatting.
- Privacy defaults for transcript/subtitle history.
- Redacted diagnostics.
- Desktop live-subtitle start/stop state transitions.
- Audio chunk sequence and backpressure handling.

Manual or fixture-based acceptance:

- Short English audio file.
- Short Chinese audio file.
- Chinese video file with background music.
- English video file translated to Simplified Chinese.
- Cantonese/Japanese/Korean multilingual smoke samples.
- Long file cancellation.
- Missing model/runtime setup.
- Desktop video playback through system audio.
- Desktop live stream playback through system audio.
- Source app changes during capture.
- App quit during capture.

Regression gates:

- Phase 1 selected-text and quick-action tasks.
- Phase 2 webpage translation closure checks where relevant.
- Phase 3 OCR checks.
- Packaged `dist/llmTools.app` verification for native media workflows.

## 12. Risks

- Fun-ASR-MLT-Nano integration requires a local streaming sidecar or compatible GGUF runtime rather than pure Swift embedding.
- SenseVoiceSmall integration may require a local runtime bridge rather than pure Swift embedding.
- Qwen3-ASR-0.6B may be too heavy for smooth local packaging and should remain optional until verified.
- Local translation after ASR can add latency to live subtitles.
- Browser tab capture behavior is permissioned and may fail on protected or browser-internal pages.
- Audio extraction from video files may require adding or bundling a media toolchain.
- Long live sessions can expose memory growth, queue buildup, or model lifecycle issues.
- Multilingual language detection on short subtitle fragments can be unstable.

## 13. Open Decisions

- Exact local runtime boundary for Fun-ASR-MLT-Nano: streaming sidecar, GGUF helper executable, or managed runtime.
- Exact local runtime boundary for SenseVoiceSmall: embedded library, local helper executable, or managed sidecar.
- Exact local runtime boundary for Qwen3-ASR-0.6B.
- Whether llmTools should manage ASR model downloads in-app or only accept user-selected local model paths in Phase 4.
- Whether transcript/subtitle history should remain completely absent or exist as an explicit opt-in feature.
- Whether bilingual timed export should use paired SRT cues or Markdown/TXT only in the first release.

## 14. References

- Phase 4 live-audio research: `docs/phase-4-live-audio-subtitles-research.md`
- Fun-ASR: https://github.com/FunAudioLLM/Fun-ASR
- SenseVoice: https://github.com/FunAudioLLM/SenseVoice
- sherpa-onnx SenseVoice guide: https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html
- Qwen3-ASR: https://github.com/QwenLM/Qwen3-ASR
- Silero VAD: https://github.com/snakers4/silero-vad
