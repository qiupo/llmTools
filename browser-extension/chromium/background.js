const HOST_NAME = "com.llmtranslate.native_host";
const VERSION = "0.1.0";
const MAX_SEGMENTS_PER_BATCH = 20;
const MAX_CHARS_PER_BATCH = 2000;
const MAX_SEGMENTS_PER_JOB = 320;
const MAX_QUEUE_BACKLOG = 80;
const RESUME_QUEUE_BACKLOG = 36;
const MAX_INLINE_PENDING_INDICATORS = 80;
const MAX_ANIMATED_SEGMENTS = 48;
const MENU_TOGGLE_ID = "llmtranslate-toggle-page";
const TARGET_LANGUAGE = "zh-Hans";
const TRANSLATION_CACHE_KEY = "webPageTranslationCacheV1";
const TRANSLATION_CACHE_MAX_ENTRIES = 2000;
const DEFAULT_PENDING_INDICATOR_STYLE = "loading";
const NATIVE_REQUEST_TIMEOUT_MS = 130000;

const tabStates = new Map();
const tabJobs = new Map();
const pendingNativeRequests = new Map();
let pendingIndicatorStyle = DEFAULT_PENDING_INDICATOR_STYLE;
let nativePort = null;

setupContextMenus();

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message, sender).then(sendResponse).catch((error) => {
    const tabID = message?.tabID || sender?.tab?.id;
    sendResponse(stateFor(tabID, "failed", error?.message || String(error)));
  });
  return true;
});

if (chrome.tabs?.onUpdated) {
  chrome.tabs.onUpdated.addListener((tabID, changeInfo) => {
    if (changeInfo.status === "loading" || changeInfo.url) {
      resetTabState(tabID, "Page changed. Ready.");
    }
  });
}

if (chrome.tabs?.onActivated) {
  chrome.tabs.onActivated.addListener(({ tabId }) => {
    refreshContextMenu(tabId);
  });
}

if (chrome.tabs?.onRemoved) {
  chrome.tabs.onRemoved.addListener((tabID) => {
    const job = tabJobs.get(tabID);
    if (job) {
      job.cancelled = true;
    }
    tabStates.delete(tabID);
    tabJobs.delete(tabID);
  });
}

async function handleMessage(message, sender) {
  const tabID = message?.tabID || sender?.tab?.id;
  switch (message?.type) {
    case "getPopupState":
      return getSyncedState(tabID);
    case "checkStatus":
      return checkStatus(tabID);
    case "translatePage":
      return translatePage(tabID);
    case "restorePage":
      return restorePage(tabID);
    case "cancelTranslation":
      return cancelTranslation(tabID);
    case "segmentsDiscovered":
      return enqueueDiscoveredSegments(sender?.tab?.id, message);
    default:
      return getState(tabID);
  }
}

function getState(tabID) {
  if (!tabStates.has(tabID)) {
    tabStates.set(tabID, {
      status: "idle",
      message: "Ready",
      total: 0,
      done: 0,
      failed: 0,
      hasTranslations: false,
      modelName: "",
      pageSessionID: null,
      jobID: null,
      pageStateInvalidated: false
    });
  }
  return tabStates.get(tabID);
}

function stateFor(tabID, status, message, patch = {}) {
  const next = { ...getState(tabID), ...patch, status, message };
  tabStates.set(tabID, next);
  refreshContextMenu(tabID, next);
  chrome.runtime.sendMessage({ type: "popupState", state: next }).catch(() => {});
  if (tabID) {
    sendContent(tabID, { type: "translationState", state: next }).catch(() => {});
  }
  return next;
}

function resetTabState(tabID, message = "Ready") {
  if (!tabID) {
    return getState(tabID);
  }
  const job = tabJobs.get(tabID);
  if (job) {
    job.cancelled = true;
  }
  tabJobs.delete(tabID);
  return stateFor(tabID, "idle", message, {
    done: 0,
    failed: 0,
    total: 0,
    hasTranslations: false,
    pageSessionID: null,
    jobID: null,
    pageStateInvalidated: true
  });
}

