const HOST_NAME = "com.llmtools.native_host";
const VERSION = "0.3.0";
const LOCAL_SEGMENTS_PER_BATCH = 5;
const LOCAL_CHARS_PER_BATCH = 800;
const REMOTE_SEGMENTS_PER_BATCH = 5;
const REMOTE_CHARS_PER_BATCH = 900;
const MENU_TOGGLE_ID = "llmtools-toggle-page";
const TARGET_LANGUAGE = "zh-Hans";
const TRANSLATION_CACHE_KEY = "webPageTranslationCacheV1";
const TRANSLATION_CACHE_MAX_ENTRIES = 2000;
const DOMAIN_RULES_KEY = "webPageDomainRulesV1";
const PAGE_DEFAULTS_KEY = "webPageDomainDefaultsV1";
const PENDING_INDICATOR_STYLE_KEY = "webPagePendingIndicatorStyleV1";
const DOMAIN_RULE_ASK = "ask";
const DOMAIN_RULE_ALWAYS = "alwaysTranslate";
const DOMAIN_RULE_NEVER = "neverTranslate";
const READING_MODE_REPLACE = "replace";
const READING_MODE_BILINGUAL = "bilingual";
const READING_MODE_ORIGINAL = "original";
const DISCOVERY_SCOPE_VISIBLE = "visible";
const DISCOVERY_SCOPE_PAGE = "page";
const QUALITY_MODE_NATURAL = "natural";
const QUALITY_MODE_LITERAL = "literal";
const QUALITY_MODE_TECHNICAL = "technical";
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
    discoveringPageEnglish: "正在发现整页英文文本...",
    noVisibleEnglishText: "没有找到可见英文文本。",
    noPageEnglishText: "没有找到页面英文文本。",
    unsupportedBrowserPage: "当前浏览器页面不支持网页翻译。请打开 http:// 或 https:// 网页后再试。",
    unsupportedPdfPage: "当前 PDF 页面暂不支持网页翻译。请先下载 PDF，或等待后续文档翻译流程。",
    contentScriptInjectionFailed: "无法访问当前页面进行翻译。浏览器可能禁止扩展在此页面运行。",
    contentScriptStartFailed: "网页翻译脚本未能在当前页面启动。请刷新页面后重试。",
    unsupportedEmbeddedContent: ({ summary }) => `部分嵌入内容暂不支持翻译：${summary}。`,
    unsupportedFrames: "跨源或受限框架",
    unsupportedShadowRoots: "封闭 Shadow DOM/组件内容",
    unsupportedCanvas: "画布",
    unsupportedImages: "图片文字",
    unsupportedPdf: "PDF/嵌入文档",
    translationCancelled: "翻译已取消。",
    translatingSegments: ({ done, total }) => `正在翻译 ${done}/${total} 个片段...`,
    translatedSegments: ({ done, total }) => `已翻译 ${done}/${total} 个片段。`,
    translatedSegmentsWithFailures: ({ done, total, failed }) => `已翻译 ${done}/${total} 个片段，${failed} 个失败。`,
    originalTextRestored: "已恢复原文。",
    retranslatingPage: "正在重新翻译当前页...",
    cancelling: "正在取消...",
    openWebpageBeforeClearingCache: "请先打开网页标签页再清除缓存。",
    cachePageUnknown: "无法识别当前页面缓存。已恢复页面翻译。",
    cacheCleared: ({ removed }) => `已清除 ${removed} 条缓存译文。点击“翻译页面”重新翻译。`,
    cacheEmpty: "当前页面没有缓存译文。点击“翻译页面”重新翻译。",
    cacheDomainUnknown: "无法识别当前网站缓存。已恢复页面翻译。",
    cacheAllCleared: ({ removed }) => `已清除全部 ${removed} 条网页缓存译文。`,
    cacheAllEmpty: "没有网页缓存译文可清除。",
    domainRuleAsk: "手动翻译",
    domainRuleAlways: "自动翻译此网站",
    domainRuleNever: "不翻译此网站",
    domainRuleSaved: ({ domain, ruleLabel }) => `${domain}：${ruleLabel}`,
    readingModeReplace: "替换译文",
    readingModeBilingual: "双语对照",
    readingModeOriginal: "原文",
    readingModeSaved: ({ modeLabel }) => `阅读模式：${modeLabel}`,
    discoveryScopeVisible: "可视区域优先",
    discoveryScopePage: "全页预翻译",
    discoveryScopeSaved: ({ scopeLabel }) => `翻译范围：${scopeLabel}`,
    qualityModeNatural: "自然",
    qualityModeLiteral: "直译",
    qualityModeTechnical: "技术术语",
    qualityModeSaved: ({ modeLabel }) => `翻译质量：${modeLabel}`,
    pendingStyleLoading: "Loading",
    pendingStyleFlipText: "翻牌",
    pendingStyleNone: "无样式",
    pendingStyleSaved: ({ styleLabel }) => `待翻译样式：${styleLabel}`,
    siteDefaultsSaved: ({ domain }) => `${domain}：已保存站点默认值。`,
    autoTranslatePermissionMissing: ({ domain }) => `${domain} 需要先在 Chrome 授权后才能自动翻译。`,
    siteTranslationBlocked: ({ domain }) => `${domain} 已设置为不翻译。`,
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
    discoveringPageEnglish: "Discovering full-page English text...",
    noVisibleEnglishText: "No visible English text found.",
    noPageEnglishText: "No English page text found.",
    unsupportedBrowserPage: "This browser page cannot be translated. Open an http:// or https:// webpage and try again.",
    unsupportedPdfPage: "PDF pages cannot be translated here yet. Download the PDF or use a later document-translation flow.",
    contentScriptInjectionFailed: "Cannot access this page for translation. The browser may block extensions on this page.",
    contentScriptStartFailed: "The webpage translation script did not start on this page. Refresh the page and try again.",
    unsupportedEmbeddedContent: ({ summary }) => `Some embedded content cannot be translated yet: ${summary}.`,
    unsupportedFrames: "cross-origin or restricted frames",
    unsupportedShadowRoots: "closed Shadow DOM/component content",
    unsupportedCanvas: "canvas",
    unsupportedImages: "image text",
    unsupportedPdf: "PDF/embedded documents",
    translationCancelled: "Translation cancelled.",
    translatingSegments: ({ done, total }) => `Translating ${done}/${total} segments...`,
    translatedSegments: ({ done, total }) => `Translated ${done}/${total} segments.`,
    translatedSegmentsWithFailures: ({ done, total, failed }) => `Translated ${done}/${total}; ${failed} failed.`,
    originalTextRestored: "Original text restored.",
    retranslatingPage: "Retranslating current page...",
    cancelling: "Cancelling...",
    openWebpageBeforeClearingCache: "Open a webpage tab before clearing cache.",
    cachePageUnknown: "Could not identify the current page cache. Page translations were restored.",
    cacheCleared: ({ removed }) => `Cleared ${removed} cached translations. Click Translate Page to translate again.`,
    cacheEmpty: "No cached translations found for this page. Click Translate Page to translate again.",
    cacheDomainUnknown: "Could not identify the current site cache. Page translations were restored.",
    cacheAllCleared: ({ removed }) => `Cleared all ${removed} cached webpage translations.`,
    cacheAllEmpty: "No cached webpage translations found.",
    domainRuleAsk: "Translate manually",
    domainRuleAlways: "Auto-translate this site",
    domainRuleNever: "Never translate this site",
    domainRuleSaved: ({ domain, ruleLabel }) => `${domain}: ${ruleLabel}`,
    readingModeReplace: "Replace",
    readingModeBilingual: "Bilingual",
    readingModeOriginal: "Original",
    readingModeSaved: ({ modeLabel }) => `Reading mode: ${modeLabel}`,
    discoveryScopeVisible: "Visible first",
    discoveryScopePage: "Full page pretranslation",
    discoveryScopeSaved: ({ scopeLabel }) => `Translation scope: ${scopeLabel}`,
    qualityModeNatural: "Natural",
    qualityModeLiteral: "Literal",
    qualityModeTechnical: "Technical",
    qualityModeSaved: ({ modeLabel }) => `Translation quality: ${modeLabel}`,
    pendingStyleLoading: "Loading",
    pendingStyleFlipText: "Flip text",
    pendingStyleNone: "No style",
    pendingStyleSaved: ({ styleLabel }) => `Pending style: ${styleLabel}`,
    siteDefaultsSaved: ({ domain }) => `${domain}: site defaults saved.`,
    autoTranslatePermissionMissing: ({ domain }) => `${domain} needs Chrome site permission before auto-translation can run.`,
    siteTranslationBlocked: ({ domain }) => `${domain} is set to never translate.`,
    contextMenuToggle: "Translate/Original",
    nativeHostRequestFailed: "Native host request failed.",
    nativeHostRequestTimedOut: "Native host request timed out.",
    nativeHostDisconnected: "Native host disconnected."
  }
};

