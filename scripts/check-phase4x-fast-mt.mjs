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
    "Sources/LLMToolsCore/FastTranslationService.swift",
    "scripts/llmtools-fastmt-sidecar.py",
    "scripts/install-phase4x-ctranslate2-en-zh.sh",
    "scripts/install-phase4x-nllb-200-distilled-600m.sh",
    "scripts/install-phase4x-argos.sh"
  ]) {
    await assertFile(relativePath);
  }

  const service = await read("Sources/LLMToolsCore/FastTranslationService.swift");
  const modelTypes = await read("Sources/LLMToolsCore/ModelTypes.swift");
  const webTypes = await read("Sources/LLMToolsCore/WebPageTranslationTypes.swift");
  const taskEngine = await read("Sources/LLMToolsCore/TaskEngine.swift");
  const appState = await read("Sources/LLMToolsApp/AppState.swift");
  const settingsView = await read("Sources/LLMToolsApp/Views.swift");
  const checks = await read("Sources/LLMToolsChecks/main.swift");
  const mediaSmoke = await read("Sources/LLMToolsMediaSmoke/main.swift");
  const sidecar = await read("scripts/llmtools-fastmt-sidecar.py");
  const ct2Installer = await read("scripts/install-phase4x-ctranslate2-en-zh.sh");
  const nllbInstaller = await read("scripts/install-phase4x-nllb-200-distilled-600m.sh");
  const argosInstaller = await read("scripts/install-phase4x-argos.sh");
  const packageScript = await read("scripts/package-app.sh");
  const background = await read("browser-extension/chromium/background.js");
  const browserCheck = await read("scripts/check-browser-extension-dom.mjs");

  for (const needle of [
    "FastTranslationService",
    "FastTranslationCommandRunner",
    "llmtools.fastmt/v1",
    "Phase4XFixtureEnvironment.fastTranslationJSON",
    "TranslationRoutingService",
    "unsupportedLanguagePair"
  ]) {
    assertIncludes(service, needle, "fast MT service");
  }

  for (const needle of [
    "FastTranslationPreferences",
    "FastTranslationModelVariant",
    "modelVariant",
    "subtitleEngine",
    "webpageEngine",
    "fallbackPolicy",
    "maxConcurrentBatches",
    "forceLLM",
    "{model_ct2}"
  ]) {
    assertIncludes(modelTypes, needle, "fast MT preferences");
  }

  for (const needle of [
    "translationEngine",
    "translationEngineID",
    "translationModelID",
    "detectedSourceLanguage",
    "domainTranslationEngines"
  ]) {
    assertIncludes(webTypes, needle, "webpage fast MT payload and result metadata");
  }

  for (const needle of [
    "translateSubtitleSegmentsWithFastMTIfSelected",
    "translateWebPageSegmentsWithFastMTIfSelected",
    "TranslationRoutingService.decide",
    "checkFastTranslationHealth",
    "fallbackPolicy == .fallbackToLLM"
  ]) {
    assertIncludes(taskEngine, needle, "fast MT task engine wiring");
  }

  for (const needle of [
    "fastTranslationHealthReport",
    "fastTranslationHealthCheckInProgress",
    "checkFastTranslationHealth"
  ]) {
    assertIncludes(appState, needle, "fast MT app state");
  }

  for (const needle of [
    "Fast MT",
    "Force LLM translation",
    "Fast MT model",
    "fastTranslationModelVariantName",
    "Text translation engine",
    "Subtitle translation engine",
    "Webpage translation engine",
    "Only Translate can use fast MT",
    "CTranslate2 command",
    "Argos command",
    "LLMTOOLS_FAST_MT_FIXTURE_JSON"
  ]) {
    assertIncludes(settingsView, needle, "fast MT settings UI");
  }

  for (const needle of [
    "checkFastMTFixtureRoundTrip",
    "checkFastMTPreferencesMigration",
    "checkTranslationRoutingDecisionTable",
    "checkTextTranslateFastMTPipeline",
    "checkSubtitleFastMTPipeline",
    "checkWebPageFastMTRouting"
  ]) {
    assertIncludes(checks, needle, "fast MT regression checks");
  }

  for (const needle of [
    "Phase4XFixtureEnvironment.fastTranslationJSON",
    "fastMTFirstTranslation",
    "fixture-opus-mt-en-zh"
  ]) {
    assertIncludes(mediaSmoke, needle, "fast MT media smoke");
  }

  for (const needle of [
    "llmtools.fastmt/v1",
    "CTranslate2",
    "BCP47_TO_NLLB",
    "target_prefix",
    "Argos",
    "available",
    "supportedPairs",
    "latencyMilliseconds"
  ]) {
    assertIncludes(sidecar, needle, "fast MT sidecar");
  }

  for (const needle of [
    "ctranslate2",
    "sentencepiece",
    "opus-mt-en-zh-ct2"
  ]) {
    assertIncludes(ct2Installer, needle, "CTranslate2 installer");
  }
  for (const needle of [
    "facebook/nllb-200-distilled-600M",
    "nllb-200-distilled-600m-ct2-int8",
    "--quantization int8",
    "sourceLanguage\":\"ja\""
  ]) {
    assertIncludes(nllbInstaller, needle, "NLLB installer");
  }
  for (const needle of [
    "argostranslate",
    "Argos Translate"
  ]) {
    assertIncludes(argosInstaller, needle, "Argos installer");
  }

  for (const needle of [
    "$RESOURCES_DIR/fastmt",
    "llmtools-fastmt-sidecar.py",
    "install-phase4x-ctranslate2-en-zh.sh",
    "install-phase4x-nllb-200-distilled-600m.sh",
    "install-phase4x-argos.sh"
  ]) {
    assertIncludes(packageScript, needle, "packaged app fast MT resources");
  }

  for (const needle of [
    "webPageTranslationCacheV2",
    "TRANSLATION_CACHE_KEY_V1",
    "migrateTranslationCacheV1ToV2",
    "translationEngineID",
    "translationEngineModelID",
    "sourceLanguage",
    "domainTranslationEngines",
    "translationEngine: job.translationEngine"
  ]) {
    assertIncludes(background, needle, "browser extension fast MT cache v2");
  }

  for (const needle of [
    "translationEngine: \"fastMT\"",
    "switching to fastMT should not reuse the existing LLM cache entries",
    "webPageTranslationCacheV2",
    "ctranslate2"
  ]) {
    assertIncludes(browserCheck, needle, "browser extension fast MT checks");
  }

  console.log("Phase 4.x fast MT checks passed");
}

run().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
