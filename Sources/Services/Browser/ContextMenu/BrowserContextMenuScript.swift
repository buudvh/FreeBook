import Foundation
import WebKit

/// Script menu nhấn giữ / bôi đen của trình duyệt người dùng. Chạy `atDocumentStart`, **chỉ khung chính**, trong
/// **cùng** world với script dịch trang (`BrowserPageTranslateScript.contentWorld`) để gọi được
/// `window.__fbPageTranslate` (bản gốc của đoạn đã dịch). Trang không thấy `window.__fbContextMenu` lẫn handler.
///
/// Việc của script (gửi qua handler `fbContextMenu`, `BrowserContextMenuMessage` đọc):
/// - `selection`: vùng chọn đổi (`selectionchange`, gửi ngay lần đầu rồi gộp 80 ms): chữ đang hiện (cắt 2 000 ký tự),
///   link bao quanh đầu/cuối vùng chọn, cờ `han` (chữ có Hán **hoặc** trang đang dịch ⇒ bản gốc là chữ Hán). Vùng
///   chọn rỗng ⇒ gửi chữ rỗng để native xoá bản cũ; document mới cũng gửi một lần rỗng lúc cài.
///   **Không** gọi `sourceTextForSelection()` ở đây (duyệt tới 20 000 node) — native lấy bản gốc lúc bấm.
/// - `touch`: `touchstart` một ngón trên ảnh ⇒ src ảnh + link bao quanh (nếu có). Native dùng bản ghi này để thêm
///   nhóm "Ảnh" vào menu nhấn giữ link (`WKContextMenuElementInfo` chỉ có `linkURL`).
/// - `imageHold`: nhấn giữ ~500 ms, không di chuyển quá 10 px, trên ảnh **không** nằm trong link ⇒ native tự trình
///   bày menu ảnh (WebKit không gọi delegate cho ảnh đã tắt callout). Chạm nhả sau đó không thành `click`.
///
/// CSS: ảnh không nằm trong link tắt callout + chọn của Safari (`-webkit-touch-callout`/`-webkit-user-select: none`);
/// ảnh trong link giữ nguyên để menu link vẫn bật.
///
/// Đoạn gọi từ Swift (`selectionContextCall`) luôn trả chuỗi JSON, không bao giờ `undefined`/`null`.
enum BrowserContextMenuScript {
    static let messageHandlerName = "fbContextMenu"

    static func userScript() -> WKUserScript {
        WKUserScript(
            source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true,
            in: BrowserPageTranslateScript.contentWorld
        )
    }

    /// Controller đã có script này chưa (chống cài trùng khi `ObjectIdentifier` của controller cũ bị tái dùng).
    static func isInstalled(in controller: WKUserContentController) -> Bool {
        controller.userScripts.contains { $0.source == source }
    }

    /// Ngữ cảnh của vùng chọn cho sheet Tra từ điển — chuỗi JSON `{text, word, offset}`:
    /// - trang chưa dịch: `text` = chữ của khối chứa vùng chọn (cắt quanh vùng chọn), `word` = chữ đang chọn, `offset`
    ///   = vị trí (UTF-16) của `word` trong `text`;
    /// - vùng chọn chạm đoạn đã dịch: `text` = bản gốc các đoạn đó, `word` rỗng, `offset` = -1 (native tra token Hán
    ///   đầu tiên — không ánh xạ được chữ Việt đang chọn về đúng từ gốc).
    static let selectionContextCall = """
    (function () { var api = window.__fbContextMenu; return api ? api.selectionContext() : JSON.stringify({ text: "", word: "", offset: -1 }); })()
    """

