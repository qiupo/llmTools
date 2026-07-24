#!/usr/bin/env node

import { accessSync, chmodSync, constants, copyFileSync, existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

function parseArgs(argv) {
  const args = {
    registry: path.join(os.homedir(), "Library", "Application Support", "llmTools", "model-registry.json"),
    repair: false,
    strict: false
  };
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--registry") {
      args.registry = argv[index + 1];
      index += 1;
    } else if (value === "--strict") {
      args.strict = true;
    } else if (value === "--repair") {
      args.repair = true;
    } else if (value === "--help" || value === "-h") {
      printHelp();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${value}`);
    }
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node scripts/check-phase4-local-asr-runtime.mjs [--registry path] [--repair] [--strict]

Checks the local Phase 4 ASR runtime setup.

The script verifies:
- registered speech-capable models and their local files
- Media Subtitle command templates
- llmTools ASR environment variables
- official FunASR Nano + VAD + CAM++ + punctuation compatibility
- automatic Fun-ASR GGUF compatibility
- automatic Fun-ASR MLT mlx-audio-plus compatibility
- automatic sherpa-onnx SenseVoice compatibility
- automatic whisper.cpp CoreML compatibility
- automatic VibeVoice-ASR MLX runtime compatibility
- automatic Nemotron Streaming Core ML compatibility
- macOS media conversion tools needed by file intake

Use --repair to install or reuse the matching isolated local ASR runtime. Managed
absolute command templates left by older builds are removed from the registry.
Use --strict to exit non-zero when a selected realtime/file ASR model is not runnable.`);
}

function loadJSON(filePath) {
  return JSON.parse(readFileSync(filePath, "utf8"));
}

function repoRoot() {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
}

function asrRuntimeRoot() {
  return nonEmpty(process.env.LLMTOOLS_ASR_RUNTIME_ROOT)
    || path.join(os.homedir(), "Library", "Application Support", "llmTools", "asr-runtime");
}

function funASRPipelineRoot() {
  return nonEmpty(process.env.LLMTOOLS_FUNASR_PIPELINE_ROOT)
    || path.join(asrRuntimeRoot(), "funasr-pipeline");
}

function sourcePathToFilePath(sourcePath) {
  if (!sourcePath) {
    return "";
  }
  if (sourcePath.startsWith("file://")) {
    return fileURLToPath(sourcePath);
  }
  return sourcePath;
}

function commandFromSettings(preferences, family) {
  const media = preferences?.mediaSubtitles ?? {};
  const familyCommand =
    family === "funASRNano" || family === "funASRMLTNano"
      ? media.funASRCommandTemplate
      : family === "senseVoiceSmall"
      ? media.senseVoiceCommandTemplate
      : family === "qwen3ASR06B"
        ? media.qwen3ASRCommandTemplate
        : family === "vibeVoiceASR"
        ? media.vibeVoiceASRCommandTemplate
        : family === "whisperCppCoreML"
        ? media.whisperCommandTemplate
        : "";
  const command = nonEmpty(familyCommand) || nonEmpty(media.genericASRCommandTemplate);
  return command ? { source: "settingsCommand", command } : null;
}

function commandFromEnv(family) {
  const familyCommand =
    family === "funASRNano" || family === "funASRMLTNano"
      ? process.env.LLMTOOLS_FUN_ASR_COMMAND
      : family === "senseVoiceSmall"
      ? process.env.LLMTOOLS_SENSEVOICE_COMMAND
      : family === "qwen3ASR06B"
        ? process.env.LLMTOOLS_QWEN3_ASR_COMMAND
        : family === "vibeVoiceASR"
        ? process.env.LLMTOOLS_VIBEVOICE_ASR_COMMAND
        : family === "whisperCppCoreML"
        ? process.env.LLMTOOLS_WHISPER_CPP_COMMAND
        : "";
  const command = nonEmpty(familyCommand) || nonEmpty(process.env.LLMTOOLS_ASR_COMMAND);
  return command ? { source: "environmentCommand", command } : null;
}

function nonEmpty(value) {
  const trimmed = String(value ?? "").trim();
  return trimmed.length > 0 ? trimmed : null;
}

function executableInPATH(name) {
  const paths = (process.env.PATH || defaultPATH()).split(":");
  for (const entry of paths) {
    const candidate = path.join(entry, name);
    try {
      accessSyncExecutable(candidate);
      return candidate;
    } catch {
      // Keep scanning PATH.
    }
  }
  return null;
}

function defaultPATH() {
  return "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
}

function accessSyncExecutable(filePath) {
  accessSync(filePath, constants.X_OK);
}

