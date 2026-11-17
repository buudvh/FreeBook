import Foundation

/// **Nơi duy nhất** chứa hợp đồng với trang ChatGPT (`chatgpt.com`, 1.3.971): URL, selector, mã JS chạy trong trang và
/// cách đọc câu trả lời — cho **cả hai** kiểu trang. ChatGPT đổi cấu trúc thì sửa đúng file này; lỗi hiện ra là
/// `ChatGPTWebError.protocolChanged(<vị trí>)`.
///
/// **Trang ẩn danh bản mobile** — đã thử thật 2026-11-17 (Chromium giả lập mobile, chưa đăng nhập, 5 tin):
/// - trang server-render riêng (`/unauth-mweb/…`), không phải app React của bản đăng nhập;
/// - ô nhập `textarea[data-mobile-composer-prompt]` (không `maxlength`; thử 12.166 ký tự gửi và trả lời được). Gán chữ
///   bằng setter gốc + sự kiện `input`; gửi bằng `form.requestSubmit(nút)` — nút `[data-composer-submit]` chỉ bật theo
///   khung hình vẽ (`requestAnimationFrame`), trang không được vẽ thì nút không bật nhưng `requestSubmit` vẫn gửi;
/// - nút gửi mang `aria-label` = `data-stop-label` trong lúc trả lời (chậm ~3 s mới trở lại sau khi xong);
/// - mỗi tin là `li[data-message-role="user|assistant"]`; tin trợ lý có `data-message-streaming` lúc đang viết và
///   `data-message-complete` khi xong; chữ nằm trong `[data-assistant-markdown-root]`;
/// - cổng chặn của máy chủ: `html[data-conversation-gated]` + `[data-gate-kind]` (`rate_limited` / `force_login` /
///   `forbidden`), nút thử lại có `data-retry-after`. Chưa gặp thật — đọc từ mã của trang;
/// - sau tin ẩn danh thứ 5 trang mở `dialog#mobile-auth-dialog` mời đăng nhập. App **không** tự đóng hộp này.
///
/// **Trang đã đăng nhập** — đã thử thật 2026-11-17 (Chrome máy tính, tài khoản Free, 3 tin chat tạm; **chưa** thử với UA
/// điện thoại):
/// - app React; ô nhập là vùng soạn thảo `form[data-chatgpt-composer] [contenteditable="true"]`. Gán chữ bằng sự kiện
///   `paste` tự dựng (`ClipboardEvent` + `DataTransfer`) — trang nhận và chặn mặc định; dự phòng
///   `execCommand('insertText')`;
/// - nút gửi `button[type="submit"]` chỉ có khi ô nhập có chữ (nhãn theo ngôn ngữ ⇒ không dò nhãn); gửi bằng
///   `form.requestSubmit(nút)`. Lúc đang trả lời nút đó bị thay bằng nút dừng `type="button"`;
/// - mỗi lượt (câu hỏi + câu trả lời) là một `[data-talvt-turn-state]` = `in_progress` → `complete`; lượt vừa gửi mang
///   `complete` trong tích tắc khi **chưa** có phần trợ lý ⇒ chỉ tin `complete` khi lượt đã có
///   `[data-conversation-role="assistant"]`; chữ nằm trong `[data-dil-response]` (có cả lúc đang viết);
/// - khối code là `[data-chatgpt-copy-code="<mã>"]` (không phải `<pre>`), phần đầu khối mang `data-markdown-copy="exclude"`.
///
/// **Chung**: hai trang dùng cùng bộ dựng markdown (`data-d-component`) ⇒ một bộ đọc chữ `__collectText`. Xuống dòng mềm
/// là text node `"\n"` (`white-space: pre-line`) ⇒ **không** gộp `\n` thành dấu cách. Mọi lượt mở `?temporary-chat=true`:
/// đã đăng nhập thì là chat tạm (không vào lịch sử ChatGPT của người dùng), trang ẩn danh bỏ qua tham số. Cuộc chat ẩn
/// danh / chat tạm chỉ sống trong trang đang mở — nạp lại là mất (đã thử `/uc/<id>` bị đưa về `/`).
enum ChatGPTWebPageContract {
    static let host = "https://chatgpt.com"
    /// Trang chat mới của mọi lượt (chat tạm khi đã đăng nhập).
    static let homeURL = URL(string: "\(host)/?temporary-chat=true")!
    /// Trang mở trong trình duyệt bypass cho người dùng (đăng nhập, qua bước kiểm tra, xem thông báo).
    static let browserURL = URL(string: "\(host)/")!