const tabStates = new Map();
const tabJobs = new Map();
const pendingNativeRequests = new Map();
let nativeAutoTranslateDomains = [];
let nativeDisabledDomains = [];
let nativeDomainRulesLoaded = false;
let nativeDomainReadingModes = {};
let nativeDomainTranslationQualities = {};
let nativePageDefaultsLoaded = false;
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

function normalizeDomainRule(rule) {
  if (rule === DOMAIN_RULE_ALWAYS || rule === DOMAIN_RULE_NEVER) {
    return rule;
  }
  return DOMAIN_RULE_ASK;
}

function domainRuleLabel(rule, language = currentAppLanguage) {
  switch (normalizeDomainRule(rule)) {
    case DOMAIN_RULE_ALWAYS:
      return t("domainRuleAlways", {}, language);
    case DOMAIN_RULE_NEVER:
      return t("domainRuleNever", {}, language);
    default:
      return t("domainRuleAsk", {}, language);
  }
}

function normalizeReadingMode(mode) {
  if (mode === READING_MODE_BILINGUAL || mode === READING_MODE_ORIGINAL) {
    return mode;
  }
  return READING_MODE_REPLACE;
}

function readingModeLabel(mode, language = currentAppLanguage) {
  switch (normalizeReadingMode(mode)) {
  case READING_MODE_BILINGUAL:
    return t("readingModeBilingual", {}, language);
  case READING_MODE_ORIGINAL:
    return t("readingModeOriginal", {}, language);
  case READING_MODE_REPLACE:
  default:
    return t("readingModeReplace", {}, language);
  }
}

function normalizeDiscoveryScope(scope) {
  return scope === DISCOVERY_SCOPE_PAGE ? DISCOVERY_SCOPE_PAGE : DISCOVERY_SCOPE_VISIBLE;
}

function discoveryScopeLabel(scope, language = currentAppLanguage) {
  return normalizeDiscoveryScope(scope) === DISCOVERY_SCOPE_PAGE
    ? t("discoveryScopePage", {}, language)
    : t("discoveryScopeVisible", {}, language);
}

function discoveringMessageForScope(scope, language = currentAppLanguage) {
  return normalizeDiscoveryScope(scope) === DISCOVERY_SCOPE_PAGE
    ? t("discoveringPageEnglish", {}, language)
    : t("discoveringVisibleEnglish", {}, language);
}

function noTextMessageForScope(scope, language = currentAppLanguage) {
  return normalizeDiscoveryScope(scope) === DISCOVERY_SCOPE_PAGE
    ? t("noPageEnglishText", {}, language)
    : t("noVisibleEnglishText", {}, language);
}

function normalizeTranslationQuality(mode) {
  if (mode === QUALITY_MODE_LITERAL || mode === QUALITY_MODE_TECHNICAL) {
    return mode;
  }
  return QUALITY_MODE_NATURAL;
}

function optionalReadingMode(mode) {
  if (mode === READING_MODE_REPLACE || mode === READING_MODE_BILINGUAL || mode === READING_MODE_ORIGINAL) {
    return mode;
  }
  return "";
}

function optionalTranslationQuality(mode) {
  if (mode === QUALITY_MODE_NATURAL || mode === QUALITY_MODE_LITERAL || mode === QUALITY_MODE_TECHNICAL) {
    return mode;
  }
  return "";
}

function translationQualityLabel(mode, language = currentAppLanguage) {
  switch (normalizeTranslationQuality(mode)) {
  case QUALITY_MODE_LITERAL:
    return t("qualityModeLiteral", {}, language);
  case QUALITY_MODE_TECHNICAL:
    return t("qualityModeTechnical", {}, language);
  case QUALITY_MODE_NATURAL:
  default:
    return t("qualityModeNatural", {}, language);
  }
}

function pendingIndicatorStyleLabel(style, language = currentAppLanguage) {
  switch (normalizePendingIndicatorStyle(style)) {
  case "flipText":
    return t("pendingStyleFlipText", {}, language);
  case "none":
    return t("pendingStyleNone", {}, language);
  case "loading":
  default:
    return t("pendingStyleLoading", {}, language);
  }
}

function normalizedDomainList(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return Array.from(new Set(value.map(normalizeDomain).filter(Boolean))).sort();
}

function normalizedModeMap(value, valueNormalizer) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  const normalized = {};
  for (const [domainValue, modeValue] of Object.entries(value)) {
    const domain = normalizeDomain(domainValue);
    const mode = valueNormalizer(modeValue);
    if (domain && mode) {
      normalized[domain] = mode;
    }
  }
  return Object.fromEntries(Object.entries(normalized).sort(([left], [right]) => left.localeCompare(right)));
}

function normalizedReadingModeDefaults(value) {
  return normalizedModeMap(value, optionalReadingMode);
}

function normalizedTranslationQualityDefaults(value) {
  return normalizedModeMap(value, optionalTranslationQuality);
}

function permissionOriginsForDomain(domain = "") {
  const normalizedDomain = normalizeDomain(domain);
  if (!normalizedDomain) {
    return [];
  }
  return [
    `http://${normalizedDomain}/*`,
    `https://${normalizedDomain}/*`,
    `http://*.${normalizedDomain}/*`,
    `https://*.${normalizedDomain}/*`
  ];
}

async function hasAutoTranslatePermission(domain = "") {
  const origins = permissionOriginsForDomain(domain);
  if (!origins.length || !chrome.permissions?.contains) {
    return true;
  }
  try {
    return Boolean(await chrome.permissions.contains({ origins }));
  } catch {
    return false;
  }
}

function emptyUnsupportedEmbeddedContent() {
  return {
    frames: 0,
    shadowRoots: 0,
    canvas: 0,
    images: 0,
    pdf: 0,
    total: 0
  };
}

function normalizeUnsupportedEmbeddedContent(value = {}) {
  const summary = emptyUnsupportedEmbeddedContent();
  for (const key of ["frames", "shadowRoots", "canvas", "images", "pdf"]) {
    summary[key] = Math.max(0, Number(value?.[key]) || 0);
  }
  const computedTotal = summary.frames + summary.shadowRoots + summary.canvas + summary.images + summary.pdf;
  summary.total = Math.max(0, Number(value?.total) || computedTotal, computedTotal);
  return summary;
}

function hasUnsupportedEmbeddedContent(value = {}) {
  return normalizeUnsupportedEmbeddedContent(value).total > 0;
}

