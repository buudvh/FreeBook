import Foundation
import WebKit

/// Nguồn `WKUserScript` bắt **mọi request mạng** của trang (XHR, `fetch`, phần tử media, Resource Timing) và báo URL
/// tuyệt đối về native qua message handler `fbNetCapture`, để `browser.urls()` / `waitUrl` của ext thấy được cả request
/// không phải điều hướng (hợp đồng VBook: "mọi URL đã request kể từ lần launch cuối"). `VideoMediaSniffer` dùng lại
/// cùng script để dò link m3u8/mp4.
///
/// Script chạy `atDocumentStart`, `forMainFrameOnly: false` nên vào cả iframe (player nhúng thường nằm trong iframe).
/// Khử trùng phía JS theo từng frame; native vẫn khử trùng lần nữa vì nhiều frame có thể báo cùng một URL.
enum WebNetworkCaptureScript {
    static let handlerName = "fbNetCapture"
    /// URL dài hơn mức này (thường là query nhồi dữ liệu) bị bỏ, không lưu.
    static let maxUrlLength = 4096

    /// Cài handler + script bắt request vào `controller`. `mediaMode` (chỉ ext video và sniffer, đi cùng autoplay):
    /// thêm hook chủ động XHR/fetch/media (xem `captureSource(patchesNatives:)`) và script ép mọi media tắt tiếng;
    /// `playMediaOnLoad` thêm việc thử `play()` mọi `<video>` sau khi frame tải xong.
    /// `onRequest(url, frameURL)` chạy trên main thread; closure phải `[weak self]` (xem `WebNetworkCaptureMessageProxy`).
    static func install(
        into controller: WKUserContentController,
        mediaMode: Bool,
        playMediaOnLoad: Bool = false,
        onRequest: @escaping (String, URL?) -> Void
    ) {
        // Thêm trùng tên handler là WebKit ném exception ⇒ gỡ trước cho chắc.
        controller.removeScriptMessageHandler(forName: handlerName)
        controller.add(WebNetworkCaptureMessageProxy(onRequest: onRequest), name: handlerName)
        let capture = captureSource(patchesNatives: mediaMode)
        controller.addUserScript(WKUserScript(source: capture, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        if mediaMode {
            let source = mutedMediaSource(playOnLoad: playMediaOnLoad)
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
    }

    /// Chỉ nhận URL http(s) có độ dài hợp lý; `blob:`/`data:`/`about:` không có ý nghĩa với ext.
    static func isRecordable(_ url: String) -> Bool {
        guard !url.isEmpty, url.utf16.count <= maxUrlLength else { return false }
        let lower = url.prefix(8).lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// Luật khớp của `waitUrl`: như VBook, mẫu là **regex khớp toàn bộ URL**; giữ thêm luật cũ của FreeBook (URL chứa
    /// nguyên văn mẫu) để ext đang truyền chuỗi con không bị hỏng. Mẫu không phải regex hợp lệ thì chỉ dùng luật cũ.
    static func url(_ url: String, matchesWaitPattern pattern: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        if url.contains(pattern) { return true }
        guard let regex = wholeMatchRegex(for: pattern) else { return false }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        return regex.firstMatch(in: url, options: [], range: range) != nil
    }

    private static let regexCache = NSCache<NSString, AnyObject>()

    /// Regex `^(?:mẫu)$` đã biên dịch, cache theo mẫu; mẫu lỗi được cache bằng `NSNull` để khỏi biên dịch lại.
    private static func wholeMatchRegex(for pattern: String) -> NSRegularExpression? {
        let key = pattern as NSString
        if let cached = regexCache.object(forKey: key) {
            return cached as? NSRegularExpression
        }
        guard let compiled = try? NSRegularExpression(pattern: "^(?:" + pattern + ")$", options: []) else {
            regexCache.setObject(NSNull(), forKey: key)
            return nil
        }
        regexCache.setObject(compiled, forKey: key)
        return compiled
    }

    /// Bắt **thụ động** (Resource Timing, quét DOM, sự kiện `loadstart`) luôn bật — không sửa prototype nào nên trang
    /// chống bot (captcha/Cloudflare ở browser hiện) không phát hiện được. `patchesNatives` thêm hook **chủ động**
    /// XHR/`fetch`/`src`/`setAttribute` để thấy request ngay lúc bắt đầu (Resource Timing chỉ báo khi tải xong — luồng
    /// mp4 dài có thể không bao giờ xong); chỉ bật cho ext video và sniffer.
    static func captureSource(patchesNatives: Bool) -> String {
        captureTemplate.replacingOccurrences(of: "__FB_PATCH_NATIVES__", with: patchesNatives ? "true" : "false")
    }

    /// Mỗi URL tuyệt đối http(s) gửi đúng một lần mỗi frame.
    private static let captureTemplate = #"""
    (function () {
        if (window.__fbNetCaptureInstalled) { return; }
        try {
            Object.defineProperty(window, "__fbNetCaptureInstalled", { value: true, enumerable: false });
        } catch (e) {
            return;
        }
        var handlers = window.webkit && window.webkit.messageHandlers;
        var bridge = handlers && handlers.fbNetCapture;
        if (!bridge) { return; }
        var patchNatives = __FB_PATCH_NATIVES__;
        var seen = Object.create(null);
        var seenCount = 0;
        var maxSeen = 3000;

        function isMediaNode(node) {
            return (window.HTMLMediaElement && node instanceof HTMLMediaElement)
                || (window.HTMLSourceElement && node instanceof HTMLSourceElement);
        }

        function report(raw) {
            try {
                if (raw === null || raw === undefined) { return; }
                if (typeof raw === "object" && typeof raw.url === "string") { raw = raw.url; }
                var text = String(raw);
                if (!text || text.length > 4096) { return; }
                var href = new URL(text, location.href).href;
                if (href.indexOf("http://") !== 0 && href.indexOf("https://") !== 0) { return; }
                if (seen[href] || seenCount >= maxSeen) { return; }
                seen[href] = true;
                seenCount += 1;
                bridge.postMessage(href);
            } catch (e) {}
        }

        function hookSrc(proto) {
            try {
                var desc = Object.getOwnPropertyDescriptor(proto, "src");
                if (!desc || typeof desc.set !== "function") { return; }
                Object.defineProperty(proto, "src", {
                    configurable: true,
                    enumerable: desc.enumerable,
                    get: desc.get,
                    set: function (value) {
                        report(value);
                        return desc.set.call(this, value);
                    }
                });
            } catch (e) {}
        }

        function installActiveHooks() {
            try {
                var nativeOpen = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function (method, url) {
                    report(url);
                    return nativeOpen.apply(this, arguments);
                };
            } catch (e) {}

            try {
                if (typeof window.fetch === "function") {
                    var nativeFetch = window.fetch;
                    window.fetch = function (input) {
                        report(input);
                        return nativeFetch.apply(this, arguments);
                    };
                }
            } catch (e) {}

            if (window.HTMLMediaElement) { hookSrc(HTMLMediaElement.prototype); }
            if (window.HTMLSourceElement) { hookSrc(HTMLSourceElement.prototype); }

            try {
                var nativeSetAttribute = Element.prototype.setAttribute;
                Element.prototype.setAttribute = function (name, value) {
                    try {
                        if (String(name).toLowerCase() === "src" && isMediaNode(this)) { report(value); }
                    } catch (e) {}
                    return nativeSetAttribute.apply(this, arguments);
                };
            } catch (e) {}
        }
        if (patchNatives) { installActiveHooks(); }

        function scanMedia() {
            try {
                var nodes = document.querySelectorAll("video, audio, source");
                for (var i = 0; i < nodes.length; i++) {
                    var node = nodes[i];
                    report(node.currentSrc || node.src || node.getAttribute("src"));
                }
            } catch (e) {}
        }

        document.addEventListener("loadstart", function (event) {
            var target = event.target;
            if (target && isMediaNode(target)) { report(target.currentSrc || target.src); }
        }, true);
        document.addEventListener("DOMContentLoaded", scanMedia);
        window.addEventListener("load", scanMedia);

        try {
            if (window.PerformanceObserver) {
                var observer = new PerformanceObserver(function (list) {
                    var entries = list.getEntries();
                    for (var i = 0; i < entries.length; i++) { report(entries[i].name); }
                });
                observer.observe({ type: "resource", buffered: true });
            }
        } catch (e) {}
    })();
    """#

    /// Ép mọi media tắt tiếng + phát inline (autoplay chỉ được phép khi tắt tiếng); tuỳ chọn thử `play()` sau `load`.
    static func mutedMediaSource(playOnLoad: Bool) -> String {
        #"""
        (function () {
            if (window.__fbMutedMediaInstalled) { return; }
            window.__fbMutedMediaInstalled = true;
            if (!window.HTMLMediaElement) { return; }

            function mute(node) {
                try {
                    node.muted = true;
                    node.defaultMuted = true;
                    node.setAttribute("muted", "");
                    node.setAttribute("playsinline", "");
                } catch (e) {}
            }

            try {
                var nativePlay = HTMLMediaElement.prototype.play;
                HTMLMediaElement.prototype.play = function () {
                    mute(this);
                    return nativePlay.apply(this, arguments);
                };
            } catch (e) {}

            ["loadstart", "play", "volumechange"].forEach(function (type) {
                document.addEventListener(type, function (event) {
                    var target = event.target;
                    if (target instanceof HTMLMediaElement && !target.muted) { mute(target); }
                }, true);
            });

            var playOnLoad = \#(playOnLoad ? "true" : "false");
            if (!playOnLoad) { return; }
            window.addEventListener("load", function () {
                setTimeout(function () {
                    try {
                        var videos = document.querySelectorAll("video");
                        for (var i = 0; i < videos.length; i++) {
                            mute(videos[i]);
                            var pending = videos[i].play();
                            if (pending && typeof pending.catch === "function") { pending.catch(function () {}); }
                        }
                    } catch (e) {}
                }, 300);
            });
        })();
        """#
    }
}
