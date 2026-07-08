#!/usr/bin/env node

import { accessSync, constants, copyFileSync, existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
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
- automatic Fun-ASR GGUF compatibility
- automatic Fun-ASR MLT mlx-audio-plus compatibility
- automatic sherpa-onnx SenseVoice compatibility
- automatic whisper.cpp CoreML compatibility
- macOS media conversion tools needed by file intake

Use --repair to install or reuse the matching isolated local ASR runtime and write the
matching Media Subtitle command template for the currently selected realtime/file
ASR models into the llmTools model registry.
Use --strict to exit non-zero when no registered speech model is runnable.`);
}

function loadJSON(filePath) {
  return JSON.parse(readFileSync(filePath, "utf8"));
}

function repoRoot() {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
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
    "fsmn-vad.gguf"
  ];
  const files = {};
  for (const name of names) {
    files[name] = existsSync(path.join(modelPath, name));
  }
  return files;
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
  const modelPath = sourcePathToFilePath(model.sourcePath);
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
    files["model.safetensors"] &&
    (family === "funASRNano" || family === "funASRMLTNano" || family === "senseVoiceSmall" || family === "qwen3ASR06B")
  ) {
    return {
      ready: true,
      source: "mlxAudioRunner",
      reason: `Bundled llmTools mlx-audio runner is available with ${mlxAudio.venv}.`
    };
  }

  if (family === "funASRNano" || family === "funASRMLTNano") {
    return {
      ready: false,
      source: "unavailable",
      reason: `${family === "funASRMLTNano" ? "Fun-ASR-MLT-Nano" : "Fun-ASR-Nano"} needs a configured local command, the matching bundled MLX runner for safetensors/MLX weights, or llama-funasr-cli with compatible GGUF files. Official Fun-ASR docs describe CUDA/vLLM and CPU/GGUF routes; they do not document Apple MPS as a supported acceleration path.`
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
  console.log(`- llmTools mlx-audio runner: ${mlxAudio.runner || funASRMLX.runner || funASRNanoMLX.runner || senseVoiceMLX.runner || "missing"}`);
  console.log(`- mlx-audio venv: ${mlxAudio.venv || "missing"}`);
  console.log(`- Fun-ASR mlx-audio-plus venv: ${funASRMLX.venv || "missing"}`);
  console.log(`- Fun-ASR-Nano mlx-audio venv: ${funASRNanoMLX.venv || "missing"}`);
  console.log(`- SenseVoice mlx-audio venv: ${senseVoiceMLX.venv || "missing"}`);
  console.log(`- whisper.cpp CoreML runner: ${whisper.runner || "missing"}`);
  console.log(`- whisper.cpp CoreML root: ${whisper.root || "missing"}`);
  console.log("- Apple MPS: not an official Fun-ASR acceleration path in the checked GitHub docs");
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
    path.join(os.homedir(), "Library", "Application Support", "llmTools", "asr-runtime", "whisper-cpp")
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
    path.join(os.homedir(), "Library", "Application Support", "llmTools", "asr-runtime", venvDirName)
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

function mlxAudioModelModule(family) {
  if (family === "funASRMLTNano") return "funasr";
  if (family === "funASRNano") return "fun_asr_nano";
  if (family === "senseVoiceSmall") return "sensevoice";
  if (family === "qwen3ASR06B") return "qwen3_asr";
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

function supportsMLXASRRepair(family) {
  return family === "funASRNano" || family === "funASRMLTNano" || family === "senseVoiceSmall" || family === "qwen3ASR06B";
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
  if (family === "whisperCppCoreML") {
    return "whisperCommandTemplate";
  }
  return null;
}

function shellEscape(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function buildMLXAudioCommandTemplate(runtime, family) {
  const envKey = mlxAudioVenvEnvironmentName(family);
  return `${envKey}=${shellEscape(runtime.venv)} ${shellEscape(runtime.runner)} --model {model} --audio {audio} --language {language}`;
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
    throw new Error(`mlx-audio runtime install failed: ${details}`);
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
    const modelPath = sourcePathToFilePath(model.sourcePath);
    const files = modelPath ? modelFiles(modelPath) : {};
    return supportsMLXASRRepair(family) && files["model.safetensors"];
  });
  if (repairable.length === 0) {
    console.log("Repair: no safetensors/MLX speech model is eligible for automatic mlx-audio repair.");
    return false;
  }

  registry.preferences ??= {};
  registry.preferences.mediaSubtitles ??= {};

  const updatedFields = new Set();
  for (const model of repairable) {
    const family = model.capabilities?.speech?.family;
    const field = commandFieldForFamily(family);
    if (!field) {
      continue;
    }
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
    const commandTemplate = buildMLXAudioCommandTemplate(runtime, family);
    registry.preferences.mediaSubtitles[field] = commandTemplate;
    updatedFields.add(field);
  }

  if (updatedFields.size === 0) {
    console.log("Repair: no Media Subtitle command template field was updated.");
    return false;
  }

  const timestamp = new Date().toISOString().replaceAll(":", "-").replace(/\.\d{3}Z$/, "Z");
  const backupPath = `${registryPath}.bak-${timestamp}`;
  copyFileSync(registryPath, backupPath);
  writeFileSync(registryPath, `${JSON.stringify(registry, null, 2)}\n`);
  console.log(`Repair: wrote ${Array.from(updatedFields).join(", ")}.`);
  console.log(`Repair: registry backup saved to ${backupPath}.`);
  return true;
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
  for (const model of speechModels) {
    const speech = model.capabilities.speech;
    const modelPath = sourcePathToFilePath(model.sourcePath);
    const files = modelPath && existsSync(modelPath) ? modelFiles(modelPath) : {};
    const runtime = resolveRuntime(model, registry.preferences);
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
    if (files["model.safetensors"] && !files["model.onnx"]) {
    console.log("- note: safetensors/MLX ASR weights require the matching bundled MLX runner or another explicit local runtime command.");
    }
    console.log("");
  }

  console.log(`Ready speech runtimes: ${readyCount}/${speechModels.length}`);
  if (args.strict && readyCount === 0) {
    process.exit(1);
  }
}

run().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