function modelFiles(modelPath) {
  const names = [
    "config.json",
    "config.yaml",
    "model.safetensors",
    "model.safetensors.index.json",
    "model.pt",
    "model.onnx",
    "tokens.txt",
    "conv_frontend.onnx",
    "encoder.int8.onnx",
    "decoder.int8.onnx",
    "encoder.onnx",
    "encoder.onnx.data",
    "decoder.onnx",
    "decoder.onnx.data",
    "tokenizer/vocab.json",
    "tokenizer/merges.txt",
    "tokenizer/tokenizer_config.json",
    "am.mvn",
    "preprocessor_config.json",
    "funasr-encoder-f16.gguf",
    "funasr-encoder-q8_0.gguf",
    "funasr-encoder.gguf",
    "qwen3-0.6b-q8_0.gguf",
    "qwen3-0.6b-q4km.gguf",
    "qwen3-0.6b-f16.gguf",
    "fsmn-vad.gguf",
    "metadata.json",
    "tokenizer.json",
    "encoder.mlmodelc",
    "decoder_joint.mlmodelc",
    "decoder.mlmodelc",
    "joint.mlmodelc"
  ];
  const files = {};
  for (const name of names) {
    files[name] = existsSync(path.join(modelPath, name));
  }
  for (const name of readdirOrNull(modelPath) ?? []) {
    if (name.endsWith(".safetensors")) {
      files[name] = true;
    }
  }
  return files;
}

function safetensorsModelFilesExist(modelPath, files = {}) {
  if (!modelPath) {
    return false;
  }
  if (files["model.safetensors"] || files["model.safetensors.index.json"]) {
    return true;
  }
  return Object.entries(files).some(([name, exists]) => exists && name.endsWith(".safetensors"));
}

function nemotronStreamingCoreMLReady(modelPath, files = {}) {
  if (!modelPath) {
    return false;
  }
  const hasVariantAssets = (candidate, candidateFiles = modelFiles(candidate)) =>
    candidateFiles["metadata.json"]
      && candidateFiles["tokenizer.json"]
      && candidateFiles["encoder.mlmodelc"]
      && (candidateFiles["decoder_joint.mlmodelc"] || (candidateFiles["decoder.mlmodelc"] && candidateFiles["joint.mlmodelc"]));

  if (hasVariantAssets(modelPath, files)) {
    return true;
  }

  // 注册表旧版本可能保存 Core ML 仓库根目录，新版本保存具体延迟变体目录。
  const multilingualRoot = path.join(modelPath, "multilingual");
  const variants = readdirOrNull(multilingualRoot) ?? [];
  return variants.some((variant) => hasVariantAssets(path.join(multilingualRoot, variant)));
}

function configModelType(modelPath) {
  const configPath = path.join(modelPath, "config.json");
  if (!existsSync(configPath)) {
    return null;
  }
  try {
    const config = loadJSON(configPath);
    return config.model_type ?? null;
  } catch {
    return null;
  }
}