function unsupportedEmbeddedSummary(value = {}, language = currentAppLanguage) {
  const summary = normalizeUnsupportedEmbeddedContent(value);
  const parts = [];
  if (summary.frames) parts.push(`${summary.frames} ${t("unsupportedFrames", {}, language)}`);
  if (summary.shadowRoots) parts.push(`${summary.shadowRoots} ${t("unsupportedShadowRoots", {}, language)}`);
  if (summary.canvas) parts.push(`${summary.canvas} ${t("unsupportedCanvas", {}, language)}`);
  if (summary.images) parts.push(`${summary.images} ${t("unsupportedImages", {}, language)}`);
  if (summary.pdf) parts.push(`${summary.pdf} ${t("unsupportedPdf", {}, language)}`);
  return parts.join(", ");
}

function messageWithUnsupportedEmbeddedContent(message, unsupportedEmbeddedContent, language = currentAppLanguage) {
  if (!hasUnsupportedEmbeddedContent(unsupportedEmbeddedContent)) {
    return message;
  }
  const summary = unsupportedEmbeddedSummary(unsupportedEmbeddedContent, language);
  if (!summary) {
    return message;
  }
  return `${message} ${t("unsupportedEmbeddedContent", { summary }, language)}`;
}

function redactedHash(value = "") {
  const text = String(value || "");
  if (!text) {
    return "";
  }
  let hash = 0x811c9dc5;
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return `h${hash.toString(16).padStart(8, "0")}`;
}

function errorCodeFromMessage(message = "") {
  const normalized = String(message || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return normalized.slice(0, 64) || "unknown_error";
}

function restrictedPageErrorCodeForURL(url = "") {
  if (!url) {
    return "";
  }
  try {
    const parsed = new URL(url);
    if (["chrome:", "edge:", "about:", "chrome-extension:", "moz-extension:", "safari-extension:", "devtools:"].includes(parsed.protocol)) {
      return "restricted_page";
    }
    if (parsed.protocol === "https:" && /(^|\.)chromewebstore\.google\.com$/.test(parsed.hostname)) {
      return "restricted_page";
    }
    if (parsed.protocol === "https:" && /(^|\.)microsoftedge\.microsoft\.com$/.test(parsed.hostname) && parsed.pathname.includes("/addons/")) {
      return "restricted_page";
    }
  } catch {
    return "";
  }
  return "";
}

function browserPDFPageErrorCodeForURL(url = "") {
  if (!url) {
    return "";
  }
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:" && parsed.protocol !== "file:") {
      return "";
    }
    const path = parsed.pathname.toLowerCase();
    const hash = parsed.hash.toLowerCase();
    if (path.endsWith(".pdf") || hash.includes(".pdf") || hash.includes("pdfviewer")) {
      return "browser_pdf_page";
    }
  } catch {
    return "";
  }
  return "";
}

function contentAccessError(code, cause) {
  const error = new Error(code);
  error.code = code;
  error.cause = cause;
  return error;
}

function diagnosticStartedAtForStatus(status, patch = {}, current = {}) {
  if (Object.prototype.hasOwnProperty.call(patch, "diagnosticStartedAt") && patch.diagnosticStartedAt == null) {
    return null;
  }
  const patchStartedAt = Number(patch.diagnosticStartedAt);
  if (Number.isFinite(patchStartedAt) && patchStartedAt > 0) {
    return patchStartedAt;
  }
  const currentStartedAt = Number(current.diagnosticStartedAt);
  if (status === "discovering") {
    return Number.isFinite(currentStartedAt) && currentStartedAt > 0 ? currentStartedAt : Date.now();
  }
  if (status === "translating" || status === "translated" || status === "partiallyTranslated" || status === "cancelled" || status === "failed") {
    return Number.isFinite(currentStartedAt) && currentStartedAt > 0 ? currentStartedAt : Date.now();
  }
  return Number.isFinite(currentStartedAt) && currentStartedAt > 0 ? currentStartedAt : null;
}

function redactedDiagnosticsForState(state = {}) {
  const startedAt = Number(state.diagnosticStartedAt);
  const hasStartedAt = Number.isFinite(startedAt) && startedAt > 0;
  const now = Date.now();
  return {
    browserID: "chrome",
    extensionVersion: VERSION,
    generatedAt: new Date(now).toISOString(),
    status: state.status || "idle",
    domainHash: redactedHash(state.domain || ""),
    urlHash: state.urlHash || "",
    pageSessionHash: redactedHash(state.pageSessionID || ""),
    jobHash: redactedHash(state.jobID || ""),
    counts: {
      done: Math.max(0, Number(state.done) || 0),
      total: Math.max(0, Number(state.total) || 0),
      failed: Math.max(0, Number(state.failed) || 0),
      unsupportedEmbeddedContent: normalizeUnsupportedEmbeddedContent(state.unsupportedEmbeddedContent)
    },
    timings: {
      startedAt: hasStartedAt ? new Date(startedAt).toISOString() : null,
      elapsedMs: hasStartedAt ? Math.max(0, now - startedAt) : null
    },
    model: {
      name: state.modelName || "",
      isRemoteProvider: Boolean(state.modelIsRemoteProvider),
      maxConcurrentTranslationRequests: normalizeTranslationConcurrency(
        state.maxConcurrentTranslationRequests,
        Boolean(state.modelIsRemoteProvider)
      )
    },
    controls: {
      readingMode: normalizeReadingMode(state.readingMode),
      translationQuality: normalizeTranslationQuality(state.translationQuality),
      discoveryScope: normalizeDiscoveryScope(state.discoveryScope),
      pendingIndicatorStyle: normalizePendingIndicatorStyle(state.pendingIndicatorStyle)
    },
    page: {
      hasTranslations: Boolean(state.hasTranslations),
      stateInvalidated: Boolean(state.pageStateInvalidated)
    },
    errorCode: state.lastErrorCode || ""
  };
}

function localizedMessageForState(state, language = currentAppLanguage) {
  if (!state?.status) {
    return t("ready", {}, language);
  }
  const done = state.done || 0;
  const total = state.total || 0;
  const failed = state.failed || 0;
  let message;
  switch (state.status) {
    case "discovering":
      message = discoveringMessageForScope(state.discoveryScope, language);
      break;
    case "translating":
      message = t("translatingSegments", { done, total }, language);
      break;
    case "translated":
      message = total > 0 ? t("translatedSegments", { done, total }, language) : t("translated", {}, language);
      break;
    case "partiallyTranslated":
      message = t("translatedSegmentsWithFailures", { done, total, failed }, language);
      break;
    case "cancelled":
      message = t("translationCancelled", {}, language);
      break;
    case "restored":
      message = t("originalTextRestored", {}, language);
      break;
    case "idle":
      message = state.message || t("ready", {}, language);
      break;
    default:
      message = state.message || state.status;
      break;
  }
  return messageWithUnsupportedEmbeddedContent(message, state.unsupportedEmbeddedContent, language);
}

setupContextMenus();

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message, sender).then(sendResponse).catch((error) => {
    const tabID = message?.tabID || sender?.tab?.id;
    sendResponse(failedStateForError(tabID, error));
  });
  return true;
});

