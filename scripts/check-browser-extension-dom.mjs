#!/usr/bin/env node

import { spawn } from "node:child_process";
import { createHash, randomBytes, randomUUID, webcrypto } from "node:crypto";
import { promises as fs } from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import vm from "node:vm";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const extensionRoot = path.join(repoRoot, "browser-extension", "chromium");
const chromiumDevelopmentExtensionID = "jednddlgkkohaebgoejcidfppddjegij";
const browserE2ETargets = [
  {
    id: "chrome",
    name: "Google Chrome",
    envPathName: "CHROME_PATH",
    path: process.env.CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  },
  {
    id: "edge",
    name: "Microsoft Edge",
    envPathName: "EDGE_PATH",
    path: process.env.EDGE_PATH || "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
  }
];

async function runExtensionManifestPermissionCheck() {
  const manifest = JSON.parse(await fs.readFile(path.join(extensionRoot, "manifest.json"), "utf8"));
  const permissions = manifest.permissions || [];
  const optionalHostPermissions = manifest.optional_host_permissions || [];
  const expectedPermissions = ["activeTab", "contextMenus", "nativeMessaging", "scripting", "storage"];
  assert(manifest.manifest_version === 3, `expected MV3 manifest, got ${manifest.manifest_version}`);
  assert(
    JSON.stringify([...permissions].sort()) === JSON.stringify(expectedPermissions),
    `manifest permissions should stay least-privilege; got ${JSON.stringify(permissions)}`
  );
  assert(!permissions.includes("tabCapture"), "browser extension must not request tabCapture after live subtitles moved into the app");
  assert(!permissions.includes("offscreen"), "browser extension must not request offscreen after live subtitles moved into the app");
  assert(!permissions.includes("<all_urls>"), "manual translation must not request <all_urls> as a normal permission");
  assert(
    !permissions.some((permission) => /^https?:\/\//.test(permission)),
    `host access must stay out of normal permissions: ${JSON.stringify(permissions)}`
  );
  assert(
    !Array.isArray(manifest.host_permissions) || manifest.host_permissions.length === 0,
    `host_permissions must stay empty/absent; use optional_host_permissions instead: ${JSON.stringify(manifest.host_permissions)}`
  );
  assert(
    JSON.stringify([...optionalHostPermissions].sort()) === JSON.stringify(["http://*/*", "https://*/*"]),
    `auto-translate should request only optional http/https host permissions; got ${JSON.stringify(optionalHostPermissions)}`
  );
  assert(
    !Array.isArray(manifest.content_scripts) || manifest.content_scripts.length === 0,
    "content scripts should remain programmatically injected after user action/permission, not globally declared"
  );
  assert(manifest.background?.service_worker === "background.js", "manifest should keep the MV3 background service worker");
  assert(typeof manifest.key === "string" && manifest.key.length > 0, "development manifest must keep a stable key for a stable extension ID");
  assert(
    extensionIDForPublicKey(manifest.key) === chromiumDevelopmentExtensionID,
    `manifest key should derive the configured development extension ID ${chromiumDevelopmentExtensionID}`
  );
}

function extensionIDForPublicKey(base64Key) {
  const digest = createHash("sha256").update(Buffer.from(base64Key, "base64")).digest().subarray(0, 16);
  const alphabet = "abcdefghijklmnop";
  return Array.from(digest, (byte) => alphabet[byte >> 4] + alphabet[byte & 0x0f]).join("");
}

async function runBackgroundBatchCheck() {
  const source = await fs.readFile(path.join(extensionRoot, "background.js"), "utf8");
  const repeatHash = "repeat-hash";
  const uniqueHash = "unique-hash";
  const discoveredSegments = [
    { segmentID: "s1", text: "Repeated label for duplicate translation.", textHash: repeatHash, tagName: "P", blockContext: "p", priority: 10 },
    { segmentID: "s2", text: "Repeated label for duplicate translation.", textHash: repeatHash, tagName: "P", blockContext: "p", priority: 10 },
    { segmentID: "s3", text: "The quick brown fox jumps over the lazy dog.", textHash: uniqueHash, tagName: "P", blockContext: "p", priority: 10 }
  ];

  let backgroundListener = null;
  let tabUpdatedListener = null;
  let tabRemovedListener = null;
  let tabActivatedListener = null;
  let contextMenuClickListener = null;
  let contextMenuShownListener = null;
  const nativeMessages = [];
  const nativeTranslatePayloads = [];
  const appliedTranslations = [];
  const applyTranslationMessages = [];
  const translationStateMessages = [];
  const popupStates = [];
  const startSessionMessages = [];
  const readingModeMessages = [];
  const contextMenuItems = new Map();
  const localStorageData = {};
  const nativeDomainRules = {
    autoTranslateDomains: [],
    disabledDomains: [],
    domainReadingModes: {},
    domainTranslationQualities: {},
    domainTranslationEngines: {}
  };
  let nativePendingIndicatorStyle = "flipText";
  let currentUnsupportedEmbeddedContent = { frames: 0, canvas: 0, images: 0, pdf: 0, total: 0 };
  const grantedOrigins = new Set();
  const tabURLs = new Map([[7, "https://example.test/article"]]);
  const contentScriptUnavailableTabs = new Set();
  const executeScriptFailureTabs = new Set();
  const failingTranslationHashes = new Set();
  let nativePortMessageListener = null;
  let nativePortDisconnectListener = null;

  function nativeResponseFor(message) {
    if (message.type === "getStatus") {
      return {
        requestID: message.requestID,
        status: "ok",
        payload: {
          modelName: "stub-model",
          webPageTranslationEngine: "llm",
          webPageTranslationEngineID: "llm",
          webPageTranslationEngineModelID: "stub-model-id",
          pendingIndicatorStyle: nativePendingIndicatorStyle,
          appLanguage: "en",
          autoTranslateDomains: nativeDomainRules.autoTranslateDomains,
          disabledDomains: nativeDomainRules.disabledDomains,
          domainReadingModes: nativeDomainRules.domainReadingModes,
          domainTranslationQualities: nativeDomainRules.domainTranslationQualities,
          domainTranslationEngines: nativeDomainRules.domainTranslationEngines
        }
      };
    }
    if (message.type === "setDomainRule") {
      const domain = message.payload.domain;
      nativeDomainRules.autoTranslateDomains = nativeDomainRules.autoTranslateDomains.filter((item) => item !== domain);
      nativeDomainRules.disabledDomains = nativeDomainRules.disabledDomains.filter((item) => item !== domain);
      if (message.payload.rule === "alwaysTranslate") {
        nativeDomainRules.autoTranslateDomains.push(domain);
      } else if (message.payload.rule === "neverTranslate") {
        nativeDomainRules.disabledDomains.push(domain);
      }
      return {
        requestID: message.requestID,
        status: "ok",
        payload: {
          domain,
          rule: message.payload.rule,
          autoTranslateDomains: nativeDomainRules.autoTranslateDomains,
          disabledDomains: nativeDomainRules.disabledDomains
        }
      };
    }
    if (message.type === "setDomainPageDefaults") {
      const domain = message.payload.domain;
      if (message.payload.readingMode) {
        nativeDomainRules.domainReadingModes[domain] = message.payload.readingMode;
      }
      if (message.payload.translationQuality) {
        nativeDomainRules.domainTranslationQualities[domain] = message.payload.translationQuality;
      }
      if (message.payload.translationEngine) {
        nativeDomainRules.domainTranslationEngines[domain] = message.payload.translationEngine;
      }
      return {
        requestID: message.requestID,
        status: "ok",
        payload: {
          domain,
          domainReadingModes: nativeDomainRules.domainReadingModes,
          domainTranslationQualities: nativeDomainRules.domainTranslationQualities,
          domainTranslationEngines: nativeDomainRules.domainTranslationEngines
        }
      };
    }
    if (message.type === "setPendingIndicatorStyle") {
      nativePendingIndicatorStyle = message.payload.pendingIndicatorStyle;
      return {
        requestID: message.requestID,
        status: "ok",
        payload: {
          pendingIndicatorStyle: nativePendingIndicatorStyle
        }
      };
    }
    if (message.type === "translateSegments") {
      nativeTranslatePayloads.push(message.payload);
      if (message.payload.segments.some((segment) => failingTranslationHashes.has(segment.textHash))) {
        return {
          requestID: message.requestID,
          status: "error",
          error: { message: "forced native translation failure" }
        };
      }
      return {
        requestID: message.requestID,
        status: "ok",
        payload: {
          modelName: "stub-model",
          translationEngineID: message.payload.translationEngine === "fastMT" ? "ctranslate2" : "llm",
          translationModelID: message.payload.translationEngine === "fastMT" ? "fixture-fastmt" : "stub-model-id",
          detectedSourceLanguage: message.payload.sourceLanguage === "auto" ? "en" : (message.payload.sourceLanguage || "en"),
          elapsedMilliseconds: 11,
          fallbackReason: "",
          translations: message.payload.segments.map((segment) => ({
            segmentID: segment.segmentID,
            translation: segment.textHash === repeatHash ? "重复标签" : "敏捷的棕色狐狸跳过懒狗。",
            status: "translated"
          }))
        }
      };
    }
    if (message.type === "cancelJob") {
      return {
        requestID: message.requestID,
        status: "ok",
        payload: { cancelled: true }
      };
    }
    return {
      requestID: message.requestID,
      status: "error",
      error: { message: `Unexpected native message type: ${message.type}` }
    };
  }

  const chrome = {
    runtime: {
      lastError: null,
      onMessage: {
        addListener(listener) {
          backgroundListener = listener;
        }
      },
      onInstalled: {
        addListener() {}
      },
      onStartup: {
        addListener() {}
      },
      sendMessage(message) {
        popupStates.push(message);
        return Promise.resolve();
      },
      connectNative() {
        return {
          postMessage(message) {
            nativeMessages.push(message);
            const response = nativeResponseFor(message);
            setTimeout(() => nativePortMessageListener?.(response), 0);
          },
          onMessage: {
            addListener(listener) {
              nativePortMessageListener = listener;
            }
          },
          onDisconnect: {
            addListener(listener) {
              nativePortDisconnectListener = listener;
            }
          }
        };
      },
      sendNativeMessage(_hostName, message) {
        nativeMessages.push(message);
        if (message.type === "getStatus") {
          return Promise.resolve({ status: "ok", payload: {
            modelName: "stub-model",
            webPageTranslationEngine: "llm",
            webPageTranslationEngineID: "llm",
            webPageTranslationEngineModelID: "stub-model-id",
            pendingIndicatorStyle: "flipText",
            appLanguage: "en",
            autoTranslateDomains: nativeDomainRules.autoTranslateDomains,
            disabledDomains: nativeDomainRules.disabledDomains,
            domainReadingModes: nativeDomainRules.domainReadingModes,
            domainTranslationQualities: nativeDomainRules.domainTranslationQualities,
            domainTranslationEngines: nativeDomainRules.domainTranslationEngines
          } });
        }
        if (message.type === "translateSegments") {
          nativeTranslatePayloads.push(message.payload);
          if (message.payload.segments.some((segment) => failingTranslationHashes.has(segment.textHash))) {
            return Promise.resolve({
              status: "error",
              error: { message: "forced native translation failure" }
            });
          }
          return Promise.resolve({
            status: "ok",
            payload: {
              modelName: "stub-model",
              translationEngineID: message.payload.translationEngine === "fastMT" ? "ctranslate2" : "llm",
              translationModelID: message.payload.translationEngine === "fastMT" ? "fixture-fastmt" : "stub-model-id",
              detectedSourceLanguage: message.payload.sourceLanguage === "auto" ? "en" : (message.payload.sourceLanguage || "en"),
              elapsedMilliseconds: 11,
              fallbackReason: "",
              translations: message.payload.segments.map((segment) => ({
                segmentID: segment.segmentID,
                translation: segment.textHash === repeatHash ? "重复标签" : "敏捷的棕色狐狸跳过懒狗。",
                status: "translated"
              }))
            }
          });
        }
        if (message.type === "cancelJob") {
          return Promise.resolve({ status: "ok", payload: { cancelled: true } });
        }
        throw new Error(`Unexpected native message type: ${message.type}`);
      }
    },
    contextMenus: {
      removeAll(callback) {
        contextMenuItems.clear();
        callback?.();
      },
      create(item, callback) {
        contextMenuItems.set(item.id, { ...item });
        callback?.();
        return item.id;
      },
      update(id, patch, callback) {
        const item = contextMenuItems.get(id) || { id };
        contextMenuItems.set(id, { ...item, ...patch });
        callback?.();
      },
      onClicked: {
        addListener(listener) {
          contextMenuClickListener = listener;
        }
      },
      onShown: {
        addListener(listener) {
          contextMenuShownListener = listener;
        }
      },
      refresh() {
        return undefined;
      }
    },
    storage: {
      local: {
        get(key) {
          if (Array.isArray(key)) {
            return Promise.resolve(Object.fromEntries(key.map((item) => [item, localStorageData[item]])));
          }
          if (typeof key === "string") {
            return Promise.resolve({ [key]: localStorageData[key] });
          }
          if (key && typeof key === "object") {
            return Promise.resolve(Object.fromEntries(Object.keys(key).map((item) => [item, localStorageData[item] ?? key[item]])));
          }
          return Promise.resolve({ ...localStorageData });
        },
        set(values) {
          Object.assign(localStorageData, values);
          return Promise.resolve();
        }
      }
    },
    permissions: {
      contains(permission) {
        const origins = permission?.origins || [];
        return Promise.resolve(origins.every((origin) => grantedOrigins.has(origin)));
      },
      request(permission) {
        for (const origin of permission?.origins || []) {
          grantedOrigins.add(origin);
        }
        return Promise.resolve(true);
      }
    },
    tabs: {
      onRemoved: {
        addListener(listener) {
          tabRemovedListener = listener;
        }
      },
      onUpdated: {
        addListener(listener) {
          tabUpdatedListener = listener;
        }
      },
      onActivated: {
        addListener(listener) {
          tabActivatedListener = listener;
        }
      },
      get(tabID) {
        return Promise.resolve({ id: tabID, url: tabURLs.get(tabID) || "https://example.test/article" });
      },
      sendMessage(tabID, message) {
        if (contentScriptUnavailableTabs.has(tabID)) {
          return Promise.reject(new Error("Could not establish connection. Receiving end does not exist."));
        }
        if (message.type === "ping") {
          return Promise.resolve({ ok: true });
        }
        if (message.type === "startSession") {
          startSessionMessages.push(message);
          return Promise.resolve({
            ok: true,
            url: "https://example.test/article",
            title: "Test Article",
            segments: discoveredSegments,
            unsupportedEmbeddedContent: currentUnsupportedEmbeddedContent
          });
        }
        if (message.type === "applyTranslations") {
          applyTranslationMessages.push(message);
          appliedTranslations.push(...message.translations);
          return Promise.resolve({ ok: true, applied: appliedTranslations.length });
        }
        if (message.type === "translationState") {
          translationStateMessages.push(message);
          return Promise.resolve({ ok: true });
        }
        if (message.type === "setReadingMode") {
          readingModeMessages.push(message);
          return Promise.resolve({ ok: true, readingMode: message.mode });
        }
        if (message.type === "getPageTranslationState") {
          return Promise.resolve({
            ok: true,
            url: "https://example.test/article",
            title: "Test Article",
            pageSessionID: "mock-page-session",
            trackedCount: discoveredSegments.length,
            translatedCount: appliedTranslations.length,
            hasTranslations: appliedTranslations.length > 0,
            readingMode: readingModeMessages.at(-1)?.mode || "replace",
            unsupportedEmbeddedContent: currentUnsupportedEmbeddedContent
          });
        }
        if (message.type === "restore" || message.type === "cancel") {
          if (message.type === "restore") {
            appliedTranslations.length = 0;
          }
          return Promise.resolve({ ok: true });
        }
        throw new Error(`Unexpected tab message type: ${message.type}`);
      }
    },
    scripting: {
      executeScript(options = {}) {
        if (executeScriptFailureTabs.has(options.target?.tabId)) {
          return Promise.reject(new Error("Cannot access contents of the page. Extension manifest must request permission."));
        }
        return Promise.resolve();
      }
    }
  };

  const context = vm.createContext({
    chrome,
    console,
    crypto: { randomUUID, subtle: webcrypto.subtle },
    TextEncoder,
    URL,
    setTimeout,
    clearTimeout
  });
  vm.runInContext(source, context, { filename: "background.js" });
  assert(backgroundListener, "background listener was not registered");
  assert(tabUpdatedListener, "tab update listener was not registered");
  assert(tabRemovedListener, "tab removal listener was not registered");
  assert(tabActivatedListener, "tab activation listener was not registered");
  assert(contextMenuClickListener, "context menu click listener was not registered");
  assert(contextMenuShownListener, "context menu shown listener was not registered");
  assert(nativePortDisconnectListener === null, "native port should not connect before a native request");
  assert(contextMenuItems.size === 1, `expected one top-level context menu item, got ${contextMenuItems.size}`);
  assert(contextMenuItems.has("llmtools-toggle-page"), "toggle context menu was not created");
  assert(!contextMenuItems.has("llmtools-toggle-live-subtitles"), "live subtitles context menu should not be created");
  assert(contextMenuItems.get("llmtools-toggle-page").title === "翻译/原文", "toggle context menu should use the requested label");
  assert(contextMenuItems.get("llmtools-toggle-page").enabled !== false, "toggle context menu should start enabled");

  contextMenuClickListener({ menuItemId: "llmtools-toggle-page" }, { id: 7 });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "background did not apply all translations");
  const finalState = await sendBackgroundMessage(backgroundListener, { type: "getPopupState", tabID: 7 });

  assert(nativeTranslatePayloads.length === 1, `expected one translateSegments call, got ${nativeTranslatePayloads.length}`);
  assert(nativeTranslatePayloads[0].sourceLanguage === "auto", `expected webpage translation to request automatic source language, got ${nativeTranslatePayloads[0].sourceLanguage}`);
  assert(nativeTranslatePayloads[0].translationQuality === "natural", `expected default natural translation quality, got ${nativeTranslatePayloads[0].translationQuality}`);
  assert(nativeTranslatePayloads[0].segments.length === 2, "expected repeated text to be sent once per batch");
  assert(nativeTranslatePayloads[0].segments.some((segment) => segment.segmentID === "s1"), "expected first repeated segment to be translated");
  assert(!nativeTranslatePayloads[0].segments.some((segment) => segment.segmentID === "s2"), "expected duplicate repeated segment to reuse the first translation");
  assert(appliedTranslations.some((item) => item.segmentID === "s2" && item.translation === "重复标签"), "expected duplicate node to receive reused translation");
  assert(startSessionMessages[0]?.pendingIndicatorStyle === "flipText", "expected background to pass configured pending indicator style to content script");
  assert(applyTranslationMessages.every((message) => message.pageSessionID === startSessionMessages[0]?.pageSessionID), "background applyTranslations messages should include the active page session id");
  assert(
    translationStateMessages.filter((message) => message.state?.jobID).every((message) => typeof message.state?.pageSessionID === "string" && message.state.pageSessionID.length > 0),
    "background job-scoped translationState messages should include a page session id"
  );
  assert(
    translationStateMessages.some((message) => message.state?.status === "translated" && message.state?.pageSessionID === startSessionMessages[0]?.pageSessionID),
    "background final translationState should keep the active page session id"
  );
  assert(startSessionMessages[0]?.appLanguage === "en", "expected background to pass app language to content script");
  assert(startSessionMessages[0]?.readingMode === "replace", "expected background to pass default replace reading mode to content script");
  assert(startSessionMessages[0]?.discoveryScope === "visible", "expected background to default to visible-first discovery");
  assert(finalState.status === "translated", `expected translated state, got ${finalState.status}`);
  assert(finalState.done === 3 && finalState.total === 3, `expected 3/3 final progress, got ${finalState.done}/${finalState.total}`);
  assert(finalState.appLanguage === "en", `expected app language to follow native status, got ${finalState.appLanguage}`);
  assert(finalState.message === "Translated 3/3 segments.", `expected English translated message, got ${finalState.message}`);
  assert(finalState.domain === "example.test", `expected popup state to include normalized domain, got ${finalState.domain}`);
  assert(finalState.domainRule === "ask", `expected default domain rule to be ask, got ${finalState.domainRule}`);
  assert(finalState.readingMode === "replace", `expected default reading mode to be replace, got ${finalState.readingMode}`);
  assert(finalState.discoveryScope === "visible", `expected default discovery scope to be visible, got ${finalState.discoveryScope}`);
  assert(finalState.translationQuality === "natural", `expected default translation quality to be natural, got ${finalState.translationQuality}`);
  assert(finalState.pendingIndicatorStyle === "flipText", `expected pending indicator style to follow native status, got ${finalState.pendingIndicatorStyle}`);
  const noPendingStyleState = await sendBackgroundMessage(backgroundListener, {
    type: "setPendingIndicatorStyle",
    tabID: 7,
    pendingIndicatorStyle: "none"
  });
  assert(noPendingStyleState.pendingIndicatorStyle === "none", "background should update pending style from popup selection");
  assert(
    nativeMessages.some((message) => message.type === "setPendingIndicatorStyle" && message.payload?.pendingIndicatorStyle === "none"),
    "background should persist popup pending style changes through native messaging"
  );
  const restoredPendingStyleState = await sendBackgroundMessage(backgroundListener, {
    type: "setPendingIndicatorStyle",
    tabID: 7,
    pendingIndicatorStyle: "flipText"
  });
  assert(restoredPendingStyleState.pendingIndicatorStyle === "flipText", "background should allow returning pending style to flip text");
  assert(finalState.diagnostics?.browserID === "chrome", "diagnostics should include the browser id");
  assert(finalState.diagnostics?.extensionVersion === "0.3.0", `unexpected diagnostics extension version: ${finalState.diagnostics?.extensionVersion}`);
  assert(finalState.diagnostics?.counts?.done === 3 && finalState.diagnostics?.counts?.total === 3, "diagnostics should include redacted progress counts");
  assert(finalState.diagnostics?.timings?.elapsedMs != null, "diagnostics should include elapsed timing");
  assert(finalState.diagnostics?.model?.name === "stub-model", `diagnostics should include model name, got ${finalState.diagnostics?.model?.name}`);
  assert(finalState.diagnostics?.translation?.detectedSource === "en", `diagnostics should include detected source language, got ${finalState.diagnostics?.translation?.detectedSource}`);
  assert(finalState.diagnostics?.domainHash && finalState.diagnostics.domainHash !== "example.test", "diagnostics should use a redacted domain hash");
  assert(finalState.diagnostics?.urlHash?.length === 64, "diagnostics should include the page URL hash");
  const finalDiagnosticsJSON = JSON.stringify(finalState.diagnostics);
  assert(!finalDiagnosticsJSON.includes("example.test"), "diagnostics should not include the raw domain");
  assert(!finalDiagnosticsJSON.includes("Repeated label"), "diagnostics should not include raw segment text");
  assert(popupStates.some((message) => message.state?.modelName === "stub-model"), "expected model name to be published to popup state");
  assert(popupStates.some((message) => message.state?.appLanguage === "en"), "expected app language to be published to popup state");
  assert(contextMenuItems.get("llmtools-toggle-page").enabled === true, "toggle context menu should be enabled after translation");
  assert(contextMenuItems.get("llmtools-toggle-page").title === "Translate/Original", "toggle context menu should follow app language after status check");
  assert(
    !nativeMessages.some((message) => message.type === "startAppLiveSubtitles" || message.type === "stopAppLiveSubtitles"),
    "browser extension should not start or stop app live subtitles"
  );

  const nativeCallsBeforeRestrictedPage = nativeTranslatePayloads.length;
  const startSessionsBeforeRestrictedPage = startSessionMessages.length;
  const restrictedPageState = await sendBackgroundMessage(backgroundListener, {
    type: "translatePage",
    tabID: 17,
    tabURL: "chrome://extensions/"
  });
  assert(restrictedPageState.status === "unsupportedPage", `expected restricted page to be unsupported, got ${restrictedPageState.status}`);
  assert(restrictedPageState.message === "This browser page cannot be translated. Open an http:// or https:// webpage and try again.", `unexpected restricted page message: ${restrictedPageState.message}`);
  assert(restrictedPageState.lastErrorCode === "restricted_page", `expected restricted_page error code, got ${restrictedPageState.lastErrorCode}`);
  assert(restrictedPageState.diagnostics?.errorCode === "restricted_page", "restricted page diagnostics should include stable error code");
  assert(restrictedPageState.canClearCache === false, "restricted page state should disable cache actions");
  assert(nativeTranslatePayloads.length === nativeCallsBeforeRestrictedPage, "restricted page should not call native translateSegments");
  assert(startSessionMessages.length === startSessionsBeforeRestrictedPage, "restricted page should not start a content-script session");

  const nativeCallsBeforePDFPage = nativeTranslatePayloads.length;
  const startSessionsBeforePDFPage = startSessionMessages.length;
  const pdfPageState = await sendBackgroundMessage(backgroundListener, {
    type: "translatePage",
    tabID: 19,
    tabURL: "https://example.test/manual.pdf"
  });
  assert(pdfPageState.status === "unsupportedPage", `expected PDF page to be unsupported, got ${pdfPageState.status}`);
  assert(pdfPageState.message === "PDF pages cannot be translated here yet. Download the PDF or use a later document-translation flow.", `unexpected PDF page message: ${pdfPageState.message}`);
  assert(pdfPageState.lastErrorCode === "browser_pdf_page", `expected browser_pdf_page error code, got ${pdfPageState.lastErrorCode}`);
  assert(pdfPageState.diagnostics?.errorCode === "browser_pdf_page", "PDF page diagnostics should include stable error code");
  assert(pdfPageState.domain === "example.test", `expected normalized PDF page domain, got ${pdfPageState.domain}`);
  assert(pdfPageState.canClearCache === false, "PDF page state should disable cache actions");
  assert(nativeTranslatePayloads.length === nativeCallsBeforePDFPage, "PDF page should not call native translateSegments");
  assert(startSessionMessages.length === startSessionsBeforePDFPage, "PDF page should not start a content-script session");

  tabURLs.set(18, "https://blocked.example/page");
  contentScriptUnavailableTabs.add(18);
  executeScriptFailureTabs.add(18);
  const nativeCallsBeforeInjectionFailure = nativeTranslatePayloads.length;
  const startSessionsBeforeInjectionFailure = startSessionMessages.length;
  const injectionFailureState = await sendBackgroundMessage(backgroundListener, {
    type: "translatePage",
    tabID: 18,
    tabURL: "https://blocked.example/page"
  });
  assert(injectionFailureState.status === "unsupportedPage", `expected injection failure to be unsupported, got ${injectionFailureState.status}`);
  assert(injectionFailureState.message === "Cannot access this page for translation. The browser may block extensions on this page.", `unexpected injection failure message: ${injectionFailureState.message}`);
  assert(injectionFailureState.lastErrorCode === "content_script_injection_failed", `expected injection error code, got ${injectionFailureState.lastErrorCode}`);
  assert(injectionFailureState.diagnostics?.errorCode === "content_script_injection_failed", "injection failure diagnostics should include stable error code");
  assert(injectionFailureState.domain === "blocked.example", `expected normalized injection failure domain, got ${injectionFailureState.domain}`);
  assert(injectionFailureState.canClearCache === false, "injection failure state should disable cache actions");
  assert(nativeTranslatePayloads.length === nativeCallsBeforeInjectionFailure, "injection failure should not call native translateSegments");
  assert(startSessionMessages.length === startSessionsBeforeInjectionFailure, "injection failure should not start a content-script session");

  contextMenuClickListener({ menuItemId: "llmtools-toggle-page" }, { id: 7 });
  await waitUntil(() => appliedTranslations.length === 0, 2_000, "context menu toggle restore did not clear translations");
  const restoredState = await sendBackgroundMessage(backgroundListener, { type: "getPopupState", tabID: 7 });
  assert(restoredState.hasTranslations === false, "context menu toggle should clear translated state");
  assert(contextMenuItems.get("llmtools-toggle-page").enabled === true, "toggle context menu should stay enabled after restore");

  const bilingualState = await sendBackgroundMessage(backgroundListener, {
    type: "setReadingMode",
    tabID: 7,
    readingMode: "bilingual"
  });
  assert(bilingualState.readingMode === "bilingual", `expected bilingual reading mode, got ${bilingualState.readingMode}`);
  assert(bilingualState.readingModeLabel === "Bilingual", `expected English bilingual label, got ${bilingualState.readingModeLabel}`);
  assert(readingModeMessages.some((message) => message.mode === "bilingual"), "setReadingMode should be forwarded to content script");

  const pageScopeState = await sendBackgroundMessage(backgroundListener, {
    type: "setDiscoveryScope",
    tabID: 7,
    discoveryScope: "page"
  });
  assert(pageScopeState.discoveryScope === "page", `expected full-page discovery scope, got ${pageScopeState.discoveryScope}`);
  assert(pageScopeState.discoveryScopeLabel === "Full page pretranslation", `expected English full-page scope label, got ${pageScopeState.discoveryScopeLabel}`);

  const nativeCallsAfterFirstTranslate = nativeTranslatePayloads.length;
  await sendBackgroundMessage(backgroundListener, { type: "translatePage", tabID: 7 });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "background did not re-apply translations");
  assert(nativeTranslatePayloads.length === nativeCallsAfterFirstTranslate, "second translation should reuse persistent cache without native translateSegments");
  assert(startSessionMessages.at(-1)?.discoveryScope === "page", "translation should pass the selected full-page discovery scope to content script");

  const technicalQualityState = await sendBackgroundMessage(backgroundListener, {
    type: "setTranslationQuality",
    tabID: 7,
    translationQuality: "technical"
  });
  assert(technicalQualityState.translationQuality === "technical", `expected technical quality mode, got ${technicalQualityState.translationQuality}`);
  assert(technicalQualityState.translationQualityLabel === "Technical", `expected English technical quality label, got ${technicalQualityState.translationQualityLabel}`);

  const siteDefaultsState = await sendBackgroundMessage(backgroundListener, {
    type: "setDomainPageDefaults",
    tabID: 7,
    tabURL: "https://example.test/article",
    readingMode: "original",
    translationQuality: "literal",
    translationEngine: "fastMT"
  });
  assert(siteDefaultsState.domainReadingModeDefault === "original", `expected site reading default to be original, got ${siteDefaultsState.domainReadingModeDefault}`);
  assert(siteDefaultsState.domainTranslationQualityDefault === "literal", `expected site quality default to be literal, got ${siteDefaultsState.domainTranslationQualityDefault}`);
  assert(siteDefaultsState.domainTranslationEngineDefault === "fastMT", `expected site engine default to be fastMT, got ${siteDefaultsState.domainTranslationEngineDefault}`);
  assert(siteDefaultsState.readingMode === "original", `expected current page reading mode to follow site default, got ${siteDefaultsState.readingMode}`);
  assert(siteDefaultsState.translationQuality === "literal", `expected current page quality to follow site default, got ${siteDefaultsState.translationQuality}`);
  assert(siteDefaultsState.translationEngine === "fastMT", `expected current page engine to follow site default, got ${siteDefaultsState.translationEngine}`);
  assert(siteDefaultsState.notice === true, "saving site defaults should publish a notice state");
  assert(nativeDomainRules.domainReadingModes["example.test"] === "original", "native preferences should store the site reading default");
  assert(nativeDomainRules.domainTranslationQualities["example.test"] === "literal", "native preferences should store the site quality default");
  assert(nativeDomainRules.domainTranslationEngines["example.test"] === "fastMT", "native preferences should store the site engine default");
  assert(readingModeMessages.some((message) => message.mode === "original"), "saving a reading default should forward the mode to content script");

  const siteDefaultSyncedState = await sendBackgroundMessage(backgroundListener, { type: "getPopupState", tabID: 7 });
  assert(siteDefaultSyncedState.readingMode === "original", "getPopupState should preserve the site reading default when there is no current-page override");
  assert(siteDefaultSyncedState.translationQuality === "literal", "getPopupState should preserve the site quality default when there is no current-page override");
  assert(siteDefaultSyncedState.translationEngine === "fastMT", "getPopupState should preserve the site engine default");

  const nativeCallsBeforeEngineSwitchTranslate = nativeTranslatePayloads.length;
  await sendBackgroundMessage(backgroundListener, { type: "restorePage", tabID: 7 });
  appliedTranslations.length = 0;
  await sendBackgroundMessage(backgroundListener, { type: "translatePage", tabID: 7 });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "engine-isolated translation did not apply translations");
  assert(nativeTranslatePayloads.length === nativeCallsBeforeEngineSwitchTranslate + 1, "switching to fastMT should not reuse the existing LLM cache entries");
  assert(nativeTranslatePayloads.at(-1).translationEngine === "fastMT", "fastMT site default should be sent to native translateSegments");
  assert(Object.values(localStorageData.webPageTranslationCacheV2 || {}).some((entry) => entry.translationEngineID === "ctranslate2"), "translation cache v2 should isolate fastMT engine entries");

  const tabOverrideState = await sendBackgroundMessage(backgroundListener, {
    type: "setReadingMode",
    tabID: 7,
    readingMode: "bilingual"
  });
  assert(tabOverrideState.readingMode === "bilingual", "manual reading-mode change should override the site default for the current page");
  const tabOverrideSyncedState = await sendBackgroundMessage(backgroundListener, { type: "getPopupState", tabID: 7 });
  assert(tabOverrideSyncedState.readingMode === "bilingual", "getPopupState should not overwrite a current-page reading-mode override");

  const nativeCallsBeforeRetranslate = nativeTranslatePayloads.length;
  await sendBackgroundMessage(backgroundListener, {
    type: "retranslatePage",
    tabID: 7,
    tabURL: "https://example.test/article"
  });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "retranslate did not apply translations");
  assert(nativeTranslatePayloads.length === nativeCallsBeforeRetranslate + 1, "retranslate should clear page cache and call native translateSegments again");
  assert(nativeTranslatePayloads.at(-1).translationQuality === "literal", `expected retranslate payload to use site default literal quality, got ${nativeTranslatePayloads.at(-1).translationQuality}`);
  const retranslatedState = await sendBackgroundMessage(backgroundListener, { type: "getPopupState", tabID: 7 });
  assert(retranslatedState.hasTranslations === true, "retranslate should leave translated state");
  assert(retranslatedState.readingMode === "bilingual", "retranslate should preserve the current reading mode");
  assert(retranslatedState.translationQuality === "literal", "retranslate should preserve the site-default translation quality");

  const nativeCallsAfterRetranslate = nativeTranslatePayloads.length;
  const clearedState = await sendBackgroundMessage(backgroundListener, {
    type: "clearCurrentPageCache",
    tabID: 7,
    tabURL: "https://example.test/article"
  });
  assert(clearedState.status === "idle", `expected idle state after clearing cache, got ${clearedState.status}`);
  assert(clearedState.hasTranslations === false, "clear cache should clear translated state");
  assert(clearedState.notice === true, "clear page cache should publish a notice state");
  assert(clearedState.message.includes("Cleared 2 cached translations"), `unexpected clear cache message: ${clearedState.message}`);
  assert(appliedTranslations.length === 0, "clear cache should restore page translations");
  assert(Object.keys(localStorageData.webPageTranslationCacheV2 || {}).length === 0, "clear cache should remove current page storage entries");
  await sendBackgroundMessage(backgroundListener, { type: "translatePage", tabID: 7 });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "background did not translate after clearing cache");
  assert(nativeTranslatePayloads.length === nativeCallsAfterRetranslate + 1, "translation after clearing cache should call native translateSegments again");
  const activePageSessionID = startSessionMessages.at(-1)?.pageSessionID;
  assert(activePageSessionID, "translation job should pass a page session id to the content script");
  const nativeCallsBeforeStaleSegments = nativeTranslatePayloads.length;
  const appliedBeforeStaleSegments = appliedTranslations.length;
  const staleSegmentsResult = await sendBackgroundMessage(backgroundListener, {
    type: "segmentsDiscovered",
    pageSessionID: "stale-page-session",
    url: "https://example.test/article",
    title: "Test Article",
    segments: [{
      segmentID: "stale-dynamic-segment",
      text: "Stale dynamic text should not be translated.",
      tagName: "P",
      blockContext: "p",
      priority: 2,
      textHash: "stale-dynamic-hash"
    }]
  }, { tab: { id: 7 } });
  assert(staleSegmentsResult.ok === false && staleSegmentsResult.reason === "stale_page_session", "stale dynamic segments should be rejected by page session id");
  assert(nativeTranslatePayloads.length === nativeCallsBeforeStaleSegments, "stale dynamic segments should not call native translation");
  assert(appliedTranslations.length === appliedBeforeStaleSegments, "stale dynamic segments should not apply translations");
  const currentSegmentsResult = await sendBackgroundMessage(backgroundListener, {
    type: "segmentsDiscovered",
    pageSessionID: activePageSessionID,
    url: "https://example.test/article",
    title: "Test Article",
    segments: [{
      segmentID: "current-dynamic-segment",
      text: "Current dynamic text should be translated.",
      tagName: "P",
      blockContext: "p",
      priority: 2,
      textHash: "current-dynamic-hash"
    }]
  }, { tab: { id: 7 } });
  assert(currentSegmentsResult.ok === true, "current-session dynamic segments should still be accepted");
  await waitUntil(
    () => appliedTranslations.some((item) => item.segmentID === "current-dynamic-segment"),
    2_000,
    "current-session dynamic segment was not translated"
  );
  const failedDynamicStateStart = translationStateMessages.length;
  failingTranslationHashes.add("failing-dynamic-hash");
  const failedSegmentsResult = await sendBackgroundMessage(backgroundListener, {
    type: "segmentsDiscovered",
    pageSessionID: activePageSessionID,
    url: "https://example.test/article",
    title: "Test Article",
    segments: [{
      segmentID: "failing-dynamic-segment",
      text: "Current dynamic text should publish a scoped failure.",
      tagName: "P",
      blockContext: "p",
      priority: 2,
      textHash: "failing-dynamic-hash"
    }]
  }, { tab: { id: 7 } });
  assert(failedSegmentsResult.ok === true, "current-session dynamic failure segment should still be accepted for translation");
  await waitUntil(
    () => translationStateMessages.slice(failedDynamicStateStart).some((message) => message.state?.status === "failed"),
    2_000,
    "dynamic segment native failure did not publish failed state"
  );
  const failedDynamicState = translationStateMessages.slice(failedDynamicStateStart).find((message) => message.state?.status === "failed")?.state;
  assert(failedDynamicState?.message === "forced native translation failure", `unexpected dynamic failure message: ${failedDynamicState?.message}`);
  assert(failedDynamicState?.pageSessionID === activePageSessionID, "dynamic failure translationState should keep the active page session id");
  assert(failedDynamicState?.jobID, "dynamic failure translationState should keep the active job id");
  failingTranslationHashes.clear();
  const translationStateCountBeforeCancel = translationStateMessages.length;
  const cancelledState = await sendBackgroundMessage(backgroundListener, {
    type: "cancelTranslation",
    tabID: 7
  });
  const cancelTranslationStates = translationStateMessages.slice(translationStateCountBeforeCancel);
  assert(
    cancelTranslationStates.some((message) => message.state?.message === "Cancelling..." && message.state?.pageSessionID === activePageSessionID),
    "cancelling translationState should keep the active page session id"
  );
  assert(
    cancelTranslationStates.some((message) => message.state?.message === "Translation cancelled." && message.state?.pageSessionID === activePageSessionID),
    "cancelled translationState should keep the active page session id"
  );
  assert(cancelledState.pageSessionID === activePageSessionID, "cancelled popup state should keep the cancelled page session id");
  const routeChangedState = await sendBackgroundMessage(backgroundListener, {
    type: "llmToolsRouteChanged",
    tabID: 7,
    previousURL: "https://example.test/article",
    url: "https://example.test/spa-route"
  });
  assert(routeChangedState.status === "idle", `expected idle state after SPA route change, got ${routeChangedState.status}`);
  assert(routeChangedState.hasTranslations === false, "SPA route change should clear translated state");
  assert(routeChangedState.pageStateInvalidated === true, "SPA route change should mark page state invalidated");
  assert(routeChangedState.domain === "example.test", `expected SPA route state to keep normalized domain, got ${routeChangedState.domain}`);
  assert(routeChangedState.readingMode === "original", "SPA route change should reapply the site reading default");
  assert(routeChangedState.translationQuality === "literal", "SPA route change should reapply the site quality default");
  tabUpdatedListener(7, { status: "loading" }, { id: 7 });
  const reloadedState = await sendBackgroundMessage(backgroundListener, { type: "getPopupState", tabID: 7 });
  assert(reloadedState.status === "idle", `expected idle state after reload, got ${reloadedState.status}`);
  assert(reloadedState.hasTranslations === false, "reload should clear translated state");
  assert(contextMenuItems.get("llmtools-toggle-page").enabled === true, "toggle context menu should stay enabled after reload");

  appliedTranslations.length = 0;
  const autoRuleState = await sendBackgroundMessage(backgroundListener, {
    type: "setDomainRule",
    tabID: 7,
    tabURL: "https://example.test/article",
    rule: "alwaysTranslate"
  });
  assert(autoRuleState.domain === "example.test", `expected saved auto rule domain, got ${autoRuleState.domain}`);
  assert(autoRuleState.domainRule === "alwaysTranslate", `expected saved auto rule, got ${autoRuleState.domainRule}`);
  assert(autoRuleState.notice === true, "saving an auto-translate rule should publish a notice state");
  assert(nativeDomainRules.autoTranslateDomains.includes("example.test"), "expected auto-translate domain rule in native preferences");
  assert(!nativeDomainRules.disabledDomains.includes("example.test"), "auto-translate rule should remove any native disabled rule");
  assert(Object.keys(localStorageData.webPageDomainRulesV1 || {}).length === 0, "native domain rule save should clear extension fallback rules");
  tabUpdatedListener(7, { status: "loading" }, { id: 7, url: "https://example.test/article" });
  tabUpdatedListener(7, { status: "complete" }, { id: 7, url: "https://example.test/article" });
  await waitUntil(
    () => popupStates.some((message) => message.state?.message === "example.test needs Chrome site permission before auto-translation can run."),
    2_000,
    "auto-translate without host permission did not publish a permission notice"
  );
  assert(appliedTranslations.length === 0, "auto-translate should wait for host permission before translating");
  for (const origin of [
    "http://example.test/*",
    "https://example.test/*",
    "http://*.example.test/*",
    "https://*.example.test/*"
  ]) {
    grantedOrigins.add(origin);
  }
  tabUpdatedListener(7, { status: "loading" }, { id: 7, url: "https://example.test/article" });
  tabUpdatedListener(7, { status: "complete" }, { id: 7, url: "https://example.test/article" });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "auto-translate rule did not translate after page load");
  const autoTranslatedState = await sendBackgroundMessage(backgroundListener, { type: "getPopupState", tabID: 7 });
  assert(autoTranslatedState.domainRule === "alwaysTranslate", `expected auto translated state to keep auto rule, got ${autoTranslatedState.domainRule}`);
  assert(autoTranslatedState.hasTranslations === true, "auto-translate should leave translated state");

  await sendBackgroundMessage(backgroundListener, { type: "restorePage", tabID: 7 });
  const neverRuleState = await sendBackgroundMessage(backgroundListener, {
    type: "setDomainRule",
    tabID: 7,
    tabURL: "https://example.test/article",
    rule: "neverTranslate"
  });
  assert(neverRuleState.domainRule === "neverTranslate", `expected saved never rule, got ${neverRuleState.domainRule}`);
  assert(neverRuleState.notice === true, "saving a never-translate rule should publish a notice state");
  assert(nativeDomainRules.disabledDomains.includes("example.test"), "expected never-translate domain rule in native preferences");
  assert(!nativeDomainRules.autoTranslateDomains.includes("example.test"), "never-translate rule should remove any native auto rule");
  const nativeCallsBeforeBlockedMenu = nativeTranslatePayloads.length;
  appliedTranslations.length = 0;
  contextMenuClickListener({ menuItemId: "llmtools-toggle-page" }, { id: 7 });
  await waitUntil(
    () => popupStates.some((message) => message.state?.message === "example.test is set to never translate."),
    2_000,
    "never-translate rule did not publish blocked context-menu state"
  );
  assert(
    popupStates.some((message) => message.state?.message === "example.test is set to never translate." && message.state?.notice === true),
    "blocked context-menu translation should publish a notice state"
  );
  assert(appliedTranslations.length === 0, "never-translate rule should block context-menu translation");
  assert(nativeTranslatePayloads.length === nativeCallsBeforeBlockedMenu, "blocked context-menu translation should not call native translateSegments");
  await sendBackgroundMessage(backgroundListener, {
    type: "translatePage",
    tabID: 7,
    tabURL: "https://example.test/article"
  });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "popup manual translation should override never-translate rule");
  assert(Object.values(localStorageData.webPageTranslationCacheV2 || {}).every((entry) => entry.domain === "example.test"), "translation cache entries should include the normalized domain");
  assert(Object.values(localStorageData.webPageTranslationCacheV2 || {}).every((entry) => entry.translationEngineID), "translation cache v2 entries should include the engine id");
  assert(Object.values(localStorageData.webPageTranslationCacheV2 || {}).every((entry) => entry.translationEngineModelID), "translation cache v2 entries should include the engine model id");
  assert(Object.values(localStorageData.webPageTranslationCacheV2 || {}).some((entry) => entry.translationEngineID === "ctranslate2"), "translation cache v2 should include fastMT engine entries after engine override");
  assert(Object.values(localStorageData.webPageTranslationCacheV2 || {}).every((entry) => entry.sourceLanguage === "auto"), "translation cache v2 entries should key entries by the requested auto source language");
  assert(Object.values(localStorageData.webPageTranslationCacheV2 || {}).every((entry) => entry.detectedSourceLanguage === "en"), "translation cache v2 entries should retain the detected source language for diagnostics");
  const domainClearedState = await sendBackgroundMessage(backgroundListener, {
    type: "clearCurrentDomainCache",
    tabID: 7,
    tabURL: "https://example.test/article"
  });
  assert(domainClearedState.status === "idle", `expected idle state after clearing domain cache, got ${domainClearedState.status}`);
  assert(domainClearedState.notice === true, "clear domain cache should publish a notice state");
  assert(domainClearedState.message.includes("Cleared 3 cached translations"), `unexpected domain clear cache message: ${domainClearedState.message}`);
  assert(Object.keys(localStorageData.webPageTranslationCacheV2 || {}).length === 0, "clear domain cache should remove current domain storage entries");

  await sendBackgroundMessage(backgroundListener, {
    type: "translatePage",
    tabID: 7,
    tabURL: "https://example.test/article"
  });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "background did not translate after clearing domain cache");
  assert(Object.keys(localStorageData.webPageTranslationCacheV2 || {}).length > 0, "translation after clearing domain cache should repopulate storage cache");
  const allClearedState = await sendBackgroundMessage(backgroundListener, { type: "clearAllPageCache", tabID: 7 });
  assert(allClearedState.status === "idle", `expected idle state after clearing all cache, got ${allClearedState.status}`);
  assert(allClearedState.notice === true, "clear all cache should publish a notice state");
  assert(allClearedState.message.includes("Cleared all 2 cached webpage translations"), `unexpected all clear cache message: ${allClearedState.message}`);
  assert(Object.keys(localStorageData.webPageTranslationCacheV2 || {}).length === 0, "clear all cache should remove all storage entries");

  currentUnsupportedEmbeddedContent = { frames: 1, shadowRoots: 1, canvas: 1, images: 1, pdf: 1, total: 5 };
  appliedTranslations.length = 0;
  await sendBackgroundMessage(backgroundListener, {
    type: "translatePage",
    tabID: 7,
    tabURL: "https://example.test/article"
  });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "background did not translate with unsupported embedded content");
  const unsupportedState = await sendBackgroundMessage(backgroundListener, { type: "getPopupState", tabID: 7 });
  assert(unsupportedState.unsupportedEmbeddedContent?.shadowRoots === 1, "popup state should include closed shadow/component counts");
  assert(unsupportedState.unsupportedEmbeddedContent?.total === 5, "popup state should include unsupported embedded content counts");
  assert(unsupportedState.diagnostics?.counts?.unsupportedEmbeddedContent?.shadowRoots === 1, "diagnostics should include closed shadow/component counts");
  assert(unsupportedState.diagnostics?.counts?.unsupportedEmbeddedContent?.total === 5, "diagnostics should include unsupported embedded content counts");
  assert(
    unsupportedState.message.includes("Some embedded content cannot be translated yet") && unsupportedState.message.includes("closed Shadow DOM/component content"),
    `expected unsupported embedded content notice, got ${unsupportedState.message}`
  );
  assertOnlyTranslationNativeRequestsCarryPageText(nativeMessages, [
    "Repeated label for duplicate translation.",
    "The quick brown fox jumps over the lazy dog.",
    "重复标签",
    "敏捷的棕色狐狸跳过懒狗。"
  ]);
  for (const message of popupStates) {
    const diagnosticsJSON = JSON.stringify(message.state?.diagnostics || {});
    assert(!diagnosticsJSON.includes("Repeated label"), "published diagnostics should not include raw source text");
    assert(!diagnosticsJSON.includes("重复标签"), "published diagnostics should not include translated text");
  }
}

