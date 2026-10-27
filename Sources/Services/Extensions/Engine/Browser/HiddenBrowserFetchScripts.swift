import Foundation

/// Hai đoạn JS mà `HiddenBrowserFetch` chạy trong trang (thế giới `page`, thấy được biến toàn cục của trang).
enum HiddenBrowserFetchScripts {
    /// Dò nhẹ mỗi nhịp — **không** tuần tự hoá cả DOM. Trả object (WebKit chuyển thành `[String: Any]`), lỗi ⇒ `null`:
    /// - `ready`: `readyState` ≠ "loading" (DOM đã dựng xong, không cần chờ ảnh/quảng cáo);
    /// - `empty`: HTML ⇒ không có `body` hoặc `body` không có phần tử con lẫn chữ; khác HTML ⇒ không có chữ;
    /// - `block`: "cloudflare" khi có `_cf_chl_opt`, phần tử/script `cf-chl`, `#challenge-form`, `.cf-browser-verification`
    ///   hoặc tiêu đề "Just a moment" / "Attention Required"; "generic" khi tiêu đề "Please Wait" / "Checking your browser"
    ///   / "DDoS-Guard";
    /// - `challengeScript`: có script `challenge-platform` (Swift chỉ tính là trang chặn khi status ≥ 400);
    /// - `interstitial`: trang chờ — dưới 64 ký tự chữ thấy được, dưới 3 ảnh, có script hoặc meta refresh.
    static let probe = #"""
    (function () {
      try {
        var d = document, b = d.body, root = d.documentElement;
        var ct = String(d.contentType || "").toLowerCase();
        var res = { ready: d.readyState !== "loading", empty: true, block: "", challengeScript: false, interstitial: false };
        if (ct.indexOf("html") < 0) {
          var raw = b ? (b.textContent || "") : (root ? (root.textContent || "") : "");
          res.empty = raw.trim().length === 0;
          return res;
        }
        res.empty = !b || (b.children.length === 0 && String(b.textContent || "").trim().length === 0);
        var title = String(d.title || "").toLowerCase();
        var cf = !!window._cf_chl_opt ||
          !!d.querySelector('#challenge-form,.cf-browser-verification,[id^="cf-chl"],[class*="cf-chl"]');
        var scripts = d.scripts;
        for (var i = 0; i < scripts.length && i < 200; i++) {
          var src = String(scripts[i].src || "").toLowerCase();
          var text = src ? "" : String(scripts[i].textContent || "").slice(0, 4096).toLowerCase();
          if (src.indexOf("cf-chl") >= 0 || text.indexOf("cf_chl_opt") >= 0 || text.indexOf("cf-chl") >= 0) { cf = true; }
          if (src.indexOf("challenge-platform") >= 0 || text.indexOf("challenge-platform") >= 0) { res.challengeScript = true; }
        }
        if (cf || title.indexOf("just a moment") >= 0 || title.indexOf("attention required") >= 0) {
          res.block = "cloudflare";
        } else if (title.indexOf("please wait") >= 0 || title.indexOf("checking your browser") >= 0 ||
                   title.indexOf("ddos-guard") >= 0) {
          res.block = "generic";
        }
        var n = 0;
        if (b) {
          var walker = d.createTreeWalker(b, 4, null), node;
          while (n < 64 && (node = walker.nextNode())) {
            var parent = node.parentNode ? node.parentNode.nodeName : "";
            if (parent !== "SCRIPT" && parent !== "STYLE" && parent !== "NOSCRIPT" && parent !== "TEMPLATE") {
              n += String(node.nodeValue || "").trim().length;
            }
          }
        }
        var refresh = !!d.querySelector('meta[http-equiv="refresh" i]');
        res.interstitial = n < 64 && d.images.length < 3 && (scripts.length > 0 || refresh);
        return res;
      } catch (e) {
        return null;
      }
    })()
    """#

    /// Đọc nội dung một lần lúc kết luận. HTML ⇒ `outerHTML` (trừ khi thân chỉ có chữ và `head` rỗng — JSON/text bị gắn
    /// nhãn text/html — thì `body.textContent`); khác HTML (JSON, text — WebKit bọc trong `<pre>`) ⇒ `body.innerText`;
    /// tài liệu XML (không có `body`) ⇒ `XMLSerializer`.
    static let content = #"""
    (function () {
      try {
        var d = document, b = d.body, root = d.documentElement;
        var ct = String(d.contentType || "").toLowerCase();
        var c = "";
        var head = d.head;
        if (ct.indexOf("html") >= 0 && b && b.children.length === 0 && (!head || head.children.length === 0)) {
          // JSON/text bị máy chủ gắn nhãn text/html: thân chỉ có chữ, head rỗng ⇒ trả chữ thô, không bọc thẻ.
          c = b.textContent || "";
        } else if (ct.indexOf("html") >= 0) {
          c = root ? root.outerHTML : "";
        } else if (b) {
          c = b.innerText || b.textContent || "";
        } else if (root) {
          c = new XMLSerializer().serializeToString(d);
        }
        return { content: String(c || ""), contentType: ct, characterSet: String(d.characterSet || ""),
                 url: String(location.href || "") };
      } catch (e) {
        return null;
      }
    })()
    """#
}