if (chrome.tabs?.onUpdated) {
  chrome.tabs.onUpdated.addListener((tabID, changeInfo, tab = {}) => {
    if (changeInfo.status === "loading" || changeInfo.url) {
      resetTabState(tabID, t("pageChangedReady", {}, getState(tabID).appLanguage));
    }
    if (changeInfo.status === "complete") {
      maybeAutoTranslate(tabID, tab?.url || changeInfo.url || "").catch((error) => {
        failedStateForError(tabID, error);
      });
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
      return translatePage(tabID, {
        source: "popup",
        tabURL: message?.tabURL || sender?.tab?.url || "",
        discoveryScope: message?.discoveryScope
      });
    case "retranslatePage":
      return retranslatePage(tabID, {
        tabURL: message?.tabURL || sender?.tab?.url || "",
        discoveryScope: message?.discoveryScope
      });
    case "restorePage":
      return restorePage(tabID);
    case "cancelTranslation":
      return cancelTranslation(tabID);
    case "clearCurrentPageCache":
      return clearCurrentPageCache(tabID, message?.tabURL || sender?.tab?.url || "");
    case "clearCurrentDomainCache":
      return clearCurrentDomainCache(tabID, message?.tabURL || sender?.tab?.url || "");
    case "clearAllPageCache":
      return clearAllPageCache(tabID);
    case "setDomainRule":
      return setDomainRuleForTab(tabID, message?.tabURL || sender?.tab?.url || "", message?.rule);
    case "setReadingMode":
      return setReadingModeForTab(tabID, message?.readingMode || message?.mode);
    case "setDiscoveryScope":
      return setDiscoveryScopeForTab(tabID, message?.discoveryScope || message?.scope);
    case "setTranslationQuality":
      return setTranslationQualityForTab(tabID, message?.translationQuality || message?.qualityMode);
    case "setPendingIndicatorStyle":
      return setPendingIndicatorStyleForTab(tabID, message?.pendingIndicatorStyle);
    case "setDomainPageDefaults":
      return setDomainPageDefaultsForTab(tabID, message?.tabURL || sender?.tab?.url || "", {
        readingMode: message?.readingMode,
        translationQuality: message?.translationQuality
      });
    case "llmToolsRouteChanged":
      return handleContentRouteChanged(tabID, message);
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
      domain: "",
      domainRule: DOMAIN_RULE_ASK,
      domainRuleLabel: domainRuleLabel(DOMAIN_RULE_ASK),
      domainReadingModeDefault: "",
      domainTranslationQualityDefault: "",
      readingMode: READING_MODE_REPLACE,
      readingModeLabel: readingModeLabel(READING_MODE_REPLACE),
      readingModeOverridden: false,
      discoveryScope: DISCOVERY_SCOPE_VISIBLE,
      discoveryScopeLabel: discoveryScopeLabel(DISCOVERY_SCOPE_VISIBLE),
      translationQuality: QUALITY_MODE_NATURAL,
      translationQualityLabel: translationQualityLabel(QUALITY_MODE_NATURAL),
      translationQualityOverridden: false,
      pendingIndicatorStyle: DEFAULT_PENDING_INDICATOR_STYLE,
      pendingIndicatorStyleLabel: pendingIndicatorStyleLabel(DEFAULT_PENDING_INDICATOR_STYLE),
      unsupportedEmbeddedContent: emptyUnsupportedEmbeddedContent(),
      diagnostics: redactedDiagnosticsForState({ status: "idle" }),
      diagnosticStartedAt: null,
      urlHash: "",
      lastErrorCode: "",
      notice: false,
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
  const domainRule = normalizeDomainRule(patch.domainRule || current.domainRule);
  const readingMode = normalizeReadingMode(patch.readingMode || current.readingMode);
  const discoveryScope = normalizeDiscoveryScope(patch.discoveryScope || current.discoveryScope);
  const translationQuality = normalizeTranslationQuality(patch.translationQuality || current.translationQuality);
  const nextPendingIndicatorStyle = normalizePendingIndicatorStyle(
    patch.pendingIndicatorStyle || current.pendingIndicatorStyle || pendingIndicatorStyle
  );
  const unsupportedEmbeddedContent = normalizeUnsupportedEmbeddedContent(patch.unsupportedEmbeddedContent || current.unsupportedEmbeddedContent);
  const diagnosticStartedAt = diagnosticStartedAtForStatus(status, patch, current);
  const lastErrorCode = patch.lastErrorCode || (status === "failed" ? errorCodeFromMessage(message) : "");
  const urlHash = Object.prototype.hasOwnProperty.call(patch, "urlHash") ? patch.urlHash : current.urlHash;
  const next = {
    ...current,
    ...patch,
    appLanguage,
    domainRule,
    domainRuleLabel: domainRuleLabel(domainRule, appLanguage),
    readingMode,
    readingModeLabel: readingModeLabel(readingMode, appLanguage),
    discoveryScope,
    discoveryScopeLabel: discoveryScopeLabel(discoveryScope, appLanguage),
    translationQuality,
    translationQualityLabel: translationQualityLabel(translationQuality, appLanguage),
    pendingIndicatorStyle: nextPendingIndicatorStyle,
    pendingIndicatorStyleLabel: pendingIndicatorStyleLabel(nextPendingIndicatorStyle, appLanguage),
    unsupportedEmbeddedContent,
    diagnosticStartedAt,
    urlHash: urlHash || "",
    lastErrorCode,
    notice: Boolean(patch.notice),
    status,
    message
  };
  next.diagnostics = redactedDiagnosticsForState(next);
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
    diagnosticStartedAt: null,
    urlHash: "",
    pageStateInvalidated: true,
    discoveryScope: DISCOVERY_SCOPE_VISIBLE,
    readingModeOverridden: false,
    translationQualityOverridden: false
  });
}

async function unsupportedPageState(tabID, messageKey, errorCode, patch = {}) {
  const current = getState(tabID);
  const language = current.appLanguage || currentAppLanguage;
  const { tabURL = "", ...statePatch } = patch;
  const urlHash = tabURL ? await sha256(tabURL).catch(() => "") : "";
  const job = tabJobs.get(tabID);
  if (job) {
    job.cancelled = true;
    tabJobs.delete(tabID);
  }
  return stateFor(tabID, "unsupportedPage", t(messageKey, {}, language), {
    appLanguage: language,
    hasTranslations: false,
    done: 0,
    failed: 0,
    total: 0,
    pageSessionID: null,
    jobID: null,
    diagnosticStartedAt: null,
    unsupportedEmbeddedContent: emptyUnsupportedEmbeddedContent(),
    urlHash,
    pageStateInvalidated: false,
    canClearCache: false,
    notice: true,
    lastErrorCode: errorCode,
    ...statePatch
  });
}

async function handleContentRouteChanged(tabID, message = {}) {
  const language = getState(tabID).appLanguage;
  resetTabState(tabID, t("pageChangedReady", {}, language));
  const domainPatch = await domainStatePatch(tabID, message.url || "");
  stateFor(tabID, "idle", t("pageChangedReady", {}, language), {
    ...domainPatch,
    appLanguage: language,
    diagnosticStartedAt: null,
    urlHash: "",
    pageStateInvalidated: true
  });
  if (domainPatch.domain && domainPatch.domainRule === DOMAIN_RULE_ALWAYS) {
    return maybeAutoTranslate(tabID, message.url || "");
  }
  return getState(tabID);
}

function normalizedDomainFromURL(url = "") {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return "";
    }
    return parsed.hostname.toLowerCase().replace(/^www\./, "");
  } catch {
    return "";
  }
}