async function runPopupPermissionCheck() {
  const source = await fs.readFile(path.join(extensionRoot, "popup.js"), "utf8");
  const runtimeMessages = [];
  const permissionRequests = [];
  let permissionGranted = false;

  function element() {
    return {
      textContent: "",
      title: "",
      disabled: false,
      value: "ask",
      style: {},
      options: [{}, {}, {}],
      listeners: {},
      addEventListener(type, listener) {
        this.listeners[type] = listener;
      },
      setAttribute(name, value) {
        this[name] = value;
      }
    };
  }

  const elements = Object.fromEntries([
    "status",
    "model",
    "bar",
    "domain",
    "domainRule",
    "diagnostics",
        "readingMode",
        "discoveryScope",
        "translationQuality",
        "pendingIndicatorStyle",
    "saveReadingDefault",
    "saveQualityDefault",
    "translate",
    "retranslate",
    "restore",
    "cancel",
    "statusBtn",
    "clearPageCache",
    "clearDomainCache",
    "clearAllCache"
  ].map((id) => [id, element()]));

  const document = {
    documentElement: { lang: "zh-Hans" },
    getElementById(id) {
      return elements[id];
    }
  };

  const chrome = {
    tabs: {
      query() {
        return Promise.resolve([{ id: 7, url: "https://www.example.test/article" }]);
      }
    },
    permissions: {
      request(permission) {
        permissionRequests.push(permission);
        return Promise.resolve(permissionGranted);
      }
    },
    runtime: {
      sendMessage(message) {
        runtimeMessages.push(message);
        return Promise.resolve({
          status: "idle",
          message: message.type === "setDomainRule" ? `rule:${message.rule}` : "Ready",
          appLanguage: "en",
          modelName: "stub-model",
          done: 0,
          total: 0,
          hasTranslations: false,
          canClearCache: true,
          domain: "example.test",
            domainRule: message.rule || "ask",
            readingMode: message.readingMode || "replace",
            discoveryScope: message.discoveryScope || "visible",
            translationQuality: message.translationQuality || "natural",
            pendingIndicatorStyle: message.pendingIndicatorStyle || "loading",
          diagnostics: {
            browserID: "chrome",
            extensionVersion: "0.3.0",
            status: "idle",
            domainHash: "h12345678",
            urlHash: "abcdef1234567890",
            counts: { done: 0, total: 0, failed: 0 },
            timings: { elapsedMs: 12 },
            model: { name: "stub-model" },
            translation: { engineID: "ctranslate2", detectedSource: "en" },
            errorCode: ""
          }
        });
      },
      onMessage: {
        addListener() {}
      }
    }
  };

  const context = vm.createContext({
    chrome,
    document,
    console,
    URL
  });
  vm.runInContext(source, context, { filename: "popup.js" });
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert(elements.diagnostics.textContent.includes("Diagnostics"), "popup should render a redacted diagnostics summary");
  assert(elements.diagnostics.textContent.includes("source en"), "popup diagnostics should render the detected source language");
  assert(elements.diagnostics.textContent.includes("h12345678"), "popup diagnostics should show the domain hash");
  assert(!elements.diagnostics.textContent.includes("example.test"), "popup diagnostics should not include the raw domain");

  elements.domainRule.value = "alwaysTranslate";
  permissionGranted = false;
  await elements.domainRule.listeners.change();
  assert(permissionRequests.length === 1, "auto-translate selection should request host permission");
  assert(
    permissionRequests[0].origins.includes("https://example.test/*")
      && permissionRequests[0].origins.includes("https://*.example.test/*"),
    `unexpected permission origins: ${permissionRequests[0].origins.join(",")}`
  );
  assert(
    runtimeMessages.some((message) => message.type === "setDomainRule" && message.rule === "ask"),
    "denied auto-translate permission should save ask rule"
  );

  runtimeMessages.length = 0;
  permissionRequests.length = 0;
  elements.domainRule.value = "alwaysTranslate";
  permissionGranted = true;
  await elements.domainRule.listeners.change();
  assert(permissionRequests.length === 1, "granted auto-translate selection should request host permission once");
  assert(
    runtimeMessages.some((message) => message.type === "setDomainRule" && message.rule === "alwaysTranslate"),
    "granted auto-translate permission should save alwaysTranslate rule"
  );

  runtimeMessages.length = 0;
  elements.readingMode.value = "bilingual";
  await elements.readingMode.listeners.change();
  assert(
    runtimeMessages.some((message) => message.type === "setReadingMode" && message.readingMode === "bilingual"),
    "reading mode selector should save bilingual mode"
  );

  runtimeMessages.length = 0;
  elements.discoveryScope.value = "page";
  await elements.discoveryScope.listeners.change();
  assert(
    runtimeMessages.some((message) => message.type === "setDiscoveryScope" && message.discoveryScope === "page"),
    "discovery scope selector should save full-page scope"
  );

  runtimeMessages.length = 0;
  elements.translationQuality.value = "technical";
  await elements.translationQuality.listeners.change();
  assert(
    runtimeMessages.some((message) => message.type === "setTranslationQuality" && message.translationQuality === "technical"),
    "translation quality selector should save technical mode"
  );

  runtimeMessages.length = 0;
  elements.pendingIndicatorStyle.value = "flipText";
  await elements.pendingIndicatorStyle.listeners.change();
  assert(
    runtimeMessages.some((message) => message.type === "setPendingIndicatorStyle" && message.pendingIndicatorStyle === "flipText"),
    "pending style selector should save flip text mode"
  );

  runtimeMessages.length = 0;
  elements.readingMode.value = "bilingual";
  await elements.saveReadingDefault.listeners.click();
  assert(
    runtimeMessages.some((message) => message.type === "setDomainPageDefaults" && message.readingMode === "bilingual"),
    "site reading default button should save the selected reading mode"
  );

  runtimeMessages.length = 0;
  elements.translationQuality.value = "technical";
  await elements.saveQualityDefault.listeners.click();
  assert(
    runtimeMessages.some((message) => message.type === "setDomainPageDefaults" && message.translationQuality === "technical"),
    "site quality default button should save the selected translation quality"
  );

  runtimeMessages.length = 0;
  elements.discoveryScope.value = "page";
  await elements.translate.listeners.click();
  assert(
    runtimeMessages.some((message) => message.type === "translatePage" && message.discoveryScope === "page"),
    "translate button should pass the selected discovery scope"
  );

  runtimeMessages.length = 0;
  await elements.retranslate.listeners.click();
  assert(
    runtimeMessages.some((message) => message.type === "retranslatePage" && message.discoveryScope === "page"),
    "retranslate button should pass the selected discovery scope"
  );
}

