import Foundation

/// **Nơi duy nhất** chứa hợp đồng với trang Chế độ AI của Google (`google.com/search?udm=50`, 1.3.609): URL, selector,
/// chuỗi trạng thái/lỗi của trang, mã JS chạy trong trang và cách làm sạch câu trả lời. Google đổi cấu trúc thì sửa đúng
/// file này; lỗi hiện ra là `GoogleAIModeError.protocolChanged(<vị trí>)`.
///
/// Đã thử thật 2026-10-26 (Chrome desktop + giả lập Android, chưa đăng nhập, `hl=vi`):
/// - phản hồi là **mảnh HTML** server-render, không phải JSON ⇒ app đọc DOM, không tự gọi `/async/folwr|folif`;
/// - mỗi lượt là một `[data-scope-id="turn"]`, phần trả lời nằm trong `[data-subtree="aimc"]`, tiêu đề ẩn lặp lại câu hỏi
///   có `data-ignore-copy`, token nối tiếp ở `data-mstk` (và tham số `mstk` của URL);
/// - mở `search?udm=50&mstk=<token mới nhất>` hiện lại đủ các lượt cũ nhưng **không** gửi `q` ⇒ lượt nối tiếp gửi qua ô
///   nhập ("Hỏi bất cứ điều gì", `maxlength=8192`) bằng sự kiện JS thuần — Google nhận;
/// - chữ trạng thái/lỗi phụ thuộc ngôn ngữ ⇒ luôn ép `hl=vi`. Trang khôi phục còn chữ lỗi/"sẵn sàng" của lượt cũ ⇒ mọi
///   phát hiện chỉ xét **lượt mới nhất**.
enum GoogleAIModePageContract {
    static let host = "https://www.google.com"
    static let readyStatusText = "Chế độ AI đã sẵn sàng trả lời"
    static let generationErrorText = "Đã xảy ra lỗi nên không tạo được nội dung"
    static let composerLabel = "Hỏi bất cứ điều gì"
    static let sendButtonLabel = "Gửi"
    /// Đoạn cuối mở đầu bằng các cụm này là câu gợi ý hỏi tiếp của Google, không phải câu trả lời.
    static let suggestionPrefixes = ["Bạn có muốn", "Bạn có cần", "Nếu bạn cần", "Nếu bạn muốn", "Bạn muốn tôi"]
    /// Nhãn do `GeminiWebPromptFormatter` dựng — thấy trong phần trích ra nghĩa là đã đọc nhầm cả câu hỏi (dòng mẫu
    /// `Tên gốc=Nghĩa` hay từ điển `原=Nghĩa` của khối ngữ cảnh sẽ thành name rác).
    static let promptEchoLabels = ["### Hướng dẫn hệ thống", "### Lượt hiện tại", "### Cập nhật ngữ cảnh"]

    /// Ảnh chụp trạng thái trang mỗi nhịp đọc.
    struct Snapshot: Sendable {
        let turnCount: Int
        /// Chữ của phần trả lời trong lượt mới nhất (đã bỏ phần ẩn, nút, câu hỏi lặp lại). Rỗng khi lượt chưa có khối
        /// `[data-subtree="aimc"]` — **không** đọc cả khối lượt (sẽ dính câu hỏi của người dùng).
        let newestText: String
        let answerFound: Bool
        let newestHasError: Bool
        let readyStatus: Bool
        let composerFound: Bool
        let mstk: String
        let path: String
        let bodyLength: Int
        let scriptError: String?

        init?(_ raw: Any?) {
            guard let dict = raw as? [String: Any] else { return nil }
            turnCount = (dict["turnCount"] as? NSNumber)?.intValue ?? 0
            newestText = dict["text"] as? String ?? ""
            answerFound = (dict["answerFound"] as? Bool) ?? false
            newestHasError = (dict["hasError"] as? Bool) ?? false
            readyStatus = (dict["ready"] as? Bool) ?? false
            composerFound = (dict["composer"] as? Bool) ?? false
            mstk = dict["mstk"] as? String ?? ""
            path = dict["path"] as? String ?? ""
            bodyLength = (dict["bodyLength"] as? NSNumber)?.intValue ?? 0
            scriptError = dict["error"] as? String
        }
    }

    // MARK: - URL

