const statusEl = document.getElementById("status");
const modelEl = document.getElementById("model");
const barEl = document.getElementById("bar");
const domainEl = document.getElementById("domain");
const domainRuleEl = document.getElementById("domainRule");
const diagnosticsEl = document.getElementById("diagnostics");
const readingModeEl = document.getElementById("readingMode");
const discoveryScopeEl = document.getElementById("discoveryScope");
const translationQualityEl = document.getElementById("translationQuality");
const pendingIndicatorStyleEl = document.getElementById("pendingIndicatorStyle");
const saveReadingDefaultBtn = document.getElementById("saveReadingDefault");
const saveQualityDefaultBtn = document.getElementById("saveQualityDefault");
const translateBtn = document.getElementById("translate");
const retranslateBtn = document.getElementById("retranslate");
const restoreBtn = document.getElementById("restore");
const cancelBtn = document.getElementById("cancel");
const statusBtn = document.getElementById("statusBtn");
const clearPageCacheBtn = document.getElementById("clearPageCache");
const clearDomainCacheBtn = document.getElementById("clearDomainCache");
const clearAllCacheBtn = document.getElementById("clearAllCache");

const DEFAULT_APP_LANGUAGE = "zh-Hans";
const POPUP_TEXT = {
  "zh-Hans": {
    ready: "就绪",
    localModel: "本地模型",
    model: ({ modelName }) => `模型：${modelName}`,
    engine: ({ engineName }) => `引擎：${engineName}`,
    engineWithDetail: ({ engineName, engineID }) => `引擎：${engineName}（${engineID}）`,
    engineFastMT: "快速 MT",
    engineAuto: "自动",
    localAppNotConnected: "本地应用未连接",
    openWebpageBeforeClearingCache: "请先打开网页标签页再清除缓存。",
    openWebpageBeforeTranslating: "请先打开网页标签页再翻译。",
    discoveringPageText: "正在发现页面文本...",
    clearingCachedTranslations: "正在清除缓存译文...",
    autoTranslatePermissionDenied: "未获得此网站权限，已保持手动翻译。",
    currentSite: "当前网站",
    domainUnknown: "当前网站",
    domainRuleAsk: "手动翻译",
    domainRuleAlways: "自动翻译此网站",
    domainRuleNever: "不翻译此网站",
    readingMode: "阅读模式",
    readingModeReplace: "替换译文",
    readingModeBilingual: "双语对照",
    readingModeOriginal: "原文",
    discoveryScope: "翻译范围",
    discoveryScopeVisible: "可视区域优先",
    discoveryScopePage: "全页预翻译",
    translationQuality: "翻译质量",
    qualityModeNatural: "自然",
    qualityModeLiteral: "直译",
    qualityModeTechnical: "技术术语",
    pendingIndicatorStyle: "待翻译样式",
    pendingStyleLoading: "Loading",
    pendingStyleFlipText: "翻牌",
    pendingStyleNone: "无样式",
    saveSiteDefault: "默认",
    saveReadingDefaultTitle: "保存为当前网站默认阅读模式",
    saveQualityDefaultTitle: "保存为当前网站默认翻译质量",
    translatePage: "翻译页面",
    retranslate: "重译",
    retranslatingPage: "正在重新翻译当前页...",
    restore: "恢复原文",
    cancel: "取消",
    test: "测试",
    clearPageCache: "清页",
    clearDomainCache: "清站",
    clearAllCache: "清全",
    clearPageCacheTitle: "清除当前页面的缓存译文",
    clearDomainCacheTitle: "清除当前网站的缓存译文",
    clearAllCacheTitle: "清除全部网页缓存译文",
    diagnosticsPrefix: "诊断",
    diagnosticsEngine: "引擎",
    diagnosticsSource: "来源",
    diagnosticsDomain: "域名",
    diagnosticsUrl: "页面",
    diagnosticsError: "错误"
  },
  en: {
    ready: "Ready",
    localModel: "Local model",
    model: ({ modelName }) => `Model: ${modelName}`,
    engine: ({ engineName }) => `Engine: ${engineName}`,
    engineWithDetail: ({ engineName, engineID }) => `Engine: ${engineName} (${engineID})`,
    engineFastMT: "Fast MT",
    engineAuto: "Auto",
    localAppNotConnected: "Local app not connected",
    openWebpageBeforeClearingCache: "Open a webpage tab before clearing cache.",
    openWebpageBeforeTranslating: "Open a webpage tab before translating.",
    discoveringPageText: "Discovering page text...",
    clearingCachedTranslations: "Clearing cached translations...",
    autoTranslatePermissionDenied: "Site permission was not granted. Manual translation is unchanged.",
    currentSite: "Current site",
    domainUnknown: "Current site",
    domainRuleAsk: "Translate manually",
    domainRuleAlways: "Auto-translate this site",
    domainRuleNever: "Never translate this site",
    readingMode: "Reading mode",
    readingModeReplace: "Replace",
    readingModeBilingual: "Bilingual",
    readingModeOriginal: "Original",
    discoveryScope: "Translation scope",
    discoveryScopeVisible: "Visible first",
    discoveryScopePage: "Full page",
    translationQuality: "Translation quality",
    qualityModeNatural: "Natural",
    qualityModeLiteral: "Literal",
    qualityModeTechnical: "Technical",
    pendingIndicatorStyle: "Pending style",
    pendingStyleLoading: "Loading",
    pendingStyleFlipText: "Flip text",
    pendingStyleNone: "No style",
    saveSiteDefault: "Default",
    saveReadingDefaultTitle: "Save as this site's default reading mode",
    saveQualityDefaultTitle: "Save as this site's default translation quality",
    translatePage: "Translate Page",
    retranslate: "Retranslate",
    retranslatingPage: "Retranslating current page...",
    restore: "Restore",
    cancel: "Cancel",
    test: "Test",
    clearPageCache: "Page",
    clearDomainCache: "Site",
    clearAllCache: "All",
    clearPageCacheTitle: "Clear cached translations for the current page",
    clearDomainCacheTitle: "Clear cached translations for the current site",
    clearAllCacheTitle: "Clear all cached webpage translations",
    diagnosticsPrefix: "Diagnostics",
    diagnosticsEngine: "engine",
    diagnosticsSource: "source",
    diagnosticsDomain: "domain",
    diagnosticsUrl: "page",
    diagnosticsError: "error"
  }
};