function normalizeDomain(domain = "") {
  const trimmed = String(domain).trim().toLowerCase().replace(/^https?:\/\//, "");
  const host = trimmed.split("/")[0].split(":")[0].replace(/^www\./, "");
  return host || "";
}

async function currentTabURL(tabID, fallbackURL = "") {
  if (fallbackURL) {
    return fallbackURL;
  }
  try {
    const pageState = await sendContent(tabID, { type: "getPageTranslationState" });
    if (pageState?.url) {
      return pageState.url;
    }
  } catch {}
  try {
    const tab = await chrome.tabs.get(tabID);
    if (tab?.url) {
      return tab.url;
    }
  } catch {}
  return "";
}

async function loadDomainRules() {
  if (!chrome.storage?.local) {
    return {};
  }
  try {
    const result = await chrome.storage.local.get(DOMAIN_RULES_KEY);
    const rules = result?.[DOMAIN_RULES_KEY];
    return rules && typeof rules === "object" ? rules : {};
  } catch {
    return {};
  }
}

async function saveDomainRules(rules) {
  if (!chrome.storage?.local) {
    return;
  }
  await chrome.storage.local.set({ [DOMAIN_RULES_KEY]: rules }).catch(() => {});
}

async function loadPageDefaults() {
  if (!chrome.storage?.local) {
    return { readingModes: {}, translationQualities: {} };
  }
  try {
    const result = await chrome.storage.local.get(PAGE_DEFAULTS_KEY);
    const defaults = result?.[PAGE_DEFAULTS_KEY];
    return {
      readingModes: normalizedReadingModeDefaults(defaults?.readingModes),
      translationQualities: normalizedTranslationQualityDefaults(defaults?.translationQualities)
    };
  } catch {
    return { readingModes: {}, translationQualities: {} };
  }
}

async function savePageDefaults(defaults) {
  if (!chrome.storage?.local) {
    return;
  }
  await chrome.storage.local.set({
    [PAGE_DEFAULTS_KEY]: {
      readingModes: normalizedReadingModeDefaults(defaults?.readingModes),
      translationQualities: normalizedTranslationQualityDefaults(defaults?.translationQualities)
    }
  }).catch(() => {});
}

async function loadLocalPendingIndicatorStyle() {
  if (!chrome.storage?.local) {
    return DEFAULT_PENDING_INDICATOR_STYLE;
  }
  const result = await chrome.storage.local.get(PENDING_INDICATOR_STYLE_KEY).catch(() => ({}));
  return normalizePendingIndicatorStyle(result?.[PENDING_INDICATOR_STYLE_KEY]);
}

async function saveLocalPendingIndicatorStyle(style) {
  if (!chrome.storage?.local) {
    return;
  }
  await chrome.storage.local.set({
    [PENDING_INDICATOR_STYLE_KEY]: normalizePendingIndicatorStyle(style)
  }).catch(() => {});
}

async function clearLocalPendingIndicatorStyle() {
  if (!chrome.storage?.local?.remove) {
    return;
  }
  await chrome.storage.local.remove(PENDING_INDICATOR_STYLE_KEY).catch(() => {});
}

async function domainRuleForURL(url = "") {
  const domain = normalizedDomainFromURL(url);
  if (!domain) {
    return { domain: "", domainRule: DOMAIN_RULE_ASK };
  }
  const rules = await loadDomainRules();
  const localRule = nativeDomainRulesLoaded ? DOMAIN_RULE_ASK : normalizeDomainRule(rules[domain]);
  const nativeDisabledSet = new Set(nativeDisabledDomains.map(normalizeDomain).filter(Boolean));
  const nativeAutoSet = new Set(nativeAutoTranslateDomains.map(normalizeDomain).filter(Boolean));
  if (localRule === DOMAIN_RULE_NEVER || nativeDisabledSet.has(domain)) {
    return { domain, domainRule: DOMAIN_RULE_NEVER };
  }
  if (localRule === DOMAIN_RULE_ALWAYS || nativeAutoSet.has(domain)) {
    return { domain, domainRule: DOMAIN_RULE_ALWAYS };
  }
  return {
    domain,
    domainRule: DOMAIN_RULE_ASK
  };
}

async function domainPageDefaultsForURL(url = "") {
  const domain = normalizedDomainFromURL(url);
  if (!domain) {
    return {
      domainReadingModeDefault: "",
      domainTranslationQualityDefault: ""
    };
  }
  const localDefaults = nativePageDefaultsLoaded
    ? { readingModes: {}, translationQualities: {} }
    : await loadPageDefaults();
  const nativeReadingMode = nativePageDefaultsLoaded ? nativeDomainReadingModes[domain] : "";
  const nativeTranslationQuality = nativePageDefaultsLoaded ? nativeDomainTranslationQualities[domain] : "";
  return {
    domainReadingModeDefault: optionalReadingMode(nativeReadingMode || localDefaults.readingModes?.[domain]),
    domainTranslationQualityDefault: optionalTranslationQuality(nativeTranslationQuality || localDefaults.translationQualities?.[domain])
  };
}

async function domainStatePatch(tabID, fallbackURL = "", options = {}) {
  if (!tabID) {
    return {
      domain: "",
      domainRule: DOMAIN_RULE_ASK,
      domainReadingModeDefault: "",
      domainTranslationQualityDefault: ""
    };
  }
  const url = await currentTabURL(tabID, fallbackURL);
  const current = getState(tabID);
  const rulePatch = await domainRuleForURL(url);
  const defaultsPatch = await domainPageDefaultsForURL(url);
  const patch = {
    ...rulePatch,
    ...defaultsPatch
  };
  if ((options.forcePageDefaults || !current.readingModeOverridden) && defaultsPatch.domainReadingModeDefault) {
    patch.readingMode = defaultsPatch.domainReadingModeDefault;
  }
  if ((options.forcePageDefaults || !current.translationQualityOverridden) && defaultsPatch.domainTranslationQualityDefault) {
    patch.translationQuality = defaultsPatch.domainTranslationQualityDefault;
  }
  return patch;
}

async function setDomainRuleForTab(tabID, fallbackURL = "", requestedRule = DOMAIN_RULE_ASK) {
  const language = getState(tabID).appLanguage;
  const url = await currentTabURL(tabID, fallbackURL);
  const domain = normalizedDomainFromURL(url);
  const domainRule = normalizeDomainRule(requestedRule);
  if (!domain) {
    return stateFor(tabID, "idle", t("ready", {}, language), {
      appLanguage: language,
      domain: "",
      domainRule: DOMAIN_RULE_ASK
    });
  }

  try {
    const response = await nativeRequest("setDomainRule", { domain, rule: domainRule }, { tabID });
    const payload = response?.payload || {};
    nativeAutoTranslateDomains = normalizedDomainList(payload.autoTranslateDomains);
    nativeDisabledDomains = normalizedDomainList(payload.disabledDomains);
    nativeDomainRulesLoaded = true;
    await saveDomainRules({});
  } catch {
    nativeDomainRulesLoaded = false;
    const rules = await loadDomainRules();
    if (domainRule === DOMAIN_RULE_ASK) {
      delete rules[domain];
    } else {
      rules[domain] = domainRule;
    }
    await saveDomainRules(rules);
  }
  return stateFor(tabID, getState(tabID).status || "idle", t("domainRuleSaved", {
    domain,
    ruleLabel: domainRuleLabel(domainRule, language)
  }, language), {
    appLanguage: language,
    domain,
    domainRule,
    notice: true
  });
}

async function setReadingModeForTab(tabID, requestedMode = READING_MODE_REPLACE) {
  const current = getState(tabID);
  const language = current.appLanguage;
  const readingMode = normalizeReadingMode(requestedMode);
  await sendContent(tabID, { type: "setReadingMode", mode: readingMode }).catch(() => {});
  return stateFor(tabID, current.status || "idle", t("readingModeSaved", {
    modeLabel: readingModeLabel(readingMode, language)
  }, language), {
    appLanguage: language,
    readingMode,
    readingModeOverridden: true
  });
}

async function setDiscoveryScopeForTab(tabID, requestedScope = DISCOVERY_SCOPE_VISIBLE) {
  const current = getState(tabID);
  const language = current.appLanguage;
  const discoveryScope = normalizeDiscoveryScope(requestedScope);
  return stateFor(tabID, current.status || "idle", t("discoveryScopeSaved", {
    scopeLabel: discoveryScopeLabel(discoveryScope, language)
  }, language), {
    appLanguage: language,
    discoveryScope,
    notice: true
  });
}

async function setTranslationQualityForTab(tabID, requestedMode = QUALITY_MODE_NATURAL) {
  const current = getState(tabID);
  const language = current.appLanguage;
  const translationQuality = normalizeTranslationQuality(requestedMode);
  return stateFor(tabID, current.status || "idle", t("qualityModeSaved", {
    modeLabel: translationQualityLabel(translationQuality, language)
  }, language), {
    appLanguage: language,
    translationQuality,
    translationQualityOverridden: true
  });
}

async function setPendingIndicatorStyleForTab(tabID, requestedStyle = DEFAULT_PENDING_INDICATOR_STYLE) {
  const current = getState(tabID);
  const language = current.appLanguage;
  const style = normalizePendingIndicatorStyle(requestedStyle);
  pendingIndicatorStyle = style;
  try {
    const response = await nativeRequest("setPendingIndicatorStyle", { pendingIndicatorStyle: style }, { tabID });
    pendingIndicatorStyle = normalizePendingIndicatorStyle(response?.payload?.pendingIndicatorStyle);
    await clearLocalPendingIndicatorStyle();
  } catch {
    await saveLocalPendingIndicatorStyle(style);
  }
  return stateFor(tabID, current.status || "idle", t("pendingStyleSaved", {
    styleLabel: pendingIndicatorStyleLabel(pendingIndicatorStyle, language)
  }, language), {
    appLanguage: language,
    pendingIndicatorStyle,
    notice: true
  });
}

async function setDomainPageDefaultsForTab(tabID, fallbackURL = "", requestedDefaults = {}) {
  const current = getState(tabID);
  const language = current.appLanguage;
  const url = await currentTabURL(tabID, fallbackURL);
  const domain = normalizedDomainFromURL(url);
  if (!domain) {
    return stateFor(tabID, current.status || "idle", t("ready", {}, language), {
      appLanguage: language,
      domain: "",
      domainReadingModeDefault: "",
      domainTranslationQualityDefault: ""
    });
  }
  const readingMode = optionalReadingMode(requestedDefaults.readingMode);
  const translationQuality = optionalTranslationQuality(requestedDefaults.translationQuality);

  try {
    const response = await nativeRequest("setDomainPageDefaults", {
      domain,
      ...(readingMode ? { readingMode } : {}),
      ...(translationQuality ? { translationQuality } : {})
    }, { tabID });
    const payload = response?.payload || {};
    nativeDomainReadingModes = normalizedReadingModeDefaults(payload.domainReadingModes);
    nativeDomainTranslationQualities = normalizedTranslationQualityDefaults(payload.domainTranslationQualities);
    nativePageDefaultsLoaded = true;
    await savePageDefaults({ readingModes: {}, translationQualities: {} });
  } catch {
    nativePageDefaultsLoaded = false;
    const defaults = await loadPageDefaults();
    if (readingMode) {
      defaults.readingModes[domain] = readingMode;
    }
    if (translationQuality) {
      defaults.translationQualities[domain] = translationQuality;
    }
    await savePageDefaults(defaults);
  }

  const defaultPatch = await domainPageDefaultsForURL(url);
  if (defaultPatch.domainReadingModeDefault) {
    await sendContent(tabID, { type: "setReadingMode", mode: defaultPatch.domainReadingModeDefault }).catch(() => {});
  }
  return stateFor(tabID, current.status || "idle", t("siteDefaultsSaved", { domain }, language), {
    appLanguage: language,
    domain,
    ...defaultPatch,
    readingMode: defaultPatch.domainReadingModeDefault || current.readingMode,
    translationQuality: defaultPatch.domainTranslationQualityDefault || current.translationQuality,
    readingModeOverridden: readingMode ? false : current.readingModeOverridden,
    translationQualityOverridden: translationQuality ? false : current.translationQualityOverridden,
    notice: true
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
      startedAt: Date.now(),
      discoveryPaused: false,
      discoveryScope: normalizeDiscoveryScope(getState(tabID).discoveryScope),
      readingMode: normalizeReadingMode(getState(tabID).readingMode),
      translationQuality: normalizeTranslationQuality(getState(tabID).translationQuality),
      unsupportedEmbeddedContent: emptyUnsupportedEmbeddedContent()
    });
  }
  return tabJobs.get(tabID);
}

