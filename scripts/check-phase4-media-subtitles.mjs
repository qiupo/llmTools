#!/usr/bin/env node

import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const extensionRoot = path.join(repoRoot, "browser-extension", "chromium");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function read(relativePath) {
  return fs.readFile(path.join(repoRoot, relativePath), "utf8");
}

async function assertFile(relativePath) {
  await fs.access(path.join(repoRoot, relativePath));
}

async function assertMissing(relativePath) {
  try {
    await fs.access(path.join(repoRoot, relativePath));
  } catch {
    return;
  }
  throw new Error(`${relativePath} should not exist`);
}

function assertIncludes(source, needle, label) {
  assert(source.includes(needle), `${label} should include ${needle}`);
}

function assertExcludes(source, needles, label) {
  const lower = source.toLowerCase();
  for (const needle of needles) {
    assert(!lower.includes(needle.toLowerCase()), `${label} must not include ${needle}`);
  }
}

async function run() {
  const manifest = JSON.parse(await read("browser-extension/chromium/manifest.json"));
  const permissions = new Set(manifest.permissions || []);
  for (const permission of ["activeTab", "scripting", "storage", "nativeMessaging", "contextMenus"]) {
    assert(permissions.has(permission), `manifest must include ${permission}`);
  }
  assert(!permissions.has("tabCapture"), "browser extension must not request tabCapture after live subtitles moved into the app");
  assert(!permissions.has("offscreen"), "browser extension must not request offscreen after live subtitles moved into the app");
  assert(!permissions.has("<all_urls>"), "manifest must not request <all_urls> as a normal permission");
  assert(!Array.isArray(manifest.host_permissions) || manifest.host_permissions.length === 0, "host_permissions must stay empty/absent");
  assert(
    JSON.stringify([...(manifest.optional_host_permissions || [])].sort()) === JSON.stringify(["http://*/*", "https://*/*"]),
    "optional_host_permissions should remain limited to http/https"
  );
  assert(manifest.background?.service_worker === "background.js", "MV3 service worker must remain background.js");

  for (const relativePath of [
				    "scripts/check-phase4-local-asr-runtime.mjs",
				    "scripts/check-phase4x-language-routing.mjs",
				    "scripts/check-phase4x-speaker-diarization.mjs",
				    "scripts/check-phase4x-fast-mt.mjs",
				    "scripts/llmtools-mlx-asr-runner.sh",
				    "scripts/llmtools-streaming-asr-sidecar.py",
				    "scripts/llmtools-funasr-pipeline.py",
				    "scripts/llmtools-lid-sidecar.py",
				    "scripts/llmtools-fastmt-sidecar.py",
				    "scripts/llmtools-pyannote-diarization-sidecar.py",
				    "scripts/llmtools-whisper-coreml-runner.sh",
				    "scripts/install-phase4-mlx-asr-runtime.sh",
		    "scripts/install-phase4-funasr-mlx-runtime.sh",
		    "scripts/install-phase4-funasr-nano-mlx-runtime.sh",
		    "scripts/install-phase4-funasr-pipeline-runtime.sh",
		    "scripts/install-phase4-sensevoice-mlx-runtime.sh",
		    "scripts/install-phase4-whisper-coreml-runtime.sh",
		    "scripts/install-phase4x-fasttext-lid.sh",
		    "scripts/install-phase4x-ctranslate2-en-zh.sh",
		    "scripts/install-phase4x-nllb-200-distilled-600m.sh",
		    "scripts/install-phase4x-argos.sh",
		    "scripts/install-phase4x-pyannote-diarization.sh"
		  ]) {
    await assertFile(relativePath);
  }
  for (const relativePath of [
    "browser-extension/chromium/offscreen-audio.html",
    "browser-extension/chromium/offscreenAudio.js",
    "browser-extension/chromium/liveAudioWorklet.js"
  ]) {
    await assertMissing(relativePath);
  }

  const background = await read("browser-extension/chromium/background.js");
  const contentScript = await read("browser-extension/chromium/contentScript.js");
  const popupHTML = await read("browser-extension/chromium/popup.html");
  const popupJS = await read("browser-extension/chromium/popup.js");
  const nativeHost = await read("Sources/LLMToolsNativeHost/main.swift");
  const bridge = await read("Sources/LLMToolsApp/LocalAppBridgeServer.swift");
  const appDelegate = await read("Sources/LLMToolsApp/AppDelegate.swift");
  const appState = await read("Sources/LLMToolsApp/AppState.swift");
  const captureService = await read("Sources/LLMToolsApp/LiveSubtitleCaptureService.swift");
  const modelTypes = await read("Sources/LLMToolsCore/ModelTypes.swift");
  const languageNormalizer = await read("Sources/LLMToolsCore/LanguageCodeNormalizer.swift");
  const mediaTypes = await read("Sources/LLMToolsCore/MediaSubtitleTypes.swift");
  const mediaServices = await read("Sources/LLMToolsCore/MediaSubtitleServices.swift");
  const processLifecycle = await read("Sources/LLMToolsCore/CancellableProcessHandle.swift");
  const taskEngine = await read("Sources/LLMToolsCore/TaskEngine.swift");
  const settingsView = await read("Sources/LLMToolsApp/Views.swift");
  const localASRRuntimeCheck = await read("scripts/check-phase4-local-asr-runtime.mjs");

  assertExcludes(background, [
    "startAppLiveSubtitles",
    "stopAppLiveSubtitles",
    "MENU_LIVE_SUBTITLES_ID",
    "contextMenuStartLiveSubtitles",
    "contextMenuStopLiveSubtitles",
    "liveAudioChunk",
    "liveAudioCaptureEnded",
    "liveSubtitleSessions",
    "offscreen-audio.html",
    "tabCapture"
  ], "browser extension background");
  for (const needle of [
    "webPageTranslationCacheV2",
    "TRANSLATION_CACHE_KEY_V1",
    "migrateTranslationCacheV1ToV2",
    "translationEngineID",
    "translationEngineModelID",
    "sourceLanguage"
  ]) {
    assertIncludes(background, needle, "browser extension webpage cache v2");
  }
  assertExcludes(contentScript, [
    "liveSubtitleStart",
    "liveSubtitleEvents",
    "liveSubtitleStop",
    "setLiveSubtitleMode",
    "renderLiveSubtitleOverlay",
    "stopLiveSubtitleOverlay",
    "stopLiveSubtitles",
    "document.body.innerHTML",
    "document.documentElement.innerHTML"
  ], "content script");
  assertExcludes(popupHTML, [
    "id=\"liveSubtitleMode\"",
    "id=\"startLiveSubtitles\"",
    "id=\"stopLiveSubtitles\"",
    "实时字幕"
  ], "popup HTML");
  assertExcludes(popupJS, [
    "startLiveSubtitles",
    "stopLiveSubtitles",
    "setLiveSubtitleMode",
    "liveSubtitleDisplayMode",
    "liveSubtitleStatus"
  ], "popup JS");

  for (const needle of [
    "createLiveSubtitleSession",
    "appendLiveAudioChunk",
    "stopLiveSubtitleSession",
    "getAppLiveSubtitleStatus",
    "startAppLiveSubtitles",
    "stopAppLiveSubtitles"
  ]) {
    assertIncludes(nativeHost, needle, "native host live subtitle forwarding");
  }
  for (const needle of [
    "\"/liveSubtitleSessions\"",
    "\"/liveSubtitleChunks\"",
    "\"/stopLiveSubtitleSession\"",
    "\"/appLiveSubtitleStatus\"",
    "\"/startAppLiveSubtitles\"",
    "\"/stopAppLiveSubtitles\""
  ]) {
    assertIncludes(bridge, needle, "native app live subtitle HTTP bridge");
  }
  for (const needle of [
    "pcm16HasSpeech",
    "startAppLiveSubtitles",
    "stopAppLiveSubtitles",
    "appLiveSubtitleStatusPayload",
    "clearAppLiveSubtitleHistory",
    "repairMediaSubtitleASRRuntime",
	    "installFunASRPipeline",
	    "LiveSubtitleCaptureService",
	    "createLiveSubtitleSession",
	    "appendLiveAudioChunk",
	    "stopLiveSubtitleSession",
			    "StreamingASRProcessSession",
			    "stopLiveMeetingStreamingASR",
			    "beginExternalModelUse()",
			    "LocalASRProcessRunner",
		    "mode: .realtime",
		    "translateSubtitleSegments"
	  ]) {
    assertIncludes(appState, needle, "native app live subtitle coordinator");
  }
  assertExcludes(appState, ["remote ASR fallback", "cloud ASR fallback"], "native app live subtitle coordinator");

  for (const needle of [
    "import ScreenCaptureKit",
    "import AVFoundation",
    "SCStreamConfiguration",
    "configuration.capturesAudio = true",
    "configuration.excludesCurrentProcessAudio = true",
    "AVAudioEngine",
    "CMSampleBufferCopyPCMDataIntoAudioBufferList",
    "LiveSubtitlePCM16Converter",
    "targetSampleRate: Double = 16_000",
    "monoFloatSamples",
    "appendPCM16"
  ]) {
    assertIncludes(captureService, needle, "app live subtitle system audio capture");
  }

  for (const needle of [
    "isPassiveAppLiveSubtitleStopReason",
    "\"navigation\"",
    "\"tab_removed\"",
    "\"capture_stopped\"",
    "\"track_ended\"",
    "continuousFinalIntervalMilliseconds",
    "shouldFinalizeDuringContinuousSpeech"
  ]) {
    assertIncludes(appState, needle, "app live subtitle session state handling");
  }
  for (const needle of [
    "stopLiveSubtitles(tabID, \"navigation\")",
    "stopLiveSubtitles(tabID, \"tab_removed\")"
  ]) {
    assert(!background.includes(needle), `background must not stop app live subtitles from passive lifecycle event ${needle}`);
  }
  assertIncludes(
    appDelegate,
    "closeLiveSubtitlesFromWindow",
    "live subtitle floating window close stops capture"
  );
  assertIncludes(
    appDelegate,
    "window.orderOut(nil)",
    "live subtitle floating window hides after stop"
  );

  for (const needle of [
    "LanguagePair",
    "TranslationEngineID",
    "languageID",
    "speakerDiarization",
    "fastTranslation",
    "LanguageRoutingPreferences",
    "SpeakerDiarizationPreferences",
    "FastTranslationPreferences"
  ]) {
    assertIncludes(modelTypes, needle, "Phase 4.x foundation model types");
  }
  for (const needle of [
    "LanguageCodeNormalizer",
    "normalizedBCP47",
    "nllbCode",
    "argosCode",
    "LLMTOOLS_LID_FIXTURE_JSON",
    "LLMTOOLS_FAST_MT_FIXTURE_JSON",
    "LLMTOOLS_DIARIZATION_FIXTURE_JSON"
  ]) {
    assertIncludes(languageNormalizer, needle, "Phase 4.x language normalization and fixture names");
  }
  for (const needle of [
    "funASRCommandTemplate",
    "senseVoiceCommandTemplate",
	    "qwen3ASRCommandTemplate",
	    "whisperCommandTemplate",
	    "genericASRCommandTemplate",
    "sourceLanguageHint",
    "sourceLanguageDetectorModel",
    "speakerID",
    "speakerLabel",
    "speakerConfidence",
    "speakerCount",
				    "diarizationModelID",
				    "diarizationErrorCode",
				    "diarizationErrorMessage",
    "SubtitleExportOptions",
    "translationEngineID",
    "liveAudioSource",
    "liveWindowOpacity",
    "liveTextColorHex",
	    "ASRRuntimeSource",
	    "funASRTorchStreaming",
	    "funASRCompositePipeline",
    "commandTemplate(for family"
  ]) {
    assertIncludes(mediaTypes, needle, "media subtitle preferences");
  }
  for (const needle of [
    "preferences.commandTemplate(for: family)",
    "{language}",
    "{mode}",
    "{isFinal}",
    "LLMTOOLS_FUN_ASR_COMMAND",
    "LLMTOOLS_SENSEVOICE_COMMAND",
	    "LLMTOOLS_QWEN3_ASR_COMMAND",
	    "LLMTOOLS_WHISPER_CPP_COMMAND",
	    "LLMTOOLS_ASR_COMMAND",
		    "funASRGGUFCommandTemplate",
		    "funASRGGUFAuto",
		    "funASRCompositeCommandTemplate",
		    "llmtools-funasr-pipeline.py",
			    "whisperCppCoreMLCommandTemplate",
			    "mlxAudioCommandTemplate",
	    "mlxAudioRunner",
			    "StreamingASRProcessSession",
			    "PersistentProcessLifecycle",
			    "funASRTorchStreaming",
		    "llmtools-streaming-asr-sidecar.py",
	    "model.onnx",
    "tokens.txt",
    "runtimeSource"
	  ]) {
	    assertIncludes(mediaServices, needle, "local ASR command resolution");
	  }
	  for (const needle of [
	    "try? inputHandle.close()",
	    "process.terminate()",
	    "Darwin.kill(process.processIdentifier, SIGKILL)"
	  ]) {
	    assertIncludes(processLifecycle, needle, "persistent sidecar lifecycle");
	  }
	  for (const needle of ["languageDetectionService.stop()", "fastTranslationService.stop()"]) {
	    assertIncludes(taskEngine, needle, "global model unload");
	  }
  for (const needle of [
    "Local ASR runtime",
    "Runtime source",
    "Repair Runtime",
	    "安装 FunASR Nano + CAM++",
    "funASRCommandTemplate",
    "senseVoiceCommandTemplate",
	    "qwen3ASRCommandTemplate",
	    "whisperCommandTemplate",
	    "genericASRCommandTemplate",
    "Audio source",
    "Source language",
    "Window opacity",
    "Subtitle text color",
    "ColorPicker",
    "Clear subtitle history",
    "LiveSubtitleFloatingView",
    "Use {model}, {audio}, {language}, {mode}, and {isFinal}"
  ]) {
    assertIncludes(settingsView, needle, "media subtitle settings UI");
  }
  for (const needle of [
	    "Phase 4 local ASR runtime check",
		    "sherpa-onnx-offline",
	    "whisperCppCoreMLRunner",
	    "model.safetensors",
    "No remote ASR fallback",
	    "llama-funasr-cli",
	    "funASRGGUFAuto",
	    "funASRCompositePipeline",
	    "install-phase4-funasr-pipeline-runtime.sh",
	    "Fun-ASR-MLT-Nano",
		    "mlxAudioRunner",
		    "LLMTOOLS_FUN_ASR_VENV",
		    "LLMTOOLS_FUN_ASR_NANO_VENV",
		    "LLMTOOLS_SENSEVOICE_ASR_VENV",
		    "install-phase4-funasr-mlx-runtime.sh",
		    "install-phase4-funasr-nano-mlx-runtime.sh",
			    "install-phase4-sensevoice-mlx-runtime.sh",
				    "install-phase4-whisper-coreml-runtime.sh",
			    "--repair",
	    "repairRegistry",
	    "Qwen3-ASR-0.6B"
	  ]) {
    assertIncludes(localASRRuntimeCheck, needle, "local ASR runtime diagnostic script");
  }
				  const mlxRunner = await read("scripts/llmtools-mlx-asr-runner.sh");
				  const streamingASRSidecar = await read("scripts/llmtools-streaming-asr-sidecar.py");
				  const whisperCoreMLRunner = await read("scripts/llmtools-whisper-coreml-runner.sh");
				  const mlxInstaller = await read("scripts/install-phase4-mlx-asr-runtime.sh");
			  const funASRMLXInstaller = await read("scripts/install-phase4-funasr-mlx-runtime.sh");
			  const funASRNanoMLXInstaller = await read("scripts/install-phase4-funasr-nano-mlx-runtime.sh");
			  const funASRPipeline = await read("scripts/llmtools-funasr-pipeline.py");
			  const funASRPipelineInstaller = await read("scripts/install-phase4-funasr-pipeline-runtime.sh");
			  const senseVoiceMLXInstaller = await read("scripts/install-phase4-sensevoice-mlx-runtime.sh");
			  const whisperCoreMLInstaller = await read("scripts/install-phase4-whisper-coreml-runtime.sh");
			  for (const needle of [
		    "mlx_audio.stt.generate",
	    "format=\"json\"",
	    "format=\"txt\"",
	    "--format",
		    "--language",
		    "LLMTOOLS_ASR_VENV",
		    "LLMTOOLS_FUN_ASR_VENV",
		    "LLMTOOLS_FUN_ASR_NANO_VENV",
		    "LLMTOOLS_SENSEVOICE_ASR_VENV",
		    "funasr-venv"
	  ]) {
		    assertIncludes(mlxRunner, needle, "llmTools mlx-audio ASR runner");
		  }
			  for (const needle of [
			    "load_model",
			    "whisperCppCoreML",
			    "whisper-server",
			    "stream=True",
			    "stream_generate",
			    "senseVoiceSmall",
			    "pcm16Base64",
			    "\"backend\": self.backend",
				    "\"type\": \"ready\"",
				    "signal.signal(signal.SIGTERM, terminate_from_signal)",
				    "\"mode\": \"streaming-window\""
			  ]) {
		    assertIncludes(streamingASRSidecar, needle, "llmTools streaming ASR sidecar");
		  }
	  for (const needle of [
	    "uv venv",
	    "mlx-audio==0.4.0",
	    "--prerelease allow",
	    "LLMTOOLS_ASR_VENV"
	  ]) {
	    assertIncludes(mlxInstaller, needle, "llmTools mlx-audio ASR installer");
	  }
	  for (const needle of [
	    "uv venv",
	    "mlx-audio-plus",
	    "LLMTOOLS_FUN_ASR_VENV",
	    "funasr-venv"
	  ]) {
		    assertIncludes(funASRMLXInstaller, needle, "llmTools Fun-ASR mlx-audio-plus installer");
		  }
		  for (const needle of [
		    "uv venv",
		    "mlx-audio==0.4.4",
		    "LLMTOOLS_FUN_ASR_NANO_VENV",
		    "funasr-nano-venv",
		    "avoid eager optional model imports"
		  ]) {
		    assertIncludes(funASRNanoMLXInstaller, needle, "llmTools Fun-ASR-Nano mlx-audio installer");
		  }
		  for (const needle of [
		    "FunASRNano",
		    "funasr-torch",
		    "prev_text",
		    "LLMTOOLS_FUNASR_DEVICE",
		    "回滚末尾 5 个 token",
		    "MODELSCOPE_OFFLINE",
		    "device",
		    "streaming-window"
		  ]) {
		    assertIncludes(streamingASRSidecar, needle, "llmTools official FunASR streaming sidecar");
		  }
		  for (const needle of [
		    "AutoModel",
		    "fsmn-vad",
		    "campp",
		    "ct-punc",
		    "sentence_info",
		    "speakerID",
		    "HF_HUB_OFFLINE",
		    "llmtools.asr/v1"
		  ]) {
		    assertIncludes(funASRPipeline, needle, "llmTools official FunASR composite sidecar");
		  }
		  for (const needle of [
		    "funasr==",
		    "modelscope==",
		    "torch==",
		    "runtime-manifest.json",
		    "campplus_cn_common.bin",
		    "LLMTOOLS_FUNASR_PIPELINE_ROOT"
		  ]) {
		    assertIncludes(funASRPipelineInstaller, needle, "llmTools official FunASR composite installer");
		  }
		  for (const needle of [
		    "uv venv",
		    "mlx-audio==0.4.4",
		    "LLMTOOLS_SENSEVOICE_ASR_VENV",
		    "sensevoice-venv",
		    "avoid eager optional model imports"
		  ]) {
			    assertIncludes(senseVoiceMLXInstaller, needle, "llmTools SenseVoice mlx-audio installer");
			  }
			  for (const needle of [
			    "whisper-cli",
			    "Core ML encoder",
			    "ggml-*.bin",
			    "LLMTOOLS_WHISPER_CPP_ROOT",
			    "\"segments\""
			  ]) {
			    assertIncludes(whisperCoreMLRunner, needle, "llmTools whisper.cpp CoreML runner");
			  }
			  for (const needle of [
			    "WHISPER_COREML=1",
			    "generate-coreml-model.sh",
			    "download-ggml-model.sh",
			    "LLMTOOLS_WHISPER_CPP_ROOT",
			    "whisper-cli"
			  ]) {
			    assertIncludes(whisperCoreMLInstaller, needle, "llmTools whisper.cpp CoreML installer");
			  }

		  const packageScript = await read("scripts/package-app.sh");
	  const packageManifest = await read("Package.swift");
		  assertIncludes(packageScript, "browser-extension", "packaged app resources");
				  assertIncludes(packageScript, "llmtools-mlx-asr-runner.sh", "packaged app ASR resources");
				  assertIncludes(packageScript, "llmtools-streaming-asr-sidecar.py", "packaged app streaming ASR resources");
				  assertIncludes(packageScript, "llmtools-funasr-pipeline.py", "packaged app official FunASR resources");
				  assertIncludes(packageScript, "llmtools-lid-sidecar.py", "packaged app LID resources");
				  assertIncludes(packageScript, "llmtools-fastmt-sidecar.py", "packaged app fast MT resources");
				  assertIncludes(packageScript, "llmtools-pyannote-diarization-sidecar.py", "packaged app diarization resources");
				  assertIncludes(packageScript, "llmtools-whisper-coreml-runner.sh", "packaged app whisper CoreML ASR resources");
			  assertIncludes(packageScript, "install-phase4-mlx-asr-runtime.sh", "packaged app ASR installer resources");
			  assertIncludes(packageScript, "install-phase4-funasr-mlx-runtime.sh", "packaged app Fun-ASR ASR installer resources");
				  assertIncludes(packageScript, "install-phase4-funasr-nano-mlx-runtime.sh", "packaged app Fun-ASR-Nano ASR installer resources");
				  assertIncludes(packageScript, "install-phase4-funasr-pipeline-runtime.sh", "packaged app official FunASR installer resources");
				  assertIncludes(packageScript, "install-phase4-sensevoice-mlx-runtime.sh", "packaged app SenseVoice ASR installer resources");
				  assertIncludes(packageScript, "install-phase4-whisper-coreml-runtime.sh", "packaged app whisper CoreML ASR installer resources");
				  assertIncludes(packageScript, "install-phase4x-fasttext-lid.sh", "packaged app LID installer resources");
				  assertIncludes(packageScript, "install-phase4x-ctranslate2-en-zh.sh", "packaged app CTranslate2 fast MT installer resources");
				  assertIncludes(packageScript, "install-phase4x-nllb-200-distilled-600m.sh", "packaged app NLLB fast MT installer resources");
				  assertIncludes(packageScript, "install-phase4x-argos.sh", "packaged app Argos fast MT installer resources");
				  assertIncludes(packageScript, "install-phase4x-pyannote-diarization.sh", "packaged app diarization installer resources");
				  assertExcludes(packageScript, ["llmtools-vibevoice-asr-runner.py", "install-phase4-vibevoice-asr-runtime.sh"], "packaged app ASR resources");
	  assertIncludes(packageScript, "chmod +x", "packaged app ASR script executability");
  assertIncludes(packageManifest, "LLMToolsMediaSmoke", "Phase 4 media smoke executable");

  console.log("Phase 4 media subtitle checks passed");
}

run().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