    /// Lượt mới (cuộc chat mới): câu hỏi nằm trong `q`.
    static func freshURL(prompt: String) -> URL? {
        URL(string: "\(host)/search?udm=50&hl=vi&q=\(encodeQueryValue(prompt))")
    }

    /// Mở lại cuộc chat cũ: hiện đủ các lượt, không gửi gì.
    static func restoreURL(mstk: String) -> URL? {
        URL(string: "\(host)/search?udm=50&hl=vi&mstk=\(encodeQueryValue(mstk))&csuir=1")
    }

    /// Trang mở trong trình duyệt bypass để người dùng giải captcha.
    static let verificationURL = URL(string: "\(host)/search?udm=50&hl=vi")!

    static func isVerificationPage(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased(), host.contains("google.") else { return false }
        return isVerificationPath(url.path)
    }

    /// Đường dẫn của trang hiện tại (từ `Snapshot.path`) là trang xác minh `/sorry`.
    static func isVerificationPath(_ path: String) -> Bool {
        path.hasPrefix("/sorry")
    }

    /// Mã hoá chặt (chỉ giữ ký tự unreserved) — `URLComponents` để nguyên `+` mà Google đọc thành dấu cách.
    static func encodeQueryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Số byte của chuỗi sau khi percent-encode — đơn vị của giới hạn độ dài URL (chữ Hán ≈ 9 byte).
    static func encodedLength(_ value: String) -> Int {
        encodeQueryValue(value).utf8.count
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Chỉ host + path cho log: query mang cả chương truyện và `mstk`.
    static func describe(_ url: URL?) -> String {
        guard let url else { return "-" }
        return "\(url.host ?? "-")\(url.path)"
    }

    // MARK: - Làm sạch câu trả lời

    /// Bỏ khoảng trắng thừa và câu gợi ý hỏi tiếp ở cuối.
    static func cleanAnswer(_ raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        if let last = lines.last?.trimmingCharacters(in: .whitespaces),
           suggestionPrefixes.contains(where: { last.hasPrefix($0) }) {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Phần phát dần trong lúc trang còn đang viết: chỉ các dòng đã trọn (đến dấu xuống dòng cuối), để câu gợi ý cuối
    /// chưa kịp hiện đủ không lọt ra trước khi bị cắt. Bỏ khoảng trắng/xuống dòng ở **cuối** — `cleanAnswer` cũng cắt
    /// chúng, nên bản cuối luôn nối tiếp phần đã phát (không thì "A\n" đã phát mà bản cuối là "A" ⇒ cả câu bị nối lại).
    static func streamablePrefix(_ raw: String) -> String {
        guard let lastBreak = raw.lastIndex(of: "\n") else { return "" }
        var prefix = raw[..<lastBreak]
        while let last = prefix.last, last.isWhitespace {
            prefix.removeLast()
        }
        return String(prefix)
    }

    static func containsPromptEcho(_ text: String) -> Bool {
        promptEchoLabels.contains { text.contains($0) }
    }

    // MARK: - JavaScript

    /// Đọc trạng thái trang. Chữ của lượt lấy bằng cách duyệt cây DOM thật (không clone, không chèn node — tránh đánh
    /// thức observer của trang): bỏ phần `display:none`, `[data-ignore-copy]`, thẻ `BUTTON` (chip trích dẫn nguồn), svg;
    /// khối ⇒ xuống dòng, `li` ⇒ "- ". **Không** bỏ `[role="button"]`: tên thực thể trong câu trả lời là
    /// `<span role="button">` (thử thật: bỏ thì "Dân số thành phố Paris…" mất chữ "Paris").
    static let snapshotScript = jsPrelude + #"""
    (function () {
      var out = { turnCount: 0, text: "", answerFound: false, hasError: false, ready: false, composer: false, mstk: "", path: location.pathname, bodyLength: 0 };
      try {
        out.bodyLength = ((document.body && document.body.innerText) || "").length;
        var turns = document.querySelectorAll('[data-scope-id="turn"]');
        out.turnCount = turns.length;
        var lives = document.querySelectorAll('[aria-live]');
        for (var i = 0; i < lives.length; i++) {
          if ((lives[i].textContent || "").trim() === __READY) { out.ready = true; break; }
        }
        out.composer = !!__findComposer();
        var marks = document.querySelectorAll('[data-mstk]');
        if (marks.length) { out.mstk = marks[marks.length - 1].getAttribute('data-mstk') || ""; }
        if (!out.mstk) { try { out.mstk = new URL(location.href).searchParams.get('mstk') || ""; } catch (e) {} }
        if (turns.length) {
          var newest = turns[turns.length - 1];
          out.hasError = (newest.innerText || "").indexOf(__FAILED) >= 0;
          var answer = newest.querySelector('[data-subtree="aimc"]');
          out.answerFound = !!answer;
          out.text = answer ? __collectText(answer) : "";
        }
      } catch (e) { out.error = String(e); }
      return out;
    })();
    """#

    /// Gán câu hỏi vào ô nhập (setter gốc + sự kiện `input` để trang bật nút gửi). `nil` khi không mã hoá được chữ.
    static func fillComposerScript(_ text: String) -> String? {
        guard let data = try? JSONEncoder().encode(text), let literal = String(data: data, encoding: .utf8) else { return nil }
        return jsPrelude + #"""
        (function (text) {
          var t = __findComposer();
          if (!t) { return false; }
          var setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
          t.focus();
          setter.call(t, text);
          t.dispatchEvent(new Event('input', { bubbles: true }));
          return true;
        })(\#(literal));
        """#
    }

    /// Nhấn Enter trong ô nhập — cách gửi đã thử được trên Chrome.
    static let pressEnterScript = jsPrelude + #"""
    (function () {
      var t = __findComposer();
      if (!t) { return false; }
      t.focus();
      var o = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
      t.dispatchEvent(new KeyboardEvent('keydown', o));
      t.dispatchEvent(new KeyboardEvent('keypress', o));
      t.dispatchEvent(new KeyboardEvent('keyup', o));
      return true;
    })();
    """#

    /// Dự phòng khi Enter không tạo lượt mới: bấm nút "Gửi" đang hiện và bật.
    static let clickSendScript = jsPrelude + #"""
    (function () {
      var list = document.querySelectorAll('button, [role="button"]');
      for (var i = 0; i < list.length; i++) {
        var b = list[i];
        if (b.getAttribute('aria-label') !== __SEND) { continue; }
        if (b.getClientRects().length === 0 || b.disabled || b.getAttribute('aria-disabled') === 'true') { continue; }
        b.click();
        return true;
      }
      return false;
    })();
    """#

    /// Hàm dùng chung cho mọi script trên — khai lại mỗi lần chạy (trang có thể đã nạp document mới).
    private static let jsPrelude = """
    var __READY = "\(readyStatusText)";
    var __FAILED = "\(generationErrorText)";
    var __COMPOSER = "\(composerLabel)";
    var __SEND = "\(sendButtonLabel)";
    """ + #"""

    function __findComposer() {
      var list = document.querySelectorAll('textarea');
      var fallback = null;
      for (var i = 0; i < list.length; i++) {
        var t = list[i];
        if (t.getClientRects().length === 0) { continue; }
        if (t.getAttribute('aria-label') === __COMPOSER) { return t; }
        if (!fallback && parseInt(t.getAttribute('maxlength') || '0', 10) >= 4096) { fallback = t; }
      }
      return fallback;
    }
    function __collectText(root) {
      var parts = [];
      var skip = { BUTTON: 1, SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEXTAREA: 1, INPUT: 1, TEMPLATE: 1, svg: 1, SVG: 1 };
      function walk(n) {
        if (n.nodeType === 3) { parts.push(n.nodeValue.replace(/\s+/g, ' ')); return; }
        if (n.nodeType !== 1) { return; }
        if (skip[n.tagName] || n.hasAttribute('data-ignore-copy')) { return; }
        var cs = window.getComputedStyle(n);
        if (cs.display === 'none' || cs.visibility === 'hidden') { return; }
        if (n.tagName === 'BR') { parts.push('\n'); return; }
        var block = /^(block|flex|grid|list-item|table)/.test(cs.display);
        if (block) { parts.push('\n'); }
        if (n.tagName === 'LI') { parts.push('- '); }
        if (/^H[1-6]$/.test(n.tagName)) { parts.push('### '); }
        for (var c = n.firstChild; c; c = c.nextSibling) { walk(c); }
        if (block) { parts.push('\n'); }
      }
      walk(root);
      return parts.join('').replace(/[ \t]+\n/g, '\n').replace(/\n[ \t]+/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
    }

    """#
}
