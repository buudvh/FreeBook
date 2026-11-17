import Foundation

/// **Nơi duy nhất** chứa hợp đồng với trang `gemini.google.com/app` khi **chưa đăng nhập** (chế độ khách, 1.3.977): selector
/// và mã JS chạy trong trang. Google đổi cấu trúc thì sửa đúng file này; lỗi hiện ra là
/// `GeminiWebError.protocolChanged("trang khách: …")`.
///
/// Vì sao khách phải đọc DOM chứ không gọi giao thức như Gemini Web đã đăng nhập: trang khách **không** có token
/// `SNlM0e`, và **không** gọi `StreamGenerate` — thử thật, sau khi gửi tin chỉ thấy `batchexecute` cùng
/// `geminiweb-pa.clients6.google.com/v1/processSession` và bước chứng thực `waa-pa…/Waa/Create`. App không dựng lại API
/// đó (là vượt cơ chế chống lạm dụng của Google); app để trang tự gửi, giống người dùng gõ.
///
/// Đã thử thật 2026-11-17 (Chromium giả lập mobile, chưa đăng nhập Google, 3 tin; model trang chọn là Gemini 3.5
/// Flash-Lite):
/// - ô nhập là Quill `rich-textarea .ql-editor[contenteditable]` (lớp `ql-blank` khi trống). Gán chữ bằng cách dựng thẳng
///   các `<p>` (`createElement` + `textContent` — trang dùng Trusted Types nên không gán `innerHTML`) rồi phát `input`:
///   trang nhận, **không cần focus** (focus là bàn phím bật — bài học 1.3.976). Sự kiện `paste` không dùng được vì Quill
///   tự focus ô nhập khi xử lý;
/// - nút gửi nằm trong `.send-button` — phần tử này chỉ có khi ô nhập có chữ (lớp `submit`) hoặc khi đang trả lời (lớp
///   `stop`); bấm bằng `button.click()` là gửi. Phím Enter ở bản mobile chỉ xuống dòng;
/// - mỗi câu hỏi là `user-query`, mỗi câu trả lời là `model-response`; chữ nằm trong `message-content .markdown`, mang
///   `aria-busy="true"` lúc đang viết; xong thì `aria-busy="false"` **và** `.response-footer` có lớp `complete`. Trong lúc
///   Gemini chưa viết chữ nào thì số `user-query` nhiều hơn số `model-response`;
/// - nạp lại `/app/<id>` bị đưa về `/app` — cuộc chat khách chỉ sống trong trang đang mở.
///
/// Script trả về đúng khuôn `ChatGPTWebPageContract.Snapshot` / `SubmitOutcome` để chạy bằng bộ điều khiển trang dùng chung
/// (`ChatGPTWebSite`). Chưa gặp nên chưa biết: trang hiện gì khi khách hết lượt hay bị bắt đăng nhập.
enum GeminiWebGuestPageContract {
    static let homeURL = GeminiWebRequestBuilder.appURL

    /// Đọc trạng thái trang. Trang đã chuyển sang `accounts.google.com` ⇒ cổng `force_login`; đường dẫn `/sorry` (Google
    /// nghi bot) ⇒ `challenge`.
    static let snapshotScript = jsPrelude + HiddenWebAnswerTextScript.source + #"""
    (function () {
      var out = { path: location.pathname, signedIn: false, turnCount: 0, text: "", answerFound: false, complete: false, streaming: false, generating: false, turnFailure: "", composer: false, ready: false, draftLength: 0, gated: false, gateKind: "", gateText: "", retryAfter: "", submitError: "", dialogOpen: false, challenge: false };
      try {
        var host = String(location.host || "");
        if (host.indexOf('accounts.google.') === 0) { out.gated = true; out.gateKind = "force_login"; return out; }
        out.challenge = location.pathname.indexOf('/sorry') === 0;
        out.signedIn = !!(window.WIZ_global_data && window.WIZ_global_data.SNlM0e);
        var editor = __editor();
        out.composer = !!editor;
        out.ready = !!editor;
        if (editor && !editor.classList.contains('ql-blank')) { out.draftLength = (editor.textContent || "").length; }
        var send = document.querySelector('.send-button');
        var responses = document.querySelectorAll('model-response');
        out.turnCount = responses.length;
        out.generating = (!!send && send.classList.contains('stop')) || document.querySelectorAll('user-query').length > responses.length;
        if (responses.length) {
          var newest = responses[responses.length - 1];
          var markdown = newest.querySelector('message-content .markdown');
          var footer = newest.querySelector('.response-footer');
          out.answerFound = !!markdown;
          if (markdown) {
            var busy = markdown.getAttribute('aria-busy');
            out.streaming = busy === 'true';
            out.complete = busy === 'false' && !!footer && footer.classList.contains('complete');
            out.text = __collectText(markdown);
          }
        }
      } catch (e) { out.error = String(e); }
      return out;
    })();
    """#

    /// Gán câu hỏi vào ô nhập Quill: mỗi dòng một `<p>`, dòng trống là `<p><br></p>`, rồi phát `input`. **Không** focus.
    /// `nil` khi không mã hoá được chữ.
    static func fillComposerScript(_ text: String) -> String? {
        guard let data = try? JSONEncoder().encode(text), let literal = String(data: data, encoding: .utf8) else { return nil }
        return jsPrelude + #"""
        (function (text) {
          var editor = __editor();
          if (!editor) { return false; }
          while (editor.firstChild) { editor.removeChild(editor.firstChild); }
          var lines = text.split('\n');
          for (var i = 0; i < lines.length; i++) {
            var p = document.createElement('p');
            if (lines[i]) { p.textContent = lines[i]; } else { p.appendChild(document.createElement('br')); }
            editor.appendChild(p);
          }
          editor.dispatchEvent(new Event('input', { bubbles: true }));
          return true;
        })(\#(literal));
        """#
    }

    /// Bấm nút gửi. Trả về một `ChatGPTWebPageContract.SubmitOutcome`: chưa có nút (trang chưa kịp dựng sau khi gán chữ) ⇒
    /// `no-submit`; đang trả lời lượt trước ⇒ `busy` (bấm lúc này là bấm "Dừng").
    static let submitScript = jsPrelude + #"""
    (function () {
      if (!__editor()) { return "no-composer"; }
      var send = document.querySelector('.send-button');
      if (!send) { return "no-submit"; }
      if (send.classList.contains('stop')) { return "busy"; }
      var button = send.querySelector('button') || send;
      if (button.disabled || button.getAttribute('aria-disabled') === 'true') { return "no-submit"; }
      button.click();
      return "clicked";
    })();
    """#

    private static let jsPrelude = #"""
    function __editor() {
      return document.querySelector('rich-textarea .ql-editor[contenteditable="true"]');
    }

    """#
}
