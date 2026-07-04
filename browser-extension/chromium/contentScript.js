(() => {
  if (window.__llmToolsContentLoaded) {
    return;
  }
  window.__llmToolsContentLoaded = true;

  const DEFAULT_APP_LANGUAGE = "zh-Hans";
  const READING_MODE_REPLACE = "replace";
  const READING_MODE_BILINGUAL = "bilingual";
  const READING_MODE_ORIGINAL = "original";
  const DISCOVERY_SCOPE_VISIBLE = "visible";
  const DISCOVERY_SCOPE_PAGE = "page";
  const VISIBLE_DISCOVERY_LIMIT = 200;
  const PAGE_DISCOVERY_LIMIT = 1000;
  const DISCOVERY_DEBOUNCE_MS = 250;
  const DISCOVERY_MAX_WAIT_MS = 1000;
  const CLOSED_SHADOW_SEMANTIC_ROLES = new Set([
    "button",
    "checkbox",
    "combobox",
    "dialog",
    "grid",
    "link",
    "listbox",
    "menu",
    "menuitem",
    "option",
    "radio",
    "region",
    "searchbox",
    "slider",
    "switch",
    "tab",
    "tabpanel",
    "textbox",
    "toolbar",
    "tooltip",
    "tree",
    "treeitem"
  ]);
  const CONTENT_TEXT = {
    "zh-Hans": {
      cancelled: "已取消",
      discoveringText: "正在发现文本...",
      foundSegments: ({ count }) => `找到 ${count} 个片段`,
      appliedTranslations: ({ count }) => `已应用 ${count} 条译文`,
      discoveryPaused: "发现已暂停",
      queuedNewSegments: ({ count }) => `已加入 ${count} 个新片段`,
      failedProgress: ({ failed }) => `，${failed} 个失败`,
      translatingAria: "正在翻译",
      minimize: "最小化",
      cancel: "取消",
      restore: "恢复原文"
    },
    en: {
      cancelled: "Cancelled",
      discoveringText: "Discovering text...",
      foundSegments: ({ count }) => `Found ${count} segments`,
      appliedTranslations: ({ count }) => `Applied ${count} translations`,
      discoveryPaused: "Discovery paused",
      queuedNewSegments: ({ count }) => `Queued ${count} new segments`,
      failedProgress: ({ failed }) => `, ${failed} failed`,
      translatingAria: "Translating",
      minimize: "Minimize",
      cancel: "Cancel",
      restore: "Restore"
    }
  };

  const state = {
    pageSessionID: null,
    appLanguage: DEFAULT_APP_LANGUAGE,
    nodeByID: new Map(),
    originalByID: new Map(),
    translatedByID: new Map(),
    spinnerByID: new Map(),
    processedNodeHashes: new WeakMap(),
    segmentIDByNode: new WeakMap(),
    pendingNodes: new Set(),
    unsupportedEmbeddedContent: emptyUnsupportedEmbeddedContent(),
    cancelled: false,
    discoveryPaused: false,
    overlay: null,
    overlayMinimized: false,
    pendingIndicatorStyle: "loading",
    readingMode: READING_MODE_REPLACE,
    discoveryScope: DISCOVERY_SCOPE_VISIBLE,
    animatedSegmentIDs: new Set(),
    segmentStyleDocuments: new WeakSet(),
    observedMutationRoots: new WeakSet(),
    intersectionObserver: null,
    mutationObserver: null,
    discoveryTimer: null,
    discoveryFirstQueuedAt: null,
    staleIndicatorCleanupTimer: null,
    overlayNoticeHideTimer: null,
    lastURL: location.href,
    routeChangeTimer: null
  };

  function normalizeAppLanguage(language) {
    return language === "en" ? "en" : DEFAULT_APP_LANGUAGE;
  }

  function setAppLanguage(language) {
    state.appLanguage = normalizeAppLanguage(language);
    return state.appLanguage;
  }

  function normalizeReadingMode(mode) {
    if (mode === READING_MODE_BILINGUAL || mode === READING_MODE_ORIGINAL) {
      return mode;
    }
    return READING_MODE_REPLACE;
  }

  function normalizeDiscoveryScope(scope) {
    return scope === DISCOVERY_SCOPE_PAGE ? DISCOVERY_SCOPE_PAGE : DISCOVERY_SCOPE_VISIBLE;
  }

  function discoveryLimitForScope(scope) {
    return normalizeDiscoveryScope(scope) === DISCOVERY_SCOPE_PAGE ? PAGE_DISCOVERY_LIMIT : VISIBLE_DISCOVERY_LIMIT;
  }

  function t(key, values = {}, language = state.appLanguage) {
    const normalizedLanguage = normalizeAppLanguage(language);
    const catalog = CONTENT_TEXT[normalizedLanguage] || CONTENT_TEXT[DEFAULT_APP_LANGUAGE];
    const entry = catalog[key] ?? CONTENT_TEXT.en[key] ?? key;
    return typeof entry === "function" ? entry(values) : entry;
  }

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    Promise.resolve(handleMessage(message)).then(sendResponse).catch((error) => {
      sendResponse({ ok: false, error: error?.message || String(error) });
    });
    return true;
  });

  installRouteChangeWatcher();

  async function handleMessage(message) {
    switch (message?.type) {
      case "ping":
        return { ok: true };
      case "startSession":
        return startSession(message.pageSessionID, message.pendingIndicatorStyle, message);
      case "applyTranslations":
        if (state.cancelled) {
          return { ok: true, applied: state.translatedByID.size, cancelled: true };
        }
        if (message.pageSessionID && message.pageSessionID !== state.pageSessionID) {
          return { ok: false, applied: state.translatedByID.size, reason: "stale_page_session" };
        }
        applyTranslations(message.translations || []);
        return { ok: true, applied: state.translatedByID.size };
      case "setReadingMode":
        setReadingMode(message.mode);
        return getPageTranslationState();
      case "translationState":
        if (message.state?.pageSessionID && message.state.pageSessionID !== state.pageSessionID) {
          return {
            ok: false,
            reason: "stale_page_session",
            pageSessionID: state.pageSessionID
          };
        }
        setAppLanguage(message.state?.appLanguage);
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
        updateOverlay(t("cancelled"));
        return { ok: true };
      case "setDiscoveryPaused":
        setDiscoveryPaused(Boolean(message.paused));
        return { ok: true };
      default:
        return { ok: true };
    }
  }

  function startSession(pageSessionID, pendingIndicatorStyle, options = {}) {
    state.pageSessionID = pageSessionID || crypto.randomUUID();
    setAppLanguage(options.appLanguage);
    state.pendingIndicatorStyle = normalizePendingIndicatorStyle(pendingIndicatorStyle);
    state.readingMode = normalizeReadingMode(options.readingMode);
    state.discoveryScope = normalizeDiscoveryScope(options.discoveryScope);
    state.cancelled = false;
    state.discoveryPaused = false;
    state.overlayMinimized = false;
    state.processedNodeHashes = new WeakMap();
    state.segmentIDByNode = new WeakMap();
    state.pendingNodes.clear();
    state.discoveryFirstQueuedAt = null;
    state.unsupportedEmbeddedContent = emptyUnsupportedEmbeddedContent();
    state.nodeByID.clear();
    state.originalByID.clear();
    state.translatedByID.clear();
    state.observedMutationRoots = new WeakSet();
    state.animatedSegmentIDs.clear();
    clearTimeout(state.staleIndicatorCleanupTimer);
    state.staleIndicatorCleanupTimer = null;
    clearOverlayNoticeHideTimer();
    removeAllSegmentSpinners();
    showOverlay(t("discoveringText"));
    installObservers();
    const segments = discoverSegments(document.body, discoveryLimitForScope(state.discoveryScope), {
      discoveryScope: state.discoveryScope
    });
    state.unsupportedEmbeddedContent = detectUnsupportedEmbeddedContent(document.body);
    updateOverlay(t("foundSegments", { count: segments.length }));
    return {
      ok: true,
      url: location.href,
      title: document.title,
      pageSessionID: state.pageSessionID,
      segments,
      unsupportedEmbeddedContent: state.unsupportedEmbeddedContent
    };
  }

  function getPageTranslationState() {
    state.unsupportedEmbeddedContent = detectUnsupportedEmbeddedContent(document.body);
    return {
      ok: true,
      url: location.href,
      title: document.title,
      pageSessionID: state.pageSessionID,
      trackedCount: state.originalByID.size,
      translatedCount: state.translatedByID.size,
      hasTranslations: state.translatedByID.size > 0,
      readingMode: state.readingMode,
      cancelled: state.cancelled,
      overlayMessage: state.overlay?.message || "",
      unsupportedEmbeddedContent: state.unsupportedEmbeddedContent
    };
  }

  function discoverSegments(root = document.body, limit = discoveryLimitForScope(state.discoveryScope), options = {}) {
    if (!root || state.cancelled || state.discoveryPaused) {
      return [];
    }
    const segments = [];
    const discoveryScope = normalizeDiscoveryScope(options.discoveryScope || state.discoveryScope);
    const requestedLimit = Number.isFinite(Number(limit)) ? Math.max(Number(limit), 0) : Number.POSITIVE_INFINITY;
    const maxSegments = Math.min(requestedLimit, discoveryLimitForScope(discoveryScope));
    for (const segmentRoot of segmentRootsFor(root)) {
      if (segments.length >= maxSegments) {
        break;
      }
      const doc = segmentRoot.ownerDocument || document;
      const walker = doc.createTreeWalker(segmentRoot, NodeFilter.SHOW_TEXT, {
        acceptNode(node) {
          if (!candidateNode(node, { discoveryScope })) return NodeFilter.FILTER_REJECT;
          return NodeFilter.FILTER_ACCEPT;
        }
      });

      const nodes = [];
      let node;
      while ((node = walker.nextNode()) && nodes.length + segments.length < maxSegments) {
        nodes.push(node);
      }

      for (const textNode of nodes) {
        const segment = registerNode(textNode);
        if (segment) {
          segments.push(segment);
        }
      }
    }
    return segments;
  }

  function segmentRootsFor(root) {
    if (!root) {
      return [];
    }
    if (root.nodeType !== Node.ELEMENT_NODE && root.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) {
      return [root].filter(Boolean);
    }
    const roots = [root];
    if (root.nodeType === Node.ELEMENT_NODE && root.tagName === "IFRAME") {
      const body = sameOriginFrameBody(root);
      return body ? [body] : [];
    }
    const frames = root.querySelectorAll?.("iframe") || [];
    for (const frame of frames) {
      const body = sameOriginFrameBody(frame);
      if (body) {
        roots.push(body);
      }
    }
    roots.push(...openShadowRootsFor(root));
    return roots;
  }

  function openShadowRootsFor(root) {
    const roots = [];
    const seen = new WeakSet();
    const visitHost = (host) => {
      const shadowRoot = host?.shadowRoot;
      if (!shadowRoot || seen.has(shadowRoot)) {
        return;
      }
      seen.add(shadowRoot);
      roots.push(shadowRoot);
      for (const nestedHost of shadowRoot.querySelectorAll?.("*") || []) {
        visitHost(nestedHost);
      }
    };
    if (root.nodeType === Node.ELEMENT_NODE) {
      visitHost(root);
    }
    for (const host of root.querySelectorAll?.("*") || []) {
      visitHost(host);
    }
    return roots;
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

  function detectUnsupportedEmbeddedContent(root = document.body) {
    const summary = emptyUnsupportedEmbeddedContent();
    if (!root || root.nodeType !== Node.ELEMENT_NODE) {
      return summary;
    }
    const embedded = [];
    const closedShadowHosts = [];
    for (const searchRoot of [root, ...openShadowRootsFor(root)]) {
      if (isEmbeddedCandidate(searchRoot)) {
        embedded.push(searchRoot);
      }
      embedded.push(...(searchRoot.querySelectorAll?.("iframe, frame, canvas, img, embed, object") || []));
      if (isPotentialClosedShadowHost(searchRoot)) {
        closedShadowHosts.push(searchRoot);
      }
      closedShadowHosts.push(...Array.from(searchRoot.querySelectorAll?.("*") || []).filter(isPotentialClosedShadowHost));
    }
    for (const element of embedded) {
      if (!shouldReportUnsupportedEmbeddedElement(element)) {
        continue;
      }
      switch (element.tagName) {
      case "IFRAME":
      case "FRAME":
        if (!sameOriginFrameBody(element)) {
          summary.frames += 1;
        }
        break;
      case "CANVAS":
        summary.canvas += 1;
        break;
      case "IMG":
        if (hasPotentialImageText(element)) {
          summary.images += 1;
        }
        break;
      case "EMBED":
      case "OBJECT":
        if (isPdfEmbed(element)) {
          summary.pdf += 1;
        }
        break;
      default:
        break;
      }
    }
    summary.shadowRoots = closedShadowHosts.length;
    summary.total = summary.frames + summary.shadowRoots + summary.canvas + summary.images + summary.pdf;
    return summary;
  }

  function isEmbeddedCandidate(element) {
    return ["IFRAME", "FRAME", "CANVAS", "IMG", "EMBED", "OBJECT"].includes(element?.tagName || "");
  }

  function shouldReportUnsupportedEmbeddedElement(element) {
    if (!element || element.dataset?.llmToolsIndicator === "true") {
      return false;
    }
    if (element.getAttribute("aria-hidden") === "true") {
      return false;
    }
    if (!isVisible(element)) {
      return false;
    }
    return state.discoveryScope === DISCOVERY_SCOPE_PAGE || nearViewport(element);
  }

  function isPotentialClosedShadowHost(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) {
      return false;
    }
    const tagName = String(element.localName || element.tagName || "").toLowerCase();
    if (!tagName.includes("-") || element.shadowRoot) {
      return false;
    }
    if (shouldSkipElement(element) || !shouldReportUnsupportedEmbeddedElement(element)) {
      return false;
    }
    const lightDomText = normalizeText(element.textContent || "");
    if (isEnglishDominant(lightDomText)) {
      return false;
    }
    const label = closedShadowAccessibleText(element);
    if (isEnglishDominant(label)) {
      return true;
    }
    return hasClosedShadowComponentSignal(element, lightDomText);
  }

  function closedShadowAccessibleText(element) {
    return [
      element.getAttribute("aria-label") || "",
      element.getAttribute("aria-description") || "",
      element.getAttribute("title") || "",
      textForIDReferences(element, "aria-labelledby"),
      textForIDReferences(element, "aria-describedby")
    ].join(" ");
  }

  function textForIDReferences(element, attributeName) {
    const ownerDocument = element.ownerDocument || document;
    const ids = String(element.getAttribute(attributeName) || "").split(/\s+/).filter(Boolean);
    return ids.map((id) => ownerDocument.getElementById(id)?.textContent || "").join(" ");
  }

  function hasClosedShadowComponentSignal(element, lightDomText) {
    if (lightDomText) {
      return false;
    }
    const role = String(element.getAttribute("role") || "").toLowerCase();
    if (CLOSED_SHADOW_SEMANTIC_ROLES.has(role)) {
      return true;
    }
    if (element.hasAttribute("part") || element.hasAttribute("exportparts")) {
      return true;
    }
    if (element.tabIndex >= 0 && element.getAttribute("aria-disabled") !== "true" && !element.hasAttribute("disabled")) {
      return true;
    }
    return false;
  }

  function hasPotentialImageText(image) {
    const label = [
      image.getAttribute("alt") || "",
      image.getAttribute("title") || "",
      image.getAttribute("aria-label") || ""
    ].join(" ");
    return isEnglishDominant(label);
  }

  function isPdfEmbed(element) {
    const type = String(element.getAttribute("type") || "").toLowerCase();
    const data = String(element.getAttribute("data") || "").toLowerCase();
    const src = String(element.getAttribute("src") || "").toLowerCase();
    return type.includes("pdf") || data.includes(".pdf") || src.includes(".pdf");
  }

  function registerNode(node) {
    const text = normalizeText(node.nodeValue || "");
    const textHash = stableHash(text);
    if (state.processedNodeHashes.get(node) === textHash) {
      return null;
    }
    forgetSegmentForNode(node);
    const segmentID = crypto.randomUUID();
    const original = node.nodeValue;
    const indicator = showSegmentSpinner(segmentID, node);
    setSegmentNode(segmentID, indicator || node, indicator ? indicator.textContent : original);
    state.originalByID.set(segmentID, original);
    markProcessedNode(node, text);
    return {
      segmentID,
      text,
      tagName: node.parentElement?.tagName || "",
      blockContext: closestBlockName(node.parentElement),
      priority: priorityFor(node.parentElement),
      textHash
    };
  }

  function setSegmentNode(segmentID, node, text = "") {
    if (!segmentID || !node) {
      return;
    }
    state.nodeByID.set(segmentID, node);
    state.segmentIDByNode.set(node, segmentID);
    markProcessedNode(node, text || node.nodeValue || node.textContent || "");
  }

  function markProcessedNode(node, text = "") {
    if (!node) {
      return;
    }
    const normalized = normalizeText(text || "");
    if (!normalized) {
      return;
    }
    state.processedNodeHashes.set(node, stableHash(normalized));
  }

  function forgetSegmentForNode(node) {
    const segmentID = state.segmentIDByNode.get(node);
    if (!segmentID) {
      return;
    }
    const mappedNode = state.nodeByID.get(segmentID);
    if (mappedNode) {
      state.segmentIDByNode.delete(mappedNode);
    }
    state.segmentIDByNode.delete(node);
    removeSegmentSpinner(segmentID);
    state.nodeByID.delete(segmentID);
    state.originalByID.delete(segmentID);
    state.translatedByID.delete(segmentID);
    state.animatedSegmentIDs.delete(segmentID);
  }

  function candidateNode(node, options = {}) {
    if (!node.nodeValue || !normalizeText(node.nodeValue)) return false;
    const element = node.parentElement;
    if (!element || shouldSkipElement(element) || !isVisible(element)) return false;
    const text = normalizeText(node.nodeValue);
    if (!isEnglishDominant(text)) return false;
    if (normalizeDiscoveryScope(options.discoveryScope || state.discoveryScope) === DISCOVERY_SCOPE_VISIBLE && !nearViewport(element)) return false;
    return true;
  }

  function applyTranslations(translations) {
    if (state.cancelled) {
      return;
    }
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
      state.translatedByID.set(item.segmentID, item.translation);
      renderSegmentTranslation(item.segmentID, { animate: shouldAnimateTranslation(item.segmentID) });
    }
    updateOverlay(t("appliedTranslations", { count: state.translatedByID.size }), {
      canRestore: state.translatedByID.size > 0
    });
  }

  function setReadingMode(mode) {
    const nextMode = normalizeReadingMode(mode);
    state.readingMode = nextMode;
    for (const segmentID of state.translatedByID.keys()) {
      renderSegmentTranslation(segmentID, { animate: false });
    }
    return nextMode;
  }

  function renderSegmentTranslation(segmentID, options = {}) {
    const original = state.originalByID.get(segmentID);
    const translation = state.translatedByID.get(segmentID);
    if (!original || !translation) {
      removeSegmentSpinner(segmentID);
      return;
    }
    let node = state.nodeByID.get(segmentID);
    if (!node || !node.isConnected) {
      removeSegmentSpinner(segmentID);
      node = state.nodeByID.get(segmentID);
      if (!node || !node.isConnected) {
        return;
      }
    }
    if (state.readingMode !== READING_MODE_REPLACE || !options.animate) {
      removeSegmentSpinner(segmentID);
      node = state.nodeByID.get(segmentID);
      if (!node || !node.isConnected) {
        return;
      }
    }
    switch (state.readingMode) {
    case READING_MODE_ORIGINAL:
      replaceSegmentNodeWithText(segmentID, original);
      break;
    case READING_MODE_BILINGUAL:
      replaceSegmentNodeWithElement(segmentID, createBilingualNode(original, translation, {
        ownerDocument: node.ownerDocument || document,
        styleRoot: styleRootForNode(node),
        tableCell: Boolean(closestTableCell(node.parentElement))
      }));
      break;
    case READING_MODE_REPLACE:
    default:
      if (options.animate) {
        state.animatedSegmentIDs.add(segmentID);
        applyFlipTextTranslation(segmentID, node, original, translation);
      } else {
        replaceSegmentNodeWithText(segmentID, preserveWhitespace(original, translation));
      }
      break;
    }
  }

  function replaceSegmentNodeWithText(segmentID, text) {
    const node = state.nodeByID.get(segmentID);
    if (!node || !node.isConnected) {
      return;
    }
    if (node.nodeType === Node.TEXT_NODE) {
      node.nodeValue = text;
      setSegmentNode(segmentID, node, text);
      return;
    }
    const textNode = (node.ownerDocument || document).createTextNode(text);
    node.replaceWith(textNode);
    setSegmentNode(segmentID, textNode, text);
  }

  function replaceSegmentNodeWithElement(segmentID, element) {
    const node = state.nodeByID.get(segmentID);
    if (!node || !node.isConnected) {
      return;
    }
    state.segmentIDByNode.delete(node);
    setSegmentNode(segmentID, element, element.textContent || "");
    if (node.nodeType === Node.TEXT_NODE) {
      node.parentNode.insertBefore(element, node);
      node.remove();
    } else {
      node.replaceWith(element);
    }
  }

  function createBilingualNode(original, translation, options = {}) {
    const ownerDocument = options.ownerDocument || document;
    installSegmentSpinnerStyle(options.styleRoot || ownerDocument);
    const wrapper = ownerDocument.createElement("span");
    wrapper.className = "llmtools-bilingual";
    wrapper.dataset.llmToolsBilingual = "true";
    wrapper.dataset.llmToolsIndicator = "true";
    if (options.tableCell) {
      wrapper.dataset.llmToolsTableCell = "true";
    }
    wrapper.setAttribute("contenteditable", "false");

    const translated = ownerDocument.createElement("span");
    translated.className = "llmtools-bilingual-translation";
    translated.textContent = preserveWhitespace(original, translation);

    const source = ownerDocument.createElement("span");
    source.className = "llmtools-bilingual-source";
    source.textContent = normalizeText(original);

    wrapper.append(translated, source);
    return wrapper;
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
          node.replaceWith((node.ownerDocument || document).createTextNode(original));
        }
      }
    }
    state.nodeByID.clear();
    state.originalByID.clear();
    state.translatedByID.clear();
    state.animatedSegmentIDs.clear();
    removeAllSegmentSpinners();
    state.processedNodeHashes = new WeakMap();
    state.segmentIDByNode = new WeakMap();
    state.observedMutationRoots = new WeakSet();
    state.pendingNodes.clear();
    state.discoveryFirstQueuedAt = null;
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
        if (mutation.type === "childList" && mutation.target?.nodeType === Node.ELEMENT_NODE) {
          observeElement(mutation.target);
          queueDiscovery(mutation.target);
        }
        if (mutation.type === "characterData" && mutation.target?.parentElement) {
          queueDiscovery(mutation.target.parentElement);
        }
      }
    });

    observeMutationRoot(document.body);
    observeElement(document.body);
    observeSameOriginFrames(document.body);
    observeOpenShadowRoots(document.body);
  }

  function setDiscoveryPaused(paused) {
    state.discoveryPaused = paused;
    if (paused) {
      state.pendingNodes.clear();
      state.discoveryFirstQueuedAt = null;
      clearTimeout(state.discoveryTimer);
      state.discoveryTimer = null;
      updateOverlay(t("discoveryPaused"), {
        canCancel: true,
        canRestore: state.translatedByID.size > 0
      });
      return;
    }
    if (!state.cancelled && state.pageSessionID) {
      queueDiscovery(document.body);
    }
  }

  function observeElement(root) {
    if (!state.intersectionObserver || !root || root.nodeType !== Node.ELEMENT_NODE) {
      return;
    }
    if (root !== document.body && root.ownerDocument === document && !shouldSkipElement(root)) {
      state.intersectionObserver.observe(root);
    }
    if (root.tagName === "IFRAME") {
      observeFrameElement(root, { queue: true });
    }
    const candidates = root.querySelectorAll?.("p, li, td, th, h1, h2, h3, h4, h5, h6, article, section, main, button, a, span, div") || [];
    if (root.ownerDocument === document) {
      for (const element of candidates) {
        if (!shouldSkipElement(element)) {
          state.intersectionObserver.observe(element);
        }
      }
    }
    observeSameOriginFrames(root);
    observeOpenShadowRoots(root, { queue: true });
  }

  function observeVisibleCandidates(root) {
    if (!state.intersectionObserver || !root || root.ownerDocument !== document) {
      return;
    }
    const candidates = root.querySelectorAll?.("p, li, td, th, h1, h2, h3, h4, h5, h6, article, section, main, button, a, span, div") || [];
    for (const element of candidates) {
      if (!shouldSkipElement(element)) {
        state.intersectionObserver.observe(element);
      }
    }
  }

  function observeMutationRoot(root) {
    if (!state.mutationObserver || !root || state.observedMutationRoots.has(root)) {
      return;
    }
    state.mutationObserver.observe(root, {
      childList: true,
      subtree: true,
      characterData: true
    });
    state.observedMutationRoots.add(root);
  }

  function observeOpenShadowRoots(root, options = {}) {
    for (const shadowRoot of openShadowRootsFor(root)) {
      observeMutationRoot(shadowRoot);
      observeVisibleCandidates(shadowRoot);
      observeSameOriginFrames(shadowRoot);
      if (options.queue) {
        queueDiscovery(shadowRoot);
      }
    }
  }

  function observeSameOriginFrames(root) {
    if (!root || (root.nodeType !== Node.ELEMENT_NODE && root.nodeType !== Node.DOCUMENT_FRAGMENT_NODE)) {
      return;
    }
    if (root.nodeType === Node.ELEMENT_NODE && root.tagName === "IFRAME") {
      observeFrameElement(root, { queue: true });
      return;
    }
    const frames = root.querySelectorAll?.("iframe") || [];
    for (const frame of frames) {
      observeFrameElement(frame, { queue: false });
    }
  }

  function observeFrameElement(frame, options = {}) {
    const body = sameOriginFrameBody(frame);
    if (body) {
      observeMutationRoot(body);
      observeVisibleCandidates(frame);
      if (options.queue) {
        queueDiscovery(body);
      }
      return;
    }
    if (!frame.dataset.llmToolsFrameLoadWatch) {
      frame.dataset.llmToolsFrameLoadWatch = "true";
      frame.addEventListener("load", () => {
        const loadedBody = sameOriginFrameBody(frame);
        if (!loadedBody) {
          return;
        }
        observeMutationRoot(loadedBody);
        observeVisibleCandidates(frame);
        queueDiscovery(loadedBody);
      }, { once: false });
    }
  }

  function sameOriginFrameBody(frame) {
    try {
      const doc = frame?.contentDocument;
      return doc?.body || null;
    } catch {
      return null;
    }
  }

  function queueDiscovery(root) {
    if (!state.pageSessionID || state.cancelled || state.discoveryPaused || !root) {
      return;
    }
    state.pendingNodes.add(root);
    if (!state.discoveryFirstQueuedAt) {
      state.discoveryFirstQueuedAt = Date.now();
    }
    const elapsed = Date.now() - state.discoveryFirstQueuedAt;
    const delay = Math.max(0, Math.min(DISCOVERY_DEBOUNCE_MS, DISCOVERY_MAX_WAIT_MS - elapsed));
    clearTimeout(state.discoveryTimer);
    state.discoveryTimer = setTimeout(flushPendingDiscovery, delay);
  }

  function flushPendingDiscovery() {
    if (!state.pageSessionID || state.cancelled || state.discoveryPaused) {
      return;
    }
    const pending = Array.from(state.pendingNodes);
    state.pendingNodes.clear();
    state.discoveryFirstQueuedAt = null;
    const segments = [];
    for (const root of pending) {
      if (!root.isConnected) continue;
      if (root.nodeType === Node.TEXT_NODE && root.parentElement) {
        const segment = candidateNode(root, { discoveryScope: state.discoveryScope }) ? registerNode(root) : null;
        if (segment) segments.push(segment);
      } else if (root.nodeType === Node.ELEMENT_NODE) {
        observeSameOriginFrames(root);
        segments.push(...discoverSegments(root, discoveryLimitForScope(state.discoveryScope), {
          discoveryScope: state.discoveryScope
        }));
      }
    }
    if (segments.length) {
      updateOverlay(t("queuedNewSegments", { count: segments.length }), {
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
    state.discoveryFirstQueuedAt = null;
    clearTimeout(state.staleIndicatorCleanupTimer);
    state.staleIndicatorCleanupTimer = null;
    clearOverlayNoticeHideTimer();
  }

  function installRouteChangeWatcher() {
    if (window.__llmToolsRouteWatcherInstalled) {
      return;
    }
    window.__llmToolsRouteWatcherInstalled = true;
    const notifyRouteMaybeChanged = () => {
      clearTimeout(state.routeChangeTimer);
      state.routeChangeTimer = setTimeout(handleRouteMaybeChanged, 80);
    };
    for (const methodName of ["pushState", "replaceState"]) {
      const original = history[methodName];
      if (typeof original !== "function") {
        continue;
      }
      history[methodName] = function llmToolsHistoryWrapper(...args) {
        const result = original.apply(this, args);
        notifyRouteMaybeChanged();
        return result;
      };
    }
    window.addEventListener("popstate", notifyRouteMaybeChanged);
    window.addEventListener("hashchange", notifyRouteMaybeChanged);
  }

  function handleRouteMaybeChanged() {
    if (location.href === state.lastURL) {
      return;
    }
    const previousURL = state.lastURL;
    const pageSessionID = state.pageSessionID;
    state.lastURL = location.href;
    if (state.originalByID.size || state.translatedByID.size || state.spinnerByID.size || state.overlay) {
      restoreOriginal();
    } else {
      state.cancelled = true;
      disconnectObservers();
      state.pendingNodes.clear();
      state.discoveryFirstQueuedAt = null;
      state.pageSessionID = null;
    }
    safeRuntimeSendMessage({
      type: "llmToolsRouteChanged",
      previousURL,
      url: location.href,
      title: document.title,
      pageSessionID
    });
  }

  function shouldSkipElement(element) {
    const skipped = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "SVG", "CANVAS", "CODE", "PRE", "KBD", "SAMP", "TEXTAREA", "INPUT", "SELECT", "OPTION"]);
    for (let current = element; current && current !== document.body; current = current.parentElement) {
      if (skipped.has(current.tagName)) return true;
      if (current.dataset?.llmToolsSpinner === "true") return true;
      if (current.dataset?.llmToolsIndicator === "true") return true;
      if (current.isContentEditable) return true;
      if (current.getAttribute("aria-hidden") === "true") return true;
    }
    return false;
  }

  function isVisible(element) {
    const view = element.ownerDocument?.defaultView || window;
    const style = view.getComputedStyle(element);
    if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
    return element.getClientRects().length > 0;
  }

  function nearViewport(element) {
    const view = element.ownerDocument?.defaultView || window;
    const margin = Math.max(view.innerHeight, 800);
    const rect = element.getBoundingClientRect();
    return rect.bottom >= -margin && rect.top <= view.innerHeight + margin;
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
      const ownerDocument = node.ownerDocument || document;
      installSegmentSpinnerStyle(styleRootForNode(node));
      const indicator = createFlipTextIndicator(node.nodeValue || "", "", "pending", ownerDocument);
      node.parentNode.insertBefore(indicator, node);
      node.remove();
      state.spinnerByID.set(segmentID, indicator);
      state.animatedSegmentIDs.add(segmentID);
      return indicator;
    }
    const ownerDocument = node.ownerDocument || document;
    installSegmentSpinnerStyle(styleRootForNode(node));
    const spinner = ownerDocument.createElement("span");
    spinner.className = "llmtools-segment-spinner";
    spinner.dataset.llmToolsSpinner = "true";
    spinner.dataset.llmToolsIndicator = "true";
    spinner.dataset.llmToolsIndicatorKind = "loading";
    spinner.dataset.llmToolsCreatedAt = String(Date.now());
    spinner.setAttribute("aria-label", t("translatingAria"));
    spinner.setAttribute("aria-live", "polite");
    spinner.setAttribute("contenteditable", "false");
    spinner.style.cssText = segmentSpinnerStyle();
    node.parentNode.insertBefore(spinner, node.nextSibling);
    state.spinnerByID.set(segmentID, spinner);
    return null;
  }

  function effectivePendingIndicatorStyle() {
    return state.pendingIndicatorStyle;
  }

  function shouldAnimateTranslation(segmentID) {
    return state.pendingIndicatorStyle === "flipText" && state.readingMode === READING_MODE_REPLACE;
  }

  function removeSegmentSpinner(segmentID) {
    if (!segmentID) {
      return;
    }
    const spinner = state.spinnerByID.get(segmentID);
    if (spinner) {
      const replacement = removeSegmentIndicatorElement(spinner);
      if (replacement) {
        setSegmentNode(segmentID, replacement, replacement.nodeValue || replacement.textContent || "");
      }
      state.spinnerByID.delete(segmentID);
    }
  }

  function removeAllSegmentSpinners() {
    for (const [segmentID, spinner] of state.spinnerByID.entries()) {
      const replacement = removeSegmentIndicatorElement(spinner);
      if (replacement) {
        setSegmentNode(segmentID, replacement, replacement.nodeValue || replacement.textContent || "");
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
      const createdAt = Number(indicator?.dataset?.llmToolsCreatedAt || 0);
      if (!indicator?.isConnected || createdAt > createdBefore) {
        continue;
      }
      const replacement = removeSegmentIndicatorElement(indicator);
      if (replacement) {
        setSegmentNode(segmentID, replacement, replacement.nodeValue || replacement.textContent || "");
      }
      state.spinnerByID.delete(segmentID);
    }
  }

  function styleRootForNode(node) {
    const root = node?.getRootNode?.();
    if (root?.nodeType === Node.DOCUMENT_FRAGMENT_NODE && root.host) {
      return root;
    }
    return node?.ownerDocument || document;
  }

  function installSegmentSpinnerStyle(styleRoot = document) {
    if (state.segmentStyleDocuments.has(styleRoot)) {
      return;
    }
    const ownerDocument = styleRoot.nodeType === Node.DOCUMENT_NODE ? styleRoot : (styleRoot.ownerDocument || document);
    const style = ownerDocument.createElement("style");
    style.dataset.llmToolsSpinnerStyle = "true";
    style.textContent = `
      @keyframes llmtools-segment-spin {
        to { transform: rotate(360deg); }
      }
      .llmtools-segment-flip {
        display: inline;
        perspective: 700px;
        transform-style: preserve-3d;
        pointer-events: none;
        user-select: none;
      }
      .llmtools-bilingual {
        display: inline;
      }
      .llmtools-bilingual[data-llm-tools-table-cell="true"] {
        display: block;
        line-height: 1.25;
      }
      .llmtools-bilingual-source {
        margin-left: .35em;
        color: #6b7280;
        font-size: .92em;
        text-decoration: none;
      }
      .llmtools-bilingual[data-llm-tools-table-cell="true"] .llmtools-bilingual-source {
        display: block;
        margin-left: 0;
        margin-top: .12em;
        font-size: .86em;
        line-height: 1.2;
      }
      .llmtools-bilingual-source::before {
        content: "(";
      }
      .llmtools-bilingual-source::after {
        content: ")";
      }
      .llmtools-segment-flip-tile {
        display: inline-grid;
        grid-template-areas: "llmtools-flip-stack";
        transform-origin: 50% 55%;
        transform-style: preserve-3d;
        vertical-align: baseline;
        will-change: transform;
      }
      .llmtools-segment-flip-face {
        display: inline-block;
        grid-area: llmtools-flip-stack;
        white-space: pre-wrap;
      }
      .llmtools-segment-flip-pending .llmtools-segment-flip-tile {
        animation: llmtools-segment-sway 1.35s ease-in-out infinite;
        animation-delay: var(--llmtools-delay, 0ms);
      }
      .llmtools-segment-flip-pending .llmtools-segment-flip-back {
        display: none;
      }
      .llmtools-segment-flip-complete .llmtools-segment-flip-tile {
        animation: llmtools-segment-complete-flip .78s cubic-bezier(.22,.9,.18,1) forwards;
        animation-delay: var(--llmtools-delay, 0ms);
      }
      .llmtools-segment-flip-complete .llmtools-segment-flip-front {
        animation: llmtools-segment-front-out .78s linear forwards;
        animation-delay: var(--llmtools-delay, 0ms);
      }
      .llmtools-segment-flip-complete .llmtools-segment-flip-back {
        color: #2563eb;
        opacity: 0;
        animation: llmtools-segment-back-in .78s linear forwards;
        animation-delay: var(--llmtools-delay, 0ms);
      }
      @keyframes llmtools-segment-sway {
        0%, 100% { transform: rotateX(0deg); }
        24% { transform: rotateX(-18deg); }
        54% { transform: rotateX(16deg); }
        76% { transform: rotateX(-6deg); }
      }
      @keyframes llmtools-segment-complete-flip {
        0% { transform: rotateX(0deg); }
        48% { transform: rotateX(172deg); }
        52% { transform: rotateX(188deg); }
        100% { transform: rotateX(360deg); }
      }
      @keyframes llmtools-segment-front-out {
        0%, 48% { opacity: 1; }
        49%, 100% { opacity: 0; }
      }
      @keyframes llmtools-segment-back-in {
        0%, 48% { opacity: 0; color: #2563eb; }
        49%, 100% { opacity: 1; color: inherit; }
      }
      @media (prefers-reduced-motion: reduce) {
        .llmtools-segment-flip-tile,
        .llmtools-segment-flip-face {
          animation: none !important;
          transform: none !important;
        }
        .llmtools-segment-flip-complete .llmtools-segment-flip-front {
          display: none;
        }
        .llmtools-segment-flip-complete .llmtools-segment-flip-back {
          opacity: 1;
          color: inherit;
        }
      }
    `;
    const target = styleRoot.nodeType === Node.DOCUMENT_FRAGMENT_NODE ? styleRoot : ownerDocument.documentElement;
    target.appendChild(style);
    state.segmentStyleDocuments.add(styleRoot);
  }

  function applyFlipTextTranslation(segmentID, node, original, translation) {
    const finalText = preserveWhitespace(original, translation);
    if (!node?.parentNode && !node?.isConnected) {
      return;
    }
    const ownerDocument = node.ownerDocument || document;
    installSegmentSpinnerStyle(styleRootForNode(node));
    const wrapper = node.nodeType === Node.ELEMENT_NODE && node.dataset?.llmToolsIndicatorKind === "flipText"
      ? node
      : createFlipTextIndicator(original, "", "pending", ownerDocument);
    wrapper.dataset.llmToolsFinalText = finalText;
    wrapper.setAttribute("aria-label", finalText);
    wrapper.setAttribute("aria-live", "polite");
    wrapper.setAttribute("contenteditable", "false");
    const blockCount = renderFlipTextBlocks(wrapper, original, finalText, "complete");

    if (wrapper !== node) {
      state.segmentIDByNode.delete(node);
      node.parentNode.insertBefore(wrapper, node);
      node.remove();
    }
    setSegmentNode(segmentID, wrapper, wrapper.textContent || original);
    state.translatedByID.set(segmentID, translation);
    state.spinnerByID.set(segmentID, wrapper);

    setTimeout(() => {
      if (state.spinnerByID.get(segmentID) !== wrapper || !wrapper.isConnected) {
        return;
      }
      const textNode = (wrapper.ownerDocument || document).createTextNode(finalText);
      wrapper.replaceWith(textNode);
      state.segmentIDByNode.delete(wrapper);
      setSegmentNode(segmentID, textNode, finalText);
      state.spinnerByID.delete(segmentID);
    }, flipSettleDelay(blockCount));
  }

  function createFlipTextIndicator(originalText, finalText, phase, ownerDocument = document) {
    const wrapper = ownerDocument.createElement("span");
    wrapper.className = "llmtools-segment-flip";
    wrapper.dataset.llmToolsIndicator = "true";
    wrapper.dataset.llmToolsIndicatorKind = "flipText";
    wrapper.dataset.llmToolsOriginalText = originalText;
    wrapper.dataset.llmToolsFinalText = finalText;
    wrapper.dataset.llmToolsCreatedAt = String(Date.now());
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
    wrapper.classList.toggle("llmtools-segment-flip-pending", phase === "pending");
    wrapper.classList.toggle("llmtools-segment-flip-complete", phase === "complete");
    wrapper.replaceChildren();
    for (let index = 0; index < blockCount; index += 1) {
      const ownerDocument = wrapper.ownerDocument || document;
      const tile = ownerDocument.createElement("span");
      tile.className = "llmtools-segment-flip-tile";
      tile.style.setProperty("--llmtools-delay", `${flipBlockDelay(index, phase)}ms`);

      const front = ownerDocument.createElement("span");
      front.className = "llmtools-segment-flip-face llmtools-segment-flip-front";
      front.textContent = originalChunks[index] || "";
      tile.appendChild(front);

      const back = ownerDocument.createElement("span");
      back.className = "llmtools-segment-flip-face llmtools-segment-flip-back";
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
    if (element.dataset?.llmToolsIndicatorKind === "flipText") {
      const textNode = (element.ownerDocument || document).createTextNode(element.dataset.llmToolsFinalText || element.textContent || "");
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
      "animation:llmtools-segment-spin .8s linear infinite",
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

  function closestTableCell(element) {
    for (let current = element; current && current.nodeType === Node.ELEMENT_NODE; current = current.parentElement) {
      if (current.tagName === "TD" || current.tagName === "TH") {
        return current;
      }
      if (current.tagName === "TABLE" || current === current.ownerDocument?.body) {
        return null;
      }
    }
    return null;
  }

  function priorityFor(element) {
    const tag = element?.tagName || "";
    if (/^H[1-3]$/.test(tag)) return 20;
    if (tag === "TH" || tag === "TD") return 12;
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
    if (translationState.readingMode) {
      setReadingMode(translationState.readingMode);
    }
    const notice = Boolean(translationState.notice);
    if (!notice && !translationState.hasTranslations && state.translatedByID.size === 0 && (translationState.status === "idle" || translationState.status === "restored")) {
      hideOverlay();
      return;
    }
    const active = translationState.status === "discovering" || translationState.status === "translating";
    const complete = translationState.status === "translated" || translationState.status === "partiallyTranslated";
    const failed = translationState.status === "failed";
    const total = translationState.total || 0;
    const done = translationState.done || 0;
    const failedCount = translationState.failed || 0;
    const progress = total > 0 ? `${done}/${total}${failedCount ? t("failedProgress", { failed: failedCount }) : ""}` : "";
    const message = translationState.message || progress || translationState.status;
    if (active) {
      clearTimeout(state.staleIndicatorCleanupTimer);
      state.staleIndicatorCleanupTimer = null;
      clearOverlayNoticeHideTimer();
    } else if (complete || failed) {
      scheduleStaleIndicatorCleanup();
    }
    updateOverlay(message, {
      progress,
      canCancel: active,
      canRestore: Boolean(translationState.hasTranslations) || complete || state.translatedByID.size > 0
    });
    if (notice && !active && !complete) {
      scheduleOverlayNoticeHide();
    }
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
      title.textContent = "llmTools";
      title.style.cssText = "font-weight:650;";
      const detail = document.createElement("div");
      detail.style.cssText = "color:rgba(255,255,255,.78);";
      text.append(title, detail);
      const minimize = document.createElement("button");
      minimize.type = "button";
      minimize.textContent = "-";
      minimize.title = t("minimize");
      minimize.style.cssText = overlayButtonStyle();
      header.append(text, minimize);
      const actions = document.createElement("div");
      actions.style.cssText = "display:flex;gap:6px;margin-top:8px;";
      const cancel = document.createElement("button");
      cancel.type = "button";
      cancel.textContent = t("cancel");
      cancel.style.cssText = overlayButtonStyle();
      const restore = document.createElement("button");
      restore.type = "button";
      restore.textContent = t("restore");
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
      ? `llmTools${state.overlay.progress ? ` ${state.overlay.progress}` : ""}`
      : "llmTools";
    state.overlay.actions.style.display = state.overlayMinimized ? "none" : "flex";
    state.overlay.minimize.title = t("minimize");
    state.overlay.cancel.textContent = t("cancel");
    state.overlay.restore.textContent = t("restore");
    state.overlay.cancel.style.display = state.overlay.canCancel ? "" : "none";
    state.overlay.restore.style.display = state.overlay.canRestore ? "" : "none";
    state.overlay.minimize.textContent = state.overlayMinimized ? "+" : "-";
  }

  function hideOverlay() {
    clearOverlayNoticeHideTimer();
    if (state.overlay) {
      state.overlay.host.remove();
      state.overlay = null;
    }
  }

  function scheduleOverlayNoticeHide() {
    clearOverlayNoticeHideTimer();
    state.overlayNoticeHideTimer = setTimeout(() => {
      if (state.translatedByID.size === 0) {
        hideOverlay();
      }
    }, 4000);
  }

  function clearOverlayNoticeHideTimer() {
    clearTimeout(state.overlayNoticeHideTimer);
    state.overlayNoticeHideTimer = null;
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