async function runContentScriptDomCheck(browserTarget) {
  await fs.access(browserTarget.path);
  const profileDir = await fs.mkdtemp(path.join(os.tmpdir(), `llmtools-${browserTarget.id}-extension-dom-`));
  const browserProcess = spawn(browserTarget.path, [
    "--headless=new",
    "--disable-gpu",
    "--no-first-run",
    "--no-default-browser-check",
    "--remote-allow-origins=*",
    "--remote-debugging-port=0",
    `--user-data-dir=${profileDir}`,
    "about:blank"
  ], { stdio: ["ignore", "pipe", "pipe"] });

  let stderr = "";
  browserProcess.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  let client;
  try {
    const { port } = await waitForDevToolsPort(profileDir);
    const pageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "article.html")).href;
    const target = await createPageTarget(port, pageURL);
    client = await CDPClient.connect(target.webSocketDebuggerUrl);
    const runtimeErrors = [];
    client.on("Runtime.exceptionThrown", (event) => {
      runtimeErrors.push(formatRuntimeException(event));
    });
    client.on("Runtime.consoleAPICalled", (event) => {
      if (event.type === "error" || event.type === "assert") {
        runtimeErrors.push(formatRuntimeConsoleError(event));
      }
    });

    await client.send("Page.enable");
    await client.send("Runtime.enable");
    await waitForReadyState(client, "complete");

    const source = await fs.readFile(path.join(extensionRoot, "contentScript.js"), "utf8");
    await installContentScriptInPage(client, source);
    const startResult = await sendContentMessage(client, { type: "startSession", pageSessionID: "dom-check-session" });

    assert(startResult.ok === true, "content script did not start a session");
    assert(Array.isArray(startResult.segments) && startResult.segments.length > 0, "expected visible segments");
    const duplicateSegments = startResult.segments.filter((segment) => segment.text === "Repeated label for duplicate translation.");
    assert(duplicateSegments.length === 2, `expected two duplicate text segments, got ${duplicateSegments.length}`);
    assert(new Set(duplicateSegments.map((segment) => segment.textHash)).size === 1, "expected duplicate text to share the same textHash");
    assert(startResult.segments.some((segment) => segment.text.includes("設定を変更すると")), "Japanese page text should be discovered for translation");
    assert(!startResult.segments.some((segment) => segment.text.includes("这段中文不应该进入翻译队列")), "Chinese target-language text should not be rediscovered for translation");
    assert(!startResult.segments.some((segment) => segment.text.includes("Code blocks should not be translated")), "code block text should be skipped");
    assert(!startResult.segments.some((segment) => segment.text.includes("Do not translate input values")), "input value text should be skipped");
    const initialSpinnerState = await evaluate(client, `
      (() => ({
        spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length,
        styleCount: document.querySelectorAll("style[data-llm-tools-spinner-style='true']").length,
        spinnerText: Array.from(document.querySelectorAll(".llmtools-segment-spinner")).map((node) => node.textContent).join(""),
        spinnerLabels: Array.from(document.querySelectorAll(".llmtools-segment-spinner")).map((node) => node.getAttribute("aria-label"))
      }))()
    `);
    assert(initialSpinnerState.spinnerCount === startResult.segments.length, `expected one spinner per segment, got ${initialSpinnerState.spinnerCount}/${startResult.segments.length}`);
    assert(initialSpinnerState.styleCount === 1, "expected one shared spinner style tag");
    assert(initialSpinnerState.spinnerText === "", "segment spinners should not add visible text content");
    assert(initialSpinnerState.spinnerLabels.every((label) => label === "正在翻译"), "default content-script spinner label should use Chinese app language");
    assert(startResult.pageSessionID === "dom-check-session", `expected start session response to include page session id, got ${startResult.pageSessionID}`);

    const staleApplyResult = await sendContentMessage(client, {
      type: "applyTranslations",
      pageSessionID: "stale-dom-check-session",
      translations: [{
        segmentID: startResult.segments[0].segmentID,
        status: "translated",
        translation: "错误会话译文不应出现"
      }]
    });
    assert(staleApplyResult.ok === false && staleApplyResult.reason === "stale_page_session", "content script should reject stale applyTranslations page session");
    const staleApplyDomState = await evaluate(client, "document.documentElement.textContent");
    assert(!staleApplyDomState.includes("错误会话译文不应出现"), "stale applyTranslations should not update the page DOM");

    const translations = startResult.segments.map((segment, index) => ({
      segmentID: segment.segmentID,
      status: "translated",
      translation: segment.text === "Repeated label for duplicate translation." ? "重复标签" : `译文 ${index + 1}`
    }));
    await sendContentMessage(client, { type: "applyTranslations", pageSessionID: startResult.pageSessionID, translations });
    const pageTranslationState = await sendContentMessage(client, { type: "getPageTranslationState" });
    assert(pageTranslationState.hasTranslations === true, "content script should report translated page state");
    assert(pageTranslationState.translatedCount === translations.length, "content script should report translated segment count");
    const translatedState = await evaluate(client, `
      (() => ({
        duplicates: Array.from(document.querySelectorAll("[data-duplicate]")).map((node) => node.textContent.trim()),
        code: document.querySelector("code").textContent,
        inputValue: document.querySelector("input").value,
        linkHref: document.querySelector("a").href,
        overlayText: document.documentElement.textContent,
        spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length
      }))()
    `);
    assert(translatedState.duplicates.every((text) => text === "重复标签"), "expected all duplicate nodes to be translated");
    assert(translatedState.code.includes("Code blocks should not be translated"), "code block should remain unchanged");
    assert(translatedState.inputValue === "Do not translate input values", "input value should remain unchanged");
    assert(translatedState.linkHref === "https://example.com/", "link href should remain unchanged");
    assert(!translatedState.overlayText.includes("CancelRestore"), "overlay controls should live in shadow DOM, not page text");
    assert(translatedState.spinnerCount === 0, "segment spinners should be removed after translations apply");

    await sendContentMessage(client, { type: "setReadingMode", mode: "bilingual" });
    const bilingualState = await evaluate(client, `
      (() => ({
        wrapperCount: document.querySelectorAll(".llmtools-bilingual").length,
        duplicateTexts: Array.from(document.querySelectorAll("[data-duplicate]")).map((node) => node.textContent.trim()),
        pageText: document.documentElement.textContent,
        code: document.querySelector("code").textContent
      }))()
    `);
    assert(bilingualState.wrapperCount === translations.length, `expected one bilingual wrapper per translated segment, got ${bilingualState.wrapperCount}/${translations.length}`);
    assert(bilingualState.duplicateTexts.every((text) => text.includes("重复标签") && text.includes("Repeated label for duplicate translation.")), "bilingual mode should show translation and original duplicate text");
    assert(bilingualState.pageText.includes("The quick brown fox jumps over the lazy dog."), "bilingual mode should keep original text visible");
    assert(bilingualState.code.includes("Code blocks should not be translated"), "bilingual mode should leave code block unchanged");

    const originalModeState = await sendContentMessage(client, { type: "setReadingMode", mode: "original" });
    assert(originalModeState.readingMode === "original", `expected content state to report original mode, got ${originalModeState.readingMode}`);
    const originalDomState = await evaluate(client, `
      (() => ({
        wrapperCount: document.querySelectorAll(".llmtools-bilingual").length,
        duplicates: Array.from(document.querySelectorAll("[data-duplicate]")).map((node) => node.textContent.trim()),
        pageText: document.documentElement.textContent
      }))()
    `);
    assert(originalDomState.wrapperCount === 0, "original mode should remove bilingual wrappers");
    assert(originalDomState.duplicates.every((text) => text === "Repeated label for duplicate translation."), "original mode should show original duplicate text");
    assert(!originalDomState.pageText.includes("重复标签"), "original mode should hide translated duplicate text without clearing translation state");

    const replaceModeState = await sendContentMessage(client, { type: "setReadingMode", mode: "replace" });
    assert(replaceModeState.readingMode === "replace", `expected content state to report replace mode, got ${replaceModeState.readingMode}`);
    const replaceDomState = await evaluate(client, `
      (() => ({
        wrapperCount: document.querySelectorAll(".llmtools-bilingual").length,
        duplicates: Array.from(document.querySelectorAll("[data-duplicate]")).map((node) => node.textContent.trim()),
        pageText: document.documentElement.textContent
      }))()
    `);
    assert(replaceDomState.wrapperCount === 0, "replace mode should not leave bilingual wrappers");
    assert(replaceDomState.duplicates.every((text) => text === "重复标签"), "replace mode should show translated duplicate text again");
    assert(!replaceDomState.pageText.includes("Repeated label for duplicate translation.Repeated label for duplicate translation."), "replace mode should not duplicate original text");

    const staleTranslationStateResult = await sendContentMessage(client, {
      type: "translationState",
      state: {
        pageSessionID: "stale-dom-check-session",
        status: "translating",
        message: "Stale translation state should not appear.",
        done: 1,
        total: 4,
        failed: 0,
        hasTranslations: true
      }
    });
    assert(
      staleTranslationStateResult.ok === false && staleTranslationStateResult.reason === "stale_page_session",
      "content script should reject stale translationState page session"
    );
    const afterStaleTranslationState = await sendContentMessage(client, { type: "getPageTranslationState" });
    assert(
      afterStaleTranslationState.overlayMessage !== "Stale translation state should not appear.",
      "stale translationState should not update the overlay message"
    );

    await sendContentMessage(client, {
      type: "translationState",
      state: {
        pageSessionID: startResult.pageSessionID,
        status: "translating",
        message: "Translating 2/4 segments...",
        done: 2,
        total: 4,
        failed: 0,
        hasTranslations: true
      }
    });

    const incrementalText = "Incremental content appears after scrolling.";
    await evaluate(client, `
      (() => {
        const p = document.createElement("p");
        p.dataset.incremental = "true";
        p.textContent = ${JSON.stringify(incrementalText)};
        document.querySelector("main").appendChild(p);
        return true;
      })()
    `);
    await evaluate(client, "new Promise((resolve) => setTimeout(resolve, 700))");
    const messages = await evaluate(client, "window.__llmToolsMessages");
    assert(
      messages.some((message) => message.type === "segmentsDiscovered" && message.segments?.some((segment) => segment.text === incrementalText)),
      "expected incremental visible text to be reported"
    );
    const incrementalSpinnerState = await evaluate(client, `
      (() => ({
        spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length,
        incrementalHasSpinner: Boolean(document.querySelector("[data-incremental] .llmtools-segment-spinner"))
      }))()
    `);
    assert(incrementalSpinnerState.spinnerCount > 0, "incremental discovered text should show a pending spinner");
    assert(incrementalSpinnerState.incrementalHasSpinner === true, "incremental paragraph should contain a pending spinner");

    await sendContentMessage(client, { type: "cancel" });
    const cancelledState = await sendContentMessage(client, { type: "getPageTranslationState" });
    assert(cancelledState.cancelled === true, "content script should report cancelled state after cancel");
    assert(cancelledState.overlayMessage === "已取消", `cancel should keep localized overlay message, got ${cancelledState.overlayMessage}`);
    const lateTranslationResult = await sendContentMessage(client, {
      type: "applyTranslations",
      translations: [{
        segmentID: startResult.segments[0].segmentID,
        status: "translated",
        translation: "迟到译文不应出现"
      }]
    });
    assert(lateTranslationResult.cancelled === true, "late translations should be acknowledged as ignored after cancel");
    const cancelledAfterLateState = await sendContentMessage(client, { type: "getPageTranslationState" });
    assert(cancelledAfterLateState.overlayMessage === "已取消", "late translations should not overwrite the cancelled overlay message");
    const postCancelDomState = await evaluate(client, `
      (() => ({
        pageText: document.documentElement.textContent,
        spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length
      }))()
    `);
    assert(!postCancelDomState.pageText.includes("迟到译文不应出现"), "late translations should not be applied after cancel");
    assert(postCancelDomState.spinnerCount === 0, "cancel should remove pending segment spinners");

    await sendContentMessage(client, { type: "restore" });
    const pageRestoredTranslationState = await sendContentMessage(client, { type: "getPageTranslationState" });
    assert(pageRestoredTranslationState.hasTranslations === false, "content script should report restored page state");
    assert(pageRestoredTranslationState.translatedCount === 0, "content script should clear translated segment count after restore");
    const restoredState = await evaluate(client, `
      (() => ({
        duplicates: Array.from(document.querySelectorAll("[data-duplicate]")).map((node) => node.textContent.trim()),
        code: document.querySelector("code").textContent,
        inputValue: document.querySelector("input").value,
        spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length
      }))()
    `);
    assert(restoredState.duplicates.every((text) => text === "Repeated label for duplicate translation."), "restore should return duplicate nodes to original text");
    assert(restoredState.code.includes("Code blocks should not be translated"), "restore should leave code block unchanged");
    assert(restoredState.inputValue === "Do not translate input values", "restore should leave input value unchanged");
    assert(restoredState.spinnerCount === 0, "restore should remove pending segment spinners");
    await assertNoPageTextNetworkCalls(client, [
      "The quick brown fox jumps over the lazy dog.",
      "Repeated label for duplicate translation.",
      "译文",
      "重复标签"
    ], "article fixture");

    await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "dom-check-session-after-cancel",
      pendingIndicatorStyle: "none"
    });
    await evaluate(client, "window.__llmToolsMessages = []");
    const postCancelIncrementalText = "Post-cancel restarted session discovers new content.";
    await evaluate(client, `
      (() => {
        const p = document.createElement("p");
        p.dataset.postCancelIncremental = "true";
        p.textContent = ${JSON.stringify(postCancelIncrementalText)};
        document.querySelector("main").appendChild(p);
        return true;
      })()
    `);
    await evaluate(client, "new Promise((resolve) => setTimeout(resolve, 700))");
    const postCancelMessages = await evaluate(client, "window.__llmToolsMessages");
    assert(
      postCancelMessages.some((message) => message.type === "segmentsDiscovered" && message.segments?.some((segment) => segment.text === postCancelIncrementalText)),
      "a new session after cancel should resume dynamic discovery"
    );
    await sendContentMessage(client, { type: "restore" });

    await sendContentMessage(client, {
      type: "translationState",
      state: {
        status: "idle",
        message: "example.test is set to never translate.",
        done: 0,
        total: 0,
        failed: 0,
        hasTranslations: false,
        notice: true
      }
    });
    const noticeOverlayState = await evaluate(client, `
      (() => ({
        overlayPresent: Boolean(document.querySelector("html > div[style*='z-index: 2147483647']")),
        pageText: document.documentElement.textContent
      }))()
    `);
    assert(noticeOverlayState.overlayPresent === true, "idle notice state should show the overlay");
    assert(!noticeOverlayState.pageText.includes("example.test is set to never translate."), "idle notice overlay should stay out of page text");
    await evaluate(client, "new Promise((resolve) => setTimeout(resolve, 4300))");
    const noticeOverlayAfter = await evaluate(client, "Boolean(document.querySelector(\"html > div[style*='z-index: 2147483647']\"))");
    assert(noticeOverlayAfter === false, "idle notice overlay should auto-hide");

    await evaluate(client, "window.__llmToolsMessages = []");
    const flipStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "flip-style-check",
      pendingIndicatorStyle: "flipText"
    });
    const flipInitialState = await evaluate(client, `
      (() => ({
        spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length,
        flipCount: document.querySelectorAll(".llmtools-segment-flip").length,
        pendingCount: document.querySelectorAll(".llmtools-segment-flip-pending").length,
        completeCount: document.querySelectorAll(".llmtools-segment-flip-complete").length,
        tileCount: document.querySelectorAll(".llmtools-segment-flip-tile").length
      }))()
    `);
    assert(flipInitialState.spinnerCount === 0, "flip text style should not show segment spinners while pending");
    assert(flipInitialState.flipCount === flipStartResult.segments.length, `expected one pending flip wrapper per segment, got ${flipInitialState.flipCount}/${flipStartResult.segments.length}`);
    assert(flipInitialState.pendingCount === flipStartResult.segments.length, "flip text style should start in pending swing state");
    assert(flipInitialState.completeCount === 0, "flip text style should not start in complete state");
    assert(flipInitialState.tileCount > flipInitialState.flipCount, "flip text style should split text into left-to-right blocks");
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: flipStartResult.segments.map((segment, index) => ({
        segmentID: segment.segmentID,
        status: "translated",
        translation: `README.md yesterday ${index + 1}`
      }))
    });
    const flipAnimatingState = await evaluate(client, `
      (() => ({
        flipCount: document.querySelectorAll(".llmtools-segment-flip").length,
        pendingCount: document.querySelectorAll(".llmtools-segment-flip-pending").length,
        completeCount: document.querySelectorAll(".llmtools-segment-flip-complete").length,
        tileCount: document.querySelectorAll(".llmtools-segment-flip-tile").length,
        flipTexts: Array.from(document.querySelectorAll(".llmtools-segment-flip")).map((node) => node.textContent || ""),
        flipFinalTexts: Array.from(document.querySelectorAll(".llmtools-segment-flip")).map((node) => node.dataset.llmToolsFinalText || ""),
        styleCount: document.querySelectorAll("style[data-llm-tools-spinner-style='true']").length
      }))()
    `);
    assert(flipAnimatingState.flipCount === flipStartResult.segments.length, `expected all flip text indicators while animating, got ${flipAnimatingState.flipCount}`);
    assert(flipAnimatingState.pendingCount === 0, "translated flip indicators should leave pending swing state");
    assert(flipAnimatingState.completeCount === flipStartResult.segments.length, "translated flip indicators should enter complete flip state");
    assert(flipAnimatingState.tileCount > flipAnimatingState.flipCount, "complete flip state should keep left-to-right block tiles");
    assert(flipAnimatingState.flipFinalTexts.some((text) => text.includes("README.md yesterday")), "flip text indicator should retain the translated text");
    assert(flipAnimatingState.styleCount === 1, "flip text style should reuse the shared indicator style tag");
    await evaluate(client, "new Promise((resolve) => setTimeout(resolve, 1900))");
    const flipSettledState = await evaluate(client, `
      (() => ({
        flipCount: document.querySelectorAll(".llmtools-segment-flip").length,
        pageText: document.documentElement.textContent
      }))()
    `);
    assert(flipSettledState.flipCount === 0, "flip text indicator should settle back to a plain text node");
    assert(flipSettledState.pageText.includes("README.md yesterday 1"), "settled flip text translation should remain visible");
    await evaluate(client, "new Promise((resolve) => setTimeout(resolve, 700))");
    const postFlipMessages = await evaluate(client, "window.__llmToolsMessages");
    assert(
      !postFlipMessages.some((message) => message.type === "segmentsDiscovered" && message.segments?.some((segment) => segment.text.includes("README.md yesterday"))),
      "settled flip text that still contains English should not be rediscovered as new segments"
    );
    await sendContentMessage(client, { type: "restore" });

    await evaluate(client, "window.__llmToolsMessages = []");
    await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "flip-stale-cleanup-check",
      pendingIndicatorStyle: "flipText"
    });
    const stalePendingBefore = await evaluate(client, "document.querySelectorAll('.llmtools-segment-flip-pending').length");
    assert(stalePendingBefore > 0, "stale cleanup check should start with pending flip indicators");
    await sendContentMessage(client, {
      type: "translationState",
      state: {
        status: "translated",
        message: "Translated 0/0 segments.",
        done: 0,
        total: 0,
        failed: 0,
        hasTranslations: false
      }
    });
    await evaluate(client, "new Promise((resolve) => setTimeout(resolve, 3300))");
    const stalePendingAfter = await evaluate(client, `
      (() => ({
        flipCount: document.querySelectorAll(".llmtools-segment-flip").length,
        messages: window.__llmToolsMessages
      }))()
    `);
    assert(stalePendingAfter.flipCount === 0, "terminal translation state should clear stale pending flip indicators");
    assert(
      !stalePendingAfter.messages.some((message) => message.type === "segmentsDiscovered"),
      "stale pending cleanup should not rediscover restored original text"
    );
    await sendContentMessage(client, { type: "restore" });

    const noneStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "none-style-check",
      pendingIndicatorStyle: "none"
    });
    const noneInitialState = await evaluate(client, `
      (() => ({
        spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length,
        flipCount: document.querySelectorAll(".llmtools-segment-flip").length
      }))()
    `);
    assert(noneStartResult.segments.length > 0, "none style session should still discover segments");
    assert(noneInitialState.spinnerCount === 0, "none style should not show segment spinners");
    assert(noneInitialState.flipCount === 0, "none style should not show flip indicators");
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: noneStartResult.segments.slice(0, 1).map((segment) => ({
        segmentID: segment.segmentID,
        status: "translated",
        translation: "无样式译文"
      }))
    });
    const noneTranslatedState = await evaluate(client, `
      (() => ({
        spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length,
        flipCount: document.querySelectorAll(".llmtools-segment-flip").length,
        pageText: document.documentElement.textContent
      }))()
    `);
    assert(noneTranslatedState.spinnerCount === 0, "none style should not leave segment spinners after translation");
    assert(noneTranslatedState.flipCount === 0, "none style should not create flip indicators after translation");
    assert(noneTranslatedState.pageText.includes("无样式译文"), "none style should still apply translations");
    await sendContentMessage(client, { type: "restore" });

    await sendContentMessage(client, { type: "startSession", pageSessionID: "invalidated-context-check" });
    await sendContentMessage(client, {
      type: "translationState",
      state: {
        status: "translated",
        message: "Translated 1/1 segments.",
        done: 1,
        total: 1,
        failed: 0,
        hasTranslations: true
      }
    });
    const invalidatedResult = await evaluate(client, `
      (async () => {
        window.__llmToolsSendMessageMode = "throw";
        window.chrome.runtime.sendMessage = () => {
          throw new Error("Extension context invalidated.");
        };
        const before = {
          spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length,
          overlayPresent: Boolean(document.querySelector("html > div[style*='z-index: 2147483647']"))
        };
        try {
          const p = document.createElement("p");
          p.dataset.invalidatedIncremental = "true";
          p.textContent = "Invalidated runtime context should not throw here.";
          document.querySelector("main").appendChild(p);
          await new Promise((resolve) => setTimeout(resolve, 700));
        } catch (error) {
          return { threw: true, message: error.message, before };
        }
        return {
          threw: false,
          before,
          after: {
            spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length,
            overlayPresent: Boolean(document.querySelector("html > div[style*='z-index: 2147483647']"))
          }
        };
      })()
    `);
    assert(invalidatedResult.before.spinnerCount > 0, "invalidated context check should start with pending spinners");
    assert(invalidatedResult.before.overlayPresent === true, "invalidated context check should start with overlay");
    assert(invalidatedResult.threw === false, `invalidated runtime send should not throw: ${invalidatedResult.message || ""}`);
    assert(invalidatedResult.after.spinnerCount === 0, "invalidated runtime send should clear pending spinners");
    assert(invalidatedResult.after.overlayPresent === false, "invalidated runtime send should hide overlay");

    await sendContentMessage(client, { type: "startSession", pageSessionID: "invalidated-context-reject-check" });
    const rejectedResult = await evaluate(client, `
      (async () => {
        window.__llmToolsSendMessageMode = "reject";
        window.chrome.runtime.sendMessage = (_message) => {
          return Promise.reject(new Error("Extension context invalidated."));
        };
        const before = {
          spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length,
          overlayPresent: Boolean(document.querySelector("html > div[style*='z-index: 2147483647']"))
        };
        try {
          const p = document.createElement("p");
          p.dataset.invalidatedPromiseReject = "true";
          p.textContent = "Rejected runtime context should not throw here.";
          document.querySelector("main").appendChild(p);
          await new Promise((resolve) => setTimeout(resolve, 700));
        } catch (error) {
          return { threw: true, message: error.message, before };
        }
        return {
          threw: false,
          before,
          after: {
            spinnerCount: document.querySelectorAll(".llmtools-segment-spinner").length,
            overlayPresent: Boolean(document.querySelector("html > div[style*='z-index: 2147483647']"))
          }
        };
      })()
    `);
    assert(rejectedResult.before.spinnerCount > 0, "rejected promise check should start with pending spinners");
    assert(rejectedResult.before.overlayPresent === true, "rejected promise check should start with overlay");
    assert(rejectedResult.threw === false, `invalidated promise rejection should not throw: ${rejectedResult.message || ""}`);
    assert(rejectedResult.after.spinnerCount === 0, "invalidated promise rejection should clear pending spinners");
    assert(rejectedResult.after.overlayPresent === false, "invalidated promise rejection should hide overlay");

    const docsPageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "docs-page.html")).href;
    await client.send("Page.navigate", { url: docsPageURL });
    await waitForReadyState(client, "complete");
    await installContentScriptInPage(client, source);

    const docsStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "docs-navigation-check",
      pendingIndicatorStyle: "none",
      appLanguage: "en"
    });
    assert(docsStartResult.ok === true, "content script did not start after page navigation");
    assert(docsStartResult.url === docsPageURL, `expected navigated page url, got ${docsStartResult.url}`);
    assert(docsStartResult.title === "llmTools Docs Fixture", `unexpected navigated page title: ${docsStartResult.title}`);
    assert(docsStartResult.segments.some((segment) => segment.text.includes("Install the command line helper")), "docs page paragraph was not discovered");
    assert(docsStartResult.segments.some((segment) => segment.text.includes("Review the permission checklist")), "docs page list item was not discovered");
    assert(!docsStartResult.segments.some((segment) => segment.text.includes("llmtools bridge status")), "docs code block should be skipped");
    assert(!docsStartResult.segments.some((segment) => segment.text.includes("Token budget notes")), "docs aside text should be skipped");

    const docsTranslations = docsStartResult.segments.map((segment, index) => ({
      segmentID: segment.segmentID,
      status: "translated",
      translation: `文档页译文 ${index + 1}`
    }));
    await sendContentMessage(client, { type: "applyTranslations", translations: docsTranslations });
    const docsTranslatedState = await evaluate(client, `
      (() => ({
        pageText: document.documentElement.textContent,
        codeText: document.querySelector("code").textContent,
        overlayPresent: Boolean(document.querySelector("html > div[style*='z-index: 2147483647']"))
      }))()
    `);
    assert(docsTranslatedState.pageText.includes("文档页译文 1"), "docs page translation was not applied");
    assert(docsTranslatedState.codeText.includes("llmtools bridge status"), "docs page code block should remain unchanged");
    assert(docsTranslatedState.overlayPresent === true, "docs page translation should keep page overlay available");

    await sendContentMessage(client, { type: "restore" });
    const docsRestoredState = await evaluate(client, `
      (() => ({
        pageText: document.documentElement.textContent,
        translatedTextPresent: document.documentElement.textContent.includes("文档页译文"),
        codeText: document.querySelector("code").textContent
      }))()
    `);
    assert(docsRestoredState.pageText.includes("Install the command line helper"), "docs page restore should bring back original text");
    assert(docsRestoredState.translatedTextPresent === false, "docs page restore should remove translated text");
    assert(docsRestoredState.codeText.includes("llmtools bridge status"), "docs page restore should keep code block unchanged");

    const productPageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "product-page.html")).href;
    await client.send("Page.navigate", { url: productPageURL });
    await waitForReadyState(client, "complete");
    await installContentScriptInPage(client, source);

    const productStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "product-page-fixture-check",
      pendingIndicatorStyle: "none"
    });
    assert(productStartResult.ok === true, "product fixture content script did not start");
    assert(productStartResult.title === "llmTools Product Fixture", `unexpected product fixture title: ${productStartResult.title}`);
    assert(productStartResult.segments.some((segment) => segment.text === "Team workspace translation controls"), "product hero heading should be discovered");
    assert(productStartResult.segments.some((segment) => segment.text === "Start free trial"), "product button text should be discovered");
    assert(productStartResult.segments.some((segment) => segment.text === "View pricing"), "product link button text should be discovered");
    assert(productStartResult.segments.some((segment) => segment.text === "Reliable restore"), "product card heading should be discovered");
    await evaluate(client, `
      (() => {
        window.__productButtonClicks = 0;
        document.querySelector("[data-primary-action]").addEventListener("click", () => {
          window.__productButtonClicks += 1;
        });
      })()
    `);
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: productStartResult.segments.map((segment, index) => ({
        segmentID: segment.segmentID,
        status: "translated",
        translation: `产品页译文 ${index + 1}`
      }))
    });
    const productTranslatedState = await evaluate(client, `
      (() => {
        const button = document.querySelector("[data-primary-action]");
        button.click();
        return {
          buttonTag: button.tagName,
          clickCount: window.__productButtonClicks,
          primaryText: button.textContent.trim(),
          linkHref: document.querySelector("[data-secondary-action]").href,
          cardText: document.querySelector(".card:last-child").textContent
        };
      })()
    `);
    assert(productTranslatedState.buttonTag === "BUTTON", "product CTA should remain a button element");
    assert(productTranslatedState.clickCount === 1, "product CTA should remain clickable after translation");
    assert(productTranslatedState.primaryText.includes("产品页译文"), "product CTA text should be translated");
    assert(productTranslatedState.linkHref === "https://example.com/pricing", "product link href should remain unchanged");
    assert(productTranslatedState.cardText.includes("产品页译文"), "product card text should be translated");
    await sendContentMessage(client, { type: "restore" });
    const productRestoredState = await evaluate(client, `
      (() => ({
        buttonText: document.querySelector("[data-primary-action]").textContent.trim(),
        cardText: document.querySelector(".card:last-child").textContent
      }))()
    `);
    assert(productRestoredState.buttonText === "Start free trial", "product restore should bring back original button text");
    assert(productRestoredState.cardText.includes("Reliable restore"), "product restore should bring back original card heading");
    await assertNoPageTextNetworkCalls(client, [
      "Team workspace translation controls",
      "Start free trial",
      "产品页译文"
    ], "product fixture");

    const shadowPageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "shadow-components-page.html")).href;
    await client.send("Page.navigate", { url: shadowPageURL });
    await waitForReadyState(client, "complete");
    await installContentScriptInPage(client, source);

    const shadowStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "shadow-components-fixture-check",
      pendingIndicatorStyle: "none"
    });
    assert(shadowStartResult.ok === true, "shadow components fixture content script did not start");
    assert(shadowStartResult.title === "llmTools Shadow Components Fixture", `unexpected shadow fixture title: ${shadowStartResult.title}`);
    assert(shadowStartResult.segments.some((segment) => segment.text === "Web component translation route"), "document text around shadow component should be discovered");
    assert(shadowStartResult.segments.some((segment) => segment.text === "Open shadow component heading"), "open shadow heading should be discovered");
    assert(shadowStartResult.segments.some((segment) => segment.text === "Shadow component body text should be translated safely."), "open shadow body text should be discovered");
    assert(shadowStartResult.segments.some((segment) => segment.text === "Confirm component action"), "open shadow button text should be discovered");
    assert(!shadowStartResult.segments.some((segment) => segment.text === "Closed shadow component heading"), "closed shadow internal text should not be discovered");
    assert(!shadowStartResult.segments.some((segment) => segment.text === "Closed shadow signal action"), "semantic closed shadow internal text should not be discovered");
    assert(shadowStartResult.unsupportedEmbeddedContent?.shadowRoots >= 2, "closed shadow components should be reported as unsupported embedded content");
    await evaluate(client, "window.__llmToolsMessages = []");
    const shadowDynamicState = await evaluate(client, `
      (async () => {
        window.addShadowParagraph();
        await new Promise((resolve) => setTimeout(resolve, 700));
        return window.__llmToolsMessages;
      })()
    `);
    assert(
      shadowDynamicState.some((message) => message.type === "segmentsDiscovered" && message.segments?.some((segment) => segment.text === "Dynamically added shadow text should be discovered.")),
      "open shadow dynamic text should be discovered"
    );
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: shadowStartResult.segments.map((segment, index) => ({
        segmentID: segment.segmentID,
        status: "translated",
        translation: `组件页译文 ${index + 1}`
      }))
    });
    const shadowTranslatedState = await evaluate(client, `
      (() => {
        const root = document.querySelector("llm-tools-shadow-card").shadowRoot;
        return {
          documentText: document.querySelector("main > h1").textContent,
          shadowText: root.textContent,
          buttonTag: root.querySelector("[data-shadow-action]").tagName
        };
      })()
    `);
    assert(shadowTranslatedState.documentText.includes("组件页译文"), "document text around shadow component should be translated");
    assert(shadowTranslatedState.shadowText.includes("组件页译文"), "open shadow text should be translated");
    assert(shadowTranslatedState.buttonTag === "BUTTON", "open shadow action should remain a button element");
    await sendContentMessage(client, { type: "restore" });
    const shadowRestoredState = await evaluate(client, `
      (() => {
        const root = document.querySelector("llm-tools-shadow-card").shadowRoot;
        return {
          documentText: document.querySelector("main > h1").textContent,
          shadowHeading: root.querySelector("[data-shadow-heading]").textContent,
          translatedTextPresent: root.textContent.includes("组件页译文")
        };
      })()
    `);
    assert(shadowRestoredState.documentText === "Web component translation route", "shadow fixture restore should bring back document heading");
    assert(shadowRestoredState.shadowHeading === "Open shadow component heading", "shadow fixture restore should bring back original shadow heading");
    assert(shadowRestoredState.translatedTextPresent === false, "shadow fixture restore should remove translated shadow text");

    const formPageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "form-editor-page.html")).href;
    await client.send("Page.navigate", { url: formPageURL });
    await waitForReadyState(client, "complete");
    await installContentScriptInPage(client, source);

    const formStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "form-editor-fixture-check",
      pendingIndicatorStyle: "none"
    });
    assert(formStartResult.ok === true, "form/editor fixture content script did not start");
    assert(formStartResult.segments.some((segment) => segment.text === "Campaign editor workflow"), "form heading should be discovered");
    assert(formStartResult.segments.some((segment) => segment.text === "Campaign title"), "form label text should be discovered");
    assert(formStartResult.segments.some((segment) => segment.text === "Preview cards and validation messages remain safe for page translation."), "form safe preview text should be discovered");
    assert(!formStartResult.segments.some((segment) => segment.text.includes("Do not translate typed campaign title")), "input value should not be discovered");
    assert(!formStartResult.segments.some((segment) => segment.text.includes("Do not translate draft customer notes")), "textarea text should not be discovered");
    assert(!formStartResult.segments.some((segment) => segment.text.includes("Do not translate editable rich text content")), "contenteditable text should not be discovered");
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: formStartResult.segments.map((segment, index) => ({
        segmentID: segment.segmentID,
        status: "translated",
        translation: `表单页译文 ${index + 1}`
      }))
    });
    const formTranslatedState = await evaluate(client, `
      (() => ({
        pageText: document.documentElement.textContent,
        inputValue: document.querySelector("[data-title-input]").value,
        textareaValue: document.querySelector("[data-notes-textarea]").value,
        richText: document.querySelector("[data-rich-editor]").textContent
      }))()
    `);
    assert(formTranslatedState.pageText.includes("表单页译文"), "form fixture visible text should be translated");
    assert(formTranslatedState.inputValue === "Do not translate typed campaign title", "input value should remain unchanged after translation");
    assert(formTranslatedState.textareaValue === "Do not translate draft customer notes.", "textarea value should remain unchanged after translation");
    assert(formTranslatedState.richText === "Do not translate editable rich text content.", "contenteditable text should remain unchanged after translation");
    await sendContentMessage(client, { type: "restore" });
    const formRestoredState = await evaluate(client, `
      (() => ({
        heading: document.querySelector("h1").textContent,
        inputValue: document.querySelector("[data-title-input]").value,
        textareaValue: document.querySelector("[data-notes-textarea]").value,
        richText: document.querySelector("[data-rich-editor]").textContent
      }))()
    `);
    assert(formRestoredState.heading === "Campaign editor workflow", "form restore should bring back original heading");
    assert(formRestoredState.inputValue === "Do not translate typed campaign title", "form restore should keep input value unchanged");
    assert(formRestoredState.textareaValue === "Do not translate draft customer notes.", "form restore should keep textarea value unchanged");
    assert(formRestoredState.richText === "Do not translate editable rich text content.", "form restore should keep contenteditable text unchanged");
    await assertNoPageTextNetworkCalls(client, [
      "Campaign editor workflow",
      "Do not translate typed campaign title",
      "表单页译文"
    ], "form/editor fixture");

    const longPageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "long-page.html")).href;
    await client.send("Page.navigate", { url: longPageURL });
    await waitForReadyState(client, "complete");
    await installContentScriptInPage(client, source);
    const longFixtureCount = await evaluate(client, "document.querySelectorAll('#long-content section').length");
    assert(longFixtureCount === 520, `long-page fixture should contain 520 sections, got ${longFixtureCount}`);

    const longStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "long-page-fixture-check",
      pendingIndicatorStyle: "none"
    });
    assert(longStartResult.ok === true, "long-page fixture content script did not start");
    assert(longStartResult.segments.length >= 10, `long-page fixture should discover visible/nearby segments, got ${longStartResult.segments.length}`);
    assert(longStartResult.segments.length <= 200, `long-page fixture should respect the per-discovery cap, got ${longStartResult.segments.length}`);
    assert(longStartResult.segments.some((segment) => segment.text === "Long knowledge base route"), "long-page heading should be discovered");
    assert(longStartResult.segments.some((segment) => segment.text.includes("Long page paragraph 1")), "long-page first paragraph should be discovered");
    assert(!longStartResult.segments.some((segment) => segment.text.includes("Long page paragraph 500")), "visible-first long-page discovery should not pretranslate distant content");
    await evaluate(client, "window.__llmToolsMessages = []");
    const longScrollState = await evaluate(client, `
      (async () => {
        document.querySelector("#long-content section:nth-of-type(500)").scrollIntoView();
        await new Promise((resolve) => setTimeout(resolve, 900));
        return {
          scrollY: window.scrollY,
          messages: window.__llmToolsMessages
        };
      })()
    `);
    assert(longScrollState.scrollY > 0, "long-page scroll check should move away from the top");
    assert(
      longScrollState.messages.some((message) => message.type === "segmentsDiscovered" && message.segments?.some((segment) => segment.text.includes("Long page paragraph 500"))),
      "long-page scrolling should discover newly visible distant content"
    );
    const longSubset = longStartResult.segments.slice(0, 8);
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: longSubset.map((segment, index) => ({
        segmentID: segment.segmentID,
        status: "translated",
        translation: `长页译文 ${index + 1}`
      }))
    });
    const longTranslatedState = await evaluate(client, `
      (() => ({
        text: document.documentElement.textContent,
        tracked: window.__llmToolsListener ? true : false
      }))()
    `);
    assert(longTranslatedState.text.includes("长页译文"), "long-page translated subset should be applied");
    await sendContentMessage(client, { type: "restore" });
    const longRestoredState = await evaluate(client, `
      (() => ({
        translatedTextPresent: document.documentElement.textContent.includes("长页译文"),
        heading: document.querySelector("h1").textContent,
        firstParagraph: document.querySelector("#long-content section p").textContent
      }))()
    `);
    assert(longRestoredState.translatedTextPresent === false, "long-page restore should remove translated subset");
    assert(longRestoredState.heading === "Long knowledge base route", "long-page restore should bring back original heading");
    assert(longRestoredState.firstParagraph === "Long page paragraph 1 should be discoverable without blocking restore behavior.", "long-page restore should bring back original first paragraph");

    const fullPageStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "long-page-full-pretranslation-check",
      pendingIndicatorStyle: "none",
      discoveryScope: "page"
    });
    assert(fullPageStartResult.ok === true, "long-page full-page content script did not start");
    assert(fullPageStartResult.segments.length > 200, `full-page discovery should exceed visible-first cap, got ${fullPageStartResult.segments.length}`);
    assert(fullPageStartResult.segments.length <= 1000, `full-page discovery should respect the full-page cap, got ${fullPageStartResult.segments.length}`);
    assert(
      fullPageStartResult.segments.some((segment) => segment.text.includes("Long page paragraph 400")),
      "full-page discovery should include distant long-page paragraph content"
    );
    assert(
      fullPageStartResult.segments.some((segment) => segment.text.includes("Documentation section 500")),
      "full-page discovery should include distant long-page headings"
    );
    await sendContentMessage(client, { type: "restore" });

    const iframePageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "iframe-page.html")).href;
    await client.send("Page.navigate", { url: iframePageURL });
    await waitForReadyState(client, "complete");
    await waitUntil(async () => {
      return Boolean(await evaluate(client, `
        Boolean(document.querySelector("[data-same-origin-frame]")?.contentDocument?.querySelector("[data-frame-copy]"))
      `));
    }, 2_000, "same-origin iframe fixture did not load");
    await installContentScriptInPage(client, source);

    const iframeStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "same-origin-iframe-check",
      pendingIndicatorStyle: "none"
    });
    const iframeSegment = iframeStartResult.segments.find((segment) => segment.text === "Same origin iframe text should be translated.");
    assert(iframeSegment, "same-origin iframe text should be discovered by the main content script");
    assert(
      !iframeStartResult.segments.some((segment) => segment.text.includes("iframe code should stay as source text")),
      "same-origin iframe code text should be skipped"
    );
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: [{
        segmentID: iframeSegment.segmentID,
        status: "translated",
        translation: "同源 iframe 译文"
      }]
    });
    const iframeTranslatedState = await evaluate(client, `
      (() => {
        const frameDoc = document.querySelector("[data-same-origin-frame]").contentDocument;
        return {
          frameText: frameDoc.body.textContent,
          codeText: frameDoc.querySelector("code").textContent
        };
      })()
    `);
    assert(iframeTranslatedState.frameText.includes("同源 iframe 译文"), "same-origin iframe translation should be applied inside the frame");
    assert(iframeTranslatedState.codeText === "iframe code should stay as source text", "same-origin iframe code block should remain unchanged");
    await sendContentMessage(client, { type: "restore" });
    const iframeRestoredState = await evaluate(client, `
      (() => {
        const frameDoc = document.querySelector("[data-same-origin-frame]").contentDocument;
        return frameDoc.querySelector("[data-frame-copy]").textContent;
      })()
    `);
    assert(iframeRestoredState === "Same origin iframe text should be translated.", "restore should restore same-origin iframe text");

    const tablePageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "table-page.html")).href;
    await client.send("Page.navigate", { url: tablePageURL });
    await waitForReadyState(client, "complete");
    await installContentScriptInPage(client, source);

    const tableStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "table-heavy-check",
      pendingIndicatorStyle: "none"
    });
    const tableSegments = tableStartResult.segments.filter((segment) => [
      "Metric name",
      "Current value",
      "Average response latency",
      "Healthy service threshold"
    ].includes(segment.text));
    assert(tableSegments.length === 4, `expected four table text segments, got ${tableSegments.length}`);
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: tableSegments.map((segment, index) => ({
        segmentID: segment.segmentID,
        status: "translated",
        translation: `表格译文 ${index + 1}`
      }))
    });
    await sendContentMessage(client, { type: "setReadingMode", mode: "bilingual" });
    const tableBilingualState = await evaluate(client, `
      (() => {
        const table = document.querySelector("[data-table-heavy]");
        const wrappers = Array.from(table.querySelectorAll(".llmtools-bilingual"));
        return {
          tableDisplay: getComputedStyle(table).display,
          wrapperCount: wrappers.length,
          allTableCellMode: wrappers.every((node) => node.dataset.llmToolsTableCell === "true"),
          allBlockDisplay: wrappers.every((node) => getComputedStyle(node).display === "block"),
          firstCellText: table.querySelector("td").textContent
        };
      })()
    `);
    assert(tableBilingualState.tableDisplay === "table", `table should keep table display, got ${tableBilingualState.tableDisplay}`);
    assert(tableBilingualState.wrapperCount === 4, `expected bilingual wrappers in four table cells, got ${tableBilingualState.wrapperCount}`);
    assert(tableBilingualState.allTableCellMode === true, "table bilingual wrappers should use table-cell mode");
    assert(tableBilingualState.allBlockDisplay === true, "table bilingual wrappers should render as block layout inside cells");
    assert(tableBilingualState.firstCellText.includes("表格译文") && tableBilingualState.firstCellText.includes("Average response latency"), "table bilingual cell should include translation and original");
    await sendContentMessage(client, { type: "restore" });
    const tableRestoredState = await evaluate(client, `
      (() => {
        const table = document.querySelector("[data-table-heavy]");
        return {
          wrapperCount: table.querySelectorAll(".llmtools-bilingual").length,
          text: table.textContent
        };
      })()
    `);
    assert(tableRestoredState.wrapperCount === 0, "table restore should remove bilingual wrappers");
    assert(tableRestoredState.text.includes("Average response latency"), "table restore should bring back original cell text");

    const dashboardPageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "dashboard-table-page.html")).href;
    await client.send("Page.navigate", { url: dashboardPageURL });
    await waitForReadyState(client, "complete");
    await installContentScriptInPage(client, source);
    const dashboardRowCount = await evaluate(client, "document.querySelectorAll('[data-dashboard-row]').length");
    assert(dashboardRowCount === 240, `dashboard fixture should contain 240 rows, got ${dashboardRowCount}`);

    const dashboardStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "dashboard-table-stress-check",
      pendingIndicatorStyle: "none",
      discoveryScope: "page"
    });
    assert(dashboardStartResult.ok === true, "dashboard table fixture content script did not start");
    assert(dashboardStartResult.segments.length > 900, `dashboard full-page discovery should cover many table cells, got ${dashboardStartResult.segments.length}`);
    assert(dashboardStartResult.segments.length <= 1000, `dashboard full-page discovery should respect the page cap, got ${dashboardStartResult.segments.length}`);
    assert(dashboardStartResult.segments.some((segment) => segment.text === "Metric name"), "dashboard table header should be discovered");
    assert(dashboardStartResult.segments.some((segment) => segment.text === "Queue depth backlog 230"), "dashboard distant row metric should be discovered");
    assert(
      dashboardStartResult.segments.some((segment) => segment.text === "Recommended action 240 requires owner follow up."),
      "dashboard final row action should be discovered"
    );
    const dashboardSegments = dashboardStartResult.segments.filter((segment) => [
      "Metric name",
      "Current value",
      "Queue depth backlog 230",
      "Recommended action 240 requires owner follow up."
    ].includes(segment.text));
    assert(dashboardSegments.length === 4, `expected four dashboard stress segments, got ${dashboardSegments.length}`);
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: dashboardSegments.map((segment, index) => ({
        segmentID: segment.segmentID,
        status: "translated",
        translation: `仪表盘译文 ${index + 1}`
      }))
    });
    await sendContentMessage(client, { type: "setReadingMode", mode: "bilingual" });
    const dashboardBilingualState = await evaluate(client, `
      (() => {
        const table = document.querySelector("[data-dashboard-table]");
        const wrappers = Array.from(table.querySelectorAll(".llmtools-bilingual"));
        const row230 = document.querySelector('[data-dashboard-row="230"]');
        const header = table.querySelector("th");
        return {
          rowCount: table.querySelectorAll("tbody tr").length,
          tableDisplay: getComputedStyle(table).display,
          stickyHeader: getComputedStyle(header).position,
          wrapperCount: wrappers.length,
          allTableCellMode: wrappers.every((node) => node.dataset.llmToolsTableCell === "true"),
          allBlockDisplay: wrappers.every((node) => getComputedStyle(node).display === "block"),
          row230Text: row230.textContent
        };
      })()
    `);
    assert(dashboardBilingualState.rowCount === 240, "dashboard bilingual mode should preserve all rows");
    assert(dashboardBilingualState.tableDisplay === "table", `dashboard table should keep table display, got ${dashboardBilingualState.tableDisplay}`);
    assert(dashboardBilingualState.stickyHeader === "sticky", `dashboard sticky header should remain sticky, got ${dashboardBilingualState.stickyHeader}`);
    assert(dashboardBilingualState.wrapperCount === 4, `expected four dashboard bilingual wrappers, got ${dashboardBilingualState.wrapperCount}`);
    assert(dashboardBilingualState.allTableCellMode === true, "dashboard bilingual wrappers should use table-cell mode");
    assert(dashboardBilingualState.allBlockDisplay === true, "dashboard bilingual wrappers should render as block layout inside cells");
    assert(dashboardBilingualState.row230Text.includes("仪表盘译文") && dashboardBilingualState.row230Text.includes("Queue depth backlog 230"), "dashboard distant row should include translation and original");
    await sendContentMessage(client, { type: "restore" });
    const dashboardRestoredState = await evaluate(client, `
      (() => {
        const table = document.querySelector("[data-dashboard-table]");
        return {
          wrapperCount: table.querySelectorAll(".llmtools-bilingual").length,
          row230Text: document.querySelector('[data-dashboard-row="230"]').textContent,
          translatedPresent: table.textContent.includes("仪表盘译文"),
          stickyHeader: getComputedStyle(table.querySelector("th")).position
        };
      })()
    `);
    assert(dashboardRestoredState.wrapperCount === 0, "dashboard restore should remove bilingual wrappers");
    assert(dashboardRestoredState.row230Text.includes("Queue depth backlog 230"), "dashboard restore should bring back distant row text");
    assert(dashboardRestoredState.translatedPresent === false, "dashboard restore should remove translated table text");
    assert(dashboardRestoredState.stickyHeader === "sticky", "dashboard restore should preserve sticky header style");

    const unsupportedPageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "unsupported-page.html")).href;
    await client.send("Page.navigate", { url: unsupportedPageURL });
    await waitForReadyState(client, "complete");
    await installContentScriptInPage(client, source);

    const unsupportedStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "unsupported-embedded-check",
      pendingIndicatorStyle: "none"
    });
    assert(unsupportedStartResult.unsupportedEmbeddedContent?.frames >= 1, "sandboxed frame should be reported as unsupported embedded content");
    assert(unsupportedStartResult.unsupportedEmbeddedContent?.canvas >= 1, "canvas should be reported as unsupported embedded content");
    assert(unsupportedStartResult.unsupportedEmbeddedContent?.images >= 1, "image text candidate should be reported as unsupported embedded content");
    assert(unsupportedStartResult.unsupportedEmbeddedContent?.pdf >= 1, "PDF embed should be reported as unsupported embedded content");
    assert(unsupportedStartResult.unsupportedEmbeddedContent?.total >= 4, `expected unsupported embedded content total >= 4, got ${unsupportedStartResult.unsupportedEmbeddedContent?.total}`);
    await sendContentMessage(client, { type: "restore" });

    const spaVirtualizedPageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "spa-virtualized-page.html")).href;
    await client.send("Page.navigate", { url: spaVirtualizedPageURL });
    await waitForReadyState(client, "complete");
    await installContentScriptInPage(client, source);

    await evaluate(client, "window.__llmToolsMessages = []");
    const spaStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "spa-route-check",
      pendingIndicatorStyle: "none"
    });
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: spaStartResult.segments.slice(0, 2).map((segment, index) => ({
        segmentID: segment.segmentID,
        status: "translated",
        translation: `SPA 旧译文 ${index + 1}`
      }))
    });
    const spaRouteState = await evaluate(client, `
      (async () => {
        const beforeURL = location.href;
        history.pushState({ route: "next" }, "", location.pathname + "?spa-route=1");
        await new Promise((resolve) => setTimeout(resolve, 350));
        const pageState = await new Promise((resolve) => window.__llmToolsListener({ type: "getPageTranslationState" }, {}, resolve));
        return {
          beforeURL,
          afterURL: location.href,
          pageText: document.documentElement.textContent,
          messages: window.__llmToolsMessages,
          pageState
        };
      })()
    `);
    assert(spaRouteState.afterURL.includes("spa-route=1"), `expected SPA route URL change, got ${spaRouteState.afterURL}`);
    assert(!spaRouteState.pageText.includes("SPA 旧译文"), "SPA route change should restore old translations before continuing");
    assert(spaRouteState.pageText.includes("SPA route content should be translated before navigation."), "SPA route change should keep restored original page text");
    assert(spaRouteState.pageState.hasTranslations === false, "SPA route change should clear content-script translation state");
    assert(spaRouteState.pageState.pageSessionID === null, "SPA route change should clear the page session id");
    assert(
      spaRouteState.messages.some((message) => message.type === "llmToolsRouteChanged" && message.previousURL === spaRouteState.beforeURL && message.url === spaRouteState.afterURL),
      "SPA route change should notify the background page"
    );

    await evaluate(client, `
      (() => {
        window.__llmToolsMessages = [];
        const row = document.querySelector("[data-virtualized-row]");
        row.textContent = "Virtualized row one should be translated.";
        return true;
      })()
    `);
    const virtualizedStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "virtualized-node-check",
      pendingIndicatorStyle: "none",
      discoveryScope: "page"
    });
    const firstVirtualizedSegment = virtualizedStartResult.segments.find((segment) => segment.text === "Virtualized row one should be translated.");
    assert(firstVirtualizedSegment, "virtualized row initial text should be discovered");
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: [{
        segmentID: firstVirtualizedSegment.segmentID,
        status: "translated",
        translation: "虚拟列表旧译文"
      }]
    });
    await evaluate(client, "window.__llmToolsMessages = []");
    const virtualizedState = await evaluate(client, `
      (async () => {
        const nextText = "Virtualized row two reuses the same text node.";
        const row = document.querySelector("[data-virtualized-row]");
        row.firstChild.nodeValue = nextText;
        await new Promise((resolve) => setTimeout(resolve, 750));
        const firstBatch = window.__llmToolsMessages.slice();
        await new Promise((resolve) => setTimeout(resolve, 750));
        return {
          text: row.textContent,
          firstBatch,
          messages: window.__llmToolsMessages
        };
      })()
    `);
    const virtualizedSegments = virtualizedState.messages
      .filter((message) => message.type === "segmentsDiscovered")
      .flatMap((message) => message.segments || [])
      .filter((segment) => segment.text === "Virtualized row two reuses the same text node.");
    assert(virtualizedState.text === "Virtualized row two reuses the same text node.", "virtualized row should keep the reused node's latest text");
    assert(virtualizedSegments.length === 1, `expected reused virtualized text node to be discovered once, got ${virtualizedSegments.length}`);
    assert(
      virtualizedState.firstBatch.some((message) => message.type === "segmentsDiscovered" && message.segments?.some((segment) => segment.text === "Virtualized row two reuses the same text node.")),
      "virtualized row changed text should be reported in the first discovery batch"
    );

    const pooledVirtualizedSegment = virtualizedStartResult.segments.find((segment) => segment.text === "Virtualized pool row one should be translated.");
    assert(pooledVirtualizedSegment, "virtualized pooled row initial text should be discovered");
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: [{
        segmentID: pooledVirtualizedSegment.segmentID,
        status: "translated",
        translation: "虚拟池旧译文"
      }]
    });
    await evaluate(client, "window.__llmToolsMessages = []");
    const pooledVirtualizedState = await evaluate(client, `
      (async () => {
        const nextText = "Virtualized pool row two returns after detaching.";
        const text = window.reuseDetachedVirtualizedRow(nextText);
        await new Promise((resolve) => setTimeout(resolve, 750));
        const firstBatch = window.__llmToolsMessages.slice();
        await new Promise((resolve) => setTimeout(resolve, 750));
        return {
          text,
          rowText: document.querySelector("[data-pooled-row]").textContent,
          oldTranslationPresent: document.querySelector("[data-pooled-row]").textContent.includes("虚拟池旧译文"),
          firstBatch,
          messages: window.__llmToolsMessages
        };
      })()
    `);
    const pooledVirtualizedSegments = pooledVirtualizedState.messages
      .filter((message) => message.type === "segmentsDiscovered")
      .flatMap((message) => message.segments || [])
      .filter((segment) => segment.text === "Virtualized pool row two returns after detaching.");
    assert(pooledVirtualizedState.text === "Virtualized pool row two returns after detaching.", "detached virtualized row helper should return the new row text");
    assert(pooledVirtualizedState.rowText === "Virtualized pool row two returns after detaching.", "reattached virtualized row should keep the latest text");
    assert(pooledVirtualizedState.oldTranslationPresent === false, "reattached virtualized row should not keep the previous translation");
    assert(pooledVirtualizedSegments.length === 1, `expected detached/reattached pooled row to be discovered once, got ${pooledVirtualizedSegments.length}`);
    assert(
      pooledVirtualizedState.firstBatch.some((message) => message.type === "segmentsDiscovered" && message.segments?.some((segment) => segment.text === "Virtualized pool row two returns after detaching.")),
      "detached/reattached virtualized row should be reported in the first discovery batch"
    );

    const initialVirtualWindowSegments = virtualizedStartResult.segments.filter((segment) => (
      segment.text.startsWith("Virtualized feed item ")
    ));
    assert(initialVirtualWindowSegments.length === 20, `expected 20 initial virtual feed window segments, got ${initialVirtualWindowSegments.length}`);
    await sendContentMessage(client, {
      type: "applyTranslations",
      translations: initialVirtualWindowSegments.slice(0, 6).map((segment, index) => ({
        segmentID: segment.segmentID,
        status: "translated",
        translation: `虚拟窗口旧译文 ${index + 1}`
      }))
    });
    await evaluate(client, "window.__llmToolsMessages = []");
    const virtualWindowStressState = await evaluate(client, `
      (async () => {
        const starts = [101, 121, 141, 161, 181, 201];
        const snapshots = [];
        for (const start of starts) {
          window.__llmToolsMessages = [];
          const expected = window.renderVirtualizedWindow(start);
          await new Promise((resolve) => setTimeout(resolve, 450));
          snapshots.push({
            start,
            expected,
            text: document.querySelector("[data-virtual-window]").textContent,
            messages: window.__llmToolsMessages.slice()
          });
        }
        const finalText = document.querySelector("[data-virtual-window]").textContent;
        return {
          snapshots,
          finalText,
          oldTranslationPresent: finalText.includes("虚拟窗口旧译文")
        };
      })()
    `);
    const stressSeenTexts = new Set();
    for (const snapshot of virtualWindowStressState.snapshots) {
      const discoveredTexts = snapshot.messages
        .filter((message) => message.type === "segmentsDiscovered")
        .flatMap((message) => message.segments || [])
        .map((segment) => segment.text)
        .filter((text) => text.startsWith("Virtualized feed item "));
      assert(discoveredTexts.length === 20, `expected 20 discovered texts for virtual window ${snapshot.start}, got ${discoveredTexts.length}`);
      assert(new Set(discoveredTexts).size === 20, `virtual window ${snapshot.start} should not duplicate discovered texts`);
      for (const expectedText of snapshot.expected) {
        assert(discoveredTexts.includes(expectedText), `virtual window ${snapshot.start} did not discover ${expectedText}`);
        assert(!stressSeenTexts.has(expectedText), `virtual window stress rediscovered ${expectedText}`);
        stressSeenTexts.add(expectedText);
      }
      assert(!snapshot.text.includes("虚拟窗口旧译文"), `virtual window ${snapshot.start} should not keep old translated text`);
    }
    assert(stressSeenTexts.size === 120, `expected 120 unique virtual feed stress texts, got ${stressSeenTexts.size}`);
    assert(virtualWindowStressState.oldTranslationPresent === false, "long virtualized feed should not leak old translations into reused rows");

    await evaluate(client, "window.__llmToolsMessages = []");
    const highFrequencyState = await evaluate(client, `
      (async () => {
        const p = document.querySelector("[data-high-frequency]");
        p.textContent = "High frequency update 0 should flush before updates stop.";
        let count = 0;
        const timer = setInterval(() => {
          count += 1;
          p.firstChild.nodeValue = "High frequency update " + count + " should flush before updates stop.";
        }, 60);
        await new Promise((resolve) => setTimeout(resolve, 1250));
        const messagesWhileRunning = window.__llmToolsMessages.slice();
        clearInterval(timer);
        await new Promise((resolve) => setTimeout(resolve, 450));
        return {
          count,
          text: p.textContent,
          messagesWhileRunning,
          messages: window.__llmToolsMessages
        };
      })()
    `);
    const highFrequencySegmentsWhileRunning = highFrequencyState.messagesWhileRunning
      .filter((message) => message.type === "segmentsDiscovered")
      .flatMap((message) => message.segments || [])
      .filter((segment) => segment.text.startsWith("High frequency update "));
    const highFrequencySegments = highFrequencyState.messages
      .filter((message) => message.type === "segmentsDiscovered")
      .flatMap((message) => message.segments || [])
      .filter((segment) => segment.text.startsWith("High frequency update "));
    assert(highFrequencyState.count > 10, "high-frequency mutation check should keep updating while waiting");
    assert(highFrequencySegmentsWhileRunning.length > 0, "high-frequency mutations should flush before updates stop");
    assert(highFrequencySegments.length <= 3, `high-frequency mutations should be throttled, got ${highFrequencySegments.length} discovered segments`);
    await assertNoPageTextNetworkCalls(client, [
      "SPA route content should be translated before navigation.",
      "Virtualized row two reuses the same text node.",
      "Virtualized feed item 201 should be translated after scroll window reuse.",
      "High frequency update",
      "SPA 旧译文"
    ], "SPA/virtualized fixture");
    await delay(100);
    assert(runtimeErrors.length === 0, `${browserTarget.name} runtime/console errors:\n${runtimeErrors.join("\n")}`);
  } catch (error) {
    error.message = `${error.message}\n${browserTarget.name} stderr:\n${stderr.slice(-4_000)}`;
    throw error;
  } finally {
    client?.close();
    browserProcess.kill("SIGTERM");
    await waitForExit(browserProcess, 2_000).catch(() => browserProcess.kill("SIGKILL"));
    await fs.rm(profileDir, { recursive: true, force: true });
  }
}

