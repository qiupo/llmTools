# Phase 4 ASR Realtime Latency Report

Last updated: 2026-07-08

Status: local benchmark notes for choosing llmTools live-subtitle ASR backends on Apple Silicon.

## 1. Goal

This report records the local ASR backends tested for Phase 4 media subtitles and desktop live subtitles.

The main question is not "which backend can transcribe a file fastest". For live subtitles, the product-critical metric is:

> How long after speech is played does readable subtitle text appear?

File transcription throughput is still useful, but it must be treated separately from realtime subtitle latency.

## 2. Test Material

Source video:

`/Users/po/Downloads/39420821618-1-192.mp4`

Test audio:

`/tmp/llmtools-mixed-first60-16k.wav`

The test audio is the first 60 seconds of the source video, normalized to 16 kHz mono WAV. This minute contains Chinese and English speech, so it is useful for testing mixed-language subtitle behavior rather than pure English dictation.

## 3. Test Environment

- Machine class: local Apple Silicon Mac.
- OS observed during testing: macOS 26.5 build 25F71.
- Swift toolchain observed during testing: Apple Swift 6.3.2, target `arm64-apple-macos26.0`.
- ASR product boundary: local-only. Remote ASR and silent cloud fallback are out of scope for Phase 4.
- HuggingFace access note: direct `huggingface.co` API requests timed out during FluidAudio model download. `REGISTRY_URL=https://hf-mirror.com` worked with FluidAudio's registry override.

## 4. Metric Definitions

- Realtime first subtitle latency: elapsed wall-clock time from realtime audio feeding start to the first non-empty subtitle/partial transcript.
- ASR processing time: model-side time to process a chunk or window once audio is already available.
- Offline throughput: wall-clock time to transcribe a complete file. This is useful for file subtitles, but it does not prove low live-subtitle latency.
- RTFx: audio duration divided by processing time. Higher is faster.

## 5. Summary

| Backend | Acceleration path | Test mode | First subtitle latency | Processing / throughput | Mixed CN/EN quality | Decision |
| --- | --- | --- | ---: | ---: | --- | --- |
| Fun-ASR-MLT-Nano | MLX sidecar runtime | Realtime window test | ~0.989 s | first ASR ~189 ms; 3 s window median ~386.5 ms | Broad-language candidate; heavier per-window cost than SenseVoice/Qwen3 | Keep as broad-language realtime candidate |
| SenseVoiceSmall | MLX sidecar runtime | Realtime window test | ~1.014 s | first ASR ~14 ms; 3 s window median ~12 ms | Very fast, but first Chinese phrase had recognition error around "勺" | Keep as low-latency fallback |
| Qwen3-ASR-0.6B 4bit | MLX sidecar runtime | Realtime window test | ~1.565 s | first ASR ~65 ms; 3 s window median ~85 ms | Strong on the Chinese opening, but quantization can change edge-case quality | Keep as faster Qwen3 alternative when quality is acceptable |
| Qwen3-ASR-0.6B bf16 | MLX sidecar runtime | App bridge realtime feed, 100 ms chunks, 60 s clip | first partial at ~1.590 s wall time | ASR event response median ~157 ms; p90 ~203 ms; max ~270 ms | Best current local quality/effect result in follow-up testing; mixed CN/EN works, with a few imperfect English/short-window partials | Preferred current Qwen3 realtime candidate |
| whisper-base CoreML | whisper.cpp Core ML | Realtime window test | ~2.605 s | Not competitive in this run | Poor on this clip | Do not use as default realtime backend |
| sherpa-onnx Qwen3-ASR | sherpa-onnx | Realtime comparison | Slower than MLX Qwen3-ASR in prior local comparison | Not retained | Did not beat the original MLX Qwen3 path | Removed from selectable backend |
| Apple SpeechAnalyzer zh-CN | Apple Speech framework / system assets | Realtime 200 ms chunk feed | ~1.062 s | 60 s audio completed in ~62.7 s under realtime feed | Chinese partials are fast, but mixed English is heavily garbled | Experimental low-latency Chinese partial backend only |
| Apple SpeechAnalyzer zh-CN | Apple Speech framework / system assets | Offline file analysis | first progressive result ~30.2 ms | full 60 s in ~494.9 ms, RTF ~0.008 | Same quality issue as realtime: English is poor | Useful file-speed data, not enough for mixed live subtitles |
| FluidAudio Parakeet EOU 120M 160 ms | CoreML / ANE | Realtime 160 ms chunk feed | ~30.263 s | 60 s audio completed in ~60.0 s; early chunks often ~18-27 ms processing | Skipped Chinese opening and only began outputting English text | Not suitable for mixed Chinese/English live subtitles |
| FluidAudio Parakeet EOU 120M 160 ms | CoreML / ANE | Offline complete-buffer run | Not applicable | full 60 s in ~6.19 s, ~9.7x realtime | English output usable; Chinese not covered | Good English streaming experiment, not llmTools default |
| FluidAudio Parakeet TDT v3 0.6B | CoreML / ANE | Batch file transcription | Not applicable | full 60 s in ~0.41 s, ~146x realtime | Chinese opening became English-like phonetic garbage; English was more complete | Strong file throughput, not a mixed-language realtime solution |

