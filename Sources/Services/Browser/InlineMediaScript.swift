import Foundation
import WebKit

/// Script cho trình duyệt người dùng: gắn `playsinline` (+ `webkit-playsinline`) lên mọi `<video>` để chạm vào video
/// thì phát **tại chỗ**, không tự bung toàn màn hình (iPhone chỉ phát inline khi cấu hình bật
/// `allowsInlineMediaPlayback` **và** thẻ video có thuộc tính này — nhiều trang không khai). Nút toàn màn hình của
/// trang / trình phát vẫn dùng được khi người dùng chủ động bấm.
///
/// Chỉ **thụ động** (quét DOM, `MutationObserver`, nghe sự kiện ở pha capture), không sửa prototype nào — trang chống bot
/// không phát hiện được (cùng lý do `WebNetworkCaptureScript` để hook chủ động tắt với trình duyệt người dùng). Chạy
/// `atDocumentStart` ở mọi frame: player nhúng thường nằm trong iframe.
enum InlineMediaScript {
    static func install(into controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }

    private static let source = #"""
    (function () {
        if (window.__fbInlineMediaInstalled) { return; }
        try {
            Object.defineProperty(window, "__fbInlineMediaInstalled", { value: true, enumerable: false });
        } catch (e) {
            return;
        }

        function inline(node) {
            try {
                if (!node.hasAttribute("playsinline")) { node.setAttribute("playsinline", ""); }
                if (!node.hasAttribute("webkit-playsinline")) { node.setAttribute("webkit-playsinline", ""); }
            } catch (e) {}
        }

        function scan(root) {
            try {
                if (root.tagName === "VIDEO") { inline(root); }
                if (!root.querySelectorAll) { return; }
                var videos = root.querySelectorAll("video");
                for (var i = 0; i < videos.length; i++) { inline(videos[i]); }
            } catch (e) {}
        }

        try {
            new MutationObserver(function (records) {
                for (var i = 0; i < records.length; i++) {
                    var added = records[i].addedNodes;
                    for (var j = 0; j < added.length; j++) {
                        if (added[j].nodeType === 1) { scan(added[j]); }
                    }
                }
            }).observe(document, { childList: true, subtree: true });
        } catch (e) {}

        // Phòng video gắn trước khi observer kịp chạy, hoặc trang gọi `play()` ngay trong handler chạm.
        document.addEventListener("loadstart", function (event) {
            if (event.target && event.target.tagName === "VIDEO") { inline(event.target); }
        }, true);
        ["touchstart", "pointerdown", "click"].forEach(function (type) {
            document.addEventListener(type, function () { scan(document); }, true);
        });
        document.addEventListener("DOMContentLoaded", function () { scan(document); });
    })();
    """#
}