let appLanguage = DEFAULT_APP_LANGUAGE;

function normalizeAppLanguage(language) {
  return language === "en" ? "en" : DEFAULT_APP_LANGUAGE;
}

function t(key, values = {}, language = appLanguage) {
  const normalizedLanguage = normalizeAppLanguage(language);
  const catalog = POPUP_TEXT[normalizedLanguage] || POPUP_TEXT[DEFAULT_APP_LANGUAGE];
  const entry = catalog[key] ?? POPUP_TEXT.en[key] ?? key;
  return typeof entry === "function" ? entry(values) : entry;
}

function applyLanguage(language = appLanguage) {
  appLanguage = normalizeAppLanguage(language);
  document.documentElement.lang = appLanguage;
  translateBtn.textContent = t("translatePage");
  retranslateBtn.textContent = t("retranslate");
  restoreBtn.textContent = t("restore");
  cancelBtn.textContent = t("cancel");
  statusBtn.textContent = t("test");
  clearPageCacheBtn.textContent = t("clearPageCache");
  clearDomainCacheBtn.textContent = t("clearDomainCache");
  clearAllCacheBtn.textContent = t("clearAllCache");
  clearPageCacheBtn.title = t("clearPageCacheTitle");
  clearDomainCacheBtn.title = t("clearDomainCacheTitle");
  clearAllCacheBtn.title = t("clearAllCacheTitle");
  domainRuleEl.options[0].textContent = t("domainRuleAsk");
  domainRuleEl.options[1].textContent = t("domainRuleAlways");
  domainRuleEl.options[2].textContent = t("domainRuleNever");
  readingModeEl.setAttribute("aria-label", t("readingMode"));
  readingModeEl.options[0].textContent = t("readingModeReplace");
  readingModeEl.options[1].textContent = t("readingModeBilingual");
  readingModeEl.options[2].textContent = t("readingModeOriginal");
  discoveryScopeEl.setAttribute("aria-label", t("discoveryScope"));
  discoveryScopeEl.options[0].textContent = t("discoveryScopeVisible");
  discoveryScopeEl.options[1].textContent = t("discoveryScopePage");
  translationQualityEl.setAttribute("aria-label", t("translationQuality"));
  translationQualityEl.options[0].textContent = t("qualityModeNatural");
  translationQualityEl.options[1].textContent = t("qualityModeLiteral");
  translationQualityEl.options[2].textContent = t("qualityModeTechnical");
  pendingIndicatorStyleEl.setAttribute("aria-label", t("pendingIndicatorStyle"));
  pendingIndicatorStyleEl.options[0].textContent = t("pendingStyleLoading");
  pendingIndicatorStyleEl.options[1].textContent = t("pendingStyleFlipText");
  pendingIndicatorStyleEl.options[2].textContent = t("pendingStyleNone");
  saveReadingDefaultBtn.textContent = t("saveSiteDefault");
  saveQualityDefaultBtn.textContent = t("saveSiteDefault");
  saveReadingDefaultBtn.title = t("saveReadingDefaultTitle");
  saveQualityDefaultBtn.title = t("saveQualityDefaultTitle");
}

