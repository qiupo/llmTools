const statusEl = document.getElementById("status");
const modelEl = document.getElementById("model");
const barEl = document.getElementById("bar");
const translateBtn = document.getElementById("translate");
const restoreBtn = document.getElementById("restore");
const cancelBtn = document.getElementById("cancel");
const statusBtn = document.getElementById("statusBtn");
const clearCacheBtn = document.getElementById("clearCache");

const DEFAULT_APP_LANGUAGE = "zh-Hans";
const POPUP_TEXT = {
  "zh-Hans": {
    ready: "就绪",
    localModel: "本地模型",
    model: ({ modelName }) => `模型：${modelName}`,
    localAppNotConnected: "本地应用未连接",
    openWebpageBeforeClearingCache: "请先打开网页标签页再清除缓存。",
    openWebpageBeforeTranslating: "请先打开网页标签页再翻译。",
    discoveringPageText: "正在发现页面文本...",
    clearingCachedTranslations: "正在清除缓存译文...",
    translatePage: "翻译页面",
    restore: "恢复原文",
    cancel: "取消",
    test: "测试",
    clearCache: "清除缓存",
    clearCacheTitle: "清除当前页面的缓存译文"
  },
  en: {
    ready: "Ready",
    localModel: "Local model",
    model: ({ modelName }) => `Model: ${modelName}`,
    localAppNotConnected: "Local app not connected",
    openWebpageBeforeClearingCache: "Open a webpage tab before clearing cache.",
    openWebpageBeforeTranslating: "Open a webpage tab before translating.",
    discoveringPageText: "Discovering page text...",
    clearingCachedTranslations: "Clearing cached translations...",
    translatePage: "Translate Page",
    restore: "Restore",
    cancel: "Cancel",
    test: "Test",
    clearCache: "Clear Cache",
    clearCacheTitle: "Clear cached translations for the current page"
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
  restoreBtn.textContent = t("restore");
  cancelBtn.textContent = t("cancel");
  statusBtn.textContent = t("test");
  clearCacheBtn.textContent = t("clearCache");
  clearCacheBtn.title = t("clearCacheTitle");
}

async function send(type) {
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
      canClearCache: false
    };
  }
  return chrome.runtime.sendMessage({ type, tabID: tab?.id, tabURL: tab?.url });
}

function render(state) {
  if (!state) return;
  applyLanguage(state.appLanguage || appLanguage);
  statusEl.textContent = state.message || state.status || t("ready");
  modelEl.textContent = state.modelName ? t("model", { modelName: state.modelName }) : t("localModel");
  const total = Math.max(state.total || 0, 1);
  const done = Math.min(state.done || 0, total);
  barEl.style.width = `${Math.round((done / total) * 100)}%`;
  translateBtn.disabled = state.status === "translating" || state.status === "discovering";
  cancelBtn.disabled = state.status !== "translating" && state.status !== "discovering";
  restoreBtn.disabled = !state.hasTranslations;
  clearCacheBtn.disabled = state.canClearCache === false;
}

async function refresh() {
  try {
    await send("checkStatus");
    render(await send("getPopupState"));
  } catch (error) {
    statusEl.textContent = error?.message || String(error);
    modelEl.textContent = t("localAppNotConnected");
    translateBtn.disabled = true;
    cancelBtn.disabled = true;
    restoreBtn.disabled = true;
    clearCacheBtn.disabled = true;
  }
}

translateBtn.addEventListener("click", async () => {
  statusEl.textContent = t("discoveringPageText");
  render(await send("translatePage"));
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

clearCacheBtn.addEventListener("click", async () => {
  statusEl.textContent = t("clearingCachedTranslations");
  render(await send("clearCurrentPageCache"));
});

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "popupState") {
    render(message.state);
  }
});

applyLanguage();
refresh();