function resolveRuntime(model, preferences) {
  const speech = model.capabilities?.speech;
  const family = speech?.family;
  const modelPath = sourcePathToFilePath(model.resolvedPath || model.sourcePath);
  const files = modelPath ? modelFiles(modelPath) : {};

  if (family === "qwen3ASRSherpaOnnx") {
    return {
      ready: false,
      source: "unavailable",
      reason: "sherpa-onnx Qwen3-ASR has been removed from llmTools because MLX Qwen3-ASR is faster on Apple Silicon."
    };
  }

  if (nonEmpty(process.env.LLMTOOLS_ASR_FIXTURE_JSON) && existsSync(process.env.LLMTOOLS_ASR_FIXTURE_JSON)) {
    return {
      ready: true,
      source: "fixtureTranscript",
      reason: "LLMTOOLS_ASR_FIXTURE_JSON points to an existing transcript fixture."
    };
  }

  if (family === "nemotron35ASRStreaming06B") {
    if (nemotronStreamingCoreMLReady(modelPath, files)) {
      return {
        ready: true,
        source: "fluidAudioNemotronCoreML",
        reason: "FluidAudio can use the registered Nemotron Streaming Core ML assets directly."
      };
    }
    return {
      ready: false,
      source: "unavailable",
      reason: "Nemotron Streaming requires metadata.json, tokenizer.json, encoder.mlmodelc, and either decoder_joint.mlmodelc or decoder.mlmodelc plus joint.mlmodelc in a local Core ML variant directory."
    };
  }

  const settings = commandFromSettings(preferences, family);
  if (settings) {
    return {
      ready: true,
      source: settings.source,
      reason: "A Media Subtitle command template is configured."
    };
  }

  const env = commandFromEnv(family);
  if (env) {
    return {
      ready: true,
      source: env.source,
      reason: "A llmTools ASR environment variable is configured."
    };
  }

  if (family === "funASRNano" && isOfficialFunASRNanoModel(modelPath, files)) {
    const pipeline = funASRCompositeRuntime(modelPath);
    if (pipeline.ready) {
      return {
        ready: true,
        source: "funASRCompositePipeline",
        reason: `Official FunASR Torch/MPS realtime and offline Nano + CAM++ pipelines are ready at ${pipeline.root}.`
      };
    }
    return {
      ready: false,
      source: "unavailable",
      reason: `Official FunASR Nano model.pt needs the isolated Torch/MPS + VAD + CAM++ runtime. ${pipeline.reason}`
    };
  }

  if ((family === "funASRNano" || family === "funASRMLTNano") && funASRGGUFReady(modelPath, files)) {
    return {
      ready: true,
      source: "funASRGGUFAuto",
      reason: "llama-funasr-cli plus Fun-ASR encoder and Qwen3 decoder GGUF files are available."
    };
  }

  if (family === "whisperCppCoreML" && whisperCppModelReady(modelPath)) {
    const whisper = whisperCppRuntime(modelPath);
    if (whisper.ready) {
      return {
        ready: true,
        source: "whisperCppCoreMLRunner",
        reason: `Bundled whisper.cpp CoreML runner is available with ${whisper.root}.`
      };
    }
    return {
      ready: false,
      source: "unavailable",
      reason: "whisper.cpp CoreML model files are present, but whisper-cli or the runner is missing. Use scripts/install-phase4-whisper-coreml-runtime.sh."
    };
  }

  const mlxAudio = mlxAudioRuntime(family);
  if (
    mlxAudio.ready &&
    safetensorsModelFilesExist(modelPath, files) &&
    supportsMLXASRRepair(family)
  ) {
    const tokenizer = family === "vibeVoiceASR" ? vibeVoiceTokenizerRuntime(modelPath) : { ready: true, path: null };
    if (!tokenizer.ready) {
      return {
        ready: false,
        source: "unavailable",
        reason: "VibeVoice-ASR MLX weights require a local Qwen2.5 tokenizer sidecar. Run --repair, Settings > Media Subtitle > Repair runtime, or set LLMTOOLS_VIBEVOICE_TOKENIZER_DIR."
      };
    }
    return {
      ready: true,
      source: "mlxAudioRunner",
      reason: tokenizer.path
        ? `Bundled llmTools mlx-audio runner is available with ${mlxAudio.venv}; VibeVoice tokenizer: ${tokenizer.path}.`
        : `Bundled llmTools mlx-audio runner is available with ${mlxAudio.venv}.`
    };
  }

  if (family === "vibeVoiceASR") {
    return {
      ready: false,
      source: "unavailable",
      reason: "VibeVoice-ASR is file-only in llmTools. The registered mlx-community model needs the shared MLX ASR runtime and local Qwen2.5 tokenizer. Original PyTorch runtimes remain available only through an explicit custom command."
    };
  }

  if (family === "funASRNano" || family === "funASRMLTNano") {
    return {
      ready: false,
      source: "unavailable",
      reason: `${family === "funASRMLTNano" ? "Fun-ASR-MLT-Nano" : "Fun-ASR-Nano"} needs a configured local command, the matching bundled MLX runner for safetensors/MLX weights, llama-funasr-cli with compatible GGUF files, or the isolated official Nano Torch runtime. The official Nano demo selects Apple MPS when available.`
    };
  }

  if (family === "senseVoiceSmall") {
    const sherpa = executableInPATH("sherpa-onnx-offline");
    if (files["model.onnx"] && files["tokens.txt"] && sherpa) {
      return {
        ready: true,
        source: "sherpaOnnxAuto",
        reason: "model.onnx, tokens.txt, and sherpa-onnx-offline are available."
      };
    }
    const missing = [];
    if (!files["model.onnx"]) missing.push("model.onnx");
    if (!files["tokens.txt"]) missing.push("tokens.txt");
    if (!sherpa) missing.push("sherpa-onnx-offline");
    return {
      ready: false,
      source: "unavailable",
      reason: `SenseVoice automatic runtime is missing ${missing.join(", ")} and no compatible SenseVoice MLX venv was found. Use --repair or configure a local command template for this model directory.`
    };
  }

  if (family === "qwen3ASR06B") {
    return {
      ready: false,
      source: "unavailable",
      reason: "Qwen3-ASR-0.6B can be used for file transcription and experimental realtime subtitles, but official streaming requires a local vLLM backend or another configured local command template."
    };
  }

  if (family === "qwen3ASRSherpaOnnx") {
    return {
      ready: false,
      source: "unavailable",
      reason: "sherpa-onnx Qwen3-ASR has been removed from llmTools because MLX Qwen3-ASR is faster on Apple Silicon."
    };
  }

  if (family === "whisperCppCoreML") {
    return {
      ready: false,
      source: "unavailable",
      reason: "whisper.cpp CoreML requires a ggml-*.bin model, an adjacent *-encoder.mlmodelc directory, whisper-cli built with WHISPER_COREML=1, and the bundled whisper runner."
    };
  }

  return {
    ready: false,
    source: "unavailable",
    reason: "Configure a local ASR command template for this speech model."
  };
}

