const HOST_NAME = "com.llmtools.native_host";
const VERSION = "0.1.0";
const LOCAL_SEGMENTS_PER_BATCH = 5;
const LOCAL_CHARS_PER_BATCH = 800;
const REMOTE_SEGMENTS_PER_BATCH = 5;
const REMOTE_CHARS_PER_BATCH = 900;
const MENU_TOGGLE_ID = "llmtools-toggle-page";
const TARGET_LANGUAGE = "zh-Hans";
const TRANSLATION_CACHE_KEY = "webPageTranslationCacheV1";
const TRANSLATION_CACHE_MAX_ENTRIES = 2000;
const DEFAULT_PENDING_INDICATOR_STYLE = "loading";
const NATIVE_REQUEST_TIMEOUT_MS = 130000;
const LOCAL_MODEL_CONCURRENCY = 1;
const REMOTE_MODEL_CONCURRENCY = 4;
const DEFAULT_APP_LANGUAGE = "zh-Hans";

const EXTENSION_TEXT = {
  "zh-Hans": {
    ready: "就绪",
    pageChangedReady: "页面已变化。就绪。",
    translated: "已翻译。",
    localAppConnected: "本地应用已连接。",
    discoveringVisibleEnglish: "正在发现可见英文文本...",
    noVisibleEnglishText: "没有找到可见英文文本。",
    translationCancelled: "翻译已取消。",
    translatingSegments: ({ done, total }) => `正在翻译 ${done}/${total} 个片段...`,
    translatedSegments: ({ done, total }) => `已翻译 ${done}/${total} 个片段。`,
    translatedSegmentsWithFailures: ({ done, total, failed }) => `已翻译 ${done}/${total} 个片段，${failed} 个失败。`,
    originalTextRestored: "已恢复原文。",
    cancelling: "正在取消...",
    openWebpageBeforeClearingCache: "请先打开网页标签页再清除缓存。",
    cachePageUnknown: "无法识别当前页面缓存。已恢复页面翻译。",
    cacheCleared: ({ removed }) => `已清除 ${removed} 条缓存译文。点击“翻译页面”重新翻译。`,
    cacheEmpty: "当前页面没有缓存译文。点击“翻译页面”重新翻译。",
    contextMenuToggle: "翻译/原文",
    nativeHostRequestFailed: "Native host 请求失败。",
    nativeHostRequestTimedOut: "Native host 请求超时。",
    nativeHostDisconnected: "Native host 已断开连接。"
  },
  en: {
    ready: "Ready",
    pageChangedReady: "Page changed. Ready.",
    translated: "Translated.",
    localAppConnected: "Local app connected.",
    discoveringVisibleEnglish: "Discovering visible English text...",
    noVisibleEnglishText: "No visible English text found.",
    translationCancelled: "Translation cancelled.",
    translatingSegments: ({ done, total }) => `Translating ${done}/${total} segments...`,
    translatedSegments: ({ done, total }) => `Translated ${done}/${total} segments.`,
    translatedSegmentsWithFailures: ({ done, total, failed }) => `Translated ${done}/${total}; ${failed} failed.`,
    originalTextRestored: "Original text restored.",
    cancelling: "Cancelling...",
    openWebpageBeforeClearingCache: "Open a webpage tab before clearing cache.",
    cachePageUnknown: "Could not identify the current page cache. Page translations were restored.",
    cacheCleared: ({ removed }) => `Cleared ${removed} cached translations. Click Translate Page to translate again.`,
    cacheEmpty: "No cached translations found for this page. Click Translate Page to translate again.",
    contextMenuToggle: "Translate/Original",
    nativeHostRequestFailed: "Native host request failed.",
    nativeHostRequestTimedOut: "Native host request timed out.",
    nativeHostDisconnected: "Native host disconnected."
  }
};

const tabStates = new Map();
const tabJobs = new Map();
const pendingNativeRequests = new Map();
let pendingIndicatorStyle = DEFAULT_PENDING_INDICATOR_STYLE;
let currentAppLanguage = DEFAULT_APP_LANGUAGE;
let nativePort = null;

function normalizeAppLanguage(language) {
  return language === "en" ? "en" : DEFAULT_APP_LANGUAGE;
}

function setCurrentAppLanguage(language) {
  currentAppLanguage = normalizeAppLanguage(language);
  return currentAppLanguage;
}

function t(key, values = {}, language = currentAppLanguage) {
  const normalizedLanguage = normalizeAppLanguage(language);
  const catalog = EXTENSION_TEXT[normalizedLanguage] || EXTENSION_TEXT[DEFAULT_APP_LANGUAGE];
  const entry = catalog[key] ?? EXTENSION_TEXT.en[key] ?? key;
  return typeof entry === "function" ? entry(values) : entry;
}