function getJob(tabID) {
  if (!tabJobs.has(tabID)) {
    tabJobs.set(tabID, {
      pageSessionID: crypto.randomUUID(),
      jobID: crypto.randomUUID(),
      queue: [],
      queuedIDs: new Set(),
      cache: new Map(),
      urlHash: "",
      title: "",
      targetLanguage: TARGET_LANGUAGE,
      running: false,
      cancelled: false,
      discovered: 0,
      done: 0,
      failed: 0,
      modelName: "",
      storageCache: null,
      pendingCacheEntries: [],
      discoveryPaused: false
    });
  }
  return tabJobs.get(tabID);
}

async function checkStatus(tabID) {
  const response = await nativeRequest("getStatus", {});
  const modelName = response?.payload?.modelName || "";
  pendingIndicatorStyle = normalizePendingIndicatorStyle(response?.payload?.pendingIndicatorStyle);
  const current = await getSyncedState(tabID).catch(() => getState(tabID));
  if (current.hasTranslations) {
    return stateFor(tabID, current.status || "translated", current.message || "Translated.", { modelName });
  }
  return stateFor(tabID, "idle", "Local app connected.", {
    modelName,
    hasTranslations: false,
    done: 0,
    failed: 0,
    total: 0,
    pageSessionID: null,
    jobID: null,
    pageStateInvalidated: Boolean(current.pageStateInvalidated)
  });
}

async function getSyncedState(tabID) {
  const current = getState(tabID);
  if (!tabID) {
    return current;
  }
  if (current.pageStateInvalidated && !current.hasTranslations) {
    refreshContextMenu(tabID, current);
    return current;
  }
  try {
    const pageState = await sendContent(tabID, { type: "getPageTranslationState" });
    const hasTranslations = Boolean(pageState?.hasTranslations);
    if (hasTranslations) {
      const done = Math.max(current.done || 0, pageState.translatedCount || 0);
      const total = Math.max(current.total || 0, pageState.trackedCount || done);
      const status = current.hasTranslations && current.status ? current.status : "translated";
      const message = current.hasTranslations && current.message
        ? current.message
        : `Translated ${done}/${total} segments.`;
      return stateFor(tabID, status, message, {
        hasTranslations: true,
        done,
        total,
        pageSessionID: pageState.pageSessionID || current.pageSessionID,
        pageStateInvalidated: false
      });
    }
    return stateFor(tabID, "idle", "Ready", {
      hasTranslations: false,
      done: 0,
      failed: 0,
      total: 0,
      pageSessionID: null,
      jobID: null,
      pageStateInvalidated: false
    });
  } catch {
    if (current.hasTranslations || current.status === "translated" || current.status === "partiallyTranslated" || current.status === "restored") {
      return resetTabState(tabID, "Ready");
    }
    refreshContextMenu(tabID, current);
    return current;
  }
}

async function translatePage(tabID) {
  await ensureContentScript(tabID);
  const status = await checkStatus(tabID);
  const job = {
    pageSessionID: crypto.randomUUID(),
    jobID: crypto.randomUUID(),
    queue: [],
    queuedIDs: new Set(),
    cache: new Map(),
    urlHash: "",
    title: "",
    targetLanguage: TARGET_LANGUAGE,
    running: false,
    cancelled: false,
    discovered: 0,
    done: 0,
    failed: 0,
    modelName: status.modelName || "",
    storageCache: null,
    pendingCacheEntries: [],
    discoveryPaused: false
  };
  tabJobs.set(tabID, job);

  stateFor(tabID, "discovering", "Discovering visible English text...", {
    modelName: job.modelName,
    done: 0,
    failed: 0,
    total: 0,
    hasTranslations: false,
    pageSessionID: job.pageSessionID,
    jobID: job.jobID,
    pageStateInvalidated: false
  });

  const discovered = await sendContent(tabID, {
    type: "startSession",
    pageSessionID: job.pageSessionID,
    pendingIndicatorStyle,
    segmentBudget: MAX_SEGMENTS_PER_JOB,
    maxInlinePendingIndicators: MAX_INLINE_PENDING_INDICATORS,
    maxAnimatedSegments: MAX_ANIMATED_SEGMENTS
  });
  job.urlHash = await sha256(discovered?.url || "");
  job.title = discovered?.title || "";
  await hydrateJobCache(job, discovered?.segments || []);
  enqueueSegments(job, discovered?.segments || []);
  await syncDiscoveryPressure(tabID, job);
  if (!job.queue.length) {
    return stateFor(tabID, "idle", "No visible English text found.", {
      total: 0,
      done: 0,
      failed: 0,
      pageStateInvalidated: false
    });
  }

  drainQueue(tabID).catch((error) => {
    stateFor(tabID, "failed", error?.message || String(error));
  });
  return getState(tabID);
}

