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
    "Sources/LLMToolsCore/LanguageCodeNormalizer.swift",
    "Sources/LLMToolsCore/LanguageDetectionService.swift",
    "scripts/llmtools-lid-sidecar.py",
    "scripts/install-phase4x-fasttext-lid.sh"
  ]) {
    await assertFile(relativePath);
  }

  const normalizer = await read("Sources/LLMToolsCore/LanguageCodeNormalizer.swift");
  const service = await read("Sources/LLMToolsCore/LanguageDetectionService.swift");
  const modelTypes = await read("Sources/LLMToolsCore/ModelTypes.swift");
  const checks = await read("Sources/LLMToolsChecks/main.swift");
  const taskEngine = await read("Sources/LLMToolsCore/TaskEngine.swift");
  const settingsView = await read("Sources/LLMToolsApp/Views.swift");
  const appState = await read("Sources/LLMToolsApp/AppState.swift");
  const sidecar = await read("scripts/llmtools-lid-sidecar.py");
  const installer = await read("scripts/install-phase4x-fasttext-lid.sh");
  const packageScript = await read("scripts/package-app.sh");

  for (const needle of [
    "normalizedBCP47",
    "fastTextCode",
    "nllbCode",
    "argosCode",
    "asrHintCode",
    "LLMTOOLS_LID_FIXTURE_JSON"
  ]) {
    assertIncludes(normalizer, needle, "language code normalizer");
  }

  for (const needle of [
    "LanguageDetectionService",
    "FastTextLIDCommandRunner",
    "LanguageDetectionProcessSession",
    "llmtools.lid/v1",
    "LLMTOOLS_LID_MODEL_FTZ",
    "LLMTOOLS_LID_MODEL_BIN",
    "LLMTOOLS_LID_PYTHON",
    "LLMTOOLS_LID_SIDECAR",
    "fixtureResult",
    "shouldSkipDetection"
  ]) {
    assertIncludes(service, needle, "language detection service");
  }

  for (const needle of [
    "LanguageRoutingPreferences",
    "shortTextMinimumCharactersLatin",
    "shortTextMinimumCharactersCJK",
    "lowConfidenceThreshold",
    "ocrConfidenceBoost",
    "useForWebpage",
    "useForOCR",
    "useForSubtitles",
    "commandTemplate"
  ]) {
    assertIncludes(modelTypes, needle, "language routing preferences");
  }

  for (const needle of [
    "checkLanguageDetectionFixture",
    "checkLanguageRoutingCallerWiring",
    "setenv(Phase4XFixtureEnvironment.languageIDJSON",
    "LanguageDetectionService().detect",
    "service.health"
  ]) {
    assertIncludes(checks, needle, "language detection regression checks");
  }

  for (const needle of [
    "requestWithDetectedSourceLanguageIfNeeded",
    "webPageSourceLanguageIfNeeded",
    "subtitleSegmentsWithDetectedSourceLanguageIfNeeded",
    "detectedSourceLanguageIfNeeded",
    "useForTextTasks",
    "useForWebpage",
    "useForOCR",
    "useForSubtitles"
  ]) {
    assertIncludes(taskEngine, needle, "language routing caller wiring");
  }

  for (const needle of [
    "Language Routing",
    "Enable language routing",
    "Language ID command",
    "Sample detection text",
    "LLMTOOLS_LID_FIXTURE_JSON",
    "checkLanguageDetectionHealth",
    "languageDetectionHealthReportView"
  ]) {
    assertIncludes(settingsView, needle, "language routing settings UI");
  }
  for (const needle of [
    "languageDetectionHealthReport",
    "languageDetectionHealthCheckInProgress",
    "languageDetectionSampleText",
    "checkLanguageDetectionHealth"
  ]) {
    assertIncludes(appState, needle, "language routing app state");
  }

  for (const needle of [
    "fasttext.load_model",
    "llmtools.lid/v1",
    "\"type\": \"ready\"",
    "command != \"detect\"",
    "\"type\": \"result\"",
    "latencyMilliseconds"
  ]) {
    assertIncludes(sidecar, needle, "language ID sidecar");
  }

  for (const needle of [
    "uv venv",
    "fasttext",
    "lid.176.ftz",
    "lid.176.bin",
    "LLMTOOLS_LID_RUNTIME_DIR",
    "LLMTOOLS_LID_MODEL_VARIANT"
  ]) {
    assertIncludes(installer, needle, "language ID installer");
  }

  for (const needle of [
    "$RESOURCES_DIR/lid",
    "llmtools-lid-sidecar.py",
    "install-phase4x-fasttext-lid.sh"
  ]) {
    assertIncludes(packageScript, needle, "packaged app LID resources");
  }

  console.log("Phase 4.x language routing checks passed");
}

run().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