function failedStateForError(tabID, error, patch = {}) {
  const job = tabJobs.get(tabID);
  return stateFor(tabID, "failed", error?.message || String(error), {
    ...(job ? {
      pageSessionID: job.pageSessionID,
      jobID: job.jobID
    } : {}),
    ...patch
  });
}

async function checkStatus(tabID) {
  const response = await nativeRequest("getStatus", {});
  const payload = response?.payload || {};
  const appLanguage = setCurrentAppLanguage(payload.appLanguage);
  const modelName = payload.modelName || "";
  const modelIsRemoteProvider = Boolean(payload.modelIsRemoteProvider);
  const maxConcurrentTranslationRequests = normalizeTranslationConcurrency(
    payload.maxConcurrentTranslationRequests,
    modelIsRemoteProvider
  );
  const localPendingIndicatorStyle = await loadLocalPendingIndicatorStyle();
  pendingIndicatorStyle = normalizePendingIndicatorStyle(payload.pendingIndicatorStyle || localPendingIndicatorStyle);
  nativeAutoTranslateDomains = normalizedDomainList(payload.autoTranslateDomains);
  nativeDisabledDomains = normalizedDomainList(payload.disabledDomains);
  nativeDomainRulesLoaded = true;
  nativeDomainReadingModes = normalizedReadingModeDefaults(payload.domainReadingModes);
  nativeDomainTranslationQualities = normalizedTranslationQualityDefaults(payload.domainTranslationQualities);
  nativePageDefaultsLoaded = true;
  const current = await getSyncedState(tabID).catch(() => getState(tabID));
  const domainPatch = await domainStatePatch(tabID).catch(() => ({
    domain: current.domain || "",
    domainRule: current.domainRule || DOMAIN_RULE_ASK
  }));
  if (current.hasTranslations) {
    return stateFor(tabID, current.status || "translated", localizedMessageForState(current, appLanguage), {
      ...domainPatch,
      appLanguage,
      modelName,
      modelIsRemoteProvider,
      maxConcurrentTranslationRequests,
      pendingIndicatorStyle
    });
  }
  return stateFor(tabID, "idle", t("localAppConnected", {}, appLanguage), {
    ...domainPatch,
    appLanguage,
    modelName,
    modelIsRemoteProvider,
    maxConcurrentTranslationRequests,
    pendingIndicatorStyle,
    hasTranslations: false,
    done: 0,
    failed: 0,
    total: 0,
    pageSessionID: null,
    jobID: null,
    diagnosticStartedAt: null,
    urlHash: "",
    pageStateInvalidated: Boolean(current.pageStateInvalidated)
  });
}

async function getSyncedState(tabID) {
  const current = getState(tabID);
  if (!tabID) {
    return current;
  }
  const domainPatch = await domainStatePatch(tabID).catch(() => ({
    domain: current.domain || "",
    domainRule: current.domainRule || DOMAIN_RULE_ASK
  }));
  if (current.pageStateInvalidated && !current.hasTranslations) {
    return stateFor(tabID, current.status || "idle", current.message || t("ready", {}, current.appLanguage), domainPatch);
  }
  try {
    const pageState = await sendContent(tabID, { type: "getPageTranslationState" });
    const hasTranslations = Boolean(pageState?.hasTranslations);
    const unsupportedEmbeddedContent = normalizeUnsupportedEmbeddedContent(pageState?.unsupportedEmbeddedContent || current.unsupportedEmbeddedContent);
    if (hasTranslations) {
      const done = Math.max(current.done || 0, pageState.translatedCount || 0);
      const total = Math.max(current.total || 0, pageState.trackedCount || done);
      const status = current.hasTranslations && current.status ? current.status : "translated";
      const message = current.hasTranslations && current.message
        ? current.message
        : t("translatedSegments", { done, total }, current.appLanguage);
      return stateFor(tabID, status, messageWithUnsupportedEmbeddedContent(message, unsupportedEmbeddedContent, current.appLanguage), {
        ...domainPatch,
        hasTranslations: true,
        done,
        total,
        unsupportedEmbeddedContent,
        pageSessionID: pageState.pageSessionID || current.pageSessionID,
        pageStateInvalidated: false
      });
    }
    return stateFor(tabID, "idle", messageWithUnsupportedEmbeddedContent(t("ready", {}, current.appLanguage), unsupportedEmbeddedContent, current.appLanguage), {
      ...domainPatch,
      hasTranslations: false,
      done: 0,
      failed: 0,
      total: 0,
      unsupportedEmbeddedContent,
      pageSessionID: null,
      jobID: null,
      diagnosticStartedAt: null,
      urlHash: "",
      pageStateInvalidated: false
    });
  } catch {
    if (current.hasTranslations || current.status === "translated" || current.status === "partiallyTranslated" || current.status === "restored") {
      return resetTabState(tabID, t("ready", {}, current.appLanguage));
    }
    return stateFor(tabID, current.status || "idle", current.message || t("ready", {}, current.appLanguage), domainPatch);
  }
}