async function enqueueDiscoveredSegments(tabID, message) {
  if (!tabID || !tabJobs.has(tabID)) {
    return { ok: false };
  }
  const job = getJob(tabID);
  if (job.cancelled || getState(tabID).status === "restored") {
    return { ok: false };
  }
  const segments = message?.segments || [];
  await hydrateJobCache(job, segments);
  enqueueSegments(job, segments);
  await syncDiscoveryPressure(tabID, job);
  if (!job.running && job.queue.length) {
    drainQueue(tabID).catch((error) => {
      stateFor(tabID, "failed", error?.message || String(error));
    });
  }
  return { ok: true, queued: job.queue.length };
}

function enqueueSegments(job, segments) {
  for (const segment of segments) {
    if (job.discovered >= MAX_SEGMENTS_PER_JOB) {
      break;
    }
    if (!segment?.segmentID || !segment?.textHash || job.queuedIDs.has(segment.segmentID)) {
      continue;
    }
    job.queuedIDs.add(segment.segmentID);
    job.discovered += 1;
    const cachedTranslation = getCachedTranslation(job, segment);
    if (cachedTranslation) {
      job.queue.push({ ...segment, cachedTranslation });
    } else {
      job.queue.push(segment);
    }
  }
}

async function syncDiscoveryPressure(tabID, job) {
  if (!tabID || !job) {
    return;
  }
  let shouldPause;
  if (job.cancelled || job.discovered >= MAX_SEGMENTS_PER_JOB) {
    shouldPause = true;
  } else if (job.discoveryPaused) {
    shouldPause = job.queue.length > RESUME_QUEUE_BACKLOG;
  } else {
    shouldPause = job.queue.length >= MAX_QUEUE_BACKLOG;
  }
  if (job.discoveryPaused === shouldPause) {
    return;
  }
  job.discoveryPaused = shouldPause;
  await sendContent(tabID, {
    type: "setDiscoveryPaused",
    paused: shouldPause,
    reason: job.discovered >= MAX_SEGMENTS_PER_JOB ? "budget" : "backlog",
    segmentBudget: MAX_SEGMENTS_PER_JOB
  }).catch(() => {});
}

