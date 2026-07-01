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
const chromePath = process.env.CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

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
  let tabActivatedListener = null;
  let contextMenuClickListener = null;
  let contextMenuShownListener = null;
  const nativeTranslatePayloads = [];
  const appliedTranslations = [];
  const popupStates = [];
  const startSessionMessages = [];
  const contextMenuItems = new Map();
  const localStorageData = {};
  let nativePortMessageListener = null;
  let nativePortDisconnectListener = null;

  function nativeResponseFor(message) {
    if (message.type === "getStatus") {
      return {
        requestID: message.requestID,
        status: "ok",
        payload: { modelName: "stub-model", pendingIndicatorStyle: "flipText" }
      };
    }
    if (message.type === "translateSegments") {
      nativeTranslatePayloads.push(message.payload);
      return {
        requestID: message.requestID,
        status: "ok",
        payload: {
          modelName: "stub-model",
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
        if (message.type === "getStatus") {
          return Promise.resolve({ status: "ok", payload: { modelName: "stub-model", pendingIndicatorStyle: "flipText" } });
        }
        if (message.type === "translateSegments") {
          nativeTranslatePayloads.push(message.payload);
          return Promise.resolve({
            status: "ok",
            payload: {
              modelName: "stub-model",
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
    tabs: {
      onRemoved: {
        addListener() {}
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
        return Promise.resolve({ id: tabID, url: "https://example.test/article" });
      },
      sendMessage(_tabID, message) {
        if (message.type === "ping") {
          return Promise.resolve({ ok: true });
        }
        if (message.type === "startSession") {
          startSessionMessages.push(message);
          return Promise.resolve({
            ok: true,
            url: "https://example.test/article",
            title: "Test Article",
            segments: discoveredSegments
          });
        }
        if (message.type === "applyTranslations") {
          appliedTranslations.push(...message.translations);
          return Promise.resolve({ ok: true, applied: appliedTranslations.length });
        }
        if (message.type === "translationState") {
          return Promise.resolve({ ok: true });
        }
        if (message.type === "getPageTranslationState") {
          return Promise.resolve({
            ok: true,
            url: "https://example.test/article",
            title: "Test Article",
            pageSessionID: "mock-page-session",
            trackedCount: discoveredSegments.length,
            translatedCount: appliedTranslations.length,
            hasTranslations: appliedTranslations.length > 0
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
      executeScript() {
        return Promise.resolve();
      }
    }
  };

  const context = vm.createContext({
    chrome,
    console,
    crypto: { randomUUID, subtle: webcrypto.subtle },
    TextEncoder,
    setTimeout,
    clearTimeout
  });
  vm.runInContext(source, context, { filename: "background.js" });
  assert(backgroundListener, "background listener was not registered");
  assert(tabUpdatedListener, "tab update listener was not registered");
  assert(tabActivatedListener, "tab activation listener was not registered");
  assert(contextMenuClickListener, "context menu click listener was not registered");
  assert(contextMenuShownListener, "context menu shown listener was not registered");
  assert(nativePortDisconnectListener === null, "native port should not connect before a native request");
  assert(contextMenuItems.size === 1, `expected one top-level context menu item, got ${contextMenuItems.size}`);
  assert(contextMenuItems.has("llmtranslate-toggle-page"), "toggle context menu was not created");
  assert(contextMenuItems.get("llmtranslate-toggle-page").title === "翻译/原文", "toggle context menu should use the requested label");
  assert(contextMenuItems.get("llmtranslate-toggle-page").enabled !== false, "toggle context menu should start enabled");

  contextMenuClickListener({ menuItemId: "llmtranslate-toggle-page" }, { id: 7 });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "background did not apply all translations");
  const finalState = await sendBackgroundMessage(backgroundListener, { type: "getPopupState", tabID: 7 });

  assert(nativeTranslatePayloads.length === 1, `expected one translateSegments call, got ${nativeTranslatePayloads.length}`);
  assert(nativeTranslatePayloads[0].segments.length === 2, "expected repeated text to be sent once per batch");
  assert(nativeTranslatePayloads[0].segments.some((segment) => segment.segmentID === "s1"), "expected first repeated segment to be translated");
  assert(!nativeTranslatePayloads[0].segments.some((segment) => segment.segmentID === "s2"), "expected duplicate repeated segment to reuse the first translation");
  assert(appliedTranslations.some((item) => item.segmentID === "s2" && item.translation === "重复标签"), "expected duplicate node to receive reused translation");
  assert(startSessionMessages[0]?.pendingIndicatorStyle === "flipText", "expected background to pass configured pending indicator style to content script");
  assert(finalState.status === "translated", `expected translated state, got ${finalState.status}`);
  assert(finalState.done === 3 && finalState.total === 3, `expected 3/3 final progress, got ${finalState.done}/${finalState.total}`);
  assert(popupStates.some((message) => message.state?.modelName === "stub-model"), "expected model name to be published to popup state");
  assert(contextMenuItems.get("llmtranslate-toggle-page").enabled === true, "toggle context menu should be enabled after translation");

  contextMenuClickListener({ menuItemId: "llmtranslate-toggle-page" }, { id: 7 });
  await waitUntil(() => appliedTranslations.length === 0, 2_000, "context menu toggle restore did not clear translations");
  const restoredState = await sendBackgroundMessage(backgroundListener, { type: "getPopupState", tabID: 7 });
  assert(restoredState.hasTranslations === false, "context menu toggle should clear translated state");
  assert(contextMenuItems.get("llmtranslate-toggle-page").enabled === true, "toggle context menu should stay enabled after restore");

  const nativeCallsAfterFirstTranslate = nativeTranslatePayloads.length;
  await sendBackgroundMessage(backgroundListener, { type: "translatePage", tabID: 7 });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "background did not re-apply translations");
  assert(nativeTranslatePayloads.length === nativeCallsAfterFirstTranslate, "second translation should reuse persistent cache without native translateSegments");
  const clearedState = await sendBackgroundMessage(backgroundListener, {
    type: "clearCurrentPageCache",
    tabID: 7,
    tabURL: "https://example.test/article"
  });
  assert(clearedState.status === "idle", `expected idle state after clearing cache, got ${clearedState.status}`);
  assert(clearedState.hasTranslations === false, "clear cache should clear translated state");
  assert(clearedState.message.includes("Cleared 2 cached translations"), `unexpected clear cache message: ${clearedState.message}`);
  assert(appliedTranslations.length === 0, "clear cache should restore page translations");
  assert(Object.keys(localStorageData.webPageTranslationCacheV1 || {}).length === 0, "clear cache should remove current page storage entries");
  await sendBackgroundMessage(backgroundListener, { type: "translatePage", tabID: 7 });
  await waitUntil(() => appliedTranslations.length === 3, 2_000, "background did not translate after clearing cache");
  assert(nativeTranslatePayloads.length === nativeCallsAfterFirstTranslate + 1, "translation after clearing cache should call native translateSegments again");
  tabUpdatedListener(7, { status: "loading" }, { id: 7 });
  const reloadedState = await sendBackgroundMessage(backgroundListener, { type: "getPopupState", tabID: 7 });
  assert(reloadedState.status === "idle", `expected idle state after reload, got ${reloadedState.status}`);
  assert(reloadedState.hasTranslations === false, "reload should clear translated state");
  assert(contextMenuItems.get("llmtranslate-toggle-page").enabled === true, "toggle context menu should stay enabled after reload");
}

async function runContentScriptDomCheck() {
  await fs.access(chromePath);
  const profileDir = await fs.mkdtemp(path.join(os.tmpdir(), "llmtranslate-extension-dom-"));
  const chrome = spawn(chromePath, [
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
  chrome.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  let client;
  try {
    const { port } = await waitForDevToolsPort(profileDir);
    const pageURL = pathToFileURL(path.join(extensionRoot, "test-pages", "article.html")).href;
    const target = await createPageTarget(port, pageURL);
    client = await CDPClient.connect(target.webSocketDebuggerUrl);

    await client.send("Page.enable");
    await client.send("Runtime.enable");
    await waitForReadyState(client, "complete");

    await evaluate(client, `
      (() => {
        window.__llmTranslateMessages = [];
        window.__llmTranslateListener = null;
        window.chrome = {
          runtime: {
            onMessage: {
              addListener(listener) {
                window.__llmTranslateListener = listener;
              }
            },
            sendMessage(message) {
              window.__llmTranslateMessages.push(message);
              return Promise.resolve({ ok: true });
            }
          }
        };
        return true;
      })()
    `);

    const source = await fs.readFile(path.join(extensionRoot, "contentScript.js"), "utf8");
    await evaluate(client, `(0, eval)(${JSON.stringify(source)}); true;`);
    const startResult = await sendContentMessage(client, { type: "startSession", pageSessionID: "dom-check-session" });

    assert(startResult.ok === true, "content script did not start a session");
    assert(Array.isArray(startResult.segments) && startResult.segments.length > 0, "expected visible segments");
    const duplicateSegments = startResult.segments.filter((segment) => segment.text === "Repeated label for duplicate translation.");
    assert(duplicateSegments.length === 2, `expected two duplicate text segments, got ${duplicateSegments.length}`);
    assert(new Set(duplicateSegments.map((segment) => segment.textHash)).size === 1, "expected duplicate text to share the same textHash");
    assert(!startResult.segments.some((segment) => segment.text.includes("Code blocks should not be translated")), "code block text should be skipped");
    assert(!startResult.segments.some((segment) => segment.text.includes("Do not translate input values")), "input value text should be skipped");
    const initialSpinnerState = await evaluate(client, `
      (() => ({
        spinnerCount: document.querySelectorAll(".llmtranslate-segment-spinner").length,
        styleCount: document.querySelectorAll("style[data-llm-translate-spinner-style='true']").length,
        spinnerText: Array.from(document.querySelectorAll(".llmtranslate-segment-spinner")).map((node) => node.textContent).join("")
      }))()
    `);
    assert(initialSpinnerState.spinnerCount === startResult.segments.length, `expected one spinner per segment, got ${initialSpinnerState.spinnerCount}/${startResult.segments.length}`);
    assert(initialSpinnerState.styleCount === 1, "expected one shared spinner style tag");
    assert(initialSpinnerState.spinnerText === "", "segment spinners should not add visible text content");

    const translations = startResult.segments.map((segment, index) => ({
      segmentID: segment.segmentID,
      status: "translated",
      translation: segment.text === "Repeated label for duplicate translation." ? "重复标签" : `译文 ${index + 1}`
    }));
    await sendContentMessage(client, { type: "applyTranslations", translations });
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
        spinnerCount: document.querySelectorAll(".llmtranslate-segment-spinner").length
      }))()
    `);
    assert(translatedState.duplicates.every((text) => text === "重复标签"), "expected all duplicate nodes to be translated");
    assert(translatedState.code.includes("Code blocks should not be translated"), "code block should remain unchanged");
    assert(translatedState.inputValue === "Do not translate input values", "input value should remain unchanged");
    assert(translatedState.linkHref === "https://example.com/", "link href should remain unchanged");
    assert(!translatedState.overlayText.includes("CancelRestore"), "overlay controls should live in shadow DOM, not page text");
    assert(translatedState.spinnerCount === 0, "segment spinners should be removed after translations apply");
    await sendContentMessage(client, {
      type: "translationState",
      state: {
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
    const messages = await evaluate(client, "window.__llmTranslateMessages");
    assert(
      messages.some((message) => message.type === "segmentsDiscovered" && message.segments?.some((segment) => segment.text === incrementalText)),
      "expected incremental visible text to be reported"
    );
    const incrementalSpinnerState = await evaluate(client, `
      (() => ({
        spinnerCount: document.querySelectorAll(".llmtranslate-segment-spinner").length,
        incrementalHasSpinner: Boolean(document.querySelector("[data-incremental] .llmtranslate-segment-spinner"))
      }))()
    `);
    assert(incrementalSpinnerState.spinnerCount > 0, "incremental discovered text should show a pending spinner");
    assert(incrementalSpinnerState.incrementalHasSpinner === true, "incremental paragraph should contain a pending spinner");

    await sendContentMessage(client, { type: "restore" });
    const pageRestoredTranslationState = await sendContentMessage(client, { type: "getPageTranslationState" });
    assert(pageRestoredTranslationState.hasTranslations === false, "content script should report restored page state");
    assert(pageRestoredTranslationState.translatedCount === 0, "content script should clear translated segment count after restore");
    const restoredState = await evaluate(client, `
      (() => ({
        duplicates: Array.from(document.querySelectorAll("[data-duplicate]")).map((node) => node.textContent.trim()),
        code: document.querySelector("code").textContent,
        inputValue: document.querySelector("input").value,
        spinnerCount: document.querySelectorAll(".llmtranslate-segment-spinner").length
      }))()
    `);
    assert(restoredState.duplicates.every((text) => text === "Repeated label for duplicate translation."), "restore should return duplicate nodes to original text");
    assert(restoredState.code.includes("Code blocks should not be translated"), "restore should leave code block unchanged");
    assert(restoredState.inputValue === "Do not translate input values", "restore should leave input value unchanged");
    assert(restoredState.spinnerCount === 0, "restore should remove pending segment spinners");

    await evaluate(client, "window.__llmTranslateMessages = []");
    const flipStartResult = await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "flip-style-check",
      pendingIndicatorStyle: "flipText"
    });
    const flipInitialState = await evaluate(client, `
      (() => ({
        spinnerCount: document.querySelectorAll(".llmtranslate-segment-spinner").length,
        flipCount: document.querySelectorAll(".llmtranslate-segment-flip").length,
        pendingCount: document.querySelectorAll(".llmtranslate-segment-flip-pending").length,
        completeCount: document.querySelectorAll(".llmtranslate-segment-flip-complete").length,
        tileCount: document.querySelectorAll(".llmtranslate-segment-flip-tile").length
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
        flipCount: document.querySelectorAll(".llmtranslate-segment-flip").length,
        pendingCount: document.querySelectorAll(".llmtranslate-segment-flip-pending").length,
        completeCount: document.querySelectorAll(".llmtranslate-segment-flip-complete").length,
        tileCount: document.querySelectorAll(".llmtranslate-segment-flip-tile").length,
        flipTexts: Array.from(document.querySelectorAll(".llmtranslate-segment-flip")).map((node) => node.textContent || ""),
        flipFinalTexts: Array.from(document.querySelectorAll(".llmtranslate-segment-flip")).map((node) => node.dataset.llmTranslateFinalText || ""),
        styleCount: document.querySelectorAll("style[data-llm-translate-spinner-style='true']").length
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
        flipCount: document.querySelectorAll(".llmtranslate-segment-flip").length,
        pageText: document.documentElement.textContent
      }))()
    `);
    assert(flipSettledState.flipCount === 0, "flip text indicator should settle back to a plain text node");
    assert(flipSettledState.pageText.includes("README.md yesterday 1"), "settled flip text translation should remain visible");
    await evaluate(client, "new Promise((resolve) => setTimeout(resolve, 700))");
    const postFlipMessages = await evaluate(client, "window.__llmTranslateMessages");
    assert(
      !postFlipMessages.some((message) => message.type === "segmentsDiscovered" && message.segments?.some((segment) => segment.text.includes("README.md yesterday"))),
      "settled flip text that still contains English should not be rediscovered as new segments"
    );
    await sendContentMessage(client, { type: "restore" });

    await evaluate(client, "window.__llmTranslateMessages = []");
    await sendContentMessage(client, {
      type: "startSession",
      pageSessionID: "flip-stale-cleanup-check",
      pendingIndicatorStyle: "flipText"
    });
    const stalePendingBefore = await evaluate(client, "document.querySelectorAll('.llmtranslate-segment-flip-pending').length");
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
        flipCount: document.querySelectorAll(".llmtranslate-segment-flip").length,
        messages: window.__llmTranslateMessages
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
        spinnerCount: document.querySelectorAll(".llmtranslate-segment-spinner").length,
        flipCount: document.querySelectorAll(".llmtranslate-segment-flip").length
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
        spinnerCount: document.querySelectorAll(".llmtranslate-segment-spinner").length,
        flipCount: document.querySelectorAll(".llmtranslate-segment-flip").length,
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
        window.__llmTranslateSendMessageMode = "throw";
        window.chrome.runtime.sendMessage = () => {
          throw new Error("Extension context invalidated.");
        };
        const before = {
          spinnerCount: document.querySelectorAll(".llmtranslate-segment-spinner").length,
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
            spinnerCount: document.querySelectorAll(".llmtranslate-segment-spinner").length,
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
        window.__llmTranslateSendMessageMode = "reject";
        window.chrome.runtime.sendMessage = (_message) => {
          return Promise.reject(new Error("Extension context invalidated."));
        };
        const before = {
          spinnerCount: document.querySelectorAll(".llmtranslate-segment-spinner").length,
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
            spinnerCount: document.querySelectorAll(".llmtranslate-segment-spinner").length,
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
  } catch (error) {
    error.message = `${error.message}\nChrome stderr:\n${stderr.slice(-4_000)}`;
    throw error;
  } finally {
    client?.close();
    chrome.kill("SIGTERM");
    await waitForExit(chrome, 2_000).catch(() => chrome.kill("SIGKILL"));
    await fs.rm(profileDir, { recursive: true, force: true });
  }
}

function sendBackgroundMessage(listener, message) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`background message timed out: ${message.type}`)), 2_000);
    try {
      listener(message, {}, (response) => {
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
      if (!window.__llmTranslateListener) {
        reject(new Error("content script listener is not installed"));
        return;
      }
      window.__llmTranslateListener(${JSON.stringify(message)}, {}, resolve);
    })
  `);
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
    throw new Error(`Could not create Chrome target: ${response.status} ${response.statusText}`);
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
  throw new Error("Chrome did not publish DevToolsActivePort");
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

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
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
    if (!message.id || !this.pending.has(message.id)) {
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

await runBackgroundBatchCheck();
await runContentScriptDomCheck();
console.log("Browser extension DOM checks passed");