async function runContentScriptDomChecks() {
  const selectedTargets = selectedBrowserE2ETargets();
  let completedChecks = 0;
  for (const browserTarget of selectedTargets) {
    if (!(await fileExists(browserTarget.path))) {
      const message = `${browserTarget.name} executable was not found at ${browserTarget.path}. Override with ${browserTarget.envPathName} if needed.`;
      if (browserTarget.required) {
        throw new Error(message);
      }
      console.warn(`Skipping ${browserTarget.name} content-script DOM check: ${message}`);
      continue;
    }
    await runContentScriptDomCheck(browserTarget);
    completedChecks += 1;
    console.log(`${browserTarget.name} content-script DOM checks passed`);
  }
  assert(completedChecks > 0, "No configured browser executable was available for content-script DOM checks");
}

function selectedBrowserE2ETargets() {
  const requestedBrowser = (process.env.LLMTOOLS_E2E_BROWSER || "chrome").trim().toLowerCase();
  if (requestedBrowser === "all") {
    return browserE2ETargets.map((target) => ({ ...target, required: false }));
  }
  const target = browserE2ETargets.find((candidate) => candidate.id === requestedBrowser);
  if (!target) {
    const supported = browserE2ETargets.map((candidate) => candidate.id).concat("all").join(", ");
    throw new Error(`Unsupported LLMTOOLS_E2E_BROWSER value: ${requestedBrowser}. Supported values: ${supported}`);
  }
  return [{ ...target, required: true }];
}