function printToolStatus() {
  const tools = ["afconvert", "avconvert", "ffmpeg", "llama-funasr-cli", "sherpa-onnx-offline", "whisper-cli"];
  console.log("Tooling:");
  for (const tool of tools) {
    const found = executableInPATH(tool);
    console.log(`- ${tool}: ${found ? found : "missing"}`);
  }
  const mlxAudio = mlxAudioRuntime("qwen3ASR06B");
  const funASRMLX = mlxAudioRuntime("funASRMLTNano");
  const funASRNanoMLX = mlxAudioRuntime("funASRNano");
  const senseVoiceMLX = mlxAudioRuntime("senseVoiceSmall");
  const whisper = whisperCppRuntime("");
  const vibeVoiceMLX = mlxAudioRuntime("vibeVoiceASR");
  const vibeVoiceTokenizer = vibeVoiceTokenizerRuntime();
  const funASRComposite = funASRCompositeRuntime();
  console.log(`- llmTools mlx-audio runner: ${mlxAudio.runner || funASRMLX.runner || funASRNanoMLX.runner || senseVoiceMLX.runner || "missing"}`);
  console.log(`- mlx-audio venv: ${mlxAudio.venv || "missing"}`);
  console.log(`- Fun-ASR mlx-audio-plus venv: ${funASRMLX.venv || "missing"}`);
  console.log(`- Fun-ASR-Nano mlx-audio venv: ${funASRNanoMLX.venv || "missing"}`);
  console.log(`- FunASR Nano + CAM++ pipeline: ${funASRComposite.ready ? funASRComposite.root : `missing (${funASRComposite.reason})`}`);
  console.log(`- SenseVoice mlx-audio venv: ${senseVoiceMLX.venv || "missing"}`);
  console.log(`- whisper.cpp CoreML runner: ${whisper.runner || "missing"}`);
  console.log(`- whisper.cpp CoreML root: ${whisper.root || "missing"}`);
  console.log(`- VibeVoice-ASR MLX venv: ${vibeVoiceMLX.venv || "missing"}`);
  console.log(`- VibeVoice-ASR MLX tokenizer: ${vibeVoiceTokenizer.path || "missing"}`);
  console.log("- Apple MPS: official Nano Torch demo selects MPS when available; llmTools verifies it through the persistent sidecar");
}

function funASRGGUFReady(modelPath, files) {
  if (!modelPath || !executableInPATH("llama-funasr-cli")) {
    return false;
  }
  const hasEncoder = files["funasr-encoder-f16.gguf"] || files["funasr-encoder-q8_0.gguf"] || files["funasr-encoder.gguf"];
  const hasDecoder = files["qwen3-0.6b-q8_0.gguf"] || files["qwen3-0.6b-q4km.gguf"] || files["qwen3-0.6b-f16.gguf"];
  return Boolean(hasEncoder && hasDecoder);
}

function whisperCppRuntime(modelPath) {
  const root = repoRoot();
  const runnerCandidates = [
    path.join(root, "dist", "llmTools.app", "Contents", "Resources", "asr", "llmtools-whisper-coreml-runner.sh"),
    path.join(root, "scripts", "llmtools-whisper-coreml-runner.sh")
  ];
  const runtimeCandidates = [
    process.env.LLMTOOLS_WHISPER_CPP_ROOT,
    path.join(asrRuntimeRoot(), "whisper-cpp")
  ].filter(Boolean);
  const runner = runnerCandidates.find((candidate) => {
    try {
      accessSyncExecutable(candidate);
      return true;
    } catch {
      return false;
    }
  });
  const runtimeRoot = runtimeCandidates.find((candidate) => {
    const cliCandidates = [
      path.join(candidate, "bin", "whisper-cli"),
      path.join(candidate, "whisper.cpp", "build", "bin", "whisper-cli")
    ];
    return cliCandidates.some((cli) => {
      try {
        accessSyncExecutable(cli);
        return true;
      } catch {
        return false;
      }
    });
  });
  return {
    ready: Boolean(runner && runtimeRoot && (!modelPath || whisperCppModelReady(modelPath))),
    runner,
    root: runtimeRoot
  };
}