async function send(type, extra = {}) {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id && type !== "checkStatus" && type !== "getPopupState") {
    return {
      status: "unsupportedPage",
      message: type === "clearCurrentPageCache"
        ? t("openWebpageBeforeClearingCache")
        : t("openWebpageBeforeTranslating"),
      appLanguage,
      done: 0,
      total: 0,
      hasTranslations: false,
      canClearCache: false,
      domain: "",
      domainRule: "ask",
      readingMode: "replace",
      discoveryScope: "visible",
      translationQuality: "natural",
      pendingIndicatorStyle: "loading"
    };
  }
  return chrome.runtime.sendMessage({ type, tabID: tab?.id, tabURL: tab?.url, ...extra });
}

async function activeTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab || null;
}

function permissionOriginsForURL(url = "") {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return [];
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return [];
  }
  const host = parsed.hostname.toLowerCase().replace(/^www\./, "");
  if (!host) {
    return [];
  }
  return [
    `http://${host}/*`,
    `https://${host}/*`,
    `http://*.${host}/*`,
    `https://*.${host}/*`
  ];
}

async function requestAutoTranslatePermission() {
  const tab = await activeTab();
  const origins = permissionOriginsForURL(tab?.url || "");
  if (!origins.length || !chrome.permissions?.request) {
    return false;
  }
  try {
    return Boolean(await chrome.permissions.request({ origins }));
  } catch {
    return false;
  }
}

function shortHash(value = "") {
  const text = String(value || "");
  return text.length > 12 ? text.slice(0, 12) : text;
}

function modelStatusText(state) {
  const engine = state?.translationEngine || "";
  const engineID = state?.translationEngineID || "";
  if (engine === "fastMT") {
    const engineName = t("engineFastMT");
    return engineID && engineID !== "fastmt" && engineID !== "auto"
      ? t("engineWithDetail", { engineName, engineID })
      : t("engine", { engineName });
  }
  if (engine === "auto") {
    return t("engine", { engineName: t("engineAuto") });
  }
  return state?.modelName ? t("model", { modelName: state.modelName }) : t("localModel");
}

function formatDiagnostics(state) {
  const diagnostics = state?.diagnostics;
  if (!diagnostics) {
    return "";
  }
  const counts = diagnostics.counts || {};
  const timings = diagnostics.timings || {};
  const model = diagnostics.model || {};
  const translation = diagnostics.translation || {};
  const engine = translation.engineID || translation.engine || "";
  const parts = [
    t("diagnosticsPrefix"),
    [diagnostics.browserID, diagnostics.extensionVersion].filter(Boolean).join(" "),
    diagnostics.status || state.status || "",
    `${Math.max(counts.done || 0, 0)}/${Math.max(counts.total || 0, 0)}`,
    timings.elapsedMs == null ? "" : `${timings.elapsedMs}ms`,
    engine ? `${t("diagnosticsEngine")} ${engine}` : "",
    translation.detectedSource ? `${t("diagnosticsSource")} ${translation.detectedSource}` : "",
    model.name || "",
    diagnostics.domainHash ? `${t("diagnosticsDomain")} ${shortHash(diagnostics.domainHash)}` : "",
    diagnostics.urlHash ? `${t("diagnosticsUrl")} ${shortHash(diagnostics.urlHash)}` : "",
    diagnostics.errorCode ? `${t("diagnosticsError")} ${diagnostics.errorCode}` : ""
  ];
  return parts.filter(Boolean).join(" · ");
}