function localizedMessageForState(state, language = currentAppLanguage) {
  if (!state?.status) {
    return t("ready", {}, language);
  }
  const done = state.done || 0;
  const total = state.total || 0;
  const failed = state.failed || 0;
  switch (state.status) {
    case "discovering":
      return t("discoveringVisibleEnglish", {}, language);
    case "translating":
      return t("translatingSegments", { done, total }, language);
    case "translated":
      return total > 0 ? t("translatedSegments", { done, total }, language) : t("translated", {}, language);
    case "partiallyTranslated":
      return t("translatedSegmentsWithFailures", { done, total, failed }, language);
    case "cancelled":
      return t("translationCancelled", {}, language);
    case "restored":
      return t("originalTextRestored", {}, language);
    case "idle":
      return state.message || t("ready", {}, language);
    default:
      return state.message || state.status;
  }
}

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
      resetTabState(tabID, t("pageChangedReady", {}, getState(tabID).appLanguage));
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
    case "clearCurrentPageCache":
      return clearCurrentPageCache(tabID, message?.tabURL || sender?.tab?.url || "");
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
      message: t("ready"),
      appLanguage: currentAppLanguage,
      total: 0,
      done: 0,
      failed: 0,
      hasTranslations: false,
      modelName: "",
      modelIsRemoteProvider: false,
      maxConcurrentTranslationRequests: LOCAL_MODEL_CONCURRENCY,
      pageSessionID: null,
      jobID: null,
      pageStateInvalidated: false
    });
  }
  return tabStates.get(tabID);
}

function stateFor(tabID, status, message, patch = {}) {
  const current = getState(tabID);
  const appLanguage = normalizeAppLanguage(patch.appLanguage || current.appLanguage || currentAppLanguage);
  const next = { ...current, ...patch, appLanguage, status, message };
  tabStates.set(tabID, next);
  refreshContextMenu(tabID, next);
  chrome.runtime.sendMessage({ type: "popupState", state: next }).catch(() => {});
  if (tabID) {
    sendContent(tabID, { type: "translationState", state: next }).catch(() => {});
  }
  return next;
}

function resetTabState(tabID, message = t("ready")) {
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
      appLanguage: currentAppLanguage,
      modelIsRemoteProvider: false,
      maxConcurrentTranslationRequests: LOCAL_MODEL_CONCURRENCY,
      maxSegmentsPerBatch: LOCAL_SEGMENTS_PER_BATCH,
      maxCharsPerBatch: LOCAL_CHARS_PER_BATCH,
      storageCache: null,
      pendingCacheEntries: [],
      discoveryPaused: false
    });
  }
  return tabJobs.get(tabID);
}