function whisperCppModelReady(modelPath) {
  const modelBin = whisperCppModelBin(modelPath);
  if (!modelBin) {
    return false;
  }
  const parsed = path.parse(modelBin);
  return existsSync(path.join(parsed.dir, `${parsed.name}-encoder.mlmodelc`));
}

function whisperCppModelBin(modelPath) {
  if (!modelPath || !existsSync(modelPath)) {
    return null;
  }
  const stat = readdirOrNull(modelPath);
  if (!stat) {
    return path.basename(modelPath).startsWith("ggml-") && modelPath.endsWith(".bin") ? modelPath : null;
  }
  return stat
    .filter((name) => name.startsWith("ggml-") && name.endsWith(".bin"))
    .sort((lhs, rhs) => lhs.localeCompare(rhs, undefined, { numeric: true }))
    .map((name) => path.join(modelPath, name))[0] ?? null;
}

function pythonModuleExists(venv, moduleName) {
  const libDir = path.join(venv, "lib");
  if (!existsSync(libDir)) {
    return false;
  }
  for (const entry of readdirSync(libDir)) {
    if (!entry.startsWith("python")) {
      continue;
    }
    if (existsSync(path.join(libDir, entry, "site-packages", moduleName))) {
      return true;
    }
  }
  return false;
}

function isOfficialFunASRNanoModel(modelPath, files = {}) {
  return Boolean(modelPath && files["model.pt"] && files["config.yaml"]);
}

function funASRCompositeRuntime(modelPath = null) {
  const root = funASRPipelineRoot();
  const runnerCandidates = [
    path.join(repoRoot(), "dist", "llmTools.app", "Contents", "Resources", "asr", "llmtools-funasr-pipeline.py"),
    path.join(repoRoot(), "scripts", "llmtools-funasr-pipeline.py")
  ];
  const runner = runnerCandidates.find((candidate) => {
    try {
      accessSyncExecutable(candidate);
      return true;
    } catch {
      return false;
    }
  }) ?? null;
  const venv = path.join(root, "venv");
  const python = path.join(venv, "bin", "python");
  const models = path.join(root, "models");
  const nano = modelPath || path.join(models, "funasr-nano");
  const requiredModels = [
    { directory: nano, checkpoint: "model.pt" },
    { directory: path.join(models, "fsmn-vad"), checkpoint: "model.pt" },
    { directory: path.join(models, "campp"), checkpoint: "campplus_cn_common.bin" },
    { directory: path.join(models, "ct-punc"), checkpoint: "model.pt" }
  ];
  const missing = [];
  if (!runner) missing.push("pipeline runner");
  try {
    accessSyncExecutable(python);
  } catch {
    missing.push("pipeline python");
  }
  if (!pythonModuleExists(venv, "funasr")) missing.push("funasr module");
  for (const model of requiredModels) {
    if (!existsSync(path.join(model.directory, "config.yaml")) || !existsSync(path.join(model.directory, model.checkpoint))) {
      missing.push(path.basename(model.directory));
    }
  }
  return {
    ready: missing.length === 0,
    root,
    runner,
    venv,
    reason: missing.length === 0 ? "all local components are present" : `missing ${missing.join(", ")}`
  };
}

function readdirOrNull(modelPath) {
  try {
    return readdirSync(modelPath);
  } catch {
    return null;
  }
}

function mlxAudioRuntime(family = "qwen3ASR06B") {
  const root = repoRoot();
  const runnerCandidates = [
    path.join(root, "dist", "llmTools.app", "Contents", "Resources", "asr", "llmtools-mlx-asr-runner.sh"),
    path.join(root, "scripts", "llmtools-mlx-asr-runner.sh")
  ];
  const venvDirName = mlxAudioVenvDirectoryName(family);
  const envKey = mlxAudioVenvEnvironmentName(family);
  const venvCandidates = [
    process.env[envKey],
    path.join(asrRuntimeRoot(), venvDirName)
  ].filter(Boolean);
  const runner = runnerCandidates.find((candidate) => {
    try {
      accessSyncExecutable(candidate);
      return true;
    } catch {
      return false;
    }
  });
  const venv = venvCandidates.find((candidate) => {
    try {
      accessSyncExecutable(path.join(candidate, "bin", "mlx_audio.stt.generate"));
      return mlxAudioModelModuleExists(candidate, family);
    } catch {
      return false;
    }
  });
  return {
    ready: Boolean(runner && venv),
    runner,
    venv
  };
}