## 6. Qwen3-ASR-0.6B bf16 Optimization Follow-up

Follow-up testing made Qwen3-ASR-0.6B bf16 the preferred local realtime candidate, even though the 4bit variant can be faster on some short windows. The quality/effect tradeoff is currently better with bf16.

The main latency problem was not just one model invocation. In the live-subtitle loop, partial subtitles were re-transcribing the entire accumulated speech buffer. During continuous speech, that makes every new partial more expensive than the previous one.

Measured hot-window sidecar timings for Qwen3-ASR-0.6B bf16 on the same first-minute test audio:

| Window | Hot ASR elapsed |
| ---: | ---: |
| 1.2 s | ~85-119 ms, but the opening phrase was less stable |
| 1.25 s | ~88-130 ms, but the opening phrase was still wrong |
| 1.30 s | ~88-90 ms, but the opening phrase was still wrong |
| 1.35 s | ~87-247 ms; text became stable for the opening phrase |
| 1.40 s | ~88 ms; text stayed stable for the opening phrase |
| 1.5 s | ~89-91 ms |
| 2.4 s | ~109-111 ms |
| 3.0 s | ~117-121 ms |
| 4.5 s | ~154-157 ms |
| 6.0 s | ~187-192 ms |
| 9.0 s | ~242-254 ms |
| 12.0 s | ~310-320 ms |
| 30.0 s | ~796 ms |
| 45.0 s | up to ~1.7 s in the observed run |

Implemented realtime optimization:

- Qwen3-ASR bf16 partial cadence is now 1.35 seconds. The previous 1.5 second cadence was conservative; 1.25-1.30 second windows were too early for the opening phrase, while 1.35 seconds was the earliest stable window in this clip.
- Non-final partial ASR now uses a rolling recent-audio window instead of the full growing speech buffer.
- Qwen3-ASR partials are capped at 4.5 seconds. This keeps the common partial model call around the observed 4.5 second window cost instead of letting it grow toward 30-45 second costs during long continuous speech.
- Final ASR is not truncated. Final subtitles still use the complete buffered utterance before the buffer is cleared.
- The same mechanism is generic: Fun-ASR Nano / Fun-ASR-MLT and SenseVoice use a 4.0 second partial cap, whisper.cpp Core ML uses a 6.0 second cap.
- The sidecar now decodes each PCM base64 payload once and reuses the raw bytes for float32 conversion, removing duplicated per-request decoding overhead across MLX ASR families.

Post-optimization app bridge benchmark:

The app bridge was tested through `/liveSubtitleSessions` and `/liveSubtitleChunks`, feeding the first 60 seconds of the same 16 kHz PCM audio as realtime 100 ms chunks. This path exercises the packaged app's live-subtitle session logic, the long-lived Qwen3 sidecar, VAD checks, partial/final scheduling, and JSON bridge overhead. One-time sidecar load was about 2.379 seconds before the realtime feed started; it is not counted as playback-to-subtitle latency.