async function drainQueue(tabID) {
  const job = getJob(tabID);
  if (job.running) {
    return;
  }
  job.running = true;
  try {
    while (job.queue.length && !job.cancelled) {
      const cached = [];
      const toTranslate = [];
      const duplicateByHash = new Map();
      let selectedCount = 0;
      let charsInBatch = 0;
      while (job.queue.length && selectedCount < MAX_SEGMENTS_PER_BATCH) {
        const next = job.queue.shift();
        const cachedTranslation = next.cachedTranslation || getCachedTranslation(job, next);
        if (cachedTranslation) {
          cached.push({
            segmentID: next.segmentID,
            translation: cachedTranslation,
            status: "translated"
          });
          selectedCount += 1;
          continue;
        }
        if (duplicateByHash.has(next.textHash)) {
          duplicateByHash.get(next.textHash).push(next);
          selectedCount += 1;
          continue;
        }
        const nextChars = charsInBatch + next.text.length;
        if (toTranslate.length && nextChars > MAX_CHARS_PER_BATCH) {
          job.queue.unshift(next);
          break;
        }
        toTranslate.push(next);
        duplicateByHash.set(next.textHash, []);
        charsInBatch = nextChars;
        selectedCount += 1;
      }

      if (cached.length) {
        await sendContent(tabID, { type: "applyTranslations", translations: cached });
        job.done += cached.length;
        await syncDiscoveryPressure(tabID, job);
      }

      if (toTranslate.length) {
        stateFor(tabID, "translating", `Translating ${job.done}/${job.discovered} segments...`, {
          done: job.done,
          failed: job.failed,
          total: job.discovered,
          hasTranslations: job.done > 0,
          modelName: job.modelName,
          pageSessionID: job.pageSessionID,
          jobID: job.jobID,
          pageStateInvalidated: false
        });
        const result = await nativeRequest("translateSegments", {
          jobID: job.jobID,
          sourceLanguage: "en",
          targetLanguage: TARGET_LANGUAGE,
          urlHash: job.urlHash,
          title: job.title,
          segments: toTranslate.map((segment) => ({
            segmentID: segment.segmentID,
            text: segment.text,
            tagName: segment.tagName,
            blockContext: segment.blockContext,
            priority: segment.priority,
            textHash: segment.textHash
          }))
        }, { tabID, pageSessionID: job.pageSessionID });

        const translations = result?.payload?.translations || [];
        const translationsByHash = new Map();
        const cacheEntries = [];
        job.modelName = result?.payload?.modelName || job.modelName;
        for (const translation of translations) {
          const source = toTranslate.find((segment) => segment.segmentID === translation.segmentID);
          if (source) {
            translationsByHash.set(source.textHash, translation);
          }
          if (source && translation.status === "translated" && translation.translation) {
            setCachedTranslation(job, source, translation.translation);
            cacheEntries.push(cacheEntryForSegment(job, source, translation.translation));
          }
        }
        queueTranslationCacheEntries(job, cacheEntries);
        const duplicatedTranslations = [];
        for (const [textHash, duplicateSegments] of duplicateByHash.entries()) {
          const sourceTranslation = translationsByHash.get(textHash);
          if (!sourceTranslation) {
            continue;
          }
          for (const duplicateSegment of duplicateSegments) {
            duplicatedTranslations.push({
              ...sourceTranslation,
              segmentID: duplicateSegment.segmentID
            });
          }
        }
        const translationsToApply = translations.concat(duplicatedTranslations);
        await sendContent(tabID, { type: "applyTranslations", translations: translationsToApply });
        job.done += translationsToApply.filter((item) => item.status === "translated").length;
        job.failed += translationsToApply.filter((item) => item.status === "failed").length;
        await syncDiscoveryPressure(tabID, job);
      }

      stateFor(tabID, "translating", `Translating ${job.done}/${job.discovered} segments...`, {
        done: job.done,
        failed: job.failed,
        total: job.discovered,
        hasTranslations: job.done > 0,
        modelName: job.modelName,
        pageStateInvalidated: false
      });
    }

    if (job.cancelled) {
      stateFor(tabID, "cancelled", "Translation cancelled.", {
        done: job.done,
        failed: job.failed,
        total: job.discovered,
        hasTranslations: job.done > 0,
        pageStateInvalidated: false
      });
    } else {
      const status = job.failed > 0 ? "partiallyTranslated" : "translated";
      const message = job.failed > 0
        ? `Translated ${job.done}/${job.discovered}; ${job.failed} failed.`
        : `Translated ${job.done}/${job.discovered} segments.`;
      stateFor(tabID, status, message, {
        done: job.done,
        failed: job.failed,
        total: job.discovered,
        hasTranslations: job.done > 0,
        modelName: job.modelName,
        pageStateInvalidated: false
      });
    }
  } finally {
    await flushTranslationCache(job).catch(() => {});
    job.running = false;
  }
}

async function restorePage(tabID) {
  const job = tabJobs.get(tabID);
  if (job) {
    job.cancelled = true;
    await flushTranslationCache(job).catch(() => {});
  }
  await sendContent(tabID, { type: "restore" }).catch(() => {});
  tabJobs.delete(tabID);
  return stateFor(tabID, "restored", "Original text restored.", {
    hasTranslations: false,
    done: 0,
    failed: 0,
    total: 0,
    jobID: null,
    pageSessionID: null,
    pageStateInvalidated: false
  });
}