function vibeVoiceTokenizerRuntime(modelPath = null) {
  const candidates = [
    modelPath,
    process.env.LLMTOOLS_VIBEVOICE_TOKENIZER_DIR,
    path.join(asrRuntimeRoot(), "qwen2.5-tokenizer"),
    path.join(os.homedir(), "code", "models", "lmstudio-community", "Qwen2.5-0.5B-Instruct-MLX-4bit"),
    path.join(os.homedir(), "code", "models", "mlx-community", "Qwen3-ASR-0.6B-4bit"),
    path.join(os.homedir(), "code", "models", "mlx-community", "Qwen3-ASR-0.6B-bf16"),
    path.join(os.homedir(), "code", "models", "mlx-community", "Qwen3-ASR-1.7B-bf16")
  ].filter(Boolean);
  const tokenizerPath = candidates.find(hasVibeVoiceTokenizerFiles) ?? null;
  return {
    ready: Boolean(tokenizerPath),
    path: tokenizerPath
  };
}

function hasVibeVoiceTokenizerFiles(candidate) {
  return Boolean(candidate)
    && existsSync(path.join(candidate, "tokenizer_config.json"))
    && (existsSync(path.join(candidate, "tokenizer.json")) || existsSync(path.join(candidate, "vocab.json")));
}

function mlxAudioModelModule(family) {
  if (family === "funASRMLTNano") return "funasr";
  if (family === "funASRNano") return "fun_asr_nano";
  if (family === "senseVoiceSmall") return "sensevoice";
  if (family === "qwen3ASR06B") return "qwen3_asr";
  if (family === "vibeVoiceASR") return "vibevoice_asr";
  return null;
}

function mlxAudioModelModuleExists(venv, family) {
  const moduleName = mlxAudioModelModule(family);
  if (!moduleName) {
    return false;
  }
  const libDir = path.join(venv, "lib");
  if (!existsSync(libDir)) {
    return false;
  }
  for (const entry of readdirSync(libDir)) {
    if (!entry.startsWith("python")) {
      continue;
    }
    if (existsSync(path.join(libDir, entry, "site-packages", "mlx_audio", "stt", "models", moduleName))) {
      return true;
    }
  }
  return false;
}

function mlxAudioInstaller(family) {
  const root = repoRoot();
  const scriptName = mlxAudioInstallerScriptName(family);
  const candidates = [
    path.join(root, "dist", "llmTools.app", "Contents", "Resources", "asr", scriptName),
    path.join(root, "scripts", scriptName)
  ];
  return candidates.find((candidate) => {
    try {
      accessSyncExecutable(candidate);
      return true;
    } catch {
      return false;
    }
  }) ?? null;
}

function funASRPipelineInstaller() {
  const scriptName = "install-phase4-funasr-pipeline-runtime.sh";
  const candidates = [
    path.join(repoRoot(), "dist", "llmTools.app", "Contents", "Resources", "asr", scriptName),
    path.join(repoRoot(), "scripts", scriptName)
  ];
  return candidates.find((candidate) => {
    try {
      accessSyncExecutable(candidate);
      return true;
    } catch {
      return false;
    }
  }) ?? null;
}

function supportsMLXASRRepair(family) {
  return family === "funASRNano" || family === "funASRMLTNano" || family === "senseVoiceSmall" || family === "qwen3ASR06B" || family === "vibeVoiceASR";
}

function commandFieldForFamily(family) {
  if (family === "funASRNano" || family === "funASRMLTNano") {
    return "funASRCommandTemplate";
  }
  if (family === "senseVoiceSmall") {
    return "senseVoiceCommandTemplate";
  }
  if (family === "qwen3ASR06B") {
    return "qwen3ASRCommandTemplate";
  }
  if (family === "vibeVoiceASR") {
    return "vibeVoiceASRCommandTemplate";
  }
  if (family === "whisperCppCoreML") {
    return "whisperCommandTemplate";
  }
  return null;
}

function mlxAudioInstallerScriptName(family) {
  if (family === "funASRMLTNano") return "install-phase4-funasr-mlx-runtime.sh";
  if (family === "funASRNano") return "install-phase4-funasr-nano-mlx-runtime.sh";
  if (family === "senseVoiceSmall") return "install-phase4-sensevoice-mlx-runtime.sh";
  return "install-phase4-mlx-asr-runtime.sh";
}

function mlxAudioVenvEnvironmentName(family) {
  if (family === "funASRMLTNano") return "LLMTOOLS_FUN_ASR_VENV";
  if (family === "funASRNano") return "LLMTOOLS_FUN_ASR_NANO_VENV";
  if (family === "senseVoiceSmall") return "LLMTOOLS_SENSEVOICE_ASR_VENV";
  return "LLMTOOLS_ASR_VENV";
}