    /// Ảnh chụp trạng thái trang mỗi nhịp đọc.
    struct Snapshot: Sendable {
        let path: String
        /// Trang là bản đã đăng nhập (app React) chứ không phải trang ẩn danh mobile.
        let signedIn: Bool
        /// Số tin của trợ lý trên trang.
        let turnCount: Int
        /// Chữ của tin trợ lý mới nhất (đã bỏ nút, phần ẩn). Rỗng khi tin chưa có khối chữ.
        let newestText: String
        let answerFound: Bool
        /// Tin trợ lý mới nhất đã xong (`data-message-complete` / lượt `complete` có phần trợ lý).
        let complete: Bool
        /// Tin trợ lý mới nhất đang được viết (`data-message-streaming` / lượt `in_progress`).
        let streaming: Bool
        /// Trang còn đang chạy một lượt (nút gửi đang là nút "Dừng" / lượt `in_progress`).
        let generating: Bool
        /// Trạng thái lạ của lượt mới nhất trên trang đã đăng nhập (khác `complete` / `in_progress`) — coi là lượt lỗi.
        let turnFailure: String
        let composerFound: Bool
        /// Script của trang đã gắn xong.
        let ready: Bool
        /// Số ký tự còn nằm trong ô nhập (gửi được thì trang tự xoá).
        let draftLength: Int
        let gated: Bool
        let gateKind: String
        let gateText: String
        let retryAfter: String
        /// Chữ của vùng báo lỗi gửi (`[data-composer-submission-status]`) khi nó đang hiện.
        let submitError: String
        /// Có `dialog[open]` — hộp mời đăng nhập của trang ẩn danh.
        let dialogOpen: Bool
        /// Trang kiểm tra của Cloudflare.
        let challenge: Bool
        let scriptError: String?

        init?(_ raw: Any?) {
            guard let dict = raw as? [String: Any] else { return nil }
            path = dict["path"] as? String ?? ""
            signedIn = (dict["signedIn"] as? Bool) ?? false
            turnCount = (dict["turnCount"] as? NSNumber)?.intValue ?? 0
            newestText = dict["text"] as? String ?? ""
            answerFound = (dict["answerFound"] as? Bool) ?? false
            complete = (dict["complete"] as? Bool) ?? false
            streaming = (dict["streaming"] as? Bool) ?? false
            generating = (dict["generating"] as? Bool) ?? false
            turnFailure = dict["turnFailure"] as? String ?? ""
            composerFound = (dict["composer"] as? Bool) ?? false
            ready = (dict["ready"] as? Bool) ?? false
            draftLength = (dict["draftLength"] as? NSNumber)?.intValue ?? 0
            gated = (dict["gated"] as? Bool) ?? false
            gateKind = dict["gateKind"] as? String ?? ""
            gateText = dict["gateText"] as? String ?? ""
            retryAfter = dict["retryAfter"] as? String ?? ""
            submitError = dict["submitError"] as? String ?? ""
            dialogOpen = (dict["dialogOpen"] as? Bool) ?? false
            challenge = (dict["challenge"] as? Bool) ?? false
            scriptError = dict["error"] as? String
        }

        /// Nhãn kiểu trang cho log.
        var kindLabel: String { signedIn ? "đã đăng nhập" : "ẩn danh" }
    }

    /// Kết quả của `submitScript`.
    enum SubmitOutcome: String, Sendable {
        case submitted
        case clicked
        /// Trang còn đang viết lượt trước — bấm lúc này là bấm "Dừng".
        case busy
        case noComposer = "no-composer"
        /// Chưa có nút gửi dùng được (trang đã đăng nhập chỉ dựng nút khi ô nhập có chữ).
        case noSubmit = "no-submit"

        var didSend: Bool { self == .submitted || self == .clicked }
    }

    // MARK: - Cổng chặn

