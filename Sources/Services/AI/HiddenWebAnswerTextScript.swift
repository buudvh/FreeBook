import Foundation

/// JavaScript đọc chữ của một câu trả lời AI từ cây DOM (1.3.971; tách dùng chung ở 1.3.977) — dùng cho trang ChatGPT
/// (ẩn danh, đã đăng nhập) và trang Gemini khách. Khai hàm `__collectText(root)`; ghép vào trước script cần dùng.
///
/// Duyệt cây DOM thật, **không** `innerText` / `getComputedStyle` (không ép trang tính lại layout), không clone, không
/// chèn node. Đã thử trên trang thật của cả ba kiểu trang:
/// - xuống dòng mềm là text node `"\n"` (`white-space: pre-line`) ⇒ chỉ gộp dấu cách / tab, **giữ** `\n` (gộp là hai dòng
///   `Tên=Nghĩa` dính thành một);
/// - `li` ⇒ `- ` / `N. `, `h1…h6` ⇒ `#`, ô bảng nối ` | `;
/// - khối code ⇒ hàng rào ba dấu huyền: `<pre>` (ChatGPT ẩn danh, Gemini) hoặc `[data-chatgpt-copy-code]` (ChatGPT đã đăng
///   nhập); bỏ phần đầu khối (`[data-message-content-controls]`, `data-markdown-copy="exclude"`,
///   `.code-block-decoration`) và mọi `BUTTON`.
enum HiddenWebAnswerTextScript {
    static let source = #"""
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
        if (n.classList && n.classList.contains('code-block-decoration')) { return; }
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