function mlxAudioVenvDirectoryName(family) {
  if (family === "funASRMLTNano") return "funasr-venv";
  if (family === "funASRNano") return "funasr-nano-venv";
  if (family === "senseVoiceSmall") return "sensevoice-venv";
  return "venv";
}

function runInstaller(installer) {
  const env = {
    ...process.env,
    PATH: `${defaultPATH()}:${process.env.PATH || ""}`
  };
  const result = spawnSync(installer, {
    env,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  });
  if (result.status !== 0) {
    const details = [result.stderr, result.stdout].map((value) => value?.trim()).find(Boolean) || `exit ${result.status}`;
    throw new Error(`ASR runtime install failed: ${details}`);
  }
  if (result.stdout.trim()) {
    console.log(result.stdout.trim());
  }
}

function repairRegistry(registry, registryPath, speechModels) {
  const selectedModelIDs = new Set([
    registry.preferences?.mediaSubtitles?.realtimeASRModelID,
    registry.preferences?.mediaSubtitles?.fileASRModelID
  ].filter(Boolean));
  const candidates = selectedModelIDs.size > 0
    ? speechModels.filter((model) => selectedModelIDs.has(model.id))
    : speechModels;
  const repairable = candidates.filter((model) => {
    const family = model.capabilities?.speech?.family;
    const modelPath = sourcePathToFilePath(model.resolvedPath || model.sourcePath);
    const files = modelPath ? modelFiles(modelPath) : {};
    return (family === "funASRNano" && isOfficialFunASRNanoModel(modelPath, files))
      || (supportsMLXASRRepair(family) && safetensorsModelFilesExist(modelPath, files));
  });
  if (repairable.length === 0) {
    console.log("Repair: no speech model is eligible for automatic ASR runtime repair.");
    return false;
  }

  registry.preferences ??= {};
  registry.preferences.mediaSubtitles ??= {};

  const clearedFields = new Set();
  const repairedModelNames = new Set();
  for (const model of repairable) {
    const family = model.capabilities?.speech?.family;
    const modelPath = sourcePathToFilePath(model.resolvedPath || model.sourcePath);
    const files = modelPath ? modelFiles(modelPath) : {};
    if (family === "funASRNano" && isOfficialFunASRNanoModel(modelPath, files)) {
      let runtime = funASRCompositeRuntime(modelPath);
      if (!runtime.ready) {
        const installer = funASRPipelineInstaller();
        if (!installer) {
          throw new Error("Repair: bundled official FunASR pipeline installer was not found.");
        }
        console.log(`Repair: installing official FunASR pipeline with ${installer}`);
        runInstaller(installer);
        runtime = funASRCompositeRuntime(modelPath);
      }
      if (!runtime.ready) {
        throw new Error(`Repair: official FunASR pipeline is still unavailable after installation: ${runtime.reason}.`);
      }
    } else {
      let runtime = mlxAudioRuntime(family);
      if (!runtime.ready) {
        const installer = mlxAudioInstaller(family);
        if (!installer) {
          throw new Error(`Repair: bundled mlx-audio installer was not found for ${family}.`);
        }
        console.log(`Repair: installing ${family} runtime with ${installer}`);
        runInstaller(installer);
        runtime = mlxAudioRuntime(family);
      }
      if (!runtime.ready) {
        throw new Error(`Repair: mlx-audio runtime is still unavailable for ${family} after installation.`);
      }
    }

    const field = commandFieldForFamily(family);
    const oldCommand = field ? String(registry.preferences.mediaSubtitles[field] ?? "") : "";
    if (field && (oldCommand.includes("llmtools-mlx-asr-runner.sh") || oldCommand.includes("llmtools-vibevoice-asr-runner.py"))) {
      registry.preferences.mediaSubtitles[field] = "";
      clearedFields.add(field);
    }
    markSpeechModelReady(model);
    repairedModelNames.add(model.name);
  }

  if (repairedModelNames.size === 0) {
    console.log("Repair: no runtime was repaired.");
    return false;
  }

  const timestamp = new Date().toISOString().replaceAll(":", "-").replace(/\.\d{3}Z$/, "Z");
  const backupPath = `${registryPath}.bak-${timestamp}`;
  copyFileSync(registryPath, backupPath);
  chmodSync(backupPath, 0o600);
  writeFileSync(registryPath, `${JSON.stringify(registry, null, 2)}\n`);
  chmodSync(registryPath, 0o600);
  if (clearedFields.size > 0) {
    console.log(`Repair: cleared stale managed command templates: ${Array.from(clearedFields).join(", ")}.`);
  }
  console.log(`Repair: verified ${Array.from(repairedModelNames).join(", ")}.`);
  console.log(`Repair: registry backup saved to ${backupPath}.`);
  return true;
}

