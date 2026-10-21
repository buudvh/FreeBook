import Foundation

/// Phần đuôi cấp luồng của mục lục (spec §13): `preUpdateJs` + `java.refreshTocUrl()` (§13.3), `formatJs` (§13.4).
/// Mọi thứ chạy **trong** phiên mục lục (cùng runtime JS, cùng ngữ cảnh `book`). `book.setReverseToc` (§13.5) do engine
/// ghi lên `LegadoBookContext.reverseTocOverride`; `toc` đảo danh sách và lưu cờ.
extension LegadoSourceRuntime {
    /// Kết quả `preUpdateJs`: `bookUrl` hiệu lực cho lượt này (JS có thể đổi tên miền), `tocUrl` JS ghi (nếu đổi), và
    /// thông tin sách nếu JS gọi `java.refreshTocUrl()`.
    struct PreUpdateOutcome {
        var bookUrl: String
        var tocUrl: String?
        var refreshedInfo: BookInfo?
        /// Trang sách vừa tải lại (dùng làm trang mục lục khi `tocUrl` rỗng).
        var response: LegadoHTTPResponse?
    }

    /// Kết quả của hook `refreshTocUrl` (chạy giữa chừng JS, trên thread engine của phiên).
    final class PreUpdateBox {
        var info: BookInfo?
        var response: LegadoHTTPResponse?
        var bookUrl: String?
    }

    /// Chạy `preUpdateJs` trước khi tải trang mục lục (spec §13.3). Biến: `book` (ghi được trong lượt), `source`, `java`,
    /// `cookie`, `cache`, `baseUrl` = `book.bookUrl`; không `result`. `java.refreshTocUrl()` / `refreshBookUrl()` /
    /// `refreshBookInfo()` (U52) / `reGetBook()` (0 nguồn — làm như `refreshTocUrl`) đánh giá lại `ruleBookInfo` trên
    /// `book.bookUrl` **hiện tại** của JS. Lỗi JS chỉ ghi chẩn đoán; lỗi tải khi làm mới ⇒ giữ `tocUrl` cũ.
    /// `nil` khi nguồn không có `preUpdateJs` (hoặc chỉ là `{{}}` rác).
    static func runPreUpdate(
        session: LegadoEngineSession,
        target: Target,
        book: LegadoBookContext,
        bookUrl: String,
        knownTocUrl: String
    ) throws -> PreUpdateOutcome? {
        let code = scriptBody(target.source.ruleToc.preUpdateJs)
        guard !code.isEmpty, code != "{{}}" else { return nil }
        let rule = target.source.ruleBookInfo
        let box = PreUpdateBox()
        let refresh: (LegadoEngineSession) throws -> Void = { engine in
            let current = try Self.jsBookString(engine, field: "bookUrl") ?? bookUrl
            do {
                let response = try engine.fetch(current)
                box.info = try Self.evaluateBookInfo(session: engine, response: response, rule: rule, book: book)
                box.response = response
                box.bookUrl = current
            } catch let error as LegadoEngineError {
                engine.diagnostics.record(.info, "refreshTocUrl lỗi — giữ tocUrl cũ: \(error.localizedDescription)")
            }
        }
        session.onRefreshTocUrl = refresh
        session.onReGetBook = refresh
        defer {
            session.onRefreshTocUrl = nil
            session.onReGetBook = nil
        }
        _ = try session.evaluateJS(code, result: nil, baseUrl: bookUrl)

        let jsBookUrl = try jsBookString(session, field: "bookUrl")
        let effectiveBookUrl = box.bookUrl ?? jsBookUrl ?? bookUrl
        var outcome = PreUpdateOutcome(bookUrl: effectiveBookUrl, tocUrl: nil, refreshedInfo: box.info, response: box.response)
        if box.info == nil, let jsTocUrl = try jsBookString(session, field: "tocUrl"), jsTocUrl != knownTocUrl {
            let absolute = LegadoURLResolver.hasHTTPScheme(jsTocUrl)
                ? jsTocUrl
                : LegadoURLResolver.absolute(jsTocUrl, base: effectiveBookUrl)
            outcome.tocUrl = LegadoURLResolver.hasHTTPScheme(absolute) ? absolute : nil
        }
        if effectiveBookUrl != bookUrl {
            session.diagnostics.record(.info, "preUpdateJs đổi bookUrl trong lượt này")
        }
        return outcome
    }