| Metric | Result |
| --- | ---: |
| Realtime feed duration | 60.0 s |
| Chunk size | 100 ms |
| First partial audio endpoint | 1.400 s |
| First partial wall time | 1.590 s |
| First partial response time | 188 ms |
| First final audio endpoint | 3.000 s |
| First final wall time | 3.130 s |
| First final response time | 129 ms |
| Chunk request latency median / p90 | 5 ms / 7 ms |
| ASR event response median / p90 / max | 157 ms / 203 ms / 270 ms |
| Partial / final event count | 37 / 19 |

### ASR partial window defaults

The realtime ASR partial-window setting means the partial ASR cadence/window used by the app scheduler. It is separate from low-level PCM transport chunks and from a model decoder's internal audio-slice size. The capture/bridge layer can still send small PCM chunks such as 100 ms; the partial window controls when the app asks the selected model to produce a readable partial subtitle and how much recent audio that partial request sees. The bundled Qwen3, SenseVoice, Fun-ASR, and whisper realtime sidecars currently report `streaming-window` mode: they keep the process warm, but each partial request decodes a rolling audio window instead of feeding audio slices into a persistent decoder state.

Follow-up model-window tests covered the current ready local speech models:

- `Qwen3-ASR-0.6B-bf16`
- `Qwen3-ASR-0.6B-4bit`
- `SenseVoiceSmall`
- `Fun-ASR-MLT-Nano-2512-fp16`
- `whisper-base-coreml`

The test used four offsets in the same 60 second mixed clip: Chinese opening, English handoff around 22 s, Chinese segment around 31.4 s, and English segment around 37 s.

| Model | Recommended default partial window | Reason |
| --- | ---: | --- |
| Qwen3-ASR-0.6B-bf16 | 1350 ms | 1.25-1.30 s was too early for the Chinese opening; 1.35 s was the earliest stable window. Median model-side response across sampled offsets was about 98 ms at 1.35 s. |
| Qwen3-ASR-0.6B-4bit | 1350 ms | Same earliest stable window as bf16, with lower model-side cost. Median response was about 64 ms at 1.35 s. |
| SenseVoiceSmall | 1200 ms | Extremely low model-side cost, around 12 ms median. 1.2 s gives useful low-latency partials; 1.5 s improves the Chinese opening but does not fix the English mixed-content weakness, so the lower-latency default is preferred. |
| Fun-ASR-MLT-Nano-2512-fp16 | 1500 ms | 1.5 s is the first tested window that produced the full Chinese opening phrase. Shorter windows were faster but more fragmentary; longer windows increased latency sharply. Median response was about 264 ms at 1.5 s. |
| whisper-base-coreml | 2000 ms | Chinese quality stayed weak regardless of window size, while English became usable around 2.0 s. 2.0 s keeps partial latency lower than the previous 2.5 s cadence. |

These defaults are now model-family defaults in the app. Settings -> Media -> Realtime ASR also exposes a `Partial window` control for the selected realtime ASR model. Manual overrides are stored per model ID, so tuning Qwen3 bf16 does not affect SenseVoice, Fun-ASR, or whisper.

Observed product effect:

- First readable subtitle appeared at about 1.59 seconds wall time from playback start on the 60 second mixed clip.
- The 1.35 second cadence moved the first partial about 100 ms earlier than the prior 1.5 second app-bridge run with the same 100 ms chunk simulation.
- Long continuous speech stayed bounded in the app path: ASR-event response p90 was about 203 ms and the worst observed event response was 270 ms.
- Final subtitle quality is preserved by design because final decoding still sees the full utterance.

## 7. Apple SpeechAnalyzer Findings

SpeechAnalyzer was tested with a minimal Swift probe against the same 60 second clip.

Observed asset state:

- `SpeechTranscriber` was available.
- `zh-CN` and `zh-TW` assets were installed.
- `en-US` was supported by API but the English asset was not installed on this machine during the test.
- Compatible ASR formats reported by the module were 16 kHz or 8 kHz Int16 PCM.

Realtime simulation:

- Audio was fed as realtime chunks rather than processed as a whole file.
- First non-empty partial appeared at about 1.062 seconds.
- Result cadence was good for a native partial-subtitle experience.
- Final output quality was not good enough for this mixed clip. The Chinese opening confused "勺", and the English section ended heavily garbled.

Conclusion:

Apple SpeechAnalyzer is worth keeping as a possible low-latency Apple-native experiment, especially for Chinese-only partial captions. It should not replace the current mixed-language ASR default until multilingual behavior is materially better.

