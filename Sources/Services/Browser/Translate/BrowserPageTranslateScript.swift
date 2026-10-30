import Foundation
import WebKit

/// Script dịch trang QT **tại chỗ** cho trình duyệt người dùng: thay chữ trong text node + thuộc tính `title`/`alt`/
/// `placeholder` bằng bản dịch, giữ bản gốc để tắt là khôi phục, `MutationObserver` dịch tiếp nội dung nạp thêm.
///
/// Chạy `atDocumentStart`, **chỉ khung chính**, trong `contentWorld` riêng: trang không thấy `window.__fbPageTranslate`
/// lẫn handler `fbPageTranslate` (`BrowserPageTranslator`). Script chọn chữ/nhấn giữ (Phần menu nhấn giữ) cài vào
/// **cùng** world này để gọi `sourceTextForSelection()`.
///
/// API trong world: `window.__fbPageTranslate = { enable(), disable(), isEnabled(), sourceTextForSelection() }`.
/// - `enable()` gọi trước `DOMContentLoaded` (lúc `didCommit`) ⇒ xếp hàng tới khi DOM sẵn sàng rồi mới quét.
/// - Gửi native theo lô ≤ 120 mục / ≤ 12 000 ký tự UTF-16, **một lô bay một lúc**; mục dài hơn trần đi một mình.
/// - Tự ghi của script không bị observer dịch lại: so `nodeValue` với bản dịch đã ghi cho node đó (`written`), và
///   `takeRecords()` ngay sau mỗi lượt ghi.
/// - `disable()` chỉ khôi phục node **còn** giữ bản dịch của script — trang đã tự đổi chữ thì để nguyên.
///
/// Mọi đoạn gọi từ Swift (`enableCall`…) luôn trả giá trị khác `undefined`/`null`: lớp `Result` của
/// `evaluateJavaScript(_:in:in:completionHandler:)` có thể crash khi không nhận được cả kết quả lẫn lỗi.
enum BrowserPageTranslateScript {
    static let contentWorld = WKContentWorld.world(name: "FreeBookPageTranslate")

