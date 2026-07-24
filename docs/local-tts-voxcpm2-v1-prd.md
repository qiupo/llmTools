# Local Text To Speech V1: VoxCPM2

Status: implemented and locally validated on 2026-07-15 with bf16/4bit real-model smokes and packaged-app checks.

## 1. Product Goal

llmTools provides a dedicated local text-to-speech workbench for ordinary single-narrator copy, long-form copy, reusable voice profiles, and optional multi-role scripts. Multi-role generation is one mode of the product rather than the main entry point.

The V1 runtime is VoxCPM2-only:

- `mlx-community/VoxCPM2-bf16` is the default high-quality model.
- `mlx-community/VoxCPM2-4bit` is the low-memory model.
- Existing `VoxCPM2-8bit` folders remain detectable for compatibility but are not shown as a primary UI choice.
- Qwen3-TTS is not installed, routed, or used as a fallback.

All text analysis, voice generation, project data, reference audio, and exports stay on the Mac. There is no cloud TTS or automatic remote fallback.

## 2. V1 Workflow

1. Open the status menu and choose `文案转语音`.
2. Keep the default single-narrator mode or switch to multi-role.
3. Enter copy. Single-narrator mode deterministically splits it into bounded synthesis segments.
4. In multi-role mode, explicit `角色：台词` / `[角色] 台词` input is parsed deterministically. Natural prose uses a selected local GGUF/MLX text model and the current voice catalog to return both speaker identity and a bounded voice index.
5. Review and edit the generated script, speaker-to-voice assignment, and spoken text. Changing one speaker's voice applies to every segment assigned to that speaker.
6. Open the separate voice-management window to configure each role as a designed voice or an authorized cloned voice, persist the preview copy, and generate or safely regenerate the solidified preview anchor.
7. Return to the workbench, select the voice, and generate or resume the sequential segment queue.
8. Preview or pause completed audio and export WAV, M4A, or an aligned SRT file.

## 3. Functional Scope

### 3.1 Copy And Script Editing

- Single-narrator and multi-role modes.
- Long text is split at natural punctuation with a bounded per-request size.
- Source text, spoken text, source offsets, role assignment, confidence, pause, generation state, duration, and error are stored per segment.
- Script rows remain editable before generation.
- Editing source, role, voice, or spoken text marks affected completed audio stale.

### 3.2 Multi-Role Analysis

- Explicit role syntax does not require a text model.
- Natural prose analysis only uses a configured local GGUF/MLX text model.
- Software deterministically splits the complete source into indexed sentence units before model inference.
- Long prose is analyzed in bounded groups of at most 16 units and stable role names are merged across groups.
- The model returns only strict JSON `index -> speaker/type/confidence` assignments; it never returns or rewrites source text.
- Missing, duplicate, or unknown unit indices are rejected instead of silently producing an incomplete script.
- The local analysis model is unloaded before VoxCPM2 is started.

### 3.3 Voices

- Designed voice: a VoxCPM2 instruction describes timbre, age, emotion, and speaking style.
- Voice creation and editing live in a separate voice-management window; the main workbench only selects voices for synthesis.
- A designed voice can generate a dedicated preview, which is persisted as that role's local reference anchor so later segments remain stable.
- If no dedicated preview exists, the first successful designed-voice segment becomes the local reference anchor.
- Cloned voice: the user imports local reference audio into the owner-only project directory.
- Cloned voice generation is blocked until the user confirms usage rights.
- Designed and cloned voices can both be previewed before document synthesis.
- Voice profiles, the selected voice, references, and preview paths are persisted with the local project.
- Multiple role profiles can be added, renamed, reassigned, or removed.

### 3.4 Generation And Recovery

- A persistent Python sidecar loads VoxCPM2 once for a sequential queue.
- Every segment transition is saved: pending, generating, completed, failed, or stale.
- Completed segments are skipped when a queue resumes.
- Failed segments keep their error and can be regenerated independently.
- Cancellation resets an in-flight segment to pending and preserves completed output.
- The latest project is restored on the next launch.
- V1 reports progress per completed segment. `mlx-audio 0.4.5` returns the completed VoxCPM2 result, so V1 does not claim incremental audio streaming.

### 3.5 Playback And Export

- Play an individual completed segment.
- Compose and preview all completed segments with configured pauses.
- Pause and resume segment, project, and voice-preview playback from the same control.
- Export 48 kHz PCM WAV.
- Export M4A through the native macOS audio converter.
- Export SRT only for segments with completed audio, using role names and generated durations.

### 3.6 Runtime And Model Health

- TTS uses an isolated runtime under `~/Library/Application Support/llmTools/tts-runtime`.
- The pinned runtime dependency is `mlx-audio==0.4.5`.
- Model discovery supports the app runtime model directory and `~/code/models/mlx-community`.
- Sharded weights are ready only when every file referenced by `model.safetensors.index.json` exists.
- The UI exposes runtime missing, model incomplete, and ready states.
- Model weights are not bundled into `llmTools.app`.

### 3.7 Privacy And Lifecycle

- Project directories are mode `0700`; project JSON, imported references, and generated audio are mode `0600`.
- TTS projects do not enter Recent History.
- The sidecar redirects model logs to stderr and reserves stdout for the NDJSON protocol.
- VoxCPM2 and the MLX cache are released after queue completion, cancellation, model switching, and app termination.
- The TTS runtime is independent of ASR, live subtitles, and meeting transcription runtimes.

## 4. Local Paths And Commands

Expected model directories:

```text
~/code/models/mlx-community/VoxCPM2-bf16
~/code/models/mlx-community/VoxCPM2-4bit
```

Install only the isolated runtime:

```sh
LLMTOOLS_TTS_DOWNLOAD_MODEL=0 ./scripts/install-tts-voxcpm2-runtime.sh
```

Run checks and a real model smoke:

```sh
swift run LLMToolsChecks
swift run LLMToolsTTSSmoke --variant voxCPM2FourBit --output /tmp/llmtools-tts.wav
```

## 5. Acceptance Gate

- Core fixtures pass for explicit roles, deterministic source units, complete indexed assignments, missing-index rejection, long-text splitting, owner-only recovery, WAV composition, SRT filtering, and sharded-model completeness.
- Both bf16 and 4bit pass a real sidecar generation smoke.
- The packaged app contains the TTS sidecar and installer but no model weights.
- The packaged app opens the TTS window, restores a project, generates and exports audio, and terminates its TTS child process on stop and quit.
- Existing Quick Action, live subtitles, media subtitles, and meeting transcription checks continue to pass.

## 6. Deferred

- Incremental audio streaming while a segment is synthesizing.
- A global voice library shared across projects.
- Automatic subtitle timing finer than generated segment duration.
- SSML, pronunciation dictionaries, batch folder import, and waveform editing.
- Cloud TTS, cloud voice cloning, and automatic remote fallback.