function render(state) {
  if (!state) return;
  applyLanguage(state.appLanguage || appLanguage);
  statusEl.textContent = state.message || state.status || t("ready");
  modelEl.textContent = modelStatusText(state);
  const diagnosticsText = formatDiagnostics(state);
  diagnosticsEl.textContent = diagnosticsText;
  diagnosticsEl.hidden = !diagnosticsText;
  domainEl.textContent = state.domain || t("domainUnknown");
  domainRuleEl.value = state.domainRule || "ask";
  domainRuleEl.disabled = !state.domain;
  readingModeEl.value = state.readingMode || "replace";
  readingModeEl.disabled = state.status === "unsupportedPage";
  discoveryScopeEl.value = state.discoveryScope || "visible";
  discoveryScopeEl.disabled = state.status === "unsupportedPage";
  translationQualityEl.value = state.translationQuality || "natural";
  translationQualityEl.disabled = state.status === "unsupportedPage";
  pendingIndicatorStyleEl.value = state.pendingIndicatorStyle || "loading";
  pendingIndicatorStyleEl.disabled = false;
  saveReadingDefaultBtn.disabled = !state.domain || state.status === "unsupportedPage";
  saveQualityDefaultBtn.disabled = !state.domain || state.status === "unsupportedPage";
  const total = Math.max(state.total || 0, 1);
  const done = Math.min(state.done || 0, total);
  barEl.style.width = `${Math.round((done / total) * 100)}%`;
  translateBtn.disabled = state.status === "translating" || state.status === "discovering";
  retranslateBtn.disabled = state.status === "translating" || state.status === "discovering";
  cancelBtn.disabled = state.status !== "translating" && state.status !== "discovering";
  restoreBtn.disabled = !state.hasTranslations;
  const cacheDisabled = state.canClearCache === false;
  clearPageCacheBtn.disabled = cacheDisabled;
  clearDomainCacheBtn.disabled = cacheDisabled || !state.domain;
  clearAllCacheBtn.disabled = cacheDisabled;
}

async function refresh() {
  try {
    await send("checkStatus");
    render(await send("getPopupState"));
  } catch (error) {
    statusEl.textContent = error?.message || String(error);
    modelEl.textContent = t("localAppNotConnected");
    translateBtn.disabled = true;
    retranslateBtn.disabled = true;
    cancelBtn.disabled = true;
    restoreBtn.disabled = true;
    readingModeEl.disabled = true;
    discoveryScopeEl.disabled = true;
    translationQualityEl.disabled = true;
    pendingIndicatorStyleEl.disabled = true;
    saveReadingDefaultBtn.disabled = true;
    saveQualityDefaultBtn.disabled = true;
    clearPageCacheBtn.disabled = true;
    clearDomainCacheBtn.disabled = true;
    clearAllCacheBtn.disabled = true;
  }
}

translateBtn.addEventListener("click", async () => {
  statusEl.textContent = t("discoveringPageText");
  render(await send("translatePage", { discoveryScope: discoveryScopeEl.value }));
});

retranslateBtn.addEventListener("click", async () => {
  statusEl.textContent = t("retranslatingPage");
  render(await send("retranslatePage", { discoveryScope: discoveryScopeEl.value }));
});

restoreBtn.addEventListener("click", async () => {
  render(await send("restorePage"));
});

cancelBtn.addEventListener("click", async () => {
  render(await send("cancelTranslation"));
});

statusBtn.addEventListener("click", async () => {
  await send("checkStatus");
  render(await send("getPopupState"));
});

clearPageCacheBtn.addEventListener("click", async () => {
  statusEl.textContent = t("clearingCachedTranslations");
  render(await send("clearCurrentPageCache"));
});

clearDomainCacheBtn.addEventListener("click", async () => {
  statusEl.textContent = t("clearingCachedTranslations");
  render(await send("clearCurrentDomainCache"));
});

clearAllCacheBtn.addEventListener("click", async () => {
  statusEl.textContent = t("clearingCachedTranslations");
  render(await send("clearAllPageCache"));
});

domainRuleEl.addEventListener("change", async () => {
  if (domainRuleEl.value === "alwaysTranslate") {
    const granted = await requestAutoTranslatePermission();
    if (!granted) {
      domainRuleEl.value = "ask";
      statusEl.textContent = t("autoTranslatePermissionDenied");
      render(await send("setDomainRule", { rule: "ask" }));
      return;
    }
  }
  render(await send("setDomainRule", { rule: domainRuleEl.value }));
});

readingModeEl.addEventListener("change", async () => {
  render(await send("setReadingMode", { readingMode: readingModeEl.value }));
});

discoveryScopeEl.addEventListener("change", async () => {
  render(await send("setDiscoveryScope", { discoveryScope: discoveryScopeEl.value }));
});

translationQualityEl.addEventListener("change", async () => {
  render(await send("setTranslationQuality", { translationQuality: translationQualityEl.value }));
});

pendingIndicatorStyleEl.addEventListener("change", async () => {
  render(await send("setPendingIndicatorStyle", { pendingIndicatorStyle: pendingIndicatorStyleEl.value }));
});

saveReadingDefaultBtn.addEventListener("click", async () => {
  render(await send("setDomainPageDefaults", { readingMode: readingModeEl.value }));
});

saveQualityDefaultBtn.addEventListener("click", async () => {
  render(await send("setDomainPageDefaults", { translationQuality: translationQualityEl.value }));
});

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "popupState") {
    render(message.state);
  }
});

applyLanguage();
refresh();