function sendBackgroundMessage(listener, message, sender = {}) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`background message timed out: ${message.type}`)), 2_000);
    try {
      listener(message, sender, (response) => {
        clearTimeout(timer);
        resolve(response);
      });
    } catch (error) {
      clearTimeout(timer);
      reject(error);
    }
  });
}

async function sendContentMessage(client, message) {
  return evaluate(client, `
    new Promise((resolve, reject) => {
      if (!window.__llmToolsListener) {
        reject(new Error("content script listener is not installed"));
        return;
      }
      window.__llmToolsListener(${JSON.stringify(message)}, {}, resolve);
    })
  `);
}

function assertOnlyTranslationNativeRequestsCarryPageText(nativeMessages, forbiddenTexts) {
  for (const message of nativeMessages) {
    if (message?.type === "translateSegments") {
      continue;
    }
    const serialized = JSON.stringify(message || {});
    for (const text of forbiddenTexts) {
      assert(!serialized.includes(text), `${message?.type || "native request"} should not carry page text: ${text}`);
    }
  }
}

async function assertNoPageTextNetworkCalls(client, forbiddenTexts, label) {
  const calls = await evaluate(client, "window.__llmToolsNetworkCalls || []");
  const serialized = JSON.stringify(calls);
  assert(calls.length === 0, `${label} should not make JS network calls, got ${serialized}`);
  for (const text of forbiddenTexts) {
    assert(!serialized.includes(text), `${label} network calls should not include page text: ${text}`);
  }
}