async function cancelTranslation(tabID) {
  const job = tabJobs.get(tabID);
  stateFor(tabID, "cancelled", "Cancelling...");
  if (job) {
    job.cancelled = true;
    job.queue = [];
    await flushTranslationCache(job).catch(() => {});
    if (job.jobID) {
      await nativeRequest("cancelJob", { jobID: job.jobID }, { tabID, pageSessionID: job.pageSessionID }).catch(() => {});
    }
  }
  await sendContent(tabID, { type: "cancel" }).catch(() => {});
  return stateFor(tabID, "cancelled", "Translation cancelled.", {
    hasTranslations: getState(tabID).hasTranslations,
    jobID: null,
    pageStateInvalidated: false
  });
}

async function ensureContentScript(tabID) {
  try {
    await sendContent(tabID, { type: "ping" });
  } catch {
    await chrome.scripting.executeScript({
      target: { tabId: tabID },
      files: ["contentScript.js"]
    });
  }
}

async function sendContent(tabID, message) {
  return chrome.tabs.sendMessage(tabID, message);
}

async function hydrateJobCache(job, segments) {
  if (!segments.length || !job.urlHash) {
    return;
  }
  const cache = await loadJobStorageCache(job);
  for (const segment of segments) {
    const entry = cache[translationCacheID(job, segment)];
    if (entry?.sourceText === segment.text && entry.translation) {
      setCachedTranslation(job, segment, entry.translation);
    }
  }
}

async function loadJobStorageCache(job) {
  if (!job.storageCache) {
    job.storageCache = await loadTranslationCache();
  }
  return job.storageCache;
}

function getCachedTranslation(job, segment) {
  return job.cache.get(translationCacheID(job, segment));
}

function setCachedTranslation(job, segment, translation) {
  job.cache.set(translationCacheID(job, segment), translation);
}

function translationCacheID(job, segment) {
  return `${job.targetLanguage || TARGET_LANGUAGE}:${job.urlHash || ""}:${segment.textHash}`;
}

function cacheEntryForSegment(job, segment, translation) {
  return {
    id: translationCacheID(job, segment),
    sourceText: segment.text,
    translation,
    targetLanguage: job.targetLanguage || TARGET_LANGUAGE,
    urlHash: job.urlHash || "",
    textHash: segment.textHash,
    modelName: job.modelName || "",
    updatedAt: Date.now()
  };
}

async function loadTranslationCache() {
  if (!chrome.storage?.local) {
    return {};
  }
  try {
    const result = await chrome.storage.local.get(TRANSLATION_CACHE_KEY);
    const cache = result?.[TRANSLATION_CACHE_KEY];
    return cache && typeof cache === "object" ? cache : {};
  } catch {
    return {};
  }
}

function queueTranslationCacheEntries(job, entries) {
  if (!entries.length) {
    return;
  }
  for (const entry of entries) {
    if (job.storageCache) {
      job.storageCache[entry.id] = entry;
    }
    job.pendingCacheEntries.push(entry);
  }
}

async function flushTranslationCache(job) {
  if (!job?.pendingCacheEntries?.length || !chrome.storage?.local) {
    return;
  }
  const cache = job.storageCache || await loadTranslationCache();
  for (const entry of job.pendingCacheEntries) {
    cache[entry.id] = entry;
  }
  pruneTranslationCache(cache);
  await chrome.storage.local.set({ [TRANSLATION_CACHE_KEY]: cache }).catch(() => {});
  job.storageCache = cache;
  job.pendingCacheEntries = [];
}

function pruneTranslationCache(cache) {
  const keys = Object.keys(cache);
  if (keys.length <= TRANSLATION_CACHE_MAX_ENTRIES) {
    return;
  }
  keys
    .sort((left, right) => (cache[left]?.updatedAt || 0) - (cache[right]?.updatedAt || 0))
    .slice(0, keys.length - TRANSLATION_CACHE_MAX_ENTRIES)
    .forEach((key) => {
      delete cache[key];
    });
}

