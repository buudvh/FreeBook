import Foundation

/// JavaScript tiêm vào trang gemini.google.com và các helper mã hoá cho `GeminiWebSessionController`.
/// Tách khỏi file chính để giữ mỗi file dưới 400 dòng; không có logic WebKit ở đây.
extension GeminiWebSessionController {
    /// Đọc `window.WIZ_global_data` — tương đương bộ regex `SNlM0e`/`cfb2h`/`FdrFJe`/`TuX5cc` của thư viện
    /// tham chiếu, nhưng đọc thẳng object nên không phụ thuộc cách Google in HTML.
    static let probeScript = """
    (function () {
      var w = window.WIZ_global_data || null;
      return {
        hasWiz: !!w,
        token: (w && w.SNlM0e) || "",
        bl: (w && w.cfb2h) || "",
        sid: (w && w.FdrFJe) || "",
        hl: (w && w.TuX5cc) || "",
        href: String(location.href)
      };
    })();
    """

    /// JSON là tập con của JS, trừ U+2028/U+2029 — thoát hai ký tự đó để chuỗi an toàn trong mọi engine.
    static func jsLiteral(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        guard let text = String(data: data, encoding: .utf8) else {
            throw GeminiWebError.protocolChanged("không mã hoá được request sang JSON")
        }
        return text
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    /// Thông điệp lỗi do JS gửi về: `HTTP <mã> <đoạn body>` thành `.http`, còn lại là `.script`.
    static func scriptError(from payload: String) -> GeminiWebError {
        if payload.hasPrefix("HTTP ") {
            let digits = payload.dropFirst(5).prefix { $0.isNumber }
            if let status = Int(digits) { return .http(status) }
        }
        return .script(String(payload.prefix(200)))
    }

    /// `fetch` + `ReadableStream` trong trang; mỗi chunk đã giải mã UTF-8 được đẩy về Swift qua message handler
    /// (`{id, type: chunk|done|error, payload}`). `post()` nuốt exception để một lỗi bridge không phá vòng đọc.
    static func fetchScript(id: String, request: GeminiWebRequestBuilder.Request) throws -> String {
        let idLiteral = try jsLiteral(id)
        let urlLiteral = try jsLiteral(request.url)
        let headersLiteral = try jsLiteral(request.headers)
        let fieldsLiteral = try jsLiteral(request.fields)
        return """
        (function () {
          var id = \(idLiteral), url = \(urlLiteral), headers = \(headersLiteral), fields = \(fieldsLiteral);
          var post = function (type, payload) {
            try {
              window.webkit.messageHandlers.\(messageHandlerName).postMessage({ id: id, type: type, payload: payload == null ? "" : String(payload) });
            } catch (e) {}
          };
          (async function () {
            try {
              var params = new URLSearchParams();
              for (var key in fields) {
                if (Object.prototype.hasOwnProperty.call(fields, key)) { params.append(key, fields[key]); }
              }
              var controller = new AbortController();
              window.__fbGeminiAbort = window.__fbGeminiAbort || {};
              window.__fbGeminiAbort[id] = controller;
              var response = await fetch(url, { method: "POST", headers: headers, body: params, credentials: "include", signal: controller.signal });
              if (!response.ok) {
                var detail = "";
                try { detail = (await response.text()).slice(0, 300); } catch (e) {}
                post("error", "HTTP " + response.status + " " + detail);
                return;
              }
              var reader = response.body.getReader();
              var decoder = new TextDecoder("utf-8");
              while (true) {
                var step = await reader.read();
                if (step.done) { break; }
                post("chunk", decoder.decode(step.value, { stream: true }));
              }
              post("chunk", decoder.decode());
              post("done", "");
            } catch (e) {
              post("error", String(e && e.message ? e.message : e));
            } finally {
              try { delete window.__fbGeminiAbort[id]; } catch (e) {}
            }
          })();
          return "started";
        })();
        """
    }
}