async function installContentScriptInPage(client, source) {
  await evaluate(client, `
    (() => {
      window.__llmToolsMessages = [];
      window.__llmToolsListener = null;
      window.__llmToolsNetworkCalls = [];
      const recordNetworkCall = (type, url, body) => {
        window.__llmToolsNetworkCalls.push({
          type,
          url: String(url || ""),
          body: typeof body === "string" ? body : body == null ? "" : Object.prototype.toString.call(body)
        });
      };
      try {
        const originalFetch = window.fetch?.bind(window);
        if (originalFetch) {
          window.fetch = (...args) => {
            recordNetworkCall("fetch", args[0]?.url || args[0], args[1]?.body);
            return originalFetch(...args);
          };
        }
      } catch {}
      try {
        const originalOpen = window.XMLHttpRequest?.prototype?.open;
        const originalSend = window.XMLHttpRequest?.prototype?.send;
        if (originalOpen && originalSend) {
          window.XMLHttpRequest.prototype.open = function llmToolsXHROpen(method, url, ...rest) {
            this.__llmToolsURL = url;
            return originalOpen.call(this, method, url, ...rest);
          };
          window.XMLHttpRequest.prototype.send = function llmToolsXHRSend(body) {
            recordNetworkCall("xhr", this.__llmToolsURL || "", body);
            return originalSend.call(this, body);
          };
        }
      } catch {}
      try {
        const originalSendBeacon = window.navigator?.sendBeacon?.bind(window.navigator);
        if (originalSendBeacon) {
          window.navigator.sendBeacon = (url, data) => {
            recordNetworkCall("beacon", url, data);
            return originalSendBeacon(url, data);
          };
        }
      } catch {}
      window.chrome = {
        runtime: {
          onMessage: {
            addListener(listener) {
              window.__llmToolsListener = listener;
            }
          },
          sendMessage(message) {
            window.__llmToolsMessages.push(message);
            return Promise.resolve({ ok: true });
          }
        }
      };
      return true;
    })()
  `);
  await evaluate(client, `(0, eval)(${JSON.stringify(source)}); true;`);
}