## 8. FluidAudio / Parakeet Findings

FluidAudio itself is relevant because it provides CoreML/ANE model paths. Parakeet is not the right model family for this llmTools test clip.

### Parakeet EOU 120M

The EOU 160 ms model was downloaded and tested from:

`/Users/po/Library/Application Support/FluidAudio/Models/parakeet-eou-streaming/160ms`

Model cache size observed:

`443 MB`

Realtime simulation result:

- Audio was fed in 160 ms chunks with realtime sleep.
- Model-side chunk processing was fast enough: early chunks were usually around 18-27 ms after the first warm chunk.
- First partial text appeared only at about 30.263 seconds.
- First text was English: `do you want`.
- The Chinese opening did not produce usable subtitles.

Conclusion:

Parakeet EOU is a true streaming model and the compute path is good, but the language coverage does not fit Chinese/English mixed live subtitles.

### Parakeet TDT v3 0.6B

The TDT v3 model was downloaded and tested from:

`/Users/po/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3`

Model cache size observed:

`470 MB`

Batch result:

- Release binary direct run completed the 60 second file in about 0.41 seconds.
- This is around 146x realtime throughput for file transcription.
- The Chinese opening was not recognized as Chinese; it was rendered as English-like phonetic text.
- English sections were substantially better than the Chinese opening.

Conclusion:

Parakeet TDT v3 is impressive for English/multilingual European-language file throughput, but it does not solve llmTools' Chinese/English mixed realtime subtitle requirement.

## 9. Current Ranking For This Clip

For realtime subtitles on this specific mixed Chinese/English video:

1. Qwen3-ASR-0.6B bf16 MLX is the current preferred realtime candidate after follow-up testing. It has the best local quality/effect result, and the rolling partial-window optimization targets its main live-latency weakness.
2. Qwen3-ASR-0.6B 4bit MLX remains the faster Qwen3 alternative when its quantized quality is acceptable for the content.
3. Fun-ASR-MLT-Nano and SenseVoiceSmall remain valuable low-latency realtime candidates. SenseVoice is extremely fast per window, while Fun-ASR-MLT-Nano is the broader-language family.
4. Apple SpeechAnalyzer is fast enough for realtime partials, but quality on mixed English is currently too weak.
5. FluidAudio Parakeet should not be used as the default for mixed Chinese/English subtitles. The CoreML/ANE route is still promising, but the next FluidAudio models to test should be SenseVoiceSmall CoreML, Paraformer-large zh CoreML, and Nemotron Streaming Multilingual.
6. whisper-base CoreML and sherpa-onnx Qwen3-ASR are not competitive with the current MLX ASR paths for this use case.

## 10. Product Implications

- Do not treat offline RTFx as the primary live-subtitle metric.
- Keep reporting both first subtitle latency and recognition quality in future ASR tests.
- Keep the Phase 4 local-only boundary. All tested paths here are local.
- Keep realtime partial-window caps enabled for Qwen3-ASR bf16 and promote the same mechanism to other streaming ASR families with family-specific caps.
- Keep the app-level `Partial window` override per model. The tested defaults should remain low-latency, while manual tuning lets a user trade first-subtitle latency for more stable partial text on specific content.
- Treat true decoder audio-slice tuning as a separate backend capability. It only applies to ASR runtimes that preserve streaming decoder state across incoming PCM slices; the current MLX Qwen3 path does not expose that behavior through the bundled sidecar.
- Keep sherpa-onnx Qwen3-ASR removed unless a future backend shows a concrete speed/quality advantage over MLX Qwen3-ASR.
- Do not make FluidAudio Parakeet the default. If FluidAudio is integrated, prioritize its CoreML/ANE models that actually target Chinese or multilingual streaming.

## 11. Recommended Next Tests

Use the same 60 second clip and the same realtime-feed harness for:

1. FluidAudio SenseVoiceSmall CoreML.
2. FluidAudio Paraformer-large zh CoreML.
3. FluidAudio Nemotron Streaming Multilingual 0.6B CoreML with `zh` or auto language mode.
4. A longer mixed-language clip with alternating Chinese and English sections, to distinguish first-subtitle speed from language-switching quality.
