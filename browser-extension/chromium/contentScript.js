(() => {
  if (window.__llmTranslateContentLoaded) {
    return;
  }
  window.__llmTranslateContentLoaded = true;

  const state = {
    pageSessionID: null,
    nodeByID: new Map(),
    originalByID: new Map(),
    translatedByID: new Map(),
    spinnerByID: new Map(),
    processedNodes: new WeakSet(),
    pendingNodes: new Set(),
    cancelled: false,
    overlay: null,
    overlayMinimized: false,
    segmentSpinnerStyleInstalled: false,
    intersectionObserver: null,
    mutationObserver: null,
    discoveryTimer: null
  };

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    Promise.resolve(handleMessage(message)).then(sendResponse).catch((error) => {
      sendResponse({ ok: false, error: error?.message || String(error) });
    });
    return true;
  });

  async function handleMessage(message) {
    switch (message?.type) {
      case "ping":
        return { ok: true };
      case "startSession":
        return startSession(message.pageSessionID);
      case "applyTranslations":
        applyTranslations(message.translations || []);
        return { ok: true, applied: state.translatedByID.size };
      case "translationState":
        updateOverlayFromState(message.state || {});
        return { ok: true };
      case "getPageTranslationState":
        return getPageTranslationState();
      case "restore":
        restoreOriginal();
        return { ok: true };
      case "cancel":
        state.cancelled = true;
        state.pendingNodes.clear();
        removeAllSegmentSpinners();
        updateOverlay("Cancelled");
        return { ok: true };
      default:
        return { ok: true };
    }
  }

  function startSession(pageSessionID) {
    state.pageSessionID = pageSessionID || crypto.randomUUID();
    state.cancelled = false;
    state.overlayMinimized = false;
    state.processedNodes = new WeakSet();
    state.pendingNodes.clear();
    state.nodeByID.clear();
    state.originalByID.clear();
    state.translatedByID.clear();
    removeAllSegmentSpinners();
    showOverlay("Discovering text...");
    installObservers();
    const segments = discoverSegments();
    updateOverlay(`Found ${segments.length} segments`);
    return {
      ok: true,
      url: location.href,
      title: document.title,
      segments
    };
  }

  function getPageTranslationState() {
    return {
      ok: true,
      url: location.href,
      title: document.title,
      pageSessionID: state.pageSessionID,
      trackedCount: state.originalByID.size,
      translatedCount: state.translatedByID.size,
      hasTranslations: state.translatedByID.size > 0
    };
  }

  function discoverSegments(root = document.body) {
    if (!root || state.cancelled) {
      return [];
    }
    const segments = [];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!candidateNode(node)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });

    let node;
    while ((node = walker.nextNode()) && segments.length < 200) {
      const segment = registerNode(node);
      if (segment) {
        segments.push(segment);
      }
    }
    return segments;
  }

  function registerNode(node) {
    const text = normalizeText(node.nodeValue || "");
    const textHash = stableHash(text);
    if (state.processedNodes.has(node)) {
      return null;
    }
    const segmentID = crypto.randomUUID();
    state.nodeByID.set(segmentID, node);
    state.originalByID.set(segmentID, node.nodeValue);
    state.processedNodes.add(node);
    showSegmentSpinner(segmentID, node);
    return {
      segmentID,
      text,
      tagName: node.parentElement?.tagName || "",
      blockContext: closestBlockName(node.parentElement),
      priority: priorityFor(node.parentElement),
      textHash
    };
  }

  function candidateNode(node) {
    if (!node.nodeValue || !normalizeText(node.nodeValue)) return false;
    const element = node.parentElement;
    if (!element || shouldSkipElement(element) || !isVisible(element)) return false;
    const text = normalizeText(node.nodeValue);
    if (!isEnglishDominant(text)) return false;
    if (!nearViewport(element)) return false;
    return true;
  }

  function applyTranslations(translations) {
    for (const item of translations) {
      if (state.cancelled) break;
      if (!item || item.status !== "translated" || !item.translation) {
        removeSegmentSpinner(item?.segmentID);
        continue;
      }
      const node = state.nodeByID.get(item.segmentID);
      if (!node || !node.isConnected) {
        removeSegmentSpinner(item.segmentID);
        continue;
      }
      const original = state.originalByID.get(item.segmentID);
      if (!original) {
        removeSegmentSpinner(item.segmentID);
        continue;
      }
      if (state.translatedByID.has(item.segmentID)) {
        removeSegmentSpinner(item.segmentID);
        continue;
      }
      node.nodeValue = preserveWhitespace(original, item.translation);
      state.translatedByID.set(item.segmentID, item.translation);
      removeSegmentSpinner(item.segmentID);
    }
    updateOverlay(`Applied ${state.translatedByID.size} translations`, {
      canRestore: state.translatedByID.size > 0
    });
  }

  function restoreOriginal() {
    state.cancelled = true;
    disconnectObservers();
    for (const [segmentID, original] of state.originalByID.entries()) {
      const node = state.nodeByID.get(segmentID);
      if (node && node.isConnected && state.translatedByID.has(segmentID)) {
        node.nodeValue = original;
      }
    }
    state.nodeByID.clear();
    state.originalByID.clear();
    state.translatedByID.clear();
    removeAllSegmentSpinners();
    state.processedNodes = new WeakSet();
    state.pendingNodes.clear();
    state.pageSessionID = null;
    state.overlayMinimized = false;
    hideOverlay();
  }

  function installObservers() {
    disconnectObservers();
    state.intersectionObserver = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting && entry.target) {
          queueDiscovery(entry.target);
          state.intersectionObserver.unobserve(entry.target);
        }
      }
    }, { rootMargin: "800px 0px" });

    state.mutationObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType === Node.ELEMENT_NODE) {
            observeElement(node);
            queueDiscovery(node);
          } else if (node.nodeType === Node.TEXT_NODE && node.parentElement) {
            observeElement(node.parentElement);
            queueDiscovery(node.parentElement);
          }
        }
        if (mutation.type === "characterData" && mutation.target?.parentElement) {
          queueDiscovery(mutation.target.parentElement);
        }
      }
    });

    state.mutationObserver.observe(document.body, {
      childList: true,
      subtree: true,
      characterData: true
    });
    observeElement(document.body);
  }

  function observeElement(root) {
    if (!state.intersectionObserver || !root || root.nodeType !== Node.ELEMENT_NODE) {
      return;
    }
    if (root !== document.body && !shouldSkipElement(root)) {
      state.intersectionObserver.observe(root);
    }
    const candidates = root.querySelectorAll?.("p, li, td, th, h1, h2, h3, h4, h5, h6, article, section, main, button, a, span, div") || [];
    for (const element of candidates) {
      if (!shouldSkipElement(element)) {
        state.intersectionObserver.observe(element);
      }
    }
  }

  function queueDiscovery(root) {
    if (!state.pageSessionID || state.cancelled || !root) {
      return;
    }
    state.pendingNodes.add(root);
    clearTimeout(state.discoveryTimer);
    state.discoveryTimer = setTimeout(flushPendingDiscovery, 250);
  }

  function flushPendingDiscovery() {
    if (!state.pageSessionID || state.cancelled) {
      return;
    }
    const pending = Array.from(state.pendingNodes);
    state.pendingNodes.clear();
    const segments = [];
    for (const root of pending) {
      if (!root.isConnected) continue;
      if (root.nodeType === Node.TEXT_NODE && root.parentElement) {
        const segment = candidateNode(root) ? registerNode(root) : null;
        if (segment) segments.push(segment);
      } else if (root.nodeType === Node.ELEMENT_NODE) {
        segments.push(...discoverSegments(root));
      }
      if (segments.length >= 200) break;
    }
    if (segments.length) {
      updateOverlay(`Queued ${segments.length} new segments`, {
        canCancel: true,
        canRestore: state.translatedByID.size > 0
      });
      safeRuntimeSendMessage({
        type: "segmentsDiscovered",
        pageSessionID: state.pageSessionID,
        url: location.href,
        title: document.title,
        segments
      });
    }
  }

  function disconnectObservers() {
    if (state.intersectionObserver) {
      state.intersectionObserver.disconnect();
      state.intersectionObserver = null;
    }
    if (state.mutationObserver) {
      state.mutationObserver.disconnect();
      state.mutationObserver = null;
    }
    clearTimeout(state.discoveryTimer);
    state.discoveryTimer = null;
  }

  function shouldSkipElement(element) {
    const skipped = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "SVG", "CANVAS", "CODE", "PRE", "KBD", "SAMP", "TEXTAREA", "INPUT", "SELECT", "OPTION"]);
    for (let current = element; current && current !== document.body; current = current.parentElement) {
      if (skipped.has(current.tagName)) return true;
      if (current.dataset?.llmTranslateSpinner === "true") return true;
      if (current.isContentEditable) return true;
      if (current.getAttribute("aria-hidden") === "true") return true;
    }
    return false;
  }

  function isVisible(element) {
    const style = getComputedStyle(element);
    if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
    return element.getClientRects().length > 0;
  }

  function nearViewport(element) {
    const margin = Math.max(window.innerHeight, 800);
    const rect = element.getBoundingClientRect();
    return rect.bottom >= -margin && rect.top <= window.innerHeight + margin;
  }

  function isEnglishDominant(text) {
    const letters = text.match(/\p{L}/gu) || [];
    const latin = text.match(/[A-Za-z]/g) || [];
    const cjk = text.match(/[\u3400-\u9fff]/g) || [];
    if (latin.length < 3) return false;
    if (cjk.length / Math.max(letters.length, 1) >= 0.25) return false;
    if (/^(https?:\/\/|www\.|[\w.-]+@[\w.-]+)$/.test(text)) return false;
    if (/^[A-Z0-9_\-./#]+$/.test(text) && text.length < 18) return false;
    return latin.length / Math.max(letters.length, 1) >= 0.6;
  }

  function normalizeText(text) {
    return text.replace(/\s+/g, " ").trim();
  }

  function preserveWhitespace(original, translation) {
    const leading = original.match(/^\s*/)?.[0] || "";
    const trailing = original.match(/\s*$/)?.[0] || "";
    return `${leading}${translation}${trailing}`;
  }

  function showSegmentSpinner(segmentID, node) {
    if (!segmentID || !node?.parentNode || state.spinnerByID.has(segmentID)) {
      return;
    }
    installSegmentSpinnerStyle();
    const spinner = document.createElement("span");
    spinner.className = "llmtranslate-segment-spinner";
    spinner.dataset.llmTranslateSpinner = "true";
    spinner.setAttribute("aria-label", "Translating");
    spinner.setAttribute("aria-live", "polite");
    spinner.setAttribute("contenteditable", "false");
    spinner.style.cssText = segmentSpinnerStyle();
    node.parentNode.insertBefore(spinner, node.nextSibling);
    state.spinnerByID.set(segmentID, spinner);
  }

  function removeSegmentSpinner(segmentID) {
    if (!segmentID) {
      return;
    }
    const spinner = state.spinnerByID.get(segmentID);
    if (spinner) {
      spinner.remove();
      state.spinnerByID.delete(segmentID);
    }
  }

  function removeAllSegmentSpinners() {
    for (const spinner of state.spinnerByID.values()) {
      spinner.remove();
    }
    state.spinnerByID.clear();
  }

  function installSegmentSpinnerStyle() {
    if (state.segmentSpinnerStyleInstalled) {
      return;
    }
    const style = document.createElement("style");
    style.dataset.llmTranslateSpinnerStyle = "true";
    style.textContent = `
      @keyframes llmtranslate-segment-spin {
        to { transform: rotate(360deg); }
      }
    `;
    document.documentElement.appendChild(style);
    state.segmentSpinnerStyleInstalled = true;
  }

  function segmentSpinnerStyle() {
    return [
      "display:inline-block",
      "width:0.72em",
      "height:0.72em",
      "margin-left:0.28em",
      "vertical-align:-0.08em",
      "border:1.5px solid rgba(37,99,235,.24)",
      "border-top-color:#2563eb",
      "border-radius:50%",
      "animation:llmtranslate-segment-spin .8s linear infinite",
      "pointer-events:none",
      "user-select:none"
    ].join(";");
  }

  function closestBlockName(element) {
    const blocks = new Set(["ARTICLE", "MAIN", "SECTION", "P", "LI", "TD", "TH", "H1", "H2", "H3", "H4", "BUTTON", "A"]);
    for (let current = element; current && current !== document.body; current = current.parentElement) {
      if (blocks.has(current.tagName)) return current.tagName.toLowerCase();
    }
    return "";
  }

  function priorityFor(element) {
    const tag = element?.tagName || "";
    if (/^H[1-3]$/.test(tag)) return 20;
    if (tag === "P" || tag === "LI") return 10;
    return 5;
  }

  function stableHash(text) {
    let hash = 2166136261;
    for (let i = 0; i < text.length; i += 1) {
      hash ^= text.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }

  function updateOverlayFromState(translationState) {
    if (!translationState.status) return;
    if (!translationState.hasTranslations && state.translatedByID.size === 0 && (translationState.status === "idle" || translationState.status === "restored")) {
      hideOverlay();
      return;
    }
    const active = translationState.status === "discovering" || translationState.status === "translating";
    const complete = translationState.status === "translated" || translationState.status === "partiallyTranslated";
    const total = translationState.total || 0;
    const done = translationState.done || 0;
    const failed = translationState.failed || 0;
    const progress = total > 0 ? `${done}/${total}${failed ? `, ${failed} failed` : ""}` : "";
    const message = translationState.message || progress || translationState.status;
    updateOverlay(message, {
      progress,
      canCancel: active,
      canRestore: Boolean(translationState.hasTranslations) || complete || state.translatedByID.size > 0
    });
  }

  function showOverlay(message) {
    if (!state.overlay) {
      const host = document.createElement("div");
      host.style.cssText = "position:fixed;right:16px;bottom:16px;z-index:2147483647;";
      const shadow = host.attachShadow({ mode: "closed" });
      const box = document.createElement("div");
      box.style.cssText = "font:13px -apple-system,BlinkMacSystemFont,sans-serif;background:#202124;color:#fff;border-radius:8px;padding:8px 10px;box-shadow:0 4px 16px rgba(0,0,0,.22);max-width:280px;min-width:220px;";
      const header = document.createElement("div");
      header.style.cssText = "display:flex;align-items:center;gap:8px;";
      const text = document.createElement("div");
      text.style.cssText = "flex:1;line-height:1.35;";
      const title = document.createElement("div");
      title.textContent = "llmTranslate";
      title.style.cssText = "font-weight:650;";
      const detail = document.createElement("div");
      detail.style.cssText = "color:rgba(255,255,255,.78);";
      text.append(title, detail);
      const minimize = document.createElement("button");
      minimize.type = "button";
      minimize.textContent = "-";
      minimize.title = "Minimize";
      minimize.style.cssText = overlayButtonStyle();
      header.append(text, minimize);
      const actions = document.createElement("div");
      actions.style.cssText = "display:flex;gap:6px;margin-top:8px;";
      const cancel = document.createElement("button");
      cancel.type = "button";
      cancel.textContent = "Cancel";
      cancel.style.cssText = overlayButtonStyle();
      const restore = document.createElement("button");
      restore.type = "button";
      restore.textContent = "Restore";
      restore.style.cssText = overlayButtonStyle();
      actions.append(cancel, restore);
      minimize.addEventListener("click", () => {
        state.overlayMinimized = !state.overlayMinimized;
        renderOverlay();
      });
      cancel.addEventListener("click", () => {
        safeRuntimeSendMessage({ type: "cancelTranslation" });
      });
      restore.addEventListener("click", () => {
        safeRuntimeSendMessage({ type: "restorePage" });
      });
      box.append(header, actions);
      shadow.appendChild(box);
      document.documentElement.appendChild(host);
      state.overlay = {
        host,
        box,
        title,
        detail,
        actions,
        cancel,
        restore,
        minimize,
        message,
        progress: "",
        canCancel: false,
        canRestore: false
      };
    }
    updateOverlay(message);
  }

  function updateOverlay(message, options = {}) {
    if (!state.overlay) showOverlay(message);
    state.overlay.message = message;
    state.overlay.progress = options.progress ?? state.overlay.progress ?? "";
    state.overlay.canCancel = options.canCancel ?? state.overlay.canCancel ?? false;
    state.overlay.canRestore = options.canRestore ?? state.overlay.canRestore ?? false;
    renderOverlay();
  }

  function renderOverlay() {
    if (!state.overlay) return;
    state.overlay.detail.textContent = state.overlayMinimized ? "" : state.overlay.message;
    state.overlay.title.textContent = state.overlayMinimized
      ? `llmTranslate${state.overlay.progress ? ` ${state.overlay.progress}` : ""}`
      : "llmTranslate";
    state.overlay.actions.style.display = state.overlayMinimized ? "none" : "flex";
    state.overlay.cancel.style.display = state.overlay.canCancel ? "" : "none";
    state.overlay.restore.style.display = state.overlay.canRestore ? "" : "none";
    state.overlay.minimize.textContent = state.overlayMinimized ? "+" : "-";
  }

  function hideOverlay() {
    if (state.overlay) {
      state.overlay.host.remove();
      state.overlay = null;
    }
  }

  function overlayButtonStyle() {
    return "border:1px solid rgba(255,255,255,.28);border-radius:6px;background:rgba(255,255,255,.08);color:#fff;padding:3px 7px;font:12px -apple-system,BlinkMacSystemFont,sans-serif;cursor:pointer;";
  }

  function safeRuntimeSendMessage(message) {
    try {
      const result = chrome.runtime.sendMessage(message);
      if (result?.catch) {
        result.catch(handleRuntimeSendFailure);
      }
      return result;
    } catch (error) {
      handleRuntimeSendFailure(error);
      return null;
    }
  }

  function handleRuntimeSendFailure(error) {
    if (!isExtensionContextInvalidated(error)) {
      return;
    }
    state.cancelled = true;
    state.pendingNodes.clear();
    disconnectObservers();
    removeAllSegmentSpinners();
    hideOverlay();
  }

  function isExtensionContextInvalidated(error) {
    return /Extension context invalidated/i.test(error?.message || String(error || ""));
  }
})();