function setupContextMenus() {
  if (!chrome.contextMenus) {
    return;
  }
  const createMenus = () => {
    chrome.contextMenus.removeAll(() => {
      ignoreLastError();
      chrome.contextMenus.create({
        id: MENU_TOGGLE_ID,
        title: "翻译/原文",
        contexts: ["page"]
      }, ignoreLastError);
    });
  };
  chrome.runtime.onInstalled?.addListener(createMenus);
  chrome.runtime.onStartup?.addListener(createMenus);
  chrome.contextMenus.onClicked.addListener((info, tab) => {
    const tabID = tab?.id;
    if (!tabID) {
      return;
    }
    if (info.menuItemId === MENU_TOGGLE_ID) {
      togglePageTranslation(tabID).catch((error) => {
        stateFor(tabID, "failed", error?.message || String(error));
      });
    }
  });
  chrome.contextMenus.onShown?.addListener((_info, tab) => {
    const tabID = tab?.id;
    if (!tabID) {
      return;
    }
    getSyncedState(tabID).finally(() => {
      chrome.contextMenus.refresh?.();
    });
  });
  createMenus();
}

function refreshContextMenu(tabID, state = getState(tabID)) {
  if (!chrome.contextMenus?.update || !tabID) {
    return;
  }
  const active = state.status === "discovering" || state.status === "translating";
  chrome.contextMenus.update(MENU_TOGGLE_ID, { enabled: !active, title: "翻译/原文" }, ignoreLastError);
}

function ignoreLastError() {
  void chrome.runtime.lastError;
}

async function togglePageTranslation(tabID) {
  const state = await getSyncedState(tabID);
  if (state.hasTranslations) {
    return restorePage(tabID);
  }
  return translatePage(tabID);
}

async function nativeRequest(type, payload, context = {}) {
  const requestID = crypto.randomUUID();
  const message = {
    protocolVersion: 1,
    requestID,
    type,
    browserID: "chrome",
    extensionVersion: VERSION,
    tabID: context.tabID,
    pageSessionID: context.pageSessionID,
    sentAt: new Date().toISOString(),
    payload
  };
  const response = await postNativeMessage(message);
  if (!response || response.status === "error") {
    throw new Error(response?.error?.message || "Native host request failed.");
  }
  return response;
}

function postNativeMessage(message) {
  return new Promise((resolve, reject) => {
    let port;
    try {
      port = ensureNativePort();
    } catch (error) {
      reject(error);
      return;
    }

    const timeout = setTimeout(() => {
      pendingNativeRequests.delete(message.requestID);
      reject(new Error("Native host request timed out."));
    }, NATIVE_REQUEST_TIMEOUT_MS);

    pendingNativeRequests.set(message.requestID, { resolve, reject, timeout });
    try {
      port.postMessage(message);
    } catch (error) {
      clearTimeout(timeout);
      pendingNativeRequests.delete(message.requestID);
      reject(error);
    }
  });
}

function ensureNativePort() {
  if (nativePort) {
    return nativePort;
  }
  nativePort = chrome.runtime.connectNative(HOST_NAME);
  nativePort.onMessage.addListener((response) => {
    const requestID = response?.requestID;
    const pending = requestID ? pendingNativeRequests.get(requestID) : null;
    if (!pending) {
      return;
    }
    clearTimeout(pending.timeout);
    pendingNativeRequests.delete(requestID);
    pending.resolve(response);
  });
  nativePort.onDisconnect.addListener(() => {
    const message = chrome.runtime.lastError?.message || "Native host disconnected.";
    nativePort = null;
    for (const [requestID, pending] of pendingNativeRequests.entries()) {
      clearTimeout(pending.timeout);
      pending.reject(new Error(message));
      pendingNativeRequests.delete(requestID);
    }
  });
  return nativePort;
}

function normalizePendingIndicatorStyle(style) {
  if (style === "flipText" || style === "none" || style === "loading") {
    return style;
  }
  return DEFAULT_PENDING_INDICATOR_STYLE;
}

async function sha256(text) {
  const bytes = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
