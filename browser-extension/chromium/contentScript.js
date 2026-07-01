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
    discoveryPaused: false,
    overlay: null,
    overlayMinimized: false,
    pendingIndicatorStyle: "loading",
    segmentBudget: 320,
    maxInlinePendingIndicators: 80,
    maxAnimatedSegments: 48,
    animatedSegmentIDs: new Set(),
    segmentSpinnerStyleInstalled: false,
    intersectionObserver: null,
    mutationObserver: null,
    discoveryTimer: null,
    staleIndicatorCleanupTimer: null
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
        return startSession(message.pageSessionID, message.pendingIndicatorStyle, message);
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
        state.discoveryPaused = true;
        state.pendingNodes.clear();
        removeAllSegmentSpinners();
        updateOverlay("Cancelled");
        return { ok: true };
      case "setDiscoveryPaused":
        setDiscoveryPaused(Boolean(message.paused), message.reason, message.segmentBudget);
        return { ok: true };
      default:
        return { ok: true };
    }
  }

  function startSession(pageSessionID, pendingIndicatorStyle, options = {}) {
    state.pageSessionID = pageSessionID || crypto.randomUUID();
    state.pendingIndicatorStyle = normalizePendingIndicatorStyle(pendingIndicatorStyle);
    state.segmentBudget = Math.max(Number(options.segmentBudget) || 320, 1);
    state.maxInlinePendingIndicators = Math.max(Number(options.maxInlinePendingIndicators) || 80, 0);
    state.maxAnimatedSegments = Math.max(Number(options.maxAnimatedSegments) || 48, 0);
    state.cancelled = false;
    state.discoveryPaused = false;
    state.overlayMinimized = false;
    state.processedNodes = new WeakSet();
    state.pendingNodes.clear();
    state.nodeByID.clear();
    state.originalByID.clear();
    state.translatedByID.clear();
    state.animatedSegmentIDs.clear();
    clearTimeout(state.staleIndicatorCleanupTimer);
    state.staleIndicatorCleanupTimer = null;
    removeAllSegmentSpinners();
    showOverlay("Discovering text...");
    installObservers();
    const segments = discoverSegments(document.body, state.segmentBudget);
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

  function remainingSegmentBudget() {
    return Math.max(state.segmentBudget - state.originalByID.size, 0);
  }

  function discoverSegments(root = document.body, limit = 200) {
    if (!root || state.cancelled || state.discoveryPaused || remainingSegmentBudget() <= 0) {
      return [];
    }
    const segments = [];
    const maxSegments = Math.min(Math.max(limit, 0), 200, remainingSegmentBudget());
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!candidateNode(node)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });

    const nodes = [];
    let node;
    while ((node = walker.nextNode()) && nodes.length < maxSegments) {
      nodes.push(node);
    }

    for (const textNode of nodes) {
      const segment = registerNode(textNode);
      if (segment) {
        segments.push(segment);
      }
    }
    return segments;
  }

  function registerNode(node) {
    if (remainingSegmentBudget() <= 0) {
      return null;
    }
    const text = normalizeText(node.nodeValue || "");
    const textHash = stableHash(text);
    if (state.processedNodes.has(node)) {
      return null;
    }
    const segmentID = crypto.randomUUID();
    const original = node.nodeValue;
    const indicator = showSegmentSpinner(segmentID, node);
    state.nodeByID.set(segmentID, indicator || node);
    state.originalByID.set(segmentID, original);
    state.processedNodes.add(node);
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
      if (shouldAnimateTranslation(item.segmentID)) {
        state.animatedSegmentIDs.add(item.segmentID);
        applyFlipTextTranslation(item.segmentID, node, original, item.translation);
      } else {
        node.nodeValue = preserveWhitespace(original, item.translation);
        state.translatedByID.set(item.segmentID, item.translation);
        removeSegmentSpinner(item.segmentID);
      }
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
        if (node.nodeType === Node.TEXT_NODE) {
          node.nodeValue = original;
        } else if (node.nodeType === Node.ELEMENT_NODE) {
          node.replaceWith(document.createTextNode(original));
        }
      }
    }
    state.nodeByID.clear();
    state.originalByID.clear();
    state.translatedByID.clear();
    state.animatedSegmentIDs.clear();
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

  function setDiscoveryPaused(paused, reason, segmentBudget) {
    state.discoveryPaused = paused;
    if (Number(segmentBudget) > 0) {
      state.segmentBudget = Number(segmentBudget);
    }
    if (paused) {
      state.pendingNodes.clear();
      clearTimeout(state.discoveryTimer);
      state.discoveryTimer = null;
      updateOverlay(reason === "budget" ? `Queued ${state.originalByID.size} segments` : "Translation queue is full", {
        canCancel: true,
        canRestore: state.translatedByID.size > 0
      });
      return;
    }
    if (!state.cancelled && state.pageSessionID && remainingSegmentBudget() > 0) {
      queueDiscovery(document.body);
    }
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
    if (!state.pageSessionID || state.cancelled || state.discoveryPaused || !root || remainingSegmentBudget() <= 0) {
      return;
    }
    state.pendingNodes.add(root);
    clearTimeout(state.discoveryTimer);
    state.discoveryTimer = setTimeout(flushPendingDiscovery, 250);
  }

  function flushPendingDiscovery() {
    if (!state.pageSessionID || state.cancelled || state.discoveryPaused || remainingSegmentBudget() <= 0) {
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
        segments.push(...discoverSegments(root, remainingSegmentBudget()));
      }
      if (segments.length >= 200 || remainingSegmentBudget() <= 0) break;
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
    clearTimeout(state.staleIndicatorCleanupTimer);
    state.staleIndicatorCleanupTimer = null;
  }

  function shouldSkipElement(element) {
    const skipped = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "SVG", "CANVAS", "CODE", "PRE", "KBD", "SAMP", "TEXTAREA", "INPUT", "SELECT", "OPTION"]);
    for (let current = element; current && current !== document.body; current = current.parentElement) {
      if (skipped.has(current.tagName)) return true;
      if (current.dataset?.llmTranslateSpinner === "true") return true;
      if (current.dataset?.llmTranslateIndicator === "true") return true;
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
      return null;
    }
    const indicatorStyle = effectivePendingIndicatorStyle();
    if (indicatorStyle === "none") {
      return null;
    }
    if (indicatorStyle === "flipText") {
      installSegmentSpinnerStyle();
      const indicator = createFlipTextIndicator(node.nodeValue || "", "", "pending");
      node.parentNode.insertBefore(indicator, node);
      node.remove();
      state.spinnerByID.set(segmentID, indicator);
      state.animatedSegmentIDs.add(segmentID);
      return indicator;
    }
    installSegmentSpinnerStyle();
    const spinner = document.createElement("span");
    spinner.className = "llmtranslate-segment-spinner";
    spinner.dataset.llmTranslateSpinner = "true";
    spinner.dataset.llmTranslateIndicator = "true";
    spinner.dataset.llmTranslateIndicatorKind = "loading";
    spinner.dataset.llmTranslateCreatedAt = String(Date.now());
    spinner.setAttribute("aria-label", "Translating");
    spinner.setAttribute("aria-live", "polite");
    spinner.setAttribute("contenteditable", "false");
    spinner.style.cssText = segmentSpinnerStyle();
    node.parentNode.insertBefore(spinner, node.nextSibling);
    state.spinnerByID.set(segmentID, spinner);
    return null;
  }

  function effectivePendingIndicatorStyle() {
    if (state.originalByID.size >= state.maxInlinePendingIndicators) {
      return "none";
    }
    return state.pendingIndicatorStyle;
  }

  function shouldAnimateTranslation(segmentID) {
    if (state.pendingIndicatorStyle !== "flipText") {
      return false;
    }
    if (state.animatedSegmentIDs.has(segmentID)) {
      return true;
    }
    return state.animatedSegmentIDs.size < state.maxAnimatedSegments;
  }

  function removeSegmentSpinner(segmentID) {
    if (!segmentID) {
      return;
    }
    const spinner = state.spinnerByID.get(segmentID);
    if (spinner) {
      const replacement = removeSegmentIndicatorElement(spinner);
      if (replacement) {
        state.nodeByID.set(segmentID, replacement);
      }
      state.spinnerByID.delete(segmentID);
    }
  }

  function removeAllSegmentSpinners() {
    for (const [segmentID, spinner] of state.spinnerByID.entries()) {
      const replacement = removeSegmentIndicatorElement(spinner);
      if (replacement) {
        state.nodeByID.set(segmentID, replacement);
      }
    }
    state.spinnerByID.clear();
  }

  function scheduleStaleIndicatorCleanup() {
    const createdBefore = Date.now();
    clearTimeout(state.staleIndicatorCleanupTimer);
    state.staleIndicatorCleanupTimer = setTimeout(() => {
      cleanupStaleSegmentIndicators(createdBefore);
    }, 2600);
  }

  function cleanupStaleSegmentIndicators(createdBefore) {
    if (!state.pageSessionID || state.cancelled || !state.spinnerByID.size) {
      return;
    }
    for (const [segmentID, indicator] of Array.from(state.spinnerByID.entries())) {
      const createdAt = Number(indicator?.dataset?.llmTranslateCreatedAt || 0);
      if (!indicator?.isConnected || createdAt > createdBefore) {
        continue;
      }
      const replacement = removeSegmentIndicatorElement(indicator);
      if (replacement) {
        state.nodeByID.set(segmentID, replacement);
      }
      state.spinnerByID.delete(segmentID);
    }
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
      .llmtranslate-segment-flip {
        display: inline;
        perspective: 700px;
        transform-style: preserve-3d;
        pointer-events: none;
        user-select: none;
      }
      .llmtranslate-segment-flip-tile {
        display: inline-grid;
        grid-template-areas: "llmtranslate-flip-stack";
        transform-origin: 50% 55%;
        transform-style: preserve-3d;
        vertical-align: baseline;
        will-change: transform;
      }
      .llmtranslate-segment-flip-face {
        display: inline-block;
        grid-area: llmtranslate-flip-stack;
        white-space: pre-wrap;
      }
      .llmtranslate-segment-flip-pending .llmtranslate-segment-flip-tile {
        animation: llmtranslate-segment-sway 1.35s ease-in-out infinite;
        animation-delay: var(--llmtranslate-delay, 0ms);
      }
      .llmtranslate-segment-flip-pending .llmtranslate-segment-flip-back {
        display: none;
      }
      .llmtranslate-segment-flip-complete .llmtranslate-segment-flip-tile {
        animation: llmtranslate-segment-complete-flip .78s cubic-bezier(.22,.9,.18,1) forwards;
        animation-delay: var(--llmtranslate-delay, 0ms);
      }
      .llmtranslate-segment-flip-complete .llmtranslate-segment-flip-front {
        animation: llmtranslate-segment-front-out .78s linear forwards;
        animation-delay: var(--llmtranslate-delay, 0ms);
      }
      .llmtranslate-segment-flip-complete .llmtranslate-segment-flip-back {
        color: #2563eb;
        opacity: 0;
        animation: llmtranslate-segment-back-in .78s linear forwards;
        animation-delay: var(--llmtranslate-delay, 0ms);
      }
      @keyframes llmtranslate-segment-sway {
        0%, 100% { transform: rotateX(0deg); }
        24% { transform: rotateX(-18deg); }
        54% { transform: rotateX(16deg); }
        76% { transform: rotateX(-6deg); }
      }
      @keyframes llmtranslate-segment-complete-flip {
        0% { transform: rotateX(0deg); }
        48% { transform: rotateX(172deg); }
        52% { transform: rotateX(188deg); }
        100% { transform: rotateX(360deg); }
      }
      @keyframes llmtranslate-segment-front-out {
        0%, 48% { opacity: 1; }
        49%, 100% { opacity: 0; }
      }
      @keyframes llmtranslate-segment-back-in {
        0%, 48% { opacity: 0; color: #2563eb; }
        49%, 100% { opacity: 1; color: inherit; }
      }
      @media (prefers-reduced-motion: reduce) {
        .llmtranslate-segment-flip-tile,
        .llmtranslate-segment-flip-face {
          animation: none !important;
          transform: none !important;
        }
        .llmtranslate-segment-flip-complete .llmtranslate-segment-flip-front {
          display: none;
        }
        .llmtranslate-segment-flip-complete .llmtranslate-segment-flip-back {
          opacity: 1;
          color: inherit;
        }
      }
    `;
    document.documentElement.appendChild(style);
    state.segmentSpinnerStyleInstalled = true;
  }

  function applyFlipTextTranslation(segmentID, node, original, translation) {
    const finalText = preserveWhitespace(original, translation);
    if (!node?.parentNode && !node?.isConnected) {
      return;
    }
    installSegmentSpinnerStyle();
    const wrapper = node.nodeType === Node.ELEMENT_NODE && node.dataset?.llmTranslateIndicatorKind === "flipText"
      ? node
      : createFlipTextIndicator(original, "", "pending");
    wrapper.dataset.llmTranslateFinalText = finalText;
    wrapper.setAttribute("aria-label", finalText);
    wrapper.setAttribute("aria-live", "polite");
    wrapper.setAttribute("contenteditable", "false");
    const blockCount = renderFlipTextBlocks(wrapper, original, finalText, "complete");

    if (wrapper !== node) {
      node.parentNode.insertBefore(wrapper, node);
      node.remove();
    }
    state.nodeByID.set(segmentID, wrapper);
    state.translatedByID.set(segmentID, translation);
    state.spinnerByID.set(segmentID, wrapper);

    setTimeout(() => {
      if (state.spinnerByID.get(segmentID) !== wrapper || !wrapper.isConnected) {
        return;
      }
      const textNode = document.createTextNode(finalText);
      state.processedNodes.add(textNode);
      wrapper.replaceWith(textNode);
      state.nodeByID.set(segmentID, textNode);
      state.spinnerByID.delete(segmentID);
    }, flipSettleDelay(blockCount));
  }

  function createFlipTextIndicator(originalText, finalText, phase) {
    const wrapper = document.createElement("span");
    wrapper.className = "llmtranslate-segment-flip";
    wrapper.dataset.llmTranslateIndicator = "true";
    wrapper.dataset.llmTranslateIndicatorKind = "flipText";
    wrapper.dataset.llmTranslateOriginalText = originalText;
    wrapper.dataset.llmTranslateFinalText = finalText;
    wrapper.dataset.llmTranslateCreatedAt = String(Date.now());
    wrapper.setAttribute("aria-live", "polite");
    wrapper.setAttribute("contenteditable", "false");
    renderFlipTextBlocks(wrapper, originalText, finalText, phase);
    return wrapper;
  }

  function renderFlipTextBlocks(wrapper, originalText, finalText, phase) {
    const originalChunks = splitFlipTextChunks(originalText);
    const finalChunks = phase === "complete" ? splitFlipTextChunks(finalText) : [];
    const blockCount = phase === "complete"
      ? Math.max(originalChunks.length, finalChunks.length, 1)
      : Math.max(originalChunks.length, 1);
    wrapper.classList.toggle("llmtranslate-segment-flip-pending", phase === "pending");
    wrapper.classList.toggle("llmtranslate-segment-flip-complete", phase === "complete");
    wrapper.replaceChildren();
    for (let index = 0; index < blockCount; index += 1) {
      const tile = document.createElement("span");
      tile.className = "llmtranslate-segment-flip-tile";
      tile.style.setProperty("--llmtranslate-delay", `${flipBlockDelay(index, phase)}ms`);

      const front = document.createElement("span");
      front.className = "llmtranslate-segment-flip-face llmtranslate-segment-flip-front";
      front.textContent = originalChunks[index] || "";
      tile.appendChild(front);

      const back = document.createElement("span");
      back.className = "llmtranslate-segment-flip-face llmtranslate-segment-flip-back";
      back.textContent = finalChunks[index] || "";
      tile.appendChild(back);

      wrapper.appendChild(tile);
    }
    return blockCount;
  }

  function splitFlipTextChunks(text) {
    const source = String(text || "");
    if (!source) {
      return [""];
    }
    const chunkSize = source.length > 160 ? 8 : source.length > 80 ? 6 : 4;
    const chunks = [];
    let chunk = "";
    for (const char of Array.from(source)) {
      if (/\s/.test(char)) {
        if (chunk) {
          chunk += char;
          chunks.push(chunk);
          chunk = "";
        } else if (chunks.length) {
          chunks[chunks.length - 1] += char;
        } else {
          chunks.push(char);
        }
        continue;
      }
      chunk += char;
      if (Array.from(chunk).length >= chunkSize) {
        chunks.push(chunk);
        chunk = "";
      }
    }
    if (chunk) {
      chunks.push(chunk);
    }
    return chunks.length ? chunks : [""];
  }

  function flipBlockDelay(index, phase) {
    const step = phase === "complete" ? 42 : 58;
    const maxDelay = phase === "complete" ? 900 : 1100;
    return Math.min(index * step, maxDelay);
  }

  function flipSettleDelay(blockCount) {
    const lastDelay = flipBlockDelay(Math.max(blockCount - 1, 0), "complete");
    return lastDelay + 880;
  }

  function removeSegmentIndicatorElement(element) {
    if (!element?.isConnected) {
      return null;
    }
    if (element.dataset?.llmTranslateIndicatorKind === "flipText") {
      const textNode = document.createTextNode(element.dataset.llmTranslateFinalText || element.textContent || "");
      state.processedNodes.add(textNode);
      element.replaceWith(textNode);
      return textNode;
    }
    element.remove();
    return null;
  }

  function normalizePendingIndicatorStyle(style) {
    if (style === "loading" || style === "flipText" || style === "none") {
      return style;
    }
    return "loading";
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
    const failed = translationState.status === "failed";
    const total = translationState.total || 0;
    const done = translationState.done || 0;
    const failedCount = translationState.failed || 0;
    const progress = total > 0 ? `${done}/${total}${failedCount ? `, ${failedCount} failed` : ""}` : "";
    const message = translationState.message || progress || translationState.status;
    if (active) {
      clearTimeout(state.staleIndicatorCleanupTimer);
      state.staleIndicatorCleanupTimer = null;
    } else if (complete || failed) {
      scheduleStaleIndicatorCleanup();
    }
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
    let handled = false;
    const handleFailure = (error) => {
      if (handled) {
        return;
      }
      handled = true;
      handleRuntimeSendFailure(error);
    };
    try {
      const result = chrome.runtime.sendMessage(message, () => {
        const error = chrome.runtime.lastError;
        if (error) {
          handleFailure(error);
        }
      });
      if (typeof result?.catch === "function") {
        result.catch(handleFailure);
      }
      return result;
    } catch (error) {
      handleFailure(error);
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