function markSpeechModelReady(model) {
  const checkedAt = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  model.validationState = "ready";
  model.lastErrorMessage = null;
  model.capabilities ??= {};
  model.capabilities.lastCheckedAt = checkedAt;
  model.capabilities.lastFailureMessage = null;
  if (model.capabilities.speech) {
    model.capabilities.speech.lastCheckedAt = checkedAt;
    model.capabilities.speech.lastFailureMessage = null;
  }
}

async function run() {
  const args = parseArgs(process.argv.slice(2));
  const registry = loadJSON(args.registry);
  const models = Array.isArray(registry.models) ? registry.models : [];
  const speechModels = models.filter((model) => {
    const family = model.capabilities?.speech?.family;
    return Boolean(family && family !== "qwen3ASRSherpaOnnx");
  });

  if (args.repair) {
    console.log("Phase 4 local ASR runtime repair");
    console.log(`Registry: ${args.registry}`);
    repairRegistry(registry, args.registry, speechModels);
    console.log("");
  }

  console.log("Phase 4 local ASR runtime check");
  console.log(`Registry: ${args.registry}`);
  console.log(`Media subtitles: ${registry.preferences?.mediaSubtitles?.isEnabled === false ? "disabled" : "enabled"}`);
  console.log(`Target language: ${registry.preferences?.mediaSubtitles?.defaultTargetLanguage ?? "zh-Hans"}`);
  console.log(`Source language hint: ${registry.preferences?.mediaSubtitles?.sourceLanguageHint ?? "auto"}`);
  console.log("No remote ASR fallback is configured or implied.");
  console.log("");
  printToolStatus();
  console.log("");

  if (speechModels.length === 0) {
    console.log("No speech-capable models are registered.");
    if (args.strict) {
      process.exit(1);
    }
    return;
  }

  let readyCount = 0;
  const runtimeByModelID = new Map();
  for (const model of speechModels) {
    const speech = model.capabilities.speech;
    const modelPath = sourcePathToFilePath(model.resolvedPath || model.sourcePath);
    const files = modelPath && existsSync(modelPath) ? modelFiles(modelPath) : {};
    const runtime = resolveRuntime(model, registry.preferences);
    runtimeByModelID.set(model.id, runtime);
    if (runtime.ready) {
      readyCount += 1;
    }

    console.log(`Model: ${model.name}`);
    console.log(`- id: ${model.id}`);
    console.log(`- family: ${speech.family}`);
    console.log(`- modes: ${(speech.modes ?? []).join(", ") || "unknown"}`);
    console.log(`- path: ${modelPath || "missing"}`);
    console.log(`- path exists: ${modelPath && existsSync(modelPath) ? "yes" : "no"}`);
    console.log(`- config model_type: ${modelPath ? configModelType(modelPath) ?? "unknown" : "unknown"}`);
    console.log(`- files: ${Object.entries(files).filter(([, exists]) => exists).map(([name]) => name).join(", ") || "none"}`);
    console.log(`- runtime ready: ${runtime.ready ? "yes" : "no"}`);
    console.log(`- runtime source: ${runtime.source}`);
    console.log(`- reason: ${runtime.reason}`);
    if (safetensorsModelFilesExist(modelPath, files) && !files["model.onnx"]) {
    console.log("- note: safetensors/MLX ASR weights require the matching bundled MLX runner or another explicit local runtime command.");
    }
    console.log("");
  }

  console.log(`Ready speech runtimes: ${readyCount}/${speechModels.length}`);
  if (args.strict) {
    const selected = [
      { label: "realtime", mode: "realtime", id: registry.preferences?.mediaSubtitles?.realtimeASRModelID },
      { label: "file", mode: "fileOnly", id: registry.preferences?.mediaSubtitles?.fileASRModelID }
    ].filter((item) => item.id);
    const failures = [];
    for (const item of selected) {
      const model = speechModels.find((candidate) => candidate.id === item.id);
      if (!model) {
        failures.push(`${item.label}: selected model is missing or no longer selectable`);
        continue;
      }
      if (!(model.capabilities?.speech?.modes ?? []).includes(item.mode)) {
        failures.push(`${item.label}: ${model.name} does not support ${item.mode}`);
        continue;
      }
      const runtime = runtimeByModelID.get(model.id);
      if (!runtime?.ready) {
        failures.push(`${item.label}: ${model.name} runtime is unavailable (${runtime?.reason || "unknown reason"})`);
      }
    }
    if (selected.length === 0 && readyCount === 0) {
      failures.push("no selected or runnable speech model");
    }
    if (failures.length > 0) {
      console.error(`Strict check failed:\n- ${failures.join("\n- ")}`);
      process.exit(1);
    }
  }
}

run().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
