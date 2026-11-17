import Foundation

/// Mã JavaScript chạy trong trang ChatGPT của `ChatGPTWebPageContract` (1.3.971; tách file ở 1.3.976 để file chính dưới
/// 400 dòng). Selector và lý do của từng script: xem chú thích đầu `ChatGPTWebPageContract.swift`.
extension ChatGPTWebPageContract {
    /// Gắn lúc document bắt đầu (`WKUserScript`, khung chính): không cho trang focus phần tử nào — `focus()` thành hàm
    /// rỗng, phần tử vẫn nhận được focus bằng đường khác (thuộc tính `autofocus`…) thì bị bỏ focus ngay. Chỉ
    /// `fillFallbackScript` được mở khoá trong tích tắc (`__fbAllowFocus`) vì `execCommand` cần ô nhập đang được focus.
    static let focusGuardScript = #"""
    (function () {
      if (window.__fbFocusGuard) { return; }
      window.__fbFocusGuard = true;
      window.__fbAllowFocus = false;
      window.__fbNativeFocus = HTMLElement.prototype.focus;
      try { HTMLElement.prototype.focus = function () {}; } catch (e) {}
      document.addEventListener('focusin', function (event) {
        if (window.__fbAllowFocus) { return; }
        try { if (event.target && event.target.blur) { event.target.blur(); } } catch (e) {}
      }, true);
    })();
    """#

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
    /// **Không** focus ô nhập (bàn phím sẽ bật). Trả `false` khi không thấy ô nhập; chữ đã vào hay chưa thì caller đọc `Snapshot.draftLength`. `nil` khi không mã
    /// hoá được chữ.
    static func fillComposerScript(_ text: String) -> String? {
        guard let literal = jsLiteral(text) else { return nil }
        return jsPrelude + #"""
        (function (text) {
          var t = __composer();
          if (!t) { return false; }
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

    /// Dự phòng cho vùng soạn thảo khi sự kiện `paste` không đưa được chữ vào: `execCommand('insertText')`. Lệnh này cần
    /// ô nhập đang được focus ⇒ mở khoá `focusGuardScript` trong tích tắc rồi bỏ focus ngay (bàn phím có thể nháy).
    static func fillFallbackScript(_ text: String) -> String? {
        guard let literal = jsLiteral(text) else { return nil }
        return jsPrelude + #"""
        (function (text) {
          var t = __composer();
          if (!t || t.tagName === 'TEXTAREA') { return false; }
          var done = false;
          window.__fbAllowFocus = true;
          try {
            (window.__fbNativeFocus || HTMLElement.prototype.focus).call(t);
            done = document.execCommand('insertText', false, text) !== false;
          } catch (e) {}
          window.__fbAllowFocus = false;
          try { t.blur(); } catch (e) {}
          return done;
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

    """# + HiddenWebAnswerTextScript.source
}
