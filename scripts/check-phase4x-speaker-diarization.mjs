#!/usr/bin/env node

import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

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

function assertIncludes(source, needle, label) {
  assert(source.includes(needle), `${label} should include ${needle}`);
}

async function run() {
  for (const relativePath of [
    "Sources/LLMToolsCore/SpeakerDiarizationService.swift",
    "docs/phase-4x-realtime-diarization-spike.md",
    "scripts/llmtools-pyannote-diarization-sidecar.py",
    "scripts/install-phase4x-pyannote-diarization.sh"
  ]) {
    await assertFile(relativePath);
  }

  const service = await read("Sources/LLMToolsCore/SpeakerDiarizationService.swift");
  const languageNormalizer = await read("Sources/LLMToolsCore/LanguageCodeNormalizer.swift");
  const modelTypes = await read("Sources/LLMToolsCore/ModelTypes.swift");
  const realtimeSpike = await read("docs/phase-4x-realtime-diarization-spike.md");
  const mediaTypes = await read("Sources/LLMToolsCore/MediaSubtitleTypes.swift");
  const mediaServices = await read("Sources/LLMToolsCore/MediaSubtitleServices.swift");
  const taskEngine = await read("Sources/LLMToolsCore/TaskEngine.swift");
  const appState = await read("Sources/LLMToolsApp/AppState.swift");
  const settingsView = await read("Sources/LLMToolsApp/Views.swift");
  const checks = await read("Sources/LLMToolsChecks/main.swift");
  const sidecar = await read("scripts/llmtools-pyannote-diarization-sidecar.py");
  const installer = await read("scripts/install-phase4x-pyannote-diarization.sh");
  const packageScript = await read("scripts/package-app.sh");

  for (const needle of [
    "SpeakerDiarizationService",
    "SpeakerTurnMapper",
    "SpeakerDiarizationCommandRunner",
    "Phase4XFixtureEnvironment.diarizationJSON",
    "PYANNOTE_AUTH_TOKEN",
    "SpeakerDiarizationHealth",
    "requiresUserToken",
    "tokenPresent",
    "tokenAcceptedRecently"
  ]) {
    assertIncludes(service, needle, "speaker diarization service");
  }
  assertIncludes(
    languageNormalizer,
    "LLMTOOLS_DIARIZATION_FIXTURE_JSON",
    "Phase 4.x fixture environment"
  );

  for (const needle of [
    "SpeakerDiarizationPreferences",
    "enabledForFileSubtitles",
    "enabledForLiveSubtitles",
    "enabledForLiveSubtitles = false",
    "persistSpeakerEmbeddings"
  ]) {
    assertIncludes(modelTypes, needle, "speaker diarization preferences");
  }
  assertIncludes(
    service,
    "SpeakerDiarizationTokenStore",
    "speaker diarization local token store"
  );

  for (const needle of [
    "Realtime speaker diarization is rejected",
    "hard-disabled",
    "less than 3 seconds",
    "file-scope diarization only"
  ]) {
    assertIncludes(realtimeSpike, needle, "realtime diarization spike report");
  }

  for (const needle of [
    "speakerCount",
    "diarizationModelID",
    "diarizationErrorCode",
    "diarizationErrorMessage",
    "SubtitleExportOptions",
    "SpeakerPrefixFormat"
  ]) {
    assertIncludes(mediaTypes, needle, "speaker diarization media types");
  }

  for (const needle of [
    "includeSpeakerLabels",
    "speakerFormat",
    "prefixedSpeakerText"
  ]) {
    assertIncludes(mediaServices, needle, "speaker label subtitle export");
  }

  for (const needle of [
    "speakerDiarizationService",
    "enabledForFileSubtitles",
    "SpeakerTurnMapper.apply",
    "diarizationErrorCode",
    "diarizationErrorMessage",
    "checkSpeakerDiarizationHealth"
  ]) {
    assertIncludes(taskEngine, needle, "speaker diarization task engine wiring");
  }

  for (const needle of [
    "speakerDiarizationHealthReport",
    "speakerDiarizationHealthCheckInProgress",
    "checkSpeakerDiarizationHealth"
  ]) {
    assertIncludes(appState, needle, "speaker diarization app state");
  }

  for (const needle of [
    "Speaker Diarization",
    "Enable for file subtitles",
    "Enable for live subtitles",
    "Live speaker diarization remains disabled",
    "Diarization command",
    "HF token local storage",
    "LLMTOOLS_DIARIZATION_FIXTURE_JSON",
    "speakerDiarizationHealthReportView"
  ]) {
    assertIncludes(settingsView, needle, "speaker diarization settings UI");
  }

  for (const needle of [
    "checkSpeakerDiarizationFixtureAndMapping",
    "checkSubtitleExportWithSpeakers",
    "checkSpeakerDiarizationFilePipeline",
    "Diarization failure must not drop transcript segments",
    "Speaker embeddings must not be persisted"
  ]) {
    assertIncludes(checks, needle, "speaker diarization regression checks");
  }

  for (const needle of [
    "pyannote.audio",
    "Pipeline.from_pretrained",
    "patch_huggingface_hub_auth_keyword",
    "pyannote/speaker-diarization-3.1",
    "PYANNOTE_AUTH_TOKEN",
    "speakerLabel",
    "latencyMilliseconds"
  ]) {
    assertIncludes(sidecar, needle, "pyannote diarization sidecar");
  }

  for (const needle of [
    "pyannote speaker diarization setup",
    "pyannote.audio==3.1.1",
    "Hugging Face terms",
    "llmTools does not upload audio"
  ]) {
    assertIncludes(installer, needle, "pyannote diarization installer");
  }

  for (const needle of [
    "$RESOURCES_DIR/diarization",
    "llmtools-pyannote-diarization-sidecar.py",
    "install-phase4x-pyannote-diarization.sh"
  ]) {
    assertIncludes(packageScript, needle, "packaged app diarization resources");
  }

  console.log("Phase 4.x speaker diarization checks passed");
}

run().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