async function maybeAutoTranslate(tabID, tabURL = "") {
  if (!tabID) {
    return getState(tabID);
  }
  if (!nativeDomainRulesLoaded || !nativePageDefaultsLoaded) {
    await checkStatus(tabID).catch(() => {});
  }
  const patch = await domainStatePatch(tabID, tabURL);
  if (!patch.domain || patch.domainRule !== DOMAIN_RULE_ALWAYS) {
    if (patch.domain) {
      stateFor(tabID, getState(tabID).status || "idle", getState(tabID).message || t("ready"), patch);
    }
    return getState(tabID);
  }
  if (!(await hasAutoTranslatePermission(patch.domain))) {
    return stateFor(tabID, "idle", t("autoTranslatePermissionMissing", { domain: patch.domain }, getState(tabID).appLanguage), {
      ...patch,
      notice: true
    });
  }
  const state = getState(tabID);
  if (state.hasTranslations || state.status === "discovering" || state.status === "translating") {
    return stateFor(tabID, state.status, state.message, patch);
  }
  return translatePage(tabID, { source: "auto", tabURL });
}

function shouldBlockTranslationForDomainRule(rule, source) {
  return normalizeDomainRule(rule) === DOMAIN_RULE_NEVER && source !== "popup";
}

async function translatePage(tabID, options = {}) {
  const source = options.source || "popup";
  const requestedDiscoveryScope = normalizeDiscoveryScope(options.discoveryScope || getState(tabID).discoveryScope);
  if (!nativeDomainRulesLoaded || !nativePageDefaultsLoaded) {
    await checkStatus(tabID).catch(() => {});
  }
  const tabURL = await currentTabURL(tabID, options.tabURL || "");
  const restrictedPageErrorCode = restrictedPageErrorCodeForURL(tabURL);
  if (restrictedPageErrorCode) {
    return unsupportedPageState(tabID, "unsupportedBrowserPage", restrictedPageErrorCode, {
      tabURL,
      domain: "",
      domainRule: DOMAIN_RULE_ASK,
      domainReadingModeDefault: "",
      domainTranslationQualityDefault: ""
    });
  }
  const browserPDFPageErrorCode = browserPDFPageErrorCodeForURL(tabURL);
  if (browserPDFPageErrorCode) {
    return unsupportedPageState(tabID, "unsupportedPdfPage", browserPDFPageErrorCode, {
      tabURL,
      domain: normalizedDomainFromURL(tabURL),
      domainRule: DOMAIN_RULE_ASK,
      domainReadingModeDefault: "",
      domainTranslationQualityDefault: ""
    });
  }
  const domainPatch = await domainStatePatch(tabID, tabURL);
  const language = getState(tabID).appLanguage;
  if (source === "auto" && domainPatch.domainRule !== DOMAIN_RULE_ALWAYS) {
    return stateFor(tabID, "idle", t("ready", {}, language), domainPatch);
  }
  if (shouldBlockTranslationForDomainRule(domainPatch.domainRule, source)) {
    return stateFor(tabID, "idle", t("siteTranslationBlocked", {
      domain: domainPatch.domain || "site"
    }, language), {
      ...domainPatch,
      notice: true
    });
  }
  try {
    await ensureContentScript(tabID);
  } catch (error) {
    return unsupportedPageState(tabID, "contentScriptInjectionFailed", error?.code || "content_script_injection_failed", {
      ...domainPatch,
      tabURL
    });
  }
  const status = await checkStatus(tabID);
  const batchLimits = batchLimitsForModel(Boolean(status.modelIsRemoteProvider));
  const job = {
    pageSessionID: crypto.randomUUID(),
    jobID: crypto.randomUUID(),
    queue: [],
    queuedIDs: new Set(),
    cache: new Map(),
    urlHash: "",
    domain: domainPatch.domain || status.domain || "",
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
    startedAt: Date.now(),
    discoveryPaused: false,
    discoveryScope: requestedDiscoveryScope,
    readingMode: normalizeReadingMode(getState(tabID).readingMode),
    translationQuality: normalizeTranslationQuality(getState(tabID).translationQuality),
    unsupportedEmbeddedContent: emptyUnsupportedEmbeddedContent()
  };
  tabJobs.set(tabID, job);

  stateFor(tabID, "discovering", discoveringMessageForScope(job.discoveryScope, job.appLanguage), {
    appLanguage: job.appLanguage,
    modelName: job.modelName,
    modelIsRemoteProvider: job.modelIsRemoteProvider,
    maxConcurrentTranslationRequests: job.maxConcurrentTranslationRequests,
    domain: job.domain,
    domainRule: domainPatch.domainRule,
    done: 0,
    failed: 0,
    discoveryScope: job.discoveryScope,
    total: 0,
    hasTranslations: false,
    pageSessionID: job.pageSessionID,
    jobID: job.jobID,
    diagnosticStartedAt: job.startedAt,
    urlHash: "",
    pageStateInvalidated: false
  });

  let discovered;
  try {
    discovered = await sendContent(tabID, {
      type: "startSession",
      pageSessionID: job.pageSessionID,
      pendingIndicatorStyle,
      appLanguage: job.appLanguage,
      readingMode: job.readingMode,
      discoveryScope: job.discoveryScope
    });
    if (discovered?.ok === false) {
      throw new Error(discovered.error || "content_script_start_failed");
    }
  } catch {
    return unsupportedPageState(tabID, "contentScriptStartFailed", "content_script_start_failed", {
      ...domainPatch,
      tabURL
    });
  }
  job.urlHash = await sha256(discovered?.url || "");
  job.title = discovered?.title || "";
  job.unsupportedEmbeddedContent = normalizeUnsupportedEmbeddedContent(discovered?.unsupportedEmbeddedContent);
  await hydrateJobCache(job, discovered?.segments || []);
  enqueueSegments(job, discovered?.segments || []);
  if (!job.queue.length) {
    return stateFor(tabID, "idle", messageWithUnsupportedEmbeddedContent(
      noTextMessageForScope(job.discoveryScope, job.appLanguage),
      job.unsupportedEmbeddedContent,
      job.appLanguage
    ), {
      appLanguage: job.appLanguage,
      total: 0,
      done: 0,
      failed: 0,
      diagnosticStartedAt: job.startedAt,
      urlHash: job.urlHash,
      unsupportedEmbeddedContent: job.unsupportedEmbeddedContent,
      notice: hasUnsupportedEmbeddedContent(job.unsupportedEmbeddedContent),
      pageSessionID: job.pageSessionID,
      jobID: job.jobID,
      pageStateInvalidated: false
    });
  }

  drainQueue(tabID).catch((error) => {
    failedStateForError(tabID, error, {
      pageSessionID: job.pageSessionID,
      jobID: job.jobID
    });
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
  if (!message?.pageSessionID || message.pageSessionID !== job.pageSessionID) {
    return { ok: false, reason: "stale_page_session" };
  }
  const segments = message?.segments || [];
  await hydrateJobCache(job, segments);
  enqueueSegments(job, segments);
  if (!job.running && job.queue.length) {
    drainQueue(tabID).catch((error) => {
      failedStateForError(tabID, error, {
        pageSessionID: job.pageSessionID,
        jobID: job.jobID
      });
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
        pageSessionID: job.pageSessionID,
        jobID: job.jobID,
        diagnosticStartedAt: job.startedAt,
        urlHash: job.urlHash,
        pageStateInvalidated: false
      });
    } else {
      const status = job.failed > 0 ? "partiallyTranslated" : "translated";
      const message = job.failed > 0
        ? t("translatedSegmentsWithFailures", { done: job.done, total: job.discovered, failed: job.failed }, job.appLanguage)
        : t("translatedSegments", { done: job.done, total: job.discovered }, job.appLanguage);
      stateFor(tabID, status, messageWithUnsupportedEmbeddedContent(message, job.unsupportedEmbeddedContent, job.appLanguage), {
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
        diagnosticStartedAt: job.startedAt,
        urlHash: job.urlHash,
        unsupportedEmbeddedContent: job.unsupportedEmbeddedContent,
        pageStateInvalidated: false
      });
    }
  } finally {
    await flushTranslationCache(job).catch(() => {});
    job.running = false;
    if (job.queue.length && !job.cancelled) {
      drainQueue(tabID).catch((error) => {
        failedStateForError(tabID, error, {
          pageSessionID: job.pageSessionID,
          jobID: job.jobID
        });
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
  await sendContent(tabID, { type: "applyTranslations", pageSessionID: job.pageSessionID, translations: cached });
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
    translationQuality: job.translationQuality,
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
  await sendContent(tabID, { type: "applyTranslations", pageSessionID: job.pageSessionID, translations: translationsToApply });
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
    diagnosticStartedAt: job.startedAt,
    urlHash: job.urlHash,
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
    diagnosticStartedAt: null,
    urlHash: "",
    pageStateInvalidated: false
  });
}

async function retranslatePage(tabID, options = {}) {
  const normalizedOptions = typeof options === "string" ? { tabURL: options } : (options || {});
  const tabURL = normalizedOptions.tabURL || "";
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
  if (urlHash) {
    await clearStoredTranslationsForURL(urlHash, TARGET_LANGUAGE);
    if (job?.storageCache) {
      removeCachedEntriesForURL(job.storageCache, urlHash, TARGET_LANGUAGE);
    }
  }

  await sendContent(tabID, { type: "restore" }).catch(() => {});
  tabJobs.delete(tabID);
  stateFor(tabID, "discovering", t("retranslatingPage", {}, language), {
    appLanguage: language,
    hasTranslations: false,
    done: 0,
    failed: 0,
    total: 0,
    jobID: null,
    pageSessionID: null,
    diagnosticStartedAt: null,
    urlHash: "",
    pageStateInvalidated: false,
    canClearCache: true
  });
  return translatePage(tabID, {
    source: "popup",
    tabURL,
    discoveryScope: normalizedOptions.discoveryScope
  });
}

async function cancelTranslation(tabID) {
  const language = getState(tabID).appLanguage;
  const job = tabJobs.get(tabID);
  const pageSessionID = job?.pageSessionID || null;
  const jobID = job?.jobID || null;
  stateFor(tabID, "cancelled", t("cancelling", {}, language), {
    appLanguage: language,
    pageSessionID,
    jobID
  });
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
    pageSessionID,
    jobID: null,
    diagnosticStartedAt: null,
    urlHash: "",
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
    diagnosticStartedAt: null,
    urlHash: "",
    pageStateInvalidated: false,
    canClearCache: true,
    notice: true
  });
}

async function clearCurrentDomainCache(tabID, tabURL = "") {
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

  const url = await currentTabURL(tabID, tabURL);
  const domain = normalizedDomainFromURL(url) || job?.domain || getState(tabID).domain || "";
  let removed = 0;
  if (domain) {
    removed += await clearStoredTranslationsForDomain(domain, TARGET_LANGUAGE);
    if (job?.storageCache) {
      removeCachedEntriesForDomain(job.storageCache, domain, TARGET_LANGUAGE);
    }
  }

  await sendContent(tabID, { type: "restore" }).catch(() => {});
  tabJobs.delete(tabID);
  return stateFor(tabID, "idle", domainCacheClearedMessage(removed, Boolean(domain), language), {
    appLanguage: language,
    domain,
    hasTranslations: false,
    done: 0,
    failed: 0,
    total: 0,
    jobID: null,
    pageSessionID: null,
    diagnosticStartedAt: null,
    urlHash: "",
    pageStateInvalidated: false,
    canClearCache: true,
    notice: true
  });
}

async function clearAllPageCache(tabID) {
  const language = getState(tabID).appLanguage;
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

  const removed = await clearStoredTranslations();
  if (tabID) {
    await sendContent(tabID, { type: "restore" }).catch(() => {});
    tabJobs.delete(tabID);
  }
  return stateFor(tabID, "idle", allCacheClearedMessage(removed, language), {
    appLanguage: language,
    hasTranslations: false,
    done: 0,
    failed: 0,
    total: 0,
    jobID: null,
    pageSessionID: null,
    diagnosticStartedAt: null,
    urlHash: "",
    pageStateInvalidated: false,
    canClearCache: true,
    notice: true
  });
}

async function ensureContentScript(tabID) {
  try {
    await sendContent(tabID, { type: "ping" });
  } catch {
    try {
      await chrome.scripting.executeScript({
        target: { tabId: tabID },
        files: ["contentScript.js"]
      });
    } catch (error) {
      throw contentAccessError("content_script_injection_failed", error);
    }
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
  return `${job.targetLanguage || TARGET_LANGUAGE}:${normalizeTranslationQuality(job.translationQuality)}:${job.urlHash || ""}:${segment.textHash}`;
}

function cacheEntryForSegment(job, segment, translation) {
  return {
    id: translationCacheID(job, segment),
    sourceText: segment.text,
    translation,
    targetLanguage: job.targetLanguage || TARGET_LANGUAGE,
    translationQuality: normalizeTranslationQuality(job.translationQuality),
    urlHash: job.urlHash || "",
    domain: job.domain || "",
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

async function clearStoredTranslationsForDomain(domain, targetLanguage = TARGET_LANGUAGE) {
  if (!chrome.storage?.local || !domain) {
    return 0;
  }
  const cache = await loadTranslationCache();
  const removed = removeCachedEntriesForDomain(cache, domain, targetLanguage);
  if (removed > 0) {
    await chrome.storage.local.set({ [TRANSLATION_CACHE_KEY]: cache }).catch(() => {});
  }
  return removed;
}

async function clearStoredTranslations() {
  if (!chrome.storage?.local) {
    return 0;
  }
  const cache = await loadTranslationCache();
  const removed = Object.keys(cache).length;
  if (removed > 0) {
    await chrome.storage.local.set({ [TRANSLATION_CACHE_KEY]: {} }).catch(() => {});
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

function removeCachedEntriesForDomain(cache, domain, targetLanguage = TARGET_LANGUAGE) {
  if (!cache || !domain) {
    return 0;
  }
  const normalizedDomain = normalizeDomain(domain);
  let removed = 0;
  for (const key of Object.keys(cache)) {
    const entry = cache[key];
    if (normalizeDomain(entry?.domain || "") === normalizedDomain && (!targetLanguage || entry.targetLanguage === targetLanguage)) {
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

function domainCacheClearedMessage(removed, hadDomain, language = currentAppLanguage) {
  if (!hadDomain) {
    return t("cacheDomainUnknown", {}, language);
  }
  if (removed > 0) {
    return t("cacheCleared", { removed }, language);
  }
  return t("cacheEmpty", {}, language);
}

function allCacheClearedMessage(removed, language = currentAppLanguage) {
  if (removed > 0) {
    return t("cacheAllCleared", { removed }, language);
  }
  return t("cacheAllEmpty", {}, language);
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
        failedStateForError(tabID, error);
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
  return translatePage(tabID, { source: "contextMenu" });
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