    private static let source = #"""
    (function () {
        if (window.__fbContextMenuInstalled) { return; }
        try {
            Object.defineProperty(window, "__fbContextMenuInstalled", { value: true, enumerable: false });
        } catch (e) {
            return;
        }
        var handlers = window.webkit && window.webkit.messageHandlers;
        var bridge = handlers && handlers.fbContextMenu;
        var HAN = /[\u3400-\u9fff]/;
        var HOLD_MS = 500, MOVE_LIMIT = 10, PREVIEW = 2000, BLOCK_WINDOW = 1500;
        var BLOCKS = "p,li,dd,dt,td,th,h1,h2,h3,h4,h5,h6,blockquote,pre,article,section,div,body";
        var STYLE_ID = "__fbContextMenuStyle";
        // Ảnh trong link `javascript:` (lightbox) cũng coi như ảnh ngoài link: menu link của native bỏ link không phải web.
        var STYLE = "img:not(a[href] img),a[href^=\"javascript:\" i] img"
            + "{-webkit-touch-callout:none!important;-webkit-user-select:none!important;}";

        function post(body) {
            if (!bridge) { return; }
            try { bridge.postMessage(body); } catch (e) {}
        }

        // Không cắt giữa cặp surrogate (chữ Hán mở rộng B…): nửa cặp lẻ làm JSON phía native không đọc được.
        function surrogateSafe(text, index, forward) {
            if (index <= 0 || index >= text.length) { return index; }
            var c = text.charCodeAt(index);
            if (c >= 0xDC00 && c <= 0xDFFF) { return forward ? index + 1 : index - 1; }
            return index;
        }

        function cut(text, length) {
            return text.length <= length ? text : text.slice(0, surrogateSafe(text, length, false));
        }

        // MARK: CSS tắt callout ảnh ngoài link

        function injectStyle() {
            if (document.getElementById(STYLE_ID)) { return true; }
            var root = document.head || document.documentElement;
            if (!root) { return false; }
            var style = document.createElement("style");
            style.id = STYLE_ID;
            style.textContent = STYLE;
            root.appendChild(style);
            return true;
        }
        if (!injectStyle()) { document.addEventListener("DOMContentLoaded", injectStyle, { once: true }); }

        // MARK: Vùng chọn

        function linkOf(node) {
            var el = node && (node.nodeType === 1 ? node : node.parentElement);
            var a = el && el.closest ? el.closest("a[href]") : null;
            return a && a.href ? String(a.href) : "";
        }

        function translating() {
            var api = window.__fbPageTranslate;
            try { return !!(api && api.isEnabled && api.isEnabled()); } catch (e) { return false; }
        }

        var lastKey = null, selTimer = 0, lastRun = 0;

        function reportSelection() {
            var sel = window.getSelection ? window.getSelection() : null;
            var text = sel ? String(sel.toString()) : "";
            var body;
            if (!text.trim()) {
                body = { type: "selection", text: "", link: "", han: false };
            } else {
                body = {
                    type: "selection",
                    text: cut(text, PREVIEW),
                    link: linkOf(sel.anchorNode) || linkOf(sel.focusNode),
                    han: HAN.test(text) || translating()
                };
            }
            var key = body.text + "\u0001" + body.link + "\u0001" + body.han;
            if (key === lastKey) { return; }
            lastKey = key;
            post(body);
        }

        // Gửi ngay lần đổi đầu tiên (menu có thể dựng ngay sau khi chọn), các lần dồn dập sau đó gộp 80 ms.
        document.addEventListener("selectionchange", function () {
            var now = Date.now();
            if (!selTimer && now - lastRun > 80) {
                lastRun = now;
                reportSelection();
                return;
            }
            if (selTimer) { clearTimeout(selTimer); }
            selTimer = setTimeout(function () {
                selTimer = 0;
                lastRun = Date.now();
                reportSelection();
            }, 80);
        }, true);
        window.addEventListener("pageshow", function () { lastKey = null; reportSelection(); });
        post({ type: "selection", text: "", link: "", han: false });

        // MARK: Ngữ cảnh cho Tra từ điển

        function selectionContext() {
            var empty = JSON.stringify({ text: "", word: "", offset: -1 });
            try {
                var sel = window.getSelection ? window.getSelection() : null;
                var text = sel ? String(sel.toString()) : "";
                if (!text.trim() || !sel.rangeCount) { return empty; }
                var api = window.__fbPageTranslate;
                if (translating() && api.sourceTextForSelection) {
                    var source = String(api.sourceTextForSelection() || "");
                    if (source && source !== text) {
                        return JSON.stringify({ text: cut(source, 4000), word: "", offset: -1 });
                    }
                }
                // `Range.toString()` (chữ thô của text node) cho cả khối lẫn vùng chọn để vị trí khớp nhau; chữ của
                // `Selection.toString()` đã gộp khoảng trắng nên có thể lệch.
                var range = sel.getRangeAt(0);
                var raw = range.toString();
                var fallback = JSON.stringify({ text: cut(text, 4000), word: cut(text, 200), offset: 0 });
                var start = range.startContainer;
                var el = start.nodeType === 1 ? start : start.parentElement;
                var block = el && el.closest ? el.closest(BLOCKS) : null;
                if (!block || !raw.trim()) { return fallback; }
                var whole = document.createRange();
                whole.selectNodeContents(block);
                var full = whole.toString();
                var before = document.createRange();
                before.selectNodeContents(block);
                before.setEnd(range.startContainer, range.startOffset);
                var offset = before.toString().length;
                if (full.substr(offset, raw.length) !== raw) { return fallback; }
                var from = surrogateSafe(full, Math.max(0, offset - BLOCK_WINDOW), false);
                var to = surrogateSafe(full, Math.min(full.length, offset + raw.length + BLOCK_WINDOW), true);
                return JSON.stringify({ text: full.slice(from, to), word: cut(raw, 200), offset: offset - from });
            } catch (e) {
                return empty;
            }
        }

        window.__fbContextMenu = { selectionContext: selectionContext };

        // MARK: Chạm / nhấn giữ ảnh

        var hold = null, suppressClickUntil = 0;

        function imageAt(target) {
            var el = target && (target.nodeType === 1 ? target : target.parentElement);
            var img = el && el.closest ? el.closest("img") : null;
            return img && (img.currentSrc || img.src) ? img : null;
        }

        function cancelHold() {
            if (hold) { clearTimeout(hold.timer); hold = null; }
        }

        window.addEventListener("touchstart", function (e) {
            cancelHold();
            // Cú chạm mới: bỏ cờ chặn click còn treo (WebKit không phát click sau nhấn giữ) để không nuốt cú bấm thật.
            suppressClickUntil = 0;
            if (!e.touches || e.touches.length !== 1) { return; }
            var img = imageAt(e.target);
            if (!img) { return; }
            var src = String(img.currentSrc || img.src);
            var anchor = img.closest("a[href]");
            // Chỉ link web mới có menu link của native; `javascript:`/`mailto:`… ⇒ xử lý như ảnh ngoài link.
            var link = anchor && /^https?:/i.test(String(anchor.href)) ? String(anchor.href) : "";
            post({ type: "touch", image: src, link: link });
            if (link) { return; }
            var touch = e.touches[0];
            var current = { x: touch.clientX, y: touch.clientY, px: touch.pageX, py: touch.pageY, src: src, timer: 0 };
            current.timer = setTimeout(function () {
                if (hold !== current) { return; }
                hold = null;
                suppressClickUntil = Date.now() + 1500;
                post({ type: "imageHold", image: current.src, x: current.px, y: current.py });
            }, HOLD_MS);
            hold = current;
        }, { capture: true, passive: true });

        window.addEventListener("touchmove", function (e) {
            if (!hold) { return; }
            var touch = e.touches && e.touches[0];
            if (!touch || e.touches.length !== 1
                || Math.abs(touch.clientX - hold.x) > MOVE_LIMIT || Math.abs(touch.clientY - hold.y) > MOVE_LIMIT) {
                cancelHold();
            }
        }, { capture: true, passive: true });

        window.addEventListener("touchend", cancelHold, { capture: true, passive: true });
        window.addEventListener("touchcancel", cancelHold, { capture: true, passive: true });
        window.addEventListener("scroll", cancelHold, { capture: true, passive: true });

        // Nhả tay sau khi đã bật menu ảnh: không để trang nhận thành chạm (mở lightbox…).
        document.addEventListener("click", function (e) {
            if (Date.now() < suppressClickUntil) {
                suppressClickUntil = 0;
                e.preventDefault();
                e.stopPropagation();
            }
        }, true);
    })();
    """#
}