async function evaluate(client, expression) {
  const response = await client.send("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
    userGesture: true
  });
  if (response.exceptionDetails) {
    throw new Error(response.exceptionDetails.text || response.exceptionDetails.exception?.description || "Runtime.evaluate failed");
  }
  return response.result?.value;
}

async function waitForReadyState(client, readyState) {
  await waitUntil(async () => {
    const state = await evaluate(client, "document.readyState");
    return state === readyState;
  }, 5_000, `page did not reach ${readyState}`);
}

async function createPageTarget(port, pageURL) {
  const endpoint = `http://127.0.0.1:${port}/json/new?${encodeURIComponent(pageURL)}`;
  let response = await fetch(endpoint, { method: "PUT" });
  if (!response.ok) {
    response = await fetch(endpoint);
  }
  if (!response.ok) {
    throw new Error(`Could not create browser target: ${response.status} ${response.statusText}`);
  }
  return response.json();
}

async function waitForDevToolsPort(profileDir) {
  const activePortFile = path.join(profileDir, "DevToolsActivePort");
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      const text = await fs.readFile(activePortFile, "utf8");
      const [portLine] = text.trim().split(/\r?\n/);
      const port = Number(portLine);
      if (Number.isInteger(port) && port > 0) {
        return { port };
      }
    } catch {}
    await delay(100);
  }
  throw new Error("Browser did not publish DevToolsActivePort");
}