async function checkStatus(tabID) {
  const response = await nativeRequest("getStatus", {});
  const appLanguage = setCurrentAppLanguage(response?.payload?.appLanguage);
  const modelName = response?.payload?.modelName || "";
  const modelIsRemoteProvider = Boolean(response?.payload?.modelIsRemoteProvider);
  const maxConcurrentTranslationRequests = normalizeTranslationConcurrency(
    response?.payload?.maxConcurrentTranslationRequests,
    modelIsRemoteProvider
  );
  pendingIndicatorStyle = normalizePendingIndicatorStyle(response?.payload?.pendingIndicatorStyle);
  const current = await getSyncedState(tabID).catch(() => getState(tabID));
  if (current.hasTranslations) {
    return stateFor(tabID, current.status || "translated", localizedMessageForState(current, appLanguage), {
      appLanguage,
      modelName,
      modelIsRemoteProvider,
      maxConcurrentTranslationRequests
    });
  }
  return stateFor(tabID, "idle", t("localAppConnected", {}, appLanguage), {
    appLanguage,
    modelName,
    modelIsRemoteProvider,
    maxConcurrentTranslationRequests,
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
        : t("translatedSegments", { done, total }, current.appLanguage);
      return stateFor(tabID, status, message, {
        hasTranslations: true,
        done,
        total,
        pageSessionID: pageState.pageSessionID || current.pageSessionID,
        pageStateInvalidated: false
      });
    }
    return stateFor(tabID, "idle", t("ready", {}, current.appLanguage), {
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
      return resetTabState(tabID, t("ready", {}, current.appLanguage));
    }
    refreshContextMenu(tabID, current);
    return current;
  }
}

async function translatePage(tabID) {
  await ensureContentScript(tabID);
  const status = await checkStatus(tabID);
  const batchLimits = batchLimitsForModel(Boolean(status.modelIsRemoteProvider));
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
    appLanguage: status.appLanguage || currentAppLanguage,
    modelIsRemoteProvider: Boolean(status.modelIsRemoteProvider),
    maxConcurrentTranslationRequests: status.maxConcurrentTranslationRequests || LOCAL_MODEL_CONCURRENCY,
    maxSegmentsPerBatch: batchLimits.maxSegmentsPerBatch,
    maxCharsPerBatch: batchLimits.maxCharsPerBatch,
    storageCache: null,
    pendingCacheEntries: [],
    discoveryPaused: false
  };
  tabJobs.set(tabID, job);

  stateFor(tabID, "discovering", t("discoveringVisibleEnglish", {}, job.appLanguage), {
    appLanguage: job.appLanguage,
    modelName: job.modelName,
    modelIsRemoteProvider: job.modelIsRemoteProvider,
    maxConcurrentTranslationRequests: job.maxConcurrentTranslationRequests,
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
    appLanguage: job.appLanguage
  });
  job.urlHash = await sha256(discovered?.url || "");
  job.title = discovered?.title || "";
  await hydrateJobCache(job, discovered?.segments || []);
  enqueueSegments(job, discovered?.segments || []);
  if (!job.queue.length) {
    return stateFor(tabID, "idle", t("noVisibleEnglishText", {}, job.appLanguage), {
      appLanguage: job.appLanguage,
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
  if (!job.running && job.queue.length) {
    drainQueue(tabID).catch((error) => {
      stateFor(tabID, "failed", error?.message || String(error));
    });
  }
  return { ok: true, queued: job.queue.length };
}

function enqueueSegments(job, segments) {
  for (const segment of segments) {
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

async function drainQueue(tabID) {
  const job = getJob(tabID);
  if (job.running) {
    return;
  }
  job.running = true;
  try {
    const workerCount = queueWorkerCount(job);
    await Promise.all(Array.from({ length: workerCount }, () => drainQueueWorker(tabID, job)));

    if (job.cancelled) {
      stateFor(tabID, "cancelled", t("translationCancelled", {}, job.appLanguage), {
        appLanguage: job.appLanguage,
        done: job.done,
        failed: job.failed,
        total: job.discovered,
        hasTranslations: job.done > 0,
        modelName: job.modelName,
        modelIsRemoteProvider: job.modelIsRemoteProvider,
        maxConcurrentTranslationRequests: job.maxConcurrentTranslationRequests,
        pageStateInvalidated: false
      });
    } else {
      const status = job.failed > 0 ? "partiallyTranslated" : "translated";
      const message = job.failed > 0
        ? t("translatedSegmentsWithFailures", { done: job.done, total: job.discovered, failed: job.failed }, job.appLanguage)
        : t("translatedSegments", { done: job.done, total: job.discovered }, job.appLanguage);
      stateFor(tabID, status, message, {
        appLanguage: job.appLanguage,
        done: job.done,
        failed: job.failed,
        total: job.discovered,
        hasTranslations: job.done > 0,
        modelName: job.modelName,
        modelIsRemoteProvider: job.modelIsRemoteProvider,
        maxConcurrentTranslationRequests: job.maxConcurrentTranslationRequests,
        pageStateInvalidated: false
      });
    }
  } finally {
    await flushTranslationCache(job).catch(() => {});
    job.running = false;
    if (job.queue.length && !job.cancelled) {
      drainQueue(tabID).catch((error) => {
        stateFor(tabID, "failed", error?.message || String(error));
      });
    }
  }
}

async function drainQueueWorker(tabID, job) {
  while (job.queue.length && !job.cancelled) {
    const batch = takeNextBatch(job);
    if (!batch.cached.length && !batch.toTranslate.length) {
      break;
    }
    await applyCachedTranslations(tabID, job, batch.cached);
    if (job.cancelled) {
      break;
    }
    if (batch.toTranslate.length) {
      await translateAndApplyBatch(tabID, job, batch);
    }
    if (!job.cancelled) {
      updateTranslatingState(tabID, job);
    }
  }
}

function takeNextBatch(job) {
  const cached = [];
  const toTranslate = [];
  const duplicateByHash = new Map();
  const maxSegments = job.maxSegmentsPerBatch || LOCAL_SEGMENTS_PER_BATCH;
  const maxChars = job.maxCharsPerBatch || LOCAL_CHARS_PER_BATCH;
  let selectedCount = 0;
  let charsInBatch = 0;
  while (job.queue.length && selectedCount < maxSegments) {
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
    if (toTranslate.length && nextChars > maxChars) {
      job.queue.unshift(next);
      break;
    }
    toTranslate.push(next);
    duplicateByHash.set(next.textHash, []);
    charsInBatch = nextChars;
    selectedCount += 1;
  }
  return { cached, toTranslate, duplicateByHash };
}

async function applyCachedTranslations(tabID, job, cached) {
  if (!cached.length) {
    return;
  }
  await sendContent(tabID, { type: "applyTranslations", translations: cached });
  if (job.cancelled) {
    return;
  }
  job.done += cached.length;
}

async function translateAndApplyBatch(tabID, job, batch) {
  updateTranslatingState(tabID, job);
  const result = await nativeRequest("translateSegments", {
    jobID: job.jobID,
    sourceLanguage: "en",
    targetLanguage: TARGET_LANGUAGE,
    urlHash: job.urlHash,
    title: job.title,
    segments: batch.toTranslate.map((segment) => ({
      segmentID: segment.segmentID,
      text: segment.text,
      tagName: segment.tagName,
      blockContext: segment.blockContext,
      priority: segment.priority,
      textHash: segment.textHash
    }))
  }, { tabID, pageSessionID: job.pageSessionID });
  if (job.cancelled) {
    return;
  }

  const translations = result?.payload?.translations || [];
  const translationsByHash = new Map();
  const cacheEntries = [];
  job.modelName = result?.payload?.modelName || job.modelName;
  for (const translation of translations) {
    const source = batch.toTranslate.find((segment) => segment.segmentID === translation.segmentID);
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
  for (const [textHash, duplicateSegments] of batch.duplicateByHash.entries()) {
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
  if (job.cancelled) {
    return;
  }
  job.done += translationsToApply.filter((item) => item.status === "translated").length;
  job.failed += translationsToApply.filter((item) => item.status === "failed").length;
}

function updateTranslatingState(tabID, job) {
  stateFor(tabID, "translating", t("translatingSegments", { done: job.done, total: job.discovered }, job.appLanguage), {
    appLanguage: job.appLanguage,
    done: job.done,
    failed: job.failed,
    total: job.discovered,
    hasTranslations: job.done > 0,
    modelName: job.modelName,
    modelIsRemoteProvider: job.modelIsRemoteProvider,
    maxConcurrentTranslationRequests: job.maxConcurrentTranslationRequests,
    pageSessionID: job.pageSessionID,
    jobID: job.jobID,
    pageStateInvalidated: false
  });
}

function queueWorkerCount(job) {
  const concurrency = normalizeTranslationConcurrency(
    job.maxConcurrentTranslationRequests,
    Boolean(job.modelIsRemoteProvider)
  );
  return Math.max(1, Math.min(concurrency, job.queue.length || 1));
}

async function restorePage(tabID) {
  const language = getState(tabID).appLanguage;
  const job = tabJobs.get(tabID);
  if (job) {
    job.cancelled = true;
    await flushTranslationCache(job).catch(() => {});
  }
  await sendContent(tabID, { type: "restore" }).catch(() => {});
  tabJobs.delete(tabID);
  return stateFor(tabID, "restored", t("originalTextRestored", {}, language), {
    appLanguage: language,
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
  const language = getState(tabID).appLanguage;
  const job = tabJobs.get(tabID);
  stateFor(tabID, "cancelled", t("cancelling", {}, language), { appLanguage: language });
  if (job) {
    job.cancelled = true;
    job.queue = [];
    await flushTranslationCache(job).catch(() => {});
    if (job.jobID) {
      await nativeRequest("cancelJob", { jobID: job.jobID }, { tabID, pageSessionID: job.pageSessionID }).catch(() => {});
    }
  }
  await sendContent(tabID, { type: "cancel" }).catch(() => {});
  return stateFor(tabID, "cancelled", t("translationCancelled", {}, language), {
    appLanguage: language,
    hasTranslations: getState(tabID).hasTranslations,
    jobID: null,
    pageStateInvalidated: false
  });
}

async function clearCurrentPageCache(tabID, tabURL = "") {
  const language = getState(tabID).appLanguage;
  if (!tabID) {
    return stateFor(tabID, "unsupportedPage", t("openWebpageBeforeClearingCache", {}, language), {
      appLanguage: language,
      canClearCache: false,
      hasTranslations: false,
      done: 0,
      failed: 0,
      total: 0
    });
  }

  const job = tabJobs.get(tabID);
  if (job) {
    job.cancelled = true;
    job.queue = [];
    job.cache.clear();
    job.pendingCacheEntries = [];
    if (job.jobID) {
      await nativeRequest("cancelJob", { jobID: job.jobID }, { tabID, pageSessionID: job.pageSessionID }).catch(() => {});
    }
  }

  const urlHash = job?.urlHash || await currentTabURLHash(tabID, tabURL);
  let removed = 0;
  if (urlHash) {
    removed += await clearStoredTranslationsForURL(urlHash, TARGET_LANGUAGE);
    if (job?.storageCache) {
      removeCachedEntriesForURL(job.storageCache, urlHash, TARGET_LANGUAGE);
    }
  }

  await sendContent(tabID, { type: "restore" }).catch(() => {});
  tabJobs.delete(tabID);
  return stateFor(tabID, "idle", cacheClearedMessage(removed, Boolean(urlHash), language), {
    appLanguage: language,
    hasTranslations: false,
    done: 0,
    failed: 0,
    total: 0,
    jobID: null,
    pageSessionID: null,
    pageStateInvalidated: false,
    canClearCache: true
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

async function currentTabURLHash(tabID, fallbackURL = "") {
  if (fallbackURL) {
    return sha256(fallbackURL);
  }
  try {
    const pageState = await sendContent(tabID, { type: "getPageTranslationState" });
    if (pageState?.url) {
      return sha256(pageState.url);
    }
  } catch {}
  try {
    const tab = await chrome.tabs.get(tabID);
    if (tab?.url) {
      return sha256(tab.url);
    }
  } catch {}
  return "";
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

async function clearStoredTranslationsForURL(urlHash, targetLanguage = TARGET_LANGUAGE) {
  if (!chrome.storage?.local || !urlHash) {
    return 0;
  }
  const cache = await loadTranslationCache();
  const removed = removeCachedEntriesForURL(cache, urlHash, targetLanguage);
  if (removed > 0) {
    await chrome.storage.local.set({ [TRANSLATION_CACHE_KEY]: cache }).catch(() => {});
  }
  return removed;
}

function removeCachedEntriesForURL(cache, urlHash, targetLanguage = TARGET_LANGUAGE) {
  if (!cache || !urlHash) {
    return 0;
  }
  let removed = 0;
  for (const key of Object.keys(cache)) {
    const entry = cache[key];
    if (entry?.urlHash === urlHash && (!targetLanguage || entry.targetLanguage === targetLanguage)) {
      delete cache[key];
      removed += 1;
    }
  }
  return removed;
}

function cacheClearedMessage(removed, hadURLHash, language = currentAppLanguage) {
  if (!hadURLHash) {
    return t("cachePageUnknown", {}, language);
  }
  if (removed > 0) {
    return t("cacheCleared", { removed }, language);
  }
  return t("cacheEmpty", {}, language);
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
        title: t("contextMenuToggle"),
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
    checkStatus(tabID).catch(() => getSyncedState(tabID)).finally(() => {
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
  chrome.contextMenus.update(MENU_TOGGLE_ID, {
    enabled: !active,
    title: t("contextMenuToggle", {}, state.appLanguage)
  }, ignoreLastError);
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
    throw new Error(response?.error?.message || t("nativeHostRequestFailed"));
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
      reject(new Error(t("nativeHostRequestTimedOut")));
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
    const message = chrome.runtime.lastError?.message || t("nativeHostDisconnected");
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

function normalizeTranslationConcurrency(value, isRemoteProvider) {
  const fallback = isRemoteProvider ? REMOTE_MODEL_CONCURRENCY : LOCAL_MODEL_CONCURRENCY;
  const maxAllowed = isRemoteProvider ? REMOTE_MODEL_CONCURRENCY : LOCAL_MODEL_CONCURRENCY;
  const numericValue = Number(value);
  if (!Number.isFinite(numericValue) || numericValue < 1) {
    return fallback;
  }
  return Math.max(LOCAL_MODEL_CONCURRENCY, Math.min(Math.floor(numericValue), maxAllowed));
}

function batchLimitsForModel(isRemoteProvider) {
  if (isRemoteProvider) {
    return {
      maxSegmentsPerBatch: REMOTE_SEGMENTS_PER_BATCH,
      maxCharsPerBatch: REMOTE_CHARS_PER_BATCH
    };
  }
  return {
    maxSegmentsPerBatch: LOCAL_SEGMENTS_PER_BATCH,
    maxCharsPerBatch: LOCAL_CHARS_PER_BATCH
  };
}

async function sha256(text) {
  const bytes = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
