const statusEl = document.getElementById("status");
const modelEl = document.getElementById("model");
const barEl = document.getElementById("bar");
const translateBtn = document.getElementById("translate");
const restoreBtn = document.getElementById("restore");
const cancelBtn = document.getElementById("cancel");
const statusBtn = document.getElementById("statusBtn");

async function send(type) {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id && type !== "checkStatus" && type !== "getPopupState") {
    return {
      status: "unsupportedPage",
      message: "Open a webpage tab before translating.",
      done: 0,
      total: 0,
      hasTranslations: false
    };
  }
  return chrome.runtime.sendMessage({ type, tabID: tab?.id });
}

function render(state) {
  if (!state) return;
  statusEl.textContent = state.message || state.status || "Ready";
  modelEl.textContent = state.modelName ? `Model: ${state.modelName}` : "Local model";
  const total = Math.max(state.total || 0, 1);
  const done = Math.min(state.done || 0, total);
  barEl.style.width = `${Math.round((done / total) * 100)}%`;
  translateBtn.disabled = state.status === "translating" || state.status === "discovering";
  cancelBtn.disabled = state.status !== "translating" && state.status !== "discovering";
  restoreBtn.disabled = !state.hasTranslations;
}

async function refresh() {
  try {
    await send("checkStatus");
    render(await send("getPopupState"));
  } catch (error) {
    statusEl.textContent = error?.message || String(error);
    modelEl.textContent = "Local app not connected";
    translateBtn.disabled = true;
    cancelBtn.disabled = true;
    restoreBtn.disabled = true;
  }
}

translateBtn.addEventListener("click", async () => {
  statusEl.textContent = "Discovering page text...";
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

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "popupState") {
    render(message.state);
  }
});

refresh();