    /// `String(book.<field>)` trong JS (đọc cả giá trị JS vừa ghi, §13.5); rỗng ⇒ `nil`.
    static func jsBookString(_ session: LegadoEngineSession, field: String) throws -> String? {
        let value = try session.evaluateJS("(function (g) { return g.book ? String(g.book.\(field)) : ''; })(this)")
        guard case .string(let text) = value else { return nil }
        return nonEmpty(text)
    }

    // MARK: - formatJs (§13.4)

    /// Đổi tên hiển thị của chương (không phải dòng tên tập) bằng `formatJs`: biến `title` (tên gốc), `index` (đếm từ 1
    /// trong các chương thường — U26), `book`, `source`, `java`. Kết quả chuỗi không rỗng thay tên; lỗi/rỗng giữ tên gốc.
    /// Một lần chạy JS cho cả mục lục, tổng tối đa 2 giây (hết giờ ⇒ chương còn lại giữ tên gốc).
    static func applyFormatJs(session: LegadoEngineSession, target: Target, entries: [TocEntry]) throws -> [TocEntry] {
        let code = scriptBody(target.source.ruleToc.formatJs)
        guard !code.isEmpty else { return entries }
        let titles = entries.filter { !$0.isVolume }.map { $0.name }
        guard !titles.isEmpty else { return entries }
        let quoted = LegadoEngineJSON.quoted(code)
        // Biến của khung lặp mang tiền tố `__lg`: `eval` trực tiếp chia sẻ phạm vi hàm, mã nguồn khai `var i` sẽ đè.
        let harness = """
        (function (__lgTitles) {
          var __lgOut = [], __lgStart = Date.now(), __lgFn = null;
          for (var __lgI = 0; __lgI < __lgTitles.length; __lgI++) {
            if (Date.now() - __lgStart > 2000) { break; }
            var title = __lgTitles[__lgI], index = __lgI + 1, __lgValue;
            try {
              __lgValue = __lgFn ? __lgFn.call(this, title, index) : eval(\(quoted));
            } catch (__lgError) {
              __lgValue = undefined;
              if (!__lgFn && __lgError instanceof SyntaxError) {
                try {
                  __lgFn = new Function('title', 'index', \(quoted));
                  __lgValue = __lgFn.call(this, title, index);
                } catch (__lgInner) { __lgValue = undefined; }
              }
            }
            __lgOut.push(__lgValue === undefined || __lgValue === null ? null : String(__lgValue));
          }
          return JSON.stringify(__lgOut);
        })(JSON.parse(result))
        """
        let savedChapter = session.chapter
        session.chapter = nil
        defer { session.chapter = savedChapter }
        let value = try session.evaluateScript(harness, result: .string(LegadoEngineJSON.strings(titles).compactText),
                                               baseUrl: nil, src: nil)
        guard case .string(let text) = value, let items = LegadoEngineJSONParser.parse(text)?.arrayValue else {
            return entries
        }
        var output = entries
        var position = 0
        for offset in output.indices where !output[offset].isVolume {
            defer { position += 1 }
            guard position < items.count, let formatted = items[position].stringValue,
                  let name = nonEmpty(formatted) else { continue }
            output[offset].name = name
        }
        if items.count < titles.count {
            session.diagnostics.record(.info, "formatJs vượt 2 giây — \(titles.count - items.count) chương giữ tên gốc")
        }
        return output
    }
}