    /// Lỗi ứng với cổng chặn trang đang hiện.
    static func gateError(_ snapshot: Snapshot) -> ChatGPTWebError {
        switch snapshot.gateKind {
        case "rate_limited":
            return .rateLimited(retryAfter: retryAfterSeconds(snapshot.retryAfter))
        case "force_login":
            return .loginRequired
        default:
            let detail = snapshot.gateText.isEmpty ? snapshot.gateKind : snapshot.gateText
            return .blocked(detail.isEmpty ? "không rõ lý do" : detail)
        }
    }

    /// `data-retry-after` của nút thử lại: số giây, hoặc một mốc thời gian ISO 8601. Không đọc được ⇒ 0.
    static func retryAfterSeconds(_ raw: String, now: Date = Date()) -> Int {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return 0 }
        if let seconds = Double(value) { return max(0, Int(seconds.rounded(.up))) }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return max(0, Int(date.timeIntervalSince(now).rounded(.up))) }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return max(0, Int(date.timeIntervalSince(now).rounded(.up))) }
        return 0
    }

    /// Chỉ host + path cho log.
    static func describe(_ url: URL?) -> String {
        guard let url else { return "-" }
        return "\(url.host ?? "-")\(url.path)"
    }

    // MARK: - Câu trả lời

    static func cleanAnswer(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Phần phát dần trong lúc trang còn đang viết: chỉ các dòng đã trọn (đến dấu xuống dòng cuối), bỏ khoảng trắng ở
    /// **cuối** để bản cuối (`cleanAnswer`) luôn nối tiếp phần đã phát.
    static func streamablePrefix(_ raw: String) -> String {
        guard let lastBreak = raw.lastIndex(of: "\n") else { return "" }
        var prefix = raw[..<lastBreak]
        while let last = prefix.last, last.isWhitespace {
            prefix.removeLast()
        }
        return String(prefix)
    }

    // MARK: - JavaScript

    /// Đọc trạng thái trang (cả hai kiểu trang). Chữ của tin lấy bằng cách duyệt cây DOM thật (không clone, không chèn
    /// node, không gọi `innerText`/`getComputedStyle` — không ép trang tính lại layout).
    static let snapshotScript = jsPrelude + #"""
    (function () {
      var out = { path: location.pathname, signedIn: false, turnCount: 0, text: "", answerFound: false, complete: false, streaming: false, generating: false, turnFailure: "", composer: false, ready: false, draftLength: 0, gated: false, gateKind: "", gateText: "", retryAfter: "", submitError: "", dialogOpen: false, challenge: false };
      try {
        var composer = __composer();
        out.composer = !!composer;
        out.signedIn = composer ? composer.tagName !== 'TEXTAREA' : !!document.querySelector('form[data-chatgpt-composer]');
        if (out.signedIn) {
          out.ready = !!composer;
          if (composer) { out.draftLength = (composer.textContent || "").length; }
          out.turnCount = document.querySelectorAll('[data-conversation-role="assistant"]').length;
          var turn = __newestTurn();
          if (turn) {
            var state = turn.getAttribute('data-talvt-turn-state') || "";
            var answered = !!turn.querySelector('[data-conversation-role="assistant"]');
            out.complete = answered && state === 'complete';
            out.streaming = state === 'in_progress';
            out.generating = out.streaming;
            if (state && state !== 'complete' && state !== 'in_progress') { out.turnFailure = state; }
            var bodies = turn.querySelectorAll('[data-dil-response]');
            if (bodies.length) {
              out.answerFound = true;
              out.text = __collectText(bodies[bodies.length - 1]);
            }
          }
        } else {
          if (composer) { out.draftLength = composer.value.length; }
          out.ready = document.documentElement.hasAttribute('data-octane-home-behavior-ready') || document.readyState === 'complete';
          var submit = document.querySelector('[data-composer-submit]');
          if (submit) { out.generating = __isStop(submit); }
          var status = document.querySelector('[data-composer-submission-status]');
          if (status && !status.hidden) { out.submitError = __flat(status.textContent, 160); }
          var messages = document.querySelectorAll('[data-message-role="assistant"]');
          out.turnCount = messages.length;
          if (messages.length) {
            var newest = messages[messages.length - 1];
            out.complete = newest.hasAttribute('data-message-complete');
            out.streaming = newest.hasAttribute('data-message-streaming');
            var root = newest.querySelector('[data-assistant-markdown-root]');
            out.answerFound = !!root;
            out.text = root ? __collectText(root) : "";
          }
        }
        out.gated = document.documentElement.hasAttribute('data-conversation-gated');
        var panel = document.querySelector('[data-gate-kind]');
        if (panel) {
          out.gated = true;
          out.gateKind = panel.getAttribute('data-gate-kind') || "";
          out.gateText = __flat(panel.textContent, 200);
          var retry = panel.querySelector('[data-retry-after]');
          if (retry) { out.retryAfter = retry.getAttribute('data-retry-after') || ""; }
        }
        out.dialogOpen = !!document.querySelector('dialog[open]');
        out.challenge = /^just a moment/i.test(document.title || "") || !!document.querySelector('#challenge-form, #challenge-running, #cf-challenge-running, iframe[src*="challenges.cloudflare.com"]');
      } catch (e) { out.error = String(e); }
      return out;
    })();
    """#

    /// Gán câu hỏi vào ô nhập: `textarea` ⇒ setter gốc + sự kiện `input`; vùng soạn thảo ⇒ sự kiện `paste` tự dựng.
    /// Trả `false` khi không thấy ô nhập; chữ đã vào hay chưa thì caller đọc `Snapshot.draftLength`. `nil` khi không mã
    /// hoá được chữ.
    static func fillComposerScript(_ text: String) -> String? {
        guard let literal = jsLiteral(text) else { return nil }
        return jsPrelude + #"""
        (function (text) {
          var t = __composer();
          if (!t) { return false; }
          t.focus();
          if (t.tagName === 'TEXTAREA') {
            var setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
            setter.call(t, text);
            t.dispatchEvent(new Event('input', { bubbles: true }));
            return true;
          }
          try {
            var data = new DataTransfer();
            data.setData('text/plain', text);
            t.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
          } catch (e) {}
          return true;
        })(\#(literal));
        """#
    }

    /// Dự phòng cho vùng soạn thảo khi sự kiện `paste` không đưa được chữ vào: `execCommand('insertText')`.
    static func fillFallbackScript(_ text: String) -> String? {
        guard let literal = jsLiteral(text) else { return nil }
        return jsPrelude + #"""
        (function (text) {
          var t = __composer();
          if (!t || t.tagName === 'TEXTAREA') { return false; }
          t.focus();
          try { return document.execCommand('insertText', false, text) !== false; } catch (e) { return false; }
        })(\#(literal));
        """#
    }

    /// Gửi form của ô nhập. Trả về một `SubmitOutcome`. Không gửi khi trang còn đang viết lượt trước.
    static let submitScript = jsPrelude + #"""
    (function () {
      var t = __composer();
      if (!t) { return "no-composer"; }
      var form = t.tagName === 'TEXTAREA' ? t.form : document.querySelector('form[data-chatgpt-composer]');
      if (!form) { return "no-composer"; }
      var submit;
      if (t.tagName === 'TEXTAREA') {
        submit = form.querySelector('[data-composer-submit]');
        if (submit && __isStop(submit)) { return "busy"; }
      } else {
        var turn = __newestTurn();
        if (turn && turn.getAttribute('data-talvt-turn-state') === 'in_progress') { return "busy"; }
        submit = form.querySelector('button[type="submit"]:not([disabled])');
        if (!submit) { return "no-submit"; }
      }
      try {
        if (submit) { form.requestSubmit(submit); } else { form.requestSubmit(); }
        return "submitted";
      } catch (e) {}
      if (submit) { submit.click(); return "clicked"; }
      return "no-submit";
    })();
    """#

    private static func jsLiteral(_ text: String) -> String? {
        guard let data = try? JSONEncoder().encode(text) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Hàm dùng chung cho mọi script trên — khai lại mỗi lần chạy (trang có thể đã nạp document mới).
    private static let jsPrelude = #"""
    function __composer() {
      var list = document.querySelectorAll('textarea[data-mobile-composer-prompt], textarea[name="prompt"]');
      for (var i = 0; i < list.length; i++) {
        if (!list[i].disabled && !list[i].hidden) { return list[i]; }
      }
      var form = document.querySelector('form[data-chatgpt-composer]');
      return form ? form.querySelector('[contenteditable="true"]') : null;
    }
    function __newestTurn() {
      var turns = document.querySelectorAll('[data-talvt-turn-state]');
      return turns.length ? turns[turns.length - 1] : null;
    }
    function __isStop(submit) {
      var stop = submit.getAttribute('data-stop-label');
      return !!stop && submit.getAttribute('aria-label') === stop;
    }
    function __flat(text, max) {
      return (text || "").replace(/\s+/g, ' ').trim().substring(0, max);
    }
    function __collectText(root) {
      var out = "";
      var pendingBreaks = 0;
      var pendingPrefix = "";
      var inItem = 0;
      var inCell = 0;
      var skip = { BUTTON: 1, SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEXTAREA: 1, INPUT: 1, TEMPLATE: 1, svg: 1, SVG: 1, AUDIO: 1, VIDEO: 1 };
      var soft = { DIV: 1, SECTION: 1, LI: 1, TR: 1, UL: 1, OL: 1, ARTICLE: 1 };
      var hard = { P: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1, PRE: 1, BLOCKQUOTE: 1, TABLE: 1 };
      function brk(n) { if (inCell === 0 && n > pendingBreaks) { pendingBreaks = n; } }
      function emit(text) {
        if (!text) { return; }
        if (out.length > 0 && pendingBreaks > 0) { out += pendingBreaks > 1 ? "\n\n" : "\n"; }
        pendingBreaks = 0;
        if (pendingPrefix) { out += pendingPrefix; pendingPrefix = ""; }
        out += text;
      }
      function fence(code, lang) {
        brk(2);
        emit("```" + lang + "\n" + (code || "").replace(/\n+$/, '') + "\n```");
        brk(2);
      }
      function walk(n) {
        if (n.nodeType === 3) {
          var value = n.nodeValue.replace(/[ \t\r\f]+/g, ' ');
          if (inCell > 0) { value = value.replace(/\n+/g, ' '); }
          if (pendingBreaks > 0 || out.length === 0) { value = value.replace(/^[ \n]+/, ''); }
          emit(value);
          return;
        }
        if (n.nodeType !== 1) { return; }
        var tag = n.tagName;
        if (skip[tag] || n.hidden || n.getAttribute('aria-hidden') === 'true') { return; }
        if (n.hasAttribute('data-message-content-controls') || n.getAttribute('data-markdown-copy') === 'exclude') { return; }
        if (tag === 'BR') { brk(1); return; }
        if (n.hasAttribute('data-chatgpt-copy-code')) { fence(n.getAttribute('data-chatgpt-copy-code'), ""); return; }
        if (tag === 'PRE') {
          var code = n.querySelector('code');
          fence(n.textContent, (code && code.getAttribute('data-code-language')) || "");
          return;
        }
        for (var k = n.firstElementChild; k; k = k.nextElementSibling) {
          if (k.tagName === 'PRE') { walk(k); return; }
        }
        var isHard = !!hard[tag];
        var isSoft = !!soft[tag];
        if (isHard) { brk(inItem > 0 ? 1 : 2); } else if (isSoft) { brk(1); }
        var isCell = tag === 'TD' || tag === 'TH';
        if (tag === 'LI') {
          var parent = n.parentElement;
          if (parent && parent.tagName === 'OL') {
            var index = 1;
            for (var s = n.previousElementSibling; s; s = s.previousElementSibling) { if (s.tagName === 'LI') { index += 1; } }
            pendingPrefix = index + ". ";
          } else {
            pendingPrefix = "- ";
          }
          inItem += 1;
        }
        if (isCell) { if (n.previousElementSibling) { emit(" | "); } inCell += 1; }
        if (/^H[1-6]$/.test(tag)) { pendingPrefix = new Array(parseInt(tag.charAt(1), 10) + 1).join('#') + " "; }
        for (var c = n.firstChild; c; c = c.nextSibling) { walk(c); }
        if (isCell) { inCell -= 1; }
        if (tag === 'LI') { inItem -= 1; pendingPrefix = ""; }
        if (isHard) { brk(inItem > 0 ? 1 : 2); } else if (isSoft) { brk(1); }
      }
      walk(root);
      return out.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
    }

    """#
}