    static func userScript() -> WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: contentWorld)
    }

    /// Controller đã có script này chưa (chống cài trùng khi `ObjectIdentifier` của controller cũ bị tái dùng).
    static func isInstalled(in controller: WKUserContentController) -> Bool {
        controller.userScripts.contains { $0.source == source }
    }

    /// Script chưa kịp chạy trong document mới ⇒ để cờ chờ, script đọc cờ khi cài xong.
    static let enableCall = """
    (function () { var api = window.__fbPageTranslate; if (api) { api.enable(); } else { window.__fbPageTranslatePending = true; } return true; })()
    """

    static let disableCall = """
    (function () { window.__fbPageTranslatePending = false; var api = window.__fbPageTranslate; if (api) { api.disable(); } return true; })()
    """

    /// Trả **chuỗi JSON** `{text, source, link}` (không bao giờ `null`): vùng chọn rỗng ⇒ `text` rỗng.
    static let selectionInfoCall = #"""
    (function () {
        var empty = JSON.stringify({ text: "", source: "", link: "" });
        try {
            var sel = window.getSelection ? window.getSelection() : null;
            var text = sel ? String(sel.toString()) : "";
            if (!text.trim()) { return empty; }
            var api = window.__fbPageTranslate;
            var source = api ? api.sourceTextForSelection() : text;
            function linkOf(node) {
                var el = node && (node.nodeType === 1 ? node : node.parentElement);
                var a = el && el.closest ? el.closest("a[href]") : null;
                return a && a.href ? String(a.href) : "";
            }
            var link = linkOf(sel.anchorNode) || linkOf(sel.focusNode);
            return JSON.stringify({ text: text, source: source || text, link: link });
        } catch (e) {
            return empty;
        }
    })()
    """#

    private static let source = #"""
    (function () {
        if (window.__fbPageTranslateInstalled) { return; }
        try {
            Object.defineProperty(window, "__fbPageTranslateInstalled", { value: true, enumerable: false });
        } catch (e) {
            return;
        }
        var handlers = window.webkit && window.webkit.messageHandlers;
        var bridge = handlers && handlers.fbPageTranslate;
        var HAN = /[\u3400-\u9fff]/;
        var SKIP_ALL = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1 };
        var SKIP_TEXT = { TEXTAREA: 1, INPUT: 1, SELECT: 1, CODE: 1 };
        var SKIP_SELECTOR = "script,style,noscript,textarea,select,code,[contenteditable]";
        var ATTRS = ["title", "alt", "placeholder"];
        var MAX_ITEMS = 120, MAX_CHARS = 12000;

        var enabled = false, waiting = false, inflight = false, generation = 0;
        var observer = null, scanTimer = 0, pumpTimer = 0;
        var queue = [], pendingRoots = new Set();
        var originals = new WeakMap(), written = new WeakMap(), pendingText = new WeakMap();
        var attrOriginals = new WeakMap(), attrWritten = new WeakMap(), pendingAttr = new WeakMap();
        var tracked = new Set(), attrTracked = new Set();

        function isSpace(c) {
            return c === 32 || c === 9 || c === 10 || c === 13 || c === 12 || c === 160 || c === 0x3000;
        }

        function split(value) {
            var s = 0, e = value.length;
            while (s < e && isSpace(value.charCodeAt(s))) { s++; }
            while (e > s && isSpace(value.charCodeAt(e - 1))) { e--; }
            return [value.slice(0, s), value.slice(s, e), value.slice(e)];
        }

        function enqueueText(node) {
            var value = node.nodeValue;
            if (!value || !HAN.test(value)) { return; }
            if (written.get(node) === value || pendingText.get(node) === value) { return; }
            var parts = split(value);
            if (!parts[1]) { return; }
            pendingText.set(node, value);
            queue.push({ kind: 0, node: node, source: value, lead: parts[0], core: parts[1], trail: parts[2] });
        }

        function collectAttributes(el) {
            for (var i = 0; i < ATTRS.length; i++) {
                var name = ATTRS[i];
                var value = el.getAttribute(name);
                if (!value || !HAN.test(value)) { continue; }
                var done = attrWritten.get(el);
                if (done && done[name] === value) { continue; }
                var pend = pendingAttr.get(el);
                if (pend && pend[name] === value) { continue; }
                var parts = split(value);
                if (!parts[1]) { continue; }
                if (!pend) { pend = {}; pendingAttr.set(el, pend); }
                pend[name] = value;
                queue.push({ kind: 1, node: el, attr: name, source: value, lead: parts[0], core: parts[1], trail: parts[2] });
            }
        }

        // false ⇒ không duyệt con. Ô nhập/khối code bỏ chữ nhưng vẫn dịch `placeholder`/`title`.
        function visitElement(el) {
            var name = String(el.nodeName).toUpperCase();
            if (SKIP_ALL[name]) { return false; }
            collectAttributes(el);
            return !(SKIP_TEXT[name] || el.hasAttribute("contenteditable"));
        }

        function scanRoot(root) {
            var body = document.body;
            if (!root || !body || !root.isConnected || !body.contains(root)) { return; }
            if (root.nodeType === 3) {
                var parent = root.parentElement;
                if (parent && !parent.closest(SKIP_SELECTOR)) { enqueueText(root); }
                return;
            }
            if (root.nodeType !== 1) { return; }
            if (root !== body && root.parentElement && root.parentElement.closest(SKIP_SELECTOR)) { return; }
            if (!visitElement(root)) { return; }
            var walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
                acceptNode: function (node) {
                    if (node.nodeType === 3) { return NodeFilter.FILTER_ACCEPT; }
                    return visitElement(node) ? NodeFilter.FILTER_SKIP : NodeFilter.FILTER_REJECT;
                }
            });
            var node;
            while ((node = walker.nextNode())) { enqueueText(node); }
        }

        function prune() {
            tracked.forEach(function (node) { if (!node.isConnected) { tracked.delete(node); } });
            attrTracked.forEach(function (el) { if (!el.isConnected) { attrTracked.delete(el); } });
        }

        function flushRoots() {
            scanTimer = 0;
            if (!enabled) { pendingRoots.clear(); return; }
            var roots = Array.from(pendingRoots);
            pendingRoots.clear();
            for (var i = 0; i < roots.length; i++) { scanRoot(roots[i]); }
            if (tracked.size + attrTracked.size > 4000) { prune(); }
            schedulePump();
        }

        function onMutations(records) {
            for (var i = 0; i < records.length; i++) {
                var record = records[i];
                if (record.type === "characterData") {
                    pendingRoots.add(record.target);
                } else {
                    for (var j = 0; j < record.addedNodes.length; j++) { pendingRoots.add(record.addedNodes[j]); }
                }
            }
            if (pendingRoots.size > 3000) {
                pendingRoots.clear();
                if (document.body) { pendingRoots.add(document.body); }
            }
            if (pendingRoots.size && !scanTimer) { scanTimer = setTimeout(flushRoots, 300); }
        }

        function stillValid(item) {
            if (!item.node.isConnected) { return false; }
            return item.kind === 0
                ? item.node.nodeValue === item.source
                : item.node.getAttribute(item.attr) === item.source;
        }

        function release(item) {
            if (item.kind === 0) {
                if (pendingText.get(item.node) === item.source) { pendingText.delete(item.node); }
                return;
            }
            var pend = pendingAttr.get(item.node);
            if (pend && pend[item.attr] === item.source) { delete pend[item.attr]; }
        }

        function apply(batch, result) {
            if (observer) { onMutations(observer.takeRecords()); }
            for (var i = 0; i < batch.length; i++) {
                var item = batch[i], out = result[i];
                if (typeof out !== "string" || !out || !stillValid(item)) { continue; }
                var text = item.lead + out + item.trail;
                if (text === item.source) { continue; }
                if (item.kind === 0) {
                    originals.set(item.node, item.source);
                    written.set(item.node, text);
                    tracked.add(item.node);
                    item.node.nodeValue = text;
                } else {
                    var origs = attrOriginals.get(item.node) || {};
                    var done = attrWritten.get(item.node) || {};
                    origs[item.attr] = item.source;
                    done[item.attr] = text;
                    attrOriginals.set(item.node, origs);
                    attrWritten.set(item.node, done);
                    attrTracked.add(item.node);
                    item.node.setAttribute(item.attr, text);
                }
            }
            if (observer) { observer.takeRecords(); }
        }

        function schedulePump() {
            if (!pumpTimer) { pumpTimer = setTimeout(pump, 0); }
        }

        function pump() {
            pumpTimer = 0;
            if (!enabled || inflight || !queue.length || !bridge) { return; }
            var batch = [], texts = [], chars = 0;
            while (queue.length && batch.length < MAX_ITEMS) {
                var item = queue[0];
                if (!stillValid(item)) { queue.shift(); release(item); continue; }
                if (batch.length && chars + item.core.length > MAX_CHARS) { break; }
                queue.shift();
                batch.push(item);
                texts.push(item.core);
                chars += item.core.length;
            }
            if (!batch.length) { return; }
            inflight = true;
            var gen = generation;
            var finish = function () {
                inflight = false;
                for (var i = 0; i < batch.length; i++) { release(batch[i]); }
                if (enabled) { schedulePump(); }
            };
            try {
                bridge.postMessage({ texts: texts }).then(function (result) {
                    try {
                        if (gen === generation && enabled && Array.isArray(result) && result.length === batch.length) {
                            apply(batch, result);
                        }
                    } catch (e) {}
                    finish();
                }, finish);
            } catch (e) {
                finish();
            }
        }

        function start() {
            waiting = false;
            if (!enabled || !document.body) { return; }
            if (!observer) {
                try {
                    observer = new MutationObserver(onMutations);
                    observer.observe(document.documentElement, { childList: true, characterData: true, subtree: true });
                } catch (e) {
                    observer = null;
                }
            }
            scanRoot(document.body);
            schedulePump();
        }

        function enable() {
            if (enabled) { return true; }
            enabled = true;
            generation++;
            if (document.readyState === "loading") {
                if (!waiting) {
                    waiting = true;
                    document.addEventListener("DOMContentLoaded", start, { once: true });
                }
            } else {
                start();
            }
            return true;
        }

        function disable() {
            enabled = false;
            generation++;
            queue = [];
            pendingRoots.clear();
            if (scanTimer) { clearTimeout(scanTimer); scanTimer = 0; }
            if (observer) { observer.disconnect(); observer = null; }
            tracked.forEach(function (node) {
                var orig = originals.get(node);
                if (orig !== undefined && node.nodeValue === written.get(node)) { node.nodeValue = orig; }
                originals.delete(node);
                written.delete(node);
            });
            attrTracked.forEach(function (el) {
                var origs = attrOriginals.get(el) || {}, done = attrWritten.get(el) || {};
                Object.keys(origs).forEach(function (name) {
                    if (el.getAttribute(name) === done[name]) { el.setAttribute(name, origs[name]); }
                });
                attrOriginals.delete(el);
                attrWritten.delete(el);
            });
            tracked.clear();
            attrTracked.clear();
            pendingText = new WeakMap();
            pendingAttr = new WeakMap();
            return true;
        }

        function sourceTextForSelection() {
            var sel = window.getSelection ? window.getSelection() : null;
            if (!sel || !sel.rangeCount) { return ""; }
            var plain = String(sel.toString());
            var parts = [], visited = 0;
            function take(node) {
                var orig = originals.get(node);
                if (orig !== undefined && node.nodeValue === written.get(node)) {
                    var trimmed = orig.trim();
                    if (trimmed) { parts.push(trimmed); }
                }
            }
            for (var r = 0; r < sel.rangeCount; r++) {
                var range = sel.getRangeAt(r);
                var root = range.commonAncestorContainer;
                if (root.nodeType === 3) { take(root); continue; }
                // Đi từ đầu vùng chọn tới hết vùng chọn (không quét từ đầu tổ tiên chung: trang dài hết trần trước
                // khi tới vùng chọn ⇒ trả nhầm chữ đã dịch).
                var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                var start = range.startContainer;
                if (start.nodeType === 3) { take(start); }
                walker.currentNode = start;
                var node;
                while ((node = walker.nextNode()) && visited < 20000) {
                    visited++;
                    if (range.comparePoint(node, 0) > 0) { break; }
                    if (range.intersectsNode(node)) { take(node); }
                }
            }
            return parts.length ? parts.join("\n") : plain;
        }

        window.__fbPageTranslate = {
            enable: enable,
            disable: disable,
            isEnabled: function () { return enabled; },
            sourceTextForSelection: sourceTextForSelection
        };
        if (window.__fbPageTranslatePending) {
            window.__fbPageTranslatePending = false;
            enable();
        }
    })();
    """#
}