async function waitUntil(predicate, timeoutMs, message) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (await predicate()) {
      return;
    }
    await delay(50);
  }
  throw new Error(message);
}

function waitForExit(child, timeoutMs) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("process exit timed out")), timeoutMs);
    child.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function formatRuntimeException(event = {}) {
  const details = event.exceptionDetails || {};
  const exception = details.exception || {};
  const message = exception.description || exception.value || details.text || "Runtime exception";
  const location = [
    details.url || "",
    Number.isInteger(details.lineNumber) ? details.lineNumber + 1 : "",
    Number.isInteger(details.columnNumber) ? details.columnNumber + 1 : ""
  ].filter((value) => value !== "").join(":");
  return location ? `${message} @ ${location}` : String(message);
}

function formatRuntimeConsoleError(event = {}) {
  const args = (event.args || []).map((arg) => arg.value ?? arg.description ?? arg.unserializableValue ?? "").filter(Boolean);
  const location = event.stackTrace?.callFrames?.[0];
  const locationText = location ? ` @ ${location.url || ""}:${(location.lineNumber || 0) + 1}:${(location.columnNumber || 0) + 1}` : "";
  return `console.${event.type || "error"} ${args.join(" ")}${locationText}`.trim();
}

class CDPClient {
  static async connect(webSocketURL) {
    const client = new CDPClient(webSocketURL);
    await client.open();
    return client;
  }

  constructor(webSocketURL) {
    this.url = new URL(webSocketURL);
    this.socket = null;
    this.nextID = 1;
    this.pending = new Map();
    this.eventListeners = new Map();
    this.buffer = Buffer.alloc(0);
    this.handshakeDone = false;
  }

  open() {
    return new Promise((resolve, reject) => {
      const key = randomBytes(16).toString("base64");
      const expectedAccept = createHash("sha1")
        .update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
        .digest("base64");
      this.socket = net.createConnection(Number(this.url.port), this.url.hostname);
      this.socket.once("error", reject);
      this.socket.on("data", (chunk) => this.handleData(chunk, expectedAccept, resolve, reject));
      this.socket.on("close", () => {
        for (const { reject: rejectPending } of this.pending.values()) {
          rejectPending(new Error("CDP socket closed"));
        }
        this.pending.clear();
      });
      this.socket.write([
        `GET ${this.url.pathname}${this.url.search} HTTP/1.1`,
        `Host: ${this.url.host}`,
        "Upgrade: websocket",
        "Connection: Upgrade",
        `Sec-WebSocket-Key: ${key}`,
        "Sec-WebSocket-Version: 13",
        "Origin: http://127.0.0.1",
        "",
        ""
      ].join("\r\n"));
    });
  }

  send(method, params = {}) {
    const id = this.nextID;
    this.nextID += 1;
    const message = { id, method, params };
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.write(encodeWebSocketFrame(JSON.stringify(message)));
    });
  }

  on(method, listener) {
    if (!this.eventListeners.has(method)) {
      this.eventListeners.set(method, []);
    }
    this.eventListeners.get(method).push(listener);
  }

  close() {
    this.socket?.end();
  }

  handleData(chunk, expectedAccept, resolveOpen, rejectOpen) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    if (!this.handshakeDone) {
      const headerEnd = this.buffer.indexOf("\r\n\r\n");
      if (headerEnd === -1) {
        return;
      }
      const header = this.buffer.subarray(0, headerEnd).toString("utf8");
      this.buffer = this.buffer.subarray(headerEnd + 4);
      if (!header.startsWith("HTTP/1.1 101") || !header.includes(`Sec-WebSocket-Accept: ${expectedAccept}`)) {
        rejectOpen(new Error(`CDP WebSocket handshake failed:\n${header}`));
        return;
      }
      this.handshakeDone = true;
      resolveOpen();
    }
    this.readFrames();
  }

  readFrames() {
    while (this.buffer.length >= 2) {
      const first = this.buffer[0];
      const second = this.buffer[1];
      const opcode = first & 0x0f;
      let offset = 2;
      let length = second & 0x7f;
      if (length === 126) {
        if (this.buffer.length < offset + 2) return;
        length = this.buffer.readUInt16BE(offset);
        offset += 2;
      } else if (length === 127) {
        if (this.buffer.length < offset + 8) return;
        const high = this.buffer.readUInt32BE(offset);
        const low = this.buffer.readUInt32BE(offset + 4);
        length = high * 2 ** 32 + low;
        offset += 8;
      }
      const masked = Boolean(second & 0x80);
      if (masked) {
        offset += 4;
      }
      if (this.buffer.length < offset + length) {
        return;
      }
      let payload = this.buffer.subarray(offset, offset + length);
      if (masked) {
        const mask = this.buffer.subarray(offset - 4, offset);
        payload = Buffer.from(payload.map((byte, index) => byte ^ mask[index % 4]));
      }
      this.buffer = this.buffer.subarray(offset + length);
      if (opcode === 1) {
        this.handleMessage(JSON.parse(payload.toString("utf8")));
      } else if (opcode === 8) {
        this.close();
        return;
      }
    }
  }

  handleMessage(message) {
    if (!message.id) {
      for (const listener of this.eventListeners.get(message.method) || []) {
        listener(message.params || {});
      }
      return;
    }
    if (!this.pending.has(message.id)) {
      return;
    }
    const { resolve, reject } = this.pending.get(message.id);
    this.pending.delete(message.id);
    if (message.error) {
      reject(new Error(message.error.message || JSON.stringify(message.error)));
    } else {
      resolve(message.result);
    }
  }
}

function encodeWebSocketFrame(text) {
  const payload = Buffer.from(text);
  let header;
  if (payload.length < 126) {
    header = Buffer.alloc(2);
    header[1] = payload.length | 0x80;
  } else if (payload.length < 65_536) {
    header = Buffer.alloc(4);
    header[1] = 126 | 0x80;
    header.writeUInt16BE(payload.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[1] = 127 | 0x80;
    header.writeUInt32BE(0, 2);
    header.writeUInt32BE(payload.length, 6);
  }
  header[0] = 0x81;
  const mask = randomBytes(4);
  const maskedPayload = Buffer.alloc(payload.length);
  for (let index = 0; index < payload.length; index += 1) {
    maskedPayload[index] = payload[index] ^ mask[index % 4];
  }
  return Buffer.concat([header, mask, maskedPayload]);
}

await runExtensionManifestPermissionCheck();
await runBackgroundBatchCheck();
await runPopupPermissionCheck();
await runContentScriptDomChecks();
console.log("Browser extension DOM checks passed");
process.exit(0);
