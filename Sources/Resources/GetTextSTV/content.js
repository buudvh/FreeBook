(function () {
  const PANEL_ID = "gettext-stv-panel";
  const AUTO_KEY = "gettextStvAuto";
  const AUTO_CHAPTER_PREFIX = "gettextStvChapter:";
  const SETTINGS_KEY = "gettextStvSettings";
  const HISTORY_KEY = "gettextStvHistory";
  const AUTO_LOG_KEY = "gettextStvAutoLog";
  const MIN_CHAPTER_CHARS = 20;
  const AUTO_WAIT_MS = 60000;
  const DEFAULT_NEXT_DELAY_MS = 1500;
  const TXT_EOL = "\r\n";
  let autoLoopStarted = false;
  let autoStopRequested = false;
  let panelLocalToc = null;
  let panelBookTitle = "";

  function cleanSpaces(value) {
    return (value || "")
      .replace(/\u00a0/g, " ")
      .replace(/[ \t]+\n/g, "\n")
      .replace(/\n[ \t]+/g, "\n")
      .replace(/\n{3,}/g, "\n\n")
      .trim();
  }

  function textOf(selector) {
    const node = document.querySelector(selector);
    return node ? cleanSpaces(node.textContent) : "";
  }

  function getChapterInfo() {
    const hiddenText = textOf("#hiddenid");
    const hidden = hiddenText ? hiddenText.split(";") : [];
    
    let bookId = hidden[0] || "";
    let chapterId = hidden[1] || "";
    let host = hidden[2] || "";

    const match = location.pathname.match(/\/truyen\/([^\/]+)\/[^\/]+\/([^\/]+)(?:\/([^\/]+))?/);
    if (match) {
      if (!host) host = match[1];
      if (!bookId) bookId = match[2];
      if (!chapterId && match[3]) chapterId = match[3];
    }

    const bookTitle =
      textOf("#booknameholder") ||
      textOf("#book_name2") ||
      document.querySelector('meta[property="og:novel:book_name"]')?.content ||
      document.querySelector('meta[property="og:title"]')?.content ||
      document.title;
    const author =
      textOf("#authornameholder") ||
      textOf("#author_name") ||
      document.querySelector('meta[property="og:novel:author"]')?.content ||
      "Sáng Tác Việt";

    const coverUrl =
      document.querySelector("#bookcover img")?.src ||
      document.querySelector('meta[property="og:image"]')?.content ||
      "";

    const desc =
      textOf("#bookdescription") ||
      textOf(".bookdescription") ||
      document.querySelector('meta[property="og:description"]')?.content ||
      "";

    const chapterTitle = textOf("#bookchapnameholder") || "";

    const rawBookId = (bookId || "").replace(/^stv_[^_]+_/, "").replace(/^stv_/, "");
    const canonicalBookId = (host && rawBookId) ? `stv_${host}_${rawBookId}` : (rawBookId ? `stv_novel_${rawBookId}` : "");

    return {
      rawBookId: rawBookId,
      bookId: canonicalBookId,
      chapterId: chapterId,
      host: host,
      bookTitle: bookTitle.replace(/^_$/, ""),
      chapterTitle: chapterTitle.replace(/^_$/, ""),
      author: author,
      coverUrl: coverUrl,
      desc: desc,
      url: location.href
    };
  }

  function getReadableTextFromNode(node) {
    if (!node) return "";

    const clone = node.cloneNode(true);
    clone.querySelectorAll("script, style, noscript, button, iframe, .spinner-border").forEach((item) => item.remove());
    clone.querySelectorAll("[hidden], [aria-hidden='true']").forEach((item) => item.remove());

    clone.querySelectorAll("br").forEach((br) => br.replaceWith("\n"));
    clone.querySelectorAll("p, div, center, h1, h2, h3, h4, li").forEach((block) => {
      block.appendChild(document.createTextNode("\n"));
    });

    return cleanSpaces(clone.textContent);
  }

  function getOriginalTextFromNode(node) {
    if (!node) return "";

    const parts = [];
    const blockTags = new Set(["P", "DIV", "CENTER", "H1", "H2", "H3", "H4", "LI"]);

    function isIgnoredSpan(element) {
      if (element.tagName !== "SPAN") return false;
      const text = cleanSpaces(element.textContent);
      const title = cleanSpaces(element.getAttribute("title") || "");

      return (
        text === "@Bạn đang đọc bản lưu trong hệ thống" ||
        (/^ID:\s*\d+$/i.test(title) && /^Người mua:/i.test(text)) ||
        (/^ID:\s*\d+$/i.test(title) && /^Nguoi mua:/i.test(text))
      );
    }

    function appendBreak() {
      const last = parts[parts.length - 1] || "";
      if (!last.endsWith("\n")) parts.push("\n");
    }

    function walk(current) {
      if (!current) return;

      if (current.nodeType === Node.TEXT_NODE) {
        const text = (current.textContent || "").replace(/[\s\u00a0]+/g, "");
        if (text) parts.push(text);
        return;
      }

      if (current.nodeType === Node.ELEMENT_NODE) {
        const element = current;
        const tagName = element.tagName;

        if (tagName === "SCRIPT" || tagName === "STYLE" || tagName === "NOSCRIPT" || tagName === "IFRAME") {
          return;
        }

        if (element.hidden || element.getAttribute("aria-hidden") === "true") {
          return;
        }

        if (isIgnoredSpan(element)) {
          return;
        }

        if (tagName === "BR") {
          appendBreak();
          return;
        }

        if (tagName === "I" && element.hasAttribute("t")) {
          const text = cleanSpaces(element.getAttribute("t") || "");
          if (text) parts.push(text);
          return;
        }

        Array.from(element.childNodes).forEach(walk);
        if (blockTags.has(tagName)) appendBreak();
      }
    }

    walk(node);
    return cleanSpaces(parts.join(""));
  }

  function indentBody(body) {
    return cleanSpaces(body)
      .split("\n")
      .map((line) => (line ? `    ${line}` : ""))
      .join(TXT_EOL);
  }

  function formatChapterTitle(chapter, toc) {
    let oriTitle = "";
    if (Array.isArray(toc) && toc.length > 0) {
      const found = toc.find(item => String(item.chapterId) === String(chapter.chapterId));
      if (found && found.originalTitle) {
        oriTitle = found.originalTitle;
      }
    }
    if (!oriTitle) {
      oriTitle = chapter.originalTitle;
    }
    if (oriTitle) {
      return cleanSpaces(oriTitle);
    }

    const rawTitle = cleanSpaces(chapter.rawChapterTitle || chapter.chapterTitle || "");
    const chapterNumber = rawTitle.match(/\d+/)?.[0] || cleanSpaces(chapter.chapterId || "");
    const titleText = rawTitle
      .replace(/^\s*thứ\s*\d+\s*chương\s*[:：\-.\s]*/i, "")
      .replace(/^\s*chương\s*\d+\s*[:：\-.\s]*/i, "")
      .replace(/^\s*\u7b2c\s*\d+\s*\u7ae0\s*[:：\-.\s]*/i, "")
      .trim();

    if (!chapterNumber) return titleText || "\u7b2c\u7ae0";
    return titleText ? `\u7b2c${chapterNumber}\u7ae0 ${titleText}` : `\u7b2c${chapterNumber}\u7ae0`;
  }

  function formatChapterText(chapter, toc) {
    const title = formatChapterTitle(chapter, toc);
    return ` ${title}${TXT_EOL}${TXT_EOL}${indentBody(chapter.body)}`.trimEnd();
  }

  function formatNovelText(chapters, bookTitle, toc) {
    return (chapters || []).map(c => formatChapterText(c, toc)).filter(Boolean).join(`${TXT_EOL}${TXT_EOL}`).trimEnd();
  }

  function extractChapter() {
    const info = getChapterInfo();
    const contentNode =
      document.querySelector("#maincontent") ||
      document.querySelector("#content-container .contentbox") ||
      document.querySelector(".contentbox");

    const originalNodeCount = contentNode ? contentNode.querySelectorAll("i[t]").length : 0;
    let body = getOriginalTextFromNode(contentNode);
    if (!body && originalNodeCount === 0) {
      body = "";
    }
    body = cleanSpaces(body);

    const chapter = {
      ...info,
      rawChapterTitle: info.chapterTitle,
      body,
      charCount: body.length,
      originalNodeCount,
      isChapterPage: Boolean(document.querySelector("#hiddenid") && contentNode),
      isReady: originalNodeCount > 0 && body.length >= MIN_CHAPTER_CHARS
    };
    chapter.text = formatChapterText(chapter);
    return chapter;
  }

  function safeFileName(value) {
    const fallback = "sangtacviet-chapter";
    return (value || fallback)
      .replace(/[<>:"/\\|?*\x00-\x1F]/g, "")
      .replace(/\s+/g, " ")
      .trim()
      .replace(/[. ]+$/g, "")
      .slice(0, 160) || fallback;
  }

  function getTimestampSuffix() {
    const d = new Date();
    const yyyy = d.getFullYear();
    const MM = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const hh = String(d.getHours()).padStart(2, '0');
    const mi = String(d.getMinutes()).padStart(2, '0');
    const ss = String(d.getSeconds()).padStart(2, '0');
    return `_${yyyy}${MM}${dd}${hh}${mi}${ss}`;
  }

  async function copyText(text) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return;
    }

    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.left = "-9999px";
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy");
    textarea.remove();
  }

  async function downloadText(chapter) {
    let toc = [];
    try {
      const origin = window.location.origin;
      const fetchUrl = `${origin}/index.php?ngmar=chapterlist&h=${chapter.host}&bookid=${chapter.bookId}&sajax=getchapterlist`;
      const response = await fetch(fetchUrl);
      const rawText = await response.text();
      const settings = await getSettings().catch(() => ({}));
      const removeText = settings.removeText || "求月票__求個月票__求首訂__求关注__求追读__求订阅__月票加更__〔__{__(__（";
      toc = parseStvToc(rawText, chapter.host, chapter.bookId, removeText);
    } catch (e) {
      console.error("Failed to fetch TOC for single download:", e);
    }

    const chapterCopy = { ...chapter };
    if (Array.isArray(toc) && toc.length > 0) {
      const found = toc.find(item => String(item.chapterId) === String(chapter.chapterId));
      if (found && found.originalTitle) {
        chapterCopy.originalTitle = found.originalTitle;
      }
    }

    const formattedTitle = formatChapterTitle(chapterCopy, toc);
    const title = [chapterCopy.bookTitle, formattedTitle].filter(Boolean).join(" - ");
    
    // Gửi trực tiếp về Swift FreeBook thay vì tải file TXT qua Blob
    if (typeof sendFreeBookPayload === "function") {
      sendFreeBookPayload("saveChapterContent", {
        chapterIndex: chapterCopy.index || 0,
        chapterTitle: formattedTitle,
        chapterUrl: chapterCopy.url || location.href,
        content: formatNovelText([chapterCopy], chapterCopy.bookTitle, toc)
      });
    }
  }

  async function downloadAutoText(state) {
    const chapters = await getStoredChapters(state);
    const title = state?.bookTitle || chapters[0]?.bookTitle || "sangtacviet-novel";
    if (chapters.length) await addDownloadHistory(state, chapters);
    
    // Gửi thông báo hoàn tất về Swift FreeBook để thêm vào Kệ Sách và mở BookDetailView
    if (typeof sendFreeBookPayload === "function") {
      sendFreeBookPayload("finishDownload", {
        bookTitle: title,
        chapterCount: chapters.length
      });
    }
  }

  function storageGet() {
    return new Promise((resolve, reject) => {
      chrome.storage.local.get(AUTO_KEY, (items) => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        resolve(items[AUTO_KEY] || null);
      });
    });
  }

  function storageSet(state) {
    return new Promise((resolve, reject) => {
      chrome.storage.local.set({ [AUTO_KEY]: state }, () => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        resolve();
      });
    });
  }

  function storageRemove() {
    return new Promise((resolve, reject) => {
      chrome.storage.local.remove(AUTO_KEY, () => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        resolve();
      });
    });
  }

  function createSessionId() {
    return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }

  function getChapterStorageKey(sessionId, index) {
    return `${AUTO_CHAPTER_PREFIX}${sessionId}:${String(index).padStart(6, "0")}`;
  }

  function getChapterCount(state) {
    return state?.chapterCount || state?.chapterRefs?.length || state?.chapters?.length || 0;
  }

  function storageGetMany(keys) {
    return new Promise((resolve, reject) => {
      chrome.storage.local.get(keys, (items) => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        resolve(items);
      });
    });
  }

  function storageGetKey(key) {
    return new Promise((resolve, reject) => {
      chrome.storage.local.get(key, (items) => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        resolve(items[key]);
      });
    });
  }

  function storageSetKey(key, value) {
    return new Promise((resolve, reject) => {
      chrome.storage.local.set({ [key]: value }, () => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        resolve();
      });
    });
  }

  async function appendAutoLog(label, details = {}) {
    const entry = {
      time: new Date().toISOString(),
      label,
      details
    };
    const logs = await storageGetKey(AUTO_LOG_KEY).catch(() => []);
    const nextLogs = Array.isArray(logs) ? logs : [];
    nextLogs.push(entry);
    await storageSetKey(AUTO_LOG_KEY, nextLogs.slice(-200)).catch(() => {});
  }

  async function getAutoLogs() {
    const logs = await storageGetKey(AUTO_LOG_KEY).catch(() => []);
    return Array.isArray(logs) ? logs : [];
  }

  async function clearAutoLogs() {
    await storageSetKey(AUTO_LOG_KEY, []);
  }

  function storageSetMany(items) {
    return new Promise((resolve, reject) => {
      chrome.storage.local.set(items, () => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        resolve();
      });
    });
  }

  function storageRemoveMany(keys) {
    return new Promise((resolve, reject) => {
      chrome.storage.local.remove(keys, () => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        resolve();
      });
    });
  }

  function getSettings() {
    return new Promise((resolve, reject) => {
      chrome.storage.local.get(SETTINGS_KEY, (items) => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        resolve(items[SETTINGS_KEY] || {});
      });
    });
  }

  function setSettings(settings) {
    return new Promise((resolve, reject) => {
      chrome.storage.local.set({ [SETTINGS_KEY]: settings }, () => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        resolve();
      });
    });
  }

  async function getNextDelayMs() {
    const settings = await getSettings().catch(() => ({}));
    const delayMs = Number(settings.nextDelayMs);
    if (!Number.isFinite(delayMs)) return DEFAULT_NEXT_DELAY_MS;
    return Math.max(0, Math.min(delayMs, 120000));
  }

  async function setNextDelayMs(delayMs) {
    const settings = await getSettings().catch(() => ({}));
    settings.nextDelayMs = Math.max(0, Math.min(Number(delayMs) || 0, 120000));
    await setSettings(settings);
    return settings;
  }

  async function getEndUrlSetting() {
    const settings = await getSettings().catch(() => ({}));
    return normalizeUrl(settings.endUrl || "");
  }

  async function setEndUrlSetting(endUrl) {
    const settings = await getSettings().catch(() => ({}));
    settings.endUrl = normalizeUrl(endUrl || "");
    await setSettings(settings);
    return settings.endUrl;
  }

  async function clearEndUrlSetting(reason) {
    await setEndUrlSetting("");
    const input = document.querySelector("[data-stv-end-url]");
    if (input) input.value = "";
    await appendAutoLog("end-url-cleared", { reason });
  }

  async function getPanelPosition() {
    const settings = await getSettings().catch(() => ({}));
    return settings.panelPosition || null;
  }

  async function setPanelPosition(position) {
    const settings = await getSettings().catch(() => ({}));
    settings.panelPosition = position;
    await setSettings(settings);
  }

  async function getPanelCollapsed() {
    const settings = await getSettings().catch(() => ({}));
    return Boolean(settings.panelCollapsed);
  }

  async function setPanelCollapsed(collapsed) {
    const settings = await getSettings().catch(() => ({}));
    settings.panelCollapsed = Boolean(collapsed);
    await setSettings(settings);
  }

  async function clearStoredChapters(state) {
    const keys = state?.chapterRefs?.map((item) => item.key).filter(Boolean) || [];
    if (keys.length) await storageRemoveMany(keys);
  }

  async function getStoredChapters(state) {
    if (Array.isArray(state?.chapters)) return state.chapters;

    const refs = Array.isArray(state?.chapterRefs) ? state.chapterRefs : [];
    if (!refs.length) return [];

    const keys = refs.map((item) => item.key).filter(Boolean);
    const items = await storageGetMany(keys);
    return refs
      .map((item) => items[item.key])
      .filter(Boolean)
      .sort((a, b) => (a.order || 0) - (b.order || 0));
  }

  async function addDownloadHistory(state, chapters) {
    const first = chapters[0];
    const last = chapters[chapters.length - 1];
    if (!first || !last) return;

    const history = await storageGetKey(HISTORY_KEY).catch(() => []);
    const nextHistory = Array.isArray(history) ? history : [];
    nextHistory.unshift({
      id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
      bookTitle: state?.bookTitle || first.bookTitle || "",
      bookKey: state?.bookKey || `${first.host}:${first.bookId}`,
      chapterCount: chapters.length,
      totalChars: chapters.reduce((sum, item) => sum + (item.charCount || 0), 0),
      startChapterId: first.chapterId || "",
      startChapterTitle: first.chapterTitle || formatChapterTitle(first),
      startUrl: first.url || state?.startUrl || "",
      endChapterId: last.chapterId || "",
      endChapterTitle: last.chapterTitle || formatChapterTitle(last),
      endUrl: last.url || state?.lastUrl || "",
      downloadedAt: new Date().toISOString()
    });

    await storageSetKey(HISTORY_KEY, nextHistory.slice(0, 50));
  }

  async function isAutoRunning() {
    if (autoStopRequested) return false;
    const state = await storageGet();
    return Boolean(state?.running);
  }

  async function sleepWhileAutoRunning(timeoutMs, stepMs = 50) {
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      if (!(await isAutoRunning())) return false;
      await new Promise((resolve) => setTimeout(resolve, stepMs));
    }
    return isAutoRunning();
  }

  function setStatus(message) {
    let status = document.getElementById("gettext-stv-toast");
    if (!status) {
      status = document.createElement("div");
      status.id = "gettext-stv-toast";
      document.documentElement.appendChild(status);
    }

    if (!status.querySelector(".gettext-stv-toast-content")) {
      status.innerHTML = [
        '<span class="gettext-stv-toast-content"></span>',
        '<button class="gettext-stv-toast-close" type="button" aria-label="Dong">&times;</button>'
      ].join("");

      status.querySelector(".gettext-stv-toast-close").addEventListener("click", () => {
        status.style.display = "none";
        if (status._animationFrame) {
          cancelAnimationFrame(status._animationFrame);
          status._animationFrame = null;
        }
      });
    }

    if (status._animationFrame) {
      cancelAnimationFrame(status._animationFrame);
      status._animationFrame = null;
    }

    const content = status.querySelector(".gettext-stv-toast-content");
    if (content) content.textContent = message;

    if (message) {
      status.style.display = "flex";
      const duration = 4000;
      const startTime = performance.now();

      const animate = (now) => {
        const elapsed = now - startTime;
        const remaining = Math.max(0, duration - elapsed);
        const progressPercent = remaining / duration;
        status.style.setProperty("--toast-progress-percent", `${progressPercent * 100}`);

        if (remaining > 0) {
          status._animationFrame = requestAnimationFrame(animate);
        } else {
          status.style.display = "none";
          status._animationFrame = null;
        }
      };

      status._animationFrame = requestAnimationFrame(animate);
    } else {
      status.style.display = "none";
    }
  }

  function showWindowsNotification(title, message) {
    setStatus(`${title}: ${message}`);
    try {
      chrome.runtime.sendMessage({
        type: "GETTEXT_STV_NOTIFY",
        title,
        message
      }, (response) => {
        if (chrome.runtime.lastError || response?.error) {
          appendAutoLog("notification-error", {
            runtimeError: chrome.runtime.lastError?.message || "",
            responseError: response?.error || "",
            title,
            message
          });
        } else {
          appendAutoLog("notification-sent", {
            id: response?.id || "",
            title,
            message
          });
        }
      });
    } catch (_error) {
    }
  }

  function setProgress(state) {
    let progress = document.getElementById("gettext-stv-progress");
    if (!progress) {
      progress = document.createElement("div");
      progress.id = "gettext-stv-progress";
      document.documentElement.appendChild(progress);
    }

    const count = getChapterCount(state);
    if (state?.running) {
      progress.style.display = "block";
      progress.textContent = `Tien do: da tai ${count} chuong`;
    } else {
      progress.style.display = "none";
      progress.textContent = "";
    }
  }

  async function runAction(action) {
    if (action === "autoStop") {
      return stopAutoDownload();
    }

    const chapter = extractChapter();
    if (!chapter.isChapterPage) {
      setStatus("Mo mot trang chuong de lay text.");
      return { ok: false, message: "Trang hien tai khong phai trang chuong." };
    }

    if (action === "autoStart") {
      return startAutoDownload();
    }

    if (!chapter.isReady) {
      setStatus("Chuong chua tai xong.");
      return { ok: false, message: "Chuong chua tai xong, hay bam vao noi dung hoac doi them." };
    }

    if (action === "copy") {
      await copyText(chapter.text);
      setStatus(`Da copy ${chapter.charCount} ky tu.`);
      return { ok: true, message: `Da copy ${chapter.charCount} ky tu.`, chapter };
    }

    if (action === "download") {
      await downloadText(chapter);
      setStatus(`Da tai ${chapter.charCount} ky tu.`);
      return { ok: true, message: `Da tai ${chapter.charCount} ky tu.`, chapter };
    }

    return { ok: true, chapter };
  }

  function openNextChapter() {
    const next = document.querySelector("#navnexttop");
    const href = next?.getAttribute("href");
    if (!href) {
      setStatus("Khong tim thay chuong sau.");
      return false;
    }
    next.click();
    return true;
  }

  function normalizeUrl(value) {
    if (!value) return "";
    try {
      const url = new URL(value, location.href);
      url.hash = "";
      url.search = "";
      url.pathname = url.pathname.replace(/\/+$/, "") + "/";
      return url.href;
    } catch (_error) {
      return "";
    }
  }

  function getChapterNumberFromUrl(value) {
    const normalized = normalizeUrl(value);
    if (!normalized) return null;
    const match = new URL(normalized).pathname.match(/\/(\d+)\/$/);
    return match ? Number(match[1]) : null;
  }

  function isZeroChapterUrl(value) {
    return getChapterNumberFromUrl(value) === 0;
  }

  function getAutoEndUrl(state) {
    return normalizeUrl(state?.endUrl || "");
  }

  function hasReachedEndUrl(state, url) {
    const endUrl = getAutoEndUrl(state);
    return Boolean(endUrl && normalizeUrl(url) === endUrl);
  }

  function isChapterUrl(value) {
    try {
      const url = new URL(value, location.href);
      const parts = url.pathname.split("/").filter(Boolean);
      if (parts[0] === "truyen" && parts.length >= 5) {
        return /^\d+$/.test(parts[parts.length - 1]);
      }
    } catch (_error) {}
    return false;
  }

  async function recoverLoadErrorPage(state) {
    const currentUrl = normalizeUrl(location.href);
    if (!currentUrl) return false;

    const items = await chrome.storage.local.get(["STV_MAX_RETRIES"]);
    const maxRetries = Number(items.STV_MAX_RETRIES) || 5;

    const attempts = state.loadErrorUrl === currentUrl
      ? Number(state.loadErrorAttempts || 0) + 1
      : 1;

    await appendAutoLog("page-load-error-recover-check", {
      currentUrl,
      attempts,
      maxRetries
    });

    if (attempts > maxRetries) {
      showWindowsNotification(
        "GetText STV: Dừng do lỗi tải trang",
        `Không thể tải trang sau ${maxRetries} lần thử lại. Sẽ tải phần đã gom.`
      );
      await finishAutoDownload(state, "Dừng vì lỗi tải trang liên tục.");
      return true;
    }

    state.loadErrorUrl = currentUrl;
    state.loadErrorAttempts = attempts;
    await storageSet(state);

    showWindowsNotification(
      "GetText STV: lỗi tải trang",
      `Phát hiện lỗi tải trang (502/503/504/404). Đang thử lại (${attempts}/${maxRetries})...`
    );

    setTimeout(() => location.reload(), 2000);
    return true;
  }

  function getNextChapterUrl() {
    const next = document.querySelector("#navnexttop");
    const href = next?.getAttribute("href");
    if (!href || href === "#") return "";
    const nextUrl = new URL(href, location.href);
    const current = getChapterInfo();
    const pattern = new RegExp(`/truyen/${current.host}/1/${current.bookId}/[^/]+/?$`);
    if (pattern.test(nextUrl.pathname) && isZeroChapterUrl(nextUrl.href)) return "";
    return pattern.test(nextUrl.pathname) ? normalizeUrl(nextUrl.href) : "";
  }

  async function waitForNextChapterUrl(timeoutMs) {
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      if (!(await isAutoRunning())) return "";
      const nextUrl = getNextChapterUrl();
      if (nextUrl) return nextUrl;
      await new Promise((resolve) => setTimeout(resolve, 300));
    }
    return getNextChapterUrl();
  }

  async function recoverNextUrlFromLastChapter(state) {
    const endUrl = getAutoEndUrl(state);
    const lastUrl = normalizeUrl(state?.lastUrl || "");
    await appendAutoLog("recover-check", {
      currentUrl: normalizeUrl(location.href),
      endUrl,
      lastUrl,
      chapterCount: getChapterCount(state)
    });
    if (!endUrl || !lastUrl) return false;

    if (hasReachedEndUrl(state, lastUrl)) {
      await appendAutoLog("recover-last-url-is-end", { lastUrl, endUrl });
      await clearEndUrlSetting("recover-last-url-is-end");
      await finishAutoDownload(state, `Hoan tat den chuong cuoi: ${getChapterCount(state)} chuong.`);
      return true;
    }

    const attempts = state.zeroRecoveryUrl === lastUrl
      ? Number(state.zeroRecoveryAttempts || 0) + 1
      : 1;
    if (attempts > 3) {
      await appendAutoLog("recover-stop-max-attempts", { lastUrl, endUrl, attempts });
      await finishAutoDownload(state, `Dung vi khong lay duoc link chuong sau tu chuong da tai.`);
      return true;
    }

    state.zeroRecoveryUrl = lastUrl;
    state.zeroRecoveryAttempts = attempts;
    delete state.pendingNextUrl;
    await storageSet(state);
    await appendAutoLog("recover-reload-last-url", { lastUrl, endUrl, attempts });
    setStatus(`Bi ve /0/, tai lai chuong cuoi da lay de tim chuong sau (${attempts}/3)...`);
    location.assign(lastUrl);
    return true;
  }

  async function recoverNotReadyChapter(state, chapter) {
    const currentUrl = normalizeUrl(chapter?.url || location.href);
    if (!getAutoEndUrl(state) || !currentUrl) return false;

    const attempts = state.notReadyUrl === currentUrl
      ? Number(state.notReadyAttempts || 0) + 1
      : 1;

    await appendAutoLog("not-ready-recover-check", {
      currentUrl,
      endUrl: getAutoEndUrl(state),
      attempts,
      chapterId: chapter?.chapterId || "",
      charCount: chapter?.charCount || 0,
      originalNodeCount: chapter?.originalNodeCount || 0
    });

    if (attempts > 3) return false;

    state.notReadyUrl = currentUrl;
    state.notReadyAttempts = attempts;
    await storageSet(state);
    showWindowsNotification(
      "GetText STV: chuong chua ready",
      `Se tai lai de thu tiep (${attempts}/3): ${currentUrl}`
    );
    setTimeout(() => location.assign(currentUrl), 1500);
    return true;
  }

  async function waitForReadyChapter(timeoutMs) {
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      if (!(await isAutoRunning())) return extractChapter();
      const chapter = extractChapter();
      if (chapter.isReady) return chapter;
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    return extractChapter();
  }

  async function appendChapterToAutoState(chapter, state) {
    if (!state.sessionId) state.sessionId = createSessionId();

    const chapterRefs = Array.isArray(state.chapterRefs) ? state.chapterRefs : [];
    const legacyChapters = Array.isArray(state.chapters) ? state.chapters : [];
    const exists = chapterRefs.some((item) => item.url === chapter.url || (
      item.host === chapter.host &&
      item.bookId === chapter.bookId &&
      item.chapterId === chapter.chapterId
    )) || legacyChapters.some((item) => item.url === chapter.url || (
      item.host === chapter.host &&
      item.bookId === chapter.bookId &&
      item.chapterId === chapter.chapterId
    ));

    if (!exists) {
      const order = getChapterCount(state) + 1;
      const key = getChapterStorageKey(state.sessionId, order);
      const storedChapter = {
        order,
        host: chapter.host,
        bookId: chapter.bookId,
        chapterId: chapter.chapterId,
        bookTitle: chapter.bookTitle,
        rawChapterTitle: chapter.rawChapterTitle || chapter.chapterTitle,
        chapterTitle: formatChapterTitle(chapter, state.toc),
        url: chapter.url,
        body: chapter.body,
        charCount: chapter.charCount
      };
      await storageSetMany({ [key]: storedChapter });
      chapterRefs.push({
        key,
        order,
        host: chapter.host,
        bookId: chapter.bookId,
        chapterId: chapter.chapterId,
        url: chapter.url,
        charCount: chapter.charCount
      });
    }

    const nextState = {
      ...state,
      bookKey: `${chapter.host}:${chapter.bookId}`,
      bookTitle: state.bookTitle || chapter.bookTitle,
      lastUrl: chapter.url,
      chapterRefs,
      chapterCount: chapterRefs.length || getChapterCount(state),
      totalChars: (chapterRefs.reduce((sum, item) => sum + (item.charCount || 0), 0))
    };
    delete nextState.chapters;
    await storageSet(nextState);

    try {
      let chapIdx = chapterRefs.length > 0 ? chapterRefs.length - 1 : 0;
      if (Array.isArray(state.toc) && state.toc.length > 0) {
        const foundIndex = state.toc.findIndex((item) => String(item.chapterId) === String(chapter.chapterId) || item.url === chapter.url);
        if (foundIndex !== -1) {
          chapIdx = foundIndex;
        }
      }

      const payload = {
        type: "GETTEXT_STV_SAVE_CHAPTER",
        action: "saveChapterContent",
        bookId: chapter.bookId || "",
        bookTitle: state.bookTitle || chapter.bookTitle || "",
        chapterIndex: chapIdx,
        chapterTitle: formatChapterTitle(chapter, state.toc) || chapter.chapterTitle || "",
        chapterUrl: chapter.url || "",
        content: chapter.body || ""
      };

      if (typeof window.sendFreeBookPayload === "function") {
        window.sendFreeBookPayload("saveChapterContent", payload);
      } else if (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.sendMessage) {
        chrome.runtime.sendMessage(payload);
      }
    } catch (e) {
      console.error("FreeBook Save Chapter Bridge Error:", e);
    }

    return nextState;
  }

  async function startAutoDownload() {
    autoStopRequested = false;
    const chapter = extractChapter();
    if (!chapter.isChapterPage) {
      setStatus("Mo mot trang chuong de bat dau.");
      return { ok: false, message: "Trang hien tai khong phai trang chuong." };
    }



    const oldState = await storageGet();
    await clearStoredChapters(oldState);
    await clearAutoLogs();
    const endUrl = await getEndUrlSetting();

    let toc = [];
    try {
      const origin = window.location.origin;
      const rawBookId = String(chapter.rawBookId || chapter.bookId || "").replace(/^stv_[^_]+_/, "").replace(/^stv_/, "");
      const fetchUrl = `${origin}/index.php?ngmar=chapterlist&h=${chapter.host}&bookid=${rawBookId}&sajax=getchapterlist`;
      const response = await fetch(fetchUrl, {
        headers: {
          "Accept": "*/*"
        }
      });
      const rawText = await response.text();
      const settings = await getSettings().catch(() => ({}));
      const removeText = settings.removeText || "求月票__求個月票__求首訂__求关注__求追读__求订阅__月票加更__〔__{__(__（";
      toc = parseStvToc(rawText, chapter.host, chapter.bookId, removeText);
      await appendAutoLog("fetch-toc-success", { chapterCount: toc.length });
      if (typeof window.sendFreeBookPayload === "function" && Array.isArray(toc) && toc.length > 0) {
        window.sendFreeBookPayload("syncTOC", {
          bookId: chapter.bookId,
          bookTitle: chapter.bookTitle,
          host: chapter.host,
          url: location.href,
          tocChapters: toc
        });
      }
    } catch (e) {
      console.error("Failed to fetch TOC during auto-download start:", e);
      await appendAutoLog("fetch-toc-error", { error: e.message });
    }

    const state = {
      running: true,
      sessionId: createSessionId(),
      startedAt: new Date().toISOString(),
      startUrl: location.href,
      bookTitle: chapter.bookTitle,
      bookKey: `${chapter.host}:${chapter.bookId}`,
      endUrl,
      chapterRefs: [],
      chapterCount: 0,
      totalChars: 0,
      toc: toc
    };
    await storageSet(state);
    await appendAutoLog("auto-start", {
      startUrl: normalizeUrl(location.href),
      endUrl,
      bookKey: state.bookKey,
      chapterId: chapter.chapterId,
      chapterTitle: formatChapterTitle(chapter)
    });
    setStatus("Dang tai nhieu chuong...");
    setProgress(state);
    resumeAutoDownload();
    return { ok: true, message: "Da bat dau tai tu dong.", auto: await storageGet(), chapter };
  }

  async function stopAutoDownload() {
    autoStopRequested = true;
    const state = await storageGet();
    if (!state) {
      setStatus("Chua co tac vu tu dong.");
      return { ok: false, message: "Chua co tac vu tu dong." };
    }

    state.running = false;
    await appendAutoLog("auto-stop-manual", {
      chapterCount: getChapterCount(state),
      lastUrl: state.lastUrl || "",
      endUrl: getAutoEndUrl(state)
    });
    await storageSet(state);
    await downloadAutoText(state);
    if (typeof window.sendFreeBookPayload === "function") {
      const bookId = state.bookKey ? state.bookKey.split(":")[1] : "";
      const host = state.bookKey ? state.bookKey.split(":")[0] : "";
      if (Array.isArray(state.toc) && state.toc.length > 0) {
        window.sendFreeBookPayload("syncTOC", {
          bookId: bookId,
          bookTitle: state.bookTitle || "",
          host: host,
          url: location.href,
          tocChapters: state.toc
        });
      }
      window.sendFreeBookPayload("finishDownload", {
        type: "GETTEXT_STV_FINISH",
        action: "finishDownload",
        bookId: bookId,
        bookTitle: state.bookTitle || "",
        url: location.href
      });
    }

    await storageRemove();
    setProgress(null);
    setStatus(`Da dung va tai ${getChapterCount(state)} chuong.`);
    return { ok: true, message: `Da dung va tai ${getChapterCount(state)} chuong.` };
  }

  async function finishAutoDownload(state, message) {
    autoStopRequested = false;
    state.running = false;
    const finishLog = {
      message,
      chapterCount: getChapterCount(state),
      lastUrl: state.lastUrl || "",
      endUrl: getAutoEndUrl(state),
      currentUrl: normalizeUrl(location.href)
    };
    if (hasReachedEndUrl(state, state.lastUrl)) {
      await clearEndUrlSetting("finish-last-url-reached-end");
    }
    await appendAutoLog("auto-finish", finishLog);
    await storageSet(state);
    await downloadAutoText(state);
    await clearStoredChapters(state);
    await storageRemove();
    setProgress(null);
    setStatus(message);
    showWindowsNotification(
      "GetText STV: tai xong",
      `${message}\nDa tai: ${finishLog.chapterCount} chuong\nChuong cuoi da tai: ${finishLog.lastUrl || "khong ro"}`
    );

    try {
      const bookId = state.bookKey ? state.bookKey.split(":")[1] : "";
      const host = state.bookKey ? state.bookKey.split(":")[0] : "";
      if (typeof window.sendFreeBookPayload === "function") {
        if (Array.isArray(state.toc) && state.toc.length > 0) {
          window.sendFreeBookPayload("syncTOC", {
            bookId: bookId,
            bookTitle: state.bookTitle || "",
            host: host,
            url: location.href,
            tocChapters: state.toc
          });
        }
        window.sendFreeBookPayload("finishDownload", finishPayload);
      } else if (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.sendMessage) {
        chrome.runtime.sendMessage(finishPayload);
      }
    } catch (_e) {}
  }

  async function resumeAutoDownload() {
    if (autoLoopStarted) return;
    autoLoopStarted = true;

    try {
      let state = await storageGet();
      if (!state?.running) return;

      const current = extractChapter();
      await appendAutoLog("resume", {
        currentUrl: normalizeUrl(location.href),
        isChapterPage: current.isChapterPage,
        currentChapterId: current.chapterId,
        stateLastUrl: state.lastUrl || "",
        stateEndUrl: getAutoEndUrl(state),
        chapterCount: getChapterCount(state)
      });
      if (isZeroChapterUrl(location.href)) {
        await appendAutoLog("zero-url-detected", {
          currentUrl: normalizeUrl(location.href),
          lastUrl: state.lastUrl || "",
          endUrl: getAutoEndUrl(state),
          reachedEndByLastUrl: hasReachedEndUrl(state, state.lastUrl)
        });
        if (hasReachedEndUrl(state, state.lastUrl)) {
          await clearEndUrlSetting("zero-url-last-url-reached-end");
          await finishAutoDownload(state, `Hoan tat den chuong cuoi: ${getChapterCount(state)} chuong.`);
          return;
        }
        if (!(await recoverNextUrlFromLastChapter(state))) await finishAutoDownload(state, `Hoan tat ${getChapterCount(state)} chuong.`);
        return;
      }
      if (!current.isChapterPage) {
        if (isChapterUrl(location.href)) {
          if (await recoverLoadErrorPage(state)) return;
        }
        return;
      }

      if (state.bookKey && current.bookId && state.bookKey !== `${current.host}:${current.bookId}`) {
        await appendAutoLog("book-key-mismatch-stop-resume", {
          expectedBookKey: state.bookKey,
          currentBookKey: `${current.host}:${current.bookId}`
        });
        return;
      }

      setStatus(`Dang doi chuong ${current.chapterId || ""}...`.trim());
      const chapter = await waitForReadyChapter(AUTO_WAIT_MS);
      state = await storageGet();
      if (autoStopRequested || !state?.running) return;

      if (!chapter.isReady) {
        await appendAutoLog("chapter-not-ready", {
          currentUrl: normalizeUrl(location.href),
          chapterId: chapter.chapterId,
          charCount: chapter.charCount,
          originalNodeCount: chapter.originalNodeCount
        });
        if (await recoverNotReadyChapter(state, chapter)) return;
        await appendAutoLog("chapter-not-ready-finish", {
          currentUrl: normalizeUrl(location.href),
          chapterId: chapter.chapterId,
          charCount: chapter.charCount,
          originalNodeCount: chapter.originalNodeCount
        });
        showWindowsNotification(
          "GetText STV: dung vi chuong chua ready",
          `Da thu lai nhung van chua co noi dung. Se tai phan da gom: ${normalizeUrl(location.href)}`
        );
        await finishAutoDownload(state, "Dung vi chuong chua tai duoc.");
        return;
      }

      state = await appendChapterToAutoState(chapter, state);
      let stateChanged = false;
      if (state.notReadyUrl && normalizeUrl(chapter.url) === state.notReadyUrl) {
        delete state.notReadyUrl;
        delete state.notReadyAttempts;
        stateChanged = true;
      }
      if (state.loadErrorUrl) {
        delete state.loadErrorUrl;
        delete state.loadErrorAttempts;
        stateChanged = true;
      }
      if (stateChanged) {
        await storageSet(state);
      }
      await appendAutoLog("chapter-saved", {
        url: normalizeUrl(chapter.url),
        chapterId: chapter.chapterId,
        title: formatChapterTitle(chapter),
        chapterCount: getChapterCount(state),
        isEndUrl: hasReachedEndUrl(state, chapter.url),
        endUrl: getAutoEndUrl(state)
      });
      if (state.zeroRecoveryUrl && normalizeUrl(chapter.url) !== state.zeroRecoveryUrl) {
        delete state.zeroRecoveryUrl;
        delete state.zeroRecoveryAttempts;
        delete state.pendingNextUrl;
        await storageSet(state);
      }
      setProgress(state);
      setStatus(`Da lay ${getChapterCount(state)} chuong.`);

      if (hasReachedEndUrl(state, chapter.url)) {
        await finishAutoDownload(state, `Hoan tat den chuong cuoi: ${getChapterCount(state)} chuong.`);
        return;
      }

      const delayMs = await getNextDelayMs();
      setStatus(`Cho ${Math.round(delayMs / 100) / 10}s roi tai chuong tiep...`);
      if (!(await sleepWhileAutoRunning(delayMs))) return;
      state = await storageGet();
      if (autoStopRequested || !state?.running) return;

      let nextUrl = await waitForNextChapterUrl(10000);
      state = await storageGet();
      if (autoStopRequested || !state?.running) return;
      await appendAutoLog("next-url-check", {
        currentUrl: normalizeUrl(location.href),
        nextUrl,
        nextIsZero: isZeroChapterUrl(nextUrl),
        endUrl: getAutoEndUrl(state),
        hasEndUrl: Boolean(getAutoEndUrl(state))
      });
      if (getAutoEndUrl(state) && (!nextUrl || isZeroChapterUrl(nextUrl))) {
        await recoverNextUrlFromLastChapter(state);
        return;
      }
      if (!getAutoEndUrl(state) && nextUrl && isZeroChapterUrl(nextUrl)) {
        nextUrl = "";
      }
      if (!nextUrl || nextUrl === location.href) {
        await finishAutoDownload(state, `Hoan tat ${getChapterCount(state)} chuong.`);
        return;
      }

      state.pendingNextUrl = nextUrl;
      await storageSet(state);
      await appendAutoLog("navigate-next", { nextUrl });
      location.assign(nextUrl);
    } catch (error) {
      const state = await storageGet().catch(() => null);
      await appendAutoLog("auto-error", {
        message: error?.message || String(error),
        currentUrl: normalizeUrl(location.href),
        chapterCount: getChapterCount(state)
      });
      if (state && getChapterCount(state) > 0) {
        await finishAutoDownload(state, `Dung va tai phan da gom vi loi luu tru: ${error.message}`);
      } else {
        setStatus(`Dung vi loi luu tru: ${error.message}`);
      }
    } finally {
      autoLoopStarted = false;
    }
  }

  function clampPanelPosition(left, top, panel) {
    const width = panel.offsetWidth || 180;
    const height = panel.offsetHeight || 240;
    return {
      left: Math.max(4, Math.min(left, window.innerWidth - width - 4)),
      top: Math.max(4, Math.min(top, window.innerHeight - height - 4))
    };
  }

  async function applySavedPanelPosition(panel) {
    const position = await getPanelPosition();
    if (!position) return;

    const next = clampPanelPosition(Number(position.left) || 14, Number(position.top) || 110, panel);
    panel.style.left = `${next.left}px`;
    panel.style.top = `${next.top}px`;
    panel.style.right = "auto";
  }

  async function movePanelToSide(panel, side) {
    const top = panel.getBoundingClientRect().top || 110;
    const left = side === "left" ? 14 : window.innerWidth - (panel.offsetWidth || 180) - 14;
    const next = clampPanelPosition(left, top, panel);
    panel.style.left = `${next.left}px`;
    panel.style.top = `${next.top}px`;
    panel.style.right = "auto";
    await setPanelPosition(next);
  }

  function initPanelDrag(panel) {
    const head = panel.querySelector(".gettext-stv-head");
    if (!head) return;

    let dragging = false;
    let offsetX = 0;
    let offsetY = 0;

    head.addEventListener("pointerdown", (event) => {
      if (event.target.closest("button")) return;

      const rect = panel.getBoundingClientRect();
      dragging = true;
      offsetX = event.clientX - rect.left;
      offsetY = event.clientY - rect.top;
      panel.classList.add("gettext-stv-dragging");
      head.setPointerCapture(event.pointerId);
    });

    head.addEventListener("pointermove", (event) => {
      if (!dragging) return;

      const next = clampPanelPosition(event.clientX - offsetX, event.clientY - offsetY, panel);
      panel.style.left = `${next.left}px`;
      panel.style.top = `${next.top}px`;
      panel.style.right = "auto";
    });

    async function finishDrag(event) {
      if (!dragging) return;
      dragging = false;
      panel.classList.remove("gettext-stv-dragging");
      try {
        head.releasePointerCapture(event.pointerId);
      } catch (_error) {
      }

      const rect = panel.getBoundingClientRect();
      await setPanelPosition(clampPanelPosition(rect.left, rect.top, panel));
    }

    head.addEventListener("pointerup", finishDrag);
    head.addEventListener("pointercancel", finishDrag);
  }

  async function initDelayInput(panel) {
    const input = panel.querySelector("[data-stv-delay]");
    if (!input) return;

    input.value = String(Math.round((await getNextDelayMs()) / 100) / 10);
    input.addEventListener("change", async () => {
      const delaySeconds = Math.max(0, Math.min(Number(input.value) || 0, 120));
      input.value = String(delaySeconds);
      await setNextDelayMs(delaySeconds * 1000);
      setStatus(`Delay: ${delaySeconds}s`);
    });
  }

  async function initEndUrlInput(panel) {
    const input = panel.querySelector("[data-stv-end-url]");
    if (!input) return;

    input.value = await getEndUrlSetting();
    input.addEventListener("change", async () => {
      const endUrl = await setEndUrlSetting(input.value);
      input.value = endUrl;
      setStatus(endUrl ? "Da luu URL chuong cuoi." : "Da xoa URL chuong cuoi.");
    });
  }

  async function applySavedPanelCollapsed(panel) {
    const collapsed = await getPanelCollapsed();
    const body = panel.querySelector(".gettext-stv-body");
    const button = panel.querySelector('[data-stv-action="toggle"]');
    if (!body || !button) return;

    body.style.display = collapsed ? "none" : "";
    panel.classList.toggle("gettext-stv-collapsed", collapsed);
    button.textContent = collapsed ? "T" : "-";
  }

  function formatHistoryTime(value) {
    if (!value) return "";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return value;
    return date.toLocaleString("vi-VN");
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function chapterLabel(title, id) {
    return cleanSpaces(title || id || "Khong ro chuong");
  }

  function renderPanelHistoryLink(url, label) {
    if (!url) return escapeHtml(label);
    return `<a href="${escapeHtml(url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(label)}</a>`;
  }

  function formatLogDetails(details) {
    return Object.entries(details || {})
      .map(([key, value]) => `${key}: ${typeof value === "string" ? value : JSON.stringify(value)}`)
      .join("\n");
  }

  async function deleteHistoryItem(id) {
    if (!id) return;
    const history = await storageGetKey(HISTORY_KEY).catch(() => []);
    const nextHistory = Array.isArray(history) ? history.filter((item) => item.id !== id) : [];
    await storageSetKey(HISTORY_KEY, nextHistory);
  }

  async function clearDownloadHistory() {
    await storageSetKey(HISTORY_KEY, []);
  }

  async function openHistoryPopup() {
    const history = await storageGetKey(HISTORY_KEY).catch(() => []);
    const shown = Array.isArray(history) ? history.slice(0, 30) : [];
    const oldPopup = document.querySelector(".gettext-stv-modal-backdrop");
    if (oldPopup) oldPopup.remove();

    const bodyHtml = shown.length ? shown.map((item) => {
      const startLabel = chapterLabel(item.startChapterTitle, item.startChapterId);
      const endLabel = chapterLabel(item.endChapterTitle, item.endChapterId);
      return `
        <div class="gettext-stv-history-card">
          <div class="gettext-stv-history-book">${escapeHtml(item.bookTitle || "Khong ro ten sach")}</div>
          <div class="gettext-stv-history-range">${item.chapterCount || 0} chuong: ${escapeHtml(startLabel)} -&gt; ${escapeHtml(endLabel)}</div>
          <div class="gettext-stv-history-meta">Tu: ${renderPanelHistoryLink(item.startUrl, startLabel)}</div>
          <div class="gettext-stv-history-meta">Den: ${renderPanelHistoryLink(item.endUrl, endLabel)}</div>
          <div class="gettext-stv-history-time">${escapeHtml(formatHistoryTime(item.downloadedAt))}</div>
          <button class="gettext-stv-history-delete" type="button" data-stv-delete-history="${escapeHtml(item.id)}">Xoa</button>
        </div>
      `;
    }).join("") : '<div class="gettext-stv-history-empty">Chua co lich su.</div>';

    const popup = document.createElement("div");
    popup.className = "gettext-stv-modal-backdrop";
    popup.innerHTML = `
      <div class="gettext-stv-modal" role="dialog" aria-modal="true" aria-label="Lich su tai">
        <div class="gettext-stv-modal-head">
          <div>
            <div class="gettext-stv-modal-title">Lich su tai</div>
            <div class="gettext-stv-modal-subtitle">Cac lan tai gan day, tu chuong dau den chuong cuoi</div>
          </div>
          <div class="gettext-stv-modal-actions">
            <button class="gettext-stv-history-clear" type="button">Xoa het</button>
            <button class="gettext-stv-modal-close" type="button" aria-label="Dong">x</button>
          </div>
        </div>
        <div class="gettext-stv-modal-body">${bodyHtml}</div>
      </div>
    `;

    popup.addEventListener("click", async (event) => {
      const deleteButton = event.target.closest("[data-stv-delete-history]");
      if (deleteButton) {
        await deleteHistoryItem(deleteButton.dataset.stvDeleteHistory);
        await openHistoryPopup();
        return;
      }

      if (event.target.closest(".gettext-stv-history-clear")) {
        await clearDownloadHistory();
        await openHistoryPopup();
        return;
      }

      if (
        event.target === popup ||
        event.target.closest(".gettext-stv-modal-close")
      ) {
        popup.remove();
      }
    });

    document.addEventListener("keydown", function closeOnEscape(event) {
      if (event.key !== "Escape") return;
      popup.remove();
      document.removeEventListener("keydown", closeOnEscape);
    });

    document.documentElement.appendChild(popup);
  }

  async function openLogPopup() {
    const logs = await getAutoLogs();
    const oldPopup = document.querySelector(".gettext-stv-modal-backdrop");
    if (oldPopup) oldPopup.remove();

    const bodyHtml = logs.length ? logs.slice().reverse().map((item) => `
      <div class="gettext-stv-log-card">
        <div class="gettext-stv-log-title">${escapeHtml(item.label || "")}</div>
        <div class="gettext-stv-log-time">${escapeHtml(formatHistoryTime(item.time))}</div>
        <pre>${escapeHtml(formatLogDetails(item.details))}</pre>
      </div>
    `).join("") : '<div class="gettext-stv-history-empty">Chua co log.</div>';

    const popup = document.createElement("div");
    popup.className = "gettext-stv-modal-backdrop";
    popup.innerHTML = `
      <div class="gettext-stv-modal" role="dialog" aria-modal="true" aria-label="Log xu ly">
        <div class="gettext-stv-modal-head">
          <div>
            <div class="gettext-stv-modal-title">Log xu ly</div>
            <div class="gettext-stv-modal-subtitle">Cac buoc xu ly auto tai gan nhat</div>
          </div>
          <div class="gettext-stv-modal-actions">
            <button class="gettext-stv-log-clear" type="button">Xoa log</button>
            <button class="gettext-stv-modal-close" type="button" aria-label="Dong">x</button>
          </div>
        </div>
        <div class="gettext-stv-modal-body">${bodyHtml}</div>
      </div>
    `;

    popup.addEventListener("click", async (event) => {
      if (event.target.closest(".gettext-stv-log-clear")) {
        await clearAutoLogs();
        await openLogPopup();
        return;
      }

      if (
        event.target === popup ||
        event.target.closest(".gettext-stv-modal-close")
      ) {
        popup.remove();
      }
    });

    document.addEventListener("keydown", function closeOnEscape(event) {
      if (event.key !== "Escape") return;
      popup.remove();
      document.removeEventListener("keydown", closeOnEscape);
    });

    document.documentElement.appendChild(popup);
  }

  async function loadPanelToc(panel) {
    const rangeContainer = panel.querySelector(".gettext-stv-range");
    const statusNode = panel.querySelector(".gettext-stv-range-status");
    const fieldsNode = panel.querySelector(".gettext-stv-range-fields");
    const startInput = panel.querySelector("[data-stv-start-chap]");
    const endInput = panel.querySelector("[data-stv-end-chap]");

    const chapter = getChapterInfo();
    if (!chapter.bookId || !chapter.host) {
      if (rangeContainer) rangeContainer.style.display = "none";
      return;
    }

    if (rangeContainer) rangeContainer.style.display = "block";

    try {
      const origin = window.location.origin;
      const rawBookId = chapter.rawBookId;
      const fetchUrl = `${origin}/index.php?ngmar=chapterlist&h=${chapter.host}&bookid=${rawBookId}&sajax=getchapterlist`;
      await appendAutoLog("load-panel-toc-start", { fetchUrl, rawBookId, host: chapter.host });
      const response = await fetch(fetchUrl, {
        headers: {
          "Accept": "*/*"
        }
      });
      const rawText = await response.text();
      const settings = await getSettings().catch(() => ({}));
      const removeText = settings.removeText || "求月票__求個月票__求首訂__求关注__求追读__求订阅__月票加更__〔__{__(__（";
      panelLocalToc = parseStvToc(rawText, chapter.host, chapter.bookId, removeText);
      panelBookTitle = chapter.bookTitle;

      if (Array.isArray(panelLocalToc) && panelLocalToc.length > 0) {
        statusNode.textContent = `Mục lục: ${panelLocalToc.length} chương.`;
        fieldsNode.style.display = "flex";
        await appendAutoLog("load-panel-toc-success", { chapterCount: panelLocalToc.length, bookId: chapter.bookId });

        if (typeof window.sendFreeBookPayload === "function") {
          window.sendFreeBookPayload("syncTOC", {
            bookId: chapter.bookId,
            bookTitle: chapter.bookTitle,
            host: chapter.host,
            url: location.href,
            tocChapters: panelLocalToc
          });
        }

        startInput.max = panelLocalToc.length;
        endInput.max = panelLocalToc.length;

        let startIndex = 0;
        if (chapter.chapterId) {
          const idx = panelLocalToc.findIndex(item => String(item.chapterId) === String(chapter.chapterId));
          if (idx !== -1) {
            startIndex = idx;
          }
        }

        startInput.value = startIndex + 1;
        endInput.value = panelLocalToc.length;
      } else {
        statusNode.textContent = "Không tải được mục lục.";
        await appendAutoLog("load-panel-toc-empty", { rawTextLength: rawText ? rawText.length : 0 });
      }
    } catch (e) {
      statusNode.textContent = "Lỗi mục lục: " + e.message;
      await appendAutoLog("load-panel-toc-error", { error: e.message });
    }
  }

  function createPanel() {
    if (document.getElementById(PANEL_ID)) return;

    const panel = document.createElement("div");
    panel.id = PANEL_ID;
    panel.innerHTML = [
      '<div class="gettext-stv-head"><span>GetText STV</span><button class="gettext-stv-mini" data-stv-action="toggle">-</button></div>',
      '<div class="gettext-stv-body">',
      
      // Chapter actions container
      '<div class="gettext-stv-chapter-actions" style="display: none;">',
      '  <button class="gettext-stv-primary" data-stv-action="copy">Copy text</button>',
      '  <button data-stv-action="download">Tai TXT</button>',
      '  <button data-stv-action="autoStart">Tai tu dong</button>',
      '  <button data-stv-action="autoStop">Dung va tai TXT</button>',
      '  <button data-stv-action="next">Chuong sau</button>',
      '  <label class="gettext-stv-delay">Delay <input type="number" min="0" max="120" step="0.5" data-stv-delay> giay</label>',
      '  <label class="gettext-stv-end-url">URL chuong cuoi <input type="url" placeholder="http://14.225.254.182/..." data-stv-end-url></label>',
      '</div>',

      // Range download container
      '<div class="gettext-stv-range" style="display: none;">',
      '  <h3>Tải khoảng chương</h3>',
      '  <div class="gettext-stv-range-status">Đang tải mục lục...</div>',
      '  <div class="gettext-stv-range-fields" style="display: none;">',
      '    <div class="gettext-stv-row">',
      '      <label>Từ <input type="number" min="1" data-stv-start-chap></label>',
      '      <label>Đến <input type="number" min="1" data-stv-end-chap></label>',
      '    </div>',
      '    <button class="gettext-stv-primary" data-stv-action="rangeStart">Bắt đầu tải</button>',
      '  </div>',
      '</div>',

      '<hr class="gettext-stv-divider">',
      '<button data-stv-action="history">Lich su</button>',
      '<button data-stv-action="log">Log</button>',
      '<div class="gettext-stv-row"><button data-stv-action="left">Trai</button><button data-stv-action="right">Phai</button></div>',

      "</div>"
    ].join("");

    applySavedPanelPosition(panel);
    initPanelDrag(panel);
    initDelayInput(panel);
    initEndUrlInput(panel);
    applySavedPanelCollapsed(panel);

    const isChapter = extractChapter().isChapterPage;
    const chapterActions = panel.querySelector(".gettext-stv-chapter-actions");
    const rangeContainer = panel.querySelector(".gettext-stv-range");
    const divider = panel.querySelector(".gettext-stv-divider");

    if (isChapter) {
      chapterActions.style.display = "grid";
      rangeContainer.style.display = "none";
      if (divider) divider.style.display = "none";
    } else {
      chapterActions.style.display = "none";
      rangeContainer.style.display = "block";
      if (divider) divider.style.display = "block";
      loadPanelToc(panel);
    }

    panel.addEventListener("click", async (event) => {
      const button = event.target.closest("button[data-stv-action]");
      if (!button) return;

      const action = button.dataset.stvAction;
      if (action === "toggle") {
        const body = panel.querySelector(".gettext-stv-body");
        const collapsed = body.style.display !== "none";
        body.style.display = collapsed ? "none" : "";
        panel.classList.toggle("gettext-stv-collapsed", collapsed);
        button.textContent = collapsed ? "T" : "-";
        await setPanelCollapsed(collapsed);
        return;
      }

      if (action === "next") {
        openNextChapter();
        return;
      }

      if (action === "left" || action === "right") {
        await movePanelToSide(panel, action);
        return;
      }

      if (action === "history") {
        await openHistoryPopup();
        return;
      }

      if (action === "log") {
        await openLogPopup();
        return;
      }

      if (action === "rangeStart") {
        const startInput = panel.querySelector("[data-stv-start-chap]");
        const endInput = panel.querySelector("[data-stv-end-chap]");
        const startNum = parseInt(startInput.value, 10);
        const endNum = parseInt(endInput.value, 10);

        if (isNaN(startNum) || isNaN(endNum) || startNum < 1 || endNum < startNum || !panelLocalToc || endNum > panelLocalToc.length) {
          alert("Khoảng chương chọn không hợp lệ!");
          return;
        }

        button.disabled = true;
        setStatus("Đang khởi tạo...");
        const startChap = panelLocalToc[startNum - 1];
        const endChap = panelLocalToc[endNum - 1];

        try {
          await startRangeDownload(startChap.url, endChap.url, panelLocalToc, panelBookTitle);
        } catch (err) {
          setStatus("Lỗi: " + err.message);
          button.disabled = false;
        }
        return;
      }

      button.disabled = true;
      setStatus("Dang xu ly...");
      try {
        if (action === "autoStart") {
          const endUrlInput = panel.querySelector("[data-stv-end-url]");
          if (endUrlInput) await setEndUrlSetting(endUrlInput.value);
        }
        await runAction(action);
      } catch (error) {
        setStatus(error?.message || "Co loi khi xu ly.");
      } finally {
        button.disabled = false;
      }
    });

    document.documentElement.appendChild(panel);
  }

  async function startRangeDownload(startUrl, endUrl, toc, bookTitle) {
    autoStopRequested = false;
    const oldState = await storageGet();
    await clearStoredChapters(oldState);
    await clearAutoLogs();

    // Cập nhật cấu hình URL chương cuối
    await setEndUrlSetting(endUrl);
    const panel = document.getElementById(PANEL_ID);
    if (panel) {
      const endUrlInput = panel.querySelector("[data-stv-end-url]");
      if (endUrlInput) endUrlInput.value = normalizeUrl(endUrl);
    }

    const match = startUrl.match(/\/truyen\/([^\/]+)\/[^\/]+\/([^\/]+)/);
    const host = match ? match[1] : "";
    const rawBookId = match ? match[2].replace(/^stv_[^_]+_/, "").replace(/^stv_/, "") : "";
    const canonicalBookId = (host && rawBookId) ? `stv_${host}_${rawBookId}` : rawBookId;

    const state = {
      running: true,
      sessionId: createSessionId(),
      startedAt: new Date().toISOString(),
      startUrl: startUrl,
      bookTitle: bookTitle,
      bookKey: `${host}:${canonicalBookId}`,
      endUrl: endUrl,
      chapterRefs: [],
      chapterCount: 0,
      totalChars: 0,
      toc: toc
    };
    await storageSet(state);

    // Gửi syncTOC ngay cho Swift để lưu Book & Chapter metadata vào Kệ sách SwiftData local DB
    if (typeof sendFreeBookPayload === "function") {
      sendFreeBookPayload("syncTOC", {
        bookId: canonicalBookId,
        bookTitle: bookTitle,
        host: host,
        url: startUrl,
        tocChapters: toc
      });
    }

    await appendAutoLog("range-start", {
      startUrl,
      endUrl,
      bookKey: state.bookKey,
      bookTitle: state.bookTitle,
      chapterCount: toc.length
    });

    setStatus("Bắt đầu tải khoảng chương...");
    location.assign(startUrl);
    return { ok: true, message: "Bắt đầu tải khoảng chương.", auto: state };
  }

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    (async () => {
      if (message?.type === "GETTEXT_STV_STATUS") {
        sendResponse({ ok: true, chapter: extractChapter(), auto: await storageGet() });
        return;
      }

      if (message?.type === "GETTEXT_STV_FETCH_TOC") {
        try {
          const chapter = extractChapter();
          if (!chapter.bookId || !chapter.host) {
            sendResponse({ ok: false, error: "Không tìm thấy thông tin truyện." });
            return;
          }
          const origin = window.location.origin;
          const rawBookId = String(chapter.rawBookId || chapter.bookId || "").replace(/^stv_[^_]+_/, "").replace(/^stv_/, "");
          const fetchUrl = `${origin}/index.php?ngmar=chapterlist&h=${chapter.host}&bookid=${rawBookId}&sajax=getchapterlist`;
          const response = await fetch(fetchUrl, {
            headers: {
              "Accept": "*/*"
            }
          });
          const rawText = await response.text();
          const settings = await getSettings().catch(() => ({}));
          const removeText = settings.removeText || "求月票__求個月票__求首訂__求关注__求追读__求订阅__月票加更__〔__{__(__（";
          const toc = parseStvToc(rawText, chapter.host, chapter.bookId, removeText);
          sendResponse({ ok: true, toc, bookTitle: chapter.bookTitle, currentChapterId: chapter.chapterId });
        } catch (e) {
          sendResponse({ ok: false, error: e.message });
        }
        return;
      }

      if (message?.type === "GETTEXT_STV_ACTION") {
        if (message.action === "next") {
          sendResponse({ ok: openNextChapter(), message: "Da mo chuong sau." });
          return;
        }
        if (message.action === "rangeStart") {
          const result = await startRangeDownload(message.startUrl, message.endUrl, message.toc, message.bookTitle);
          sendResponse(result);
          return;
        }
        sendResponse(await runAction(message.action));
      }
    })();
    return true;
  });

  function formatTocName(name, removeText) {
    let result = name || "";
    const reLeading = /^(\d+)\.第(\d+)章\s*/;
    result = result.replace(reLeading, '第$2章 ');

    const reEpisodeChapter = /第[一二三四五六七八九十百千\d]+集\s*(第[一二三四五六七八九十百千\d]+章\s*)/;
    result = result.replace(reEpisodeChapter, '$1');

    const reDuplicate = /^第([0-9]+)章\s+\1\s*(.*)$/;
    if (reDuplicate.test(result)) {
      result = result.replace(reDuplicate, '第$1章 $2');
    }

    const arrTextRemove = (removeText || "").split('__');
    const arrTextLastIndex = arrTextRemove.map(item => result.lastIndexOf(item));
    const filtered = arrTextLastIndex.filter(x => x !== -1);
    const lastTextIndex = filtered.length > 0
      ? Math.min.apply(null, filtered)
      : -1;
    if (lastTextIndex > 0) {
      result = result.slice(0, lastTextIndex);
    }

    return result.trim();
  }

  function parseStvToc(rawText, host, bookId, removeText) {
    try {
      const objData = JSON.parse(rawText);
      if (!objData || (objData.code != 1 && objData.code != '1')) {
        return [];
      }
      const chapters = [];
      const rawChapters = (objData.data || "").split("-//-");
      const rawOriginalChapters = (objData.oridata || "").split("-//-");

      const originalTitles = {};
      for (let i = 0; i < rawOriginalChapters.length; i++) {
        if (!rawOriginalChapters[i]) continue;
        const parts = rawOriginalChapters[i].split("-/-");
        if (parts.length < 3) continue;
        const chapterId = parts[1];
        let originalTitle = parts[2].trim()
          .replace(/([\t\n]+|<br>| )/g, "")
          .replace(/([\t\n]+|<br>|&nbsp;)/g, "");
        originalTitle = formatTocName(originalTitle, removeText);
        originalTitles[chapterId] = originalTitle;
      }

      for (let i = 0; i < rawChapters.length; i++) {
        if (!rawChapters[i]) continue;
        const parts = rawChapters[i].split("-/-");
        if (parts.length < 3) continue;
        const chapterId = parts[1];
        if (chapterId === '0') continue;
        const chapterName = parts[2].trim()
          .replace(/([\t\n]+|<br>| )/g, "")
          .replace(/([\t\n]+|<br>|&nbsp;)/g, "")
          .replace(/Thứ ([\d\,]+) chương/, "Chương $1:");
        
        const rawBookId = String(bookId || "").replace(/^stv_[^_]+_/, "").replace(/^stv_/, "");
        const url = `${window.location.origin}/truyen/${host}/1/${rawBookId}/${chapterId}/`;

        chapters.push({
          chapterId: chapterId,
          title: chapterName,
          originalTitle: originalTitles[chapterId] || chapterName,
          url: url
        });
      }

      return chapters;
    } catch (e) {
      console.error("Failed to parse STV TOC response:", e);
      return [];
    }
  }

  function checkAndInitPanel() {
    if (location.pathname.includes("/truyen/") || document.querySelector("#hiddenid, #booknameholder, #bookchapnameholder")) {
      if (!document.getElementById(PANEL_ID)) {
        createPanel();
        storageGet().then(setProgress);
        setTimeout(resumeAutoDownload, 800);
      }
    }
  }

  checkAndInitPanel();
  setInterval(checkAndInitPanel, 1000);
})();
