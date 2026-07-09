# Phase 4.x Realtime Speaker Diarization Spike

Date: 2026-07-08

## Decision

Realtime speaker diarization is rejected for the Phase 4.x MVP. File subtitle diarization remains in scope, but live subtitle speaker labels stay hard-disabled until a later milestone proves the latency budget.

## Acceptance Gate

Realtime diarization may only move back into scope if a later spike demonstrates both conditions on the packaged app path:

- ASR partial and final subtitle events are never blocked by diarization work.
- Speaker labels arrive with less than 3 seconds of lag while first subtitle latency remains governed by ASR only.

## Current Implementation

- `SpeakerDiarizationPreferences.enabledForLiveSubtitles` defaults to `false`.
- Decoding an older or hand-edited registry value of `enabledForLiveSubtitles: true` still normalizes to `false`.
- Settings shows the live speaker diarization toggle as disabled.
- File subtitle diarization is available through the pyannote command runner/sidecar path and is non-blocking for transcription failures.
- Speaker embeddings are not persisted by the MVP pipeline.

## Out Of Scope

- Realtime speaker labels in app-level live subtitles.
- Cross-file speaker identity or speaker embedding persistence.
- Any live diarization flow that waits for pyannote before emitting ASR partial/final subtitle text.

## Follow-Up Milestone

If this is revisited, create a separate 4.x.6 milestone with an isolated realtime worker queue, measured ASR partial latency before/after enabling diarization, and packaged-app verification. Until that evidence exists, the product behavior is file-scope diarization only.
