import Foundation

/// Đổi lỗi của một bước nghiệm thu thành (lớp lỗi, mã HTTP, thông điệp **đã redact**).
///
/// Luật redact: **không bao giờ** `"\(error)"` / `String(describing: error)` — case `httpStatus` của engine mang
/// 4000 ký tự thân trang. Mỗi case lấy đúng phần được phép: mã + URL qua `ExtensionDebugRedactor.url` (giá trị
/// query thành `…`); câu chữ tự do thì gom khoảng trắng, redact URL bên trong và cắt 300 ký tự.
enum LegadoCorpusErrorClassifier {
    struct Classification: Sendable, Equatable {
        let failureClass: LegadoCorpusReport.FailureClass
        let httpStatus: Int?
        let message: String
        let abandoned: Bool
    }

    /// Lỗi do chính bộ nghiệm thu dựng (bước trả rỗng, nguồn không có lối vào…).
    struct StepFailure: Error, Sendable {
        let failureClass: LegadoCorpusReport.FailureClass
        let message: String
    }

    static let maxMessageLength = 300
    /// Tiền tố thông báo của hàm/cú pháp chưa hỗ trợ (engine, spec §6.11).
    static let unsupportedPrefix = "Chưa hỗ trợ"

    static func classify(_ error: Error) -> Classification {
        if let exceeded = error as? LegadoCorpusDeadline.Exceeded {
            return Classification(
                failureClass: .timeout,
                httpStatus: nil,
                message: "Bước vượt trần \(exceeded.seconds) giây — đã bỏ chờ",
                abandoned: true
            )
        }
        if let failure = error as? StepFailure {
            return make(failure.failureClass, message: failure.message)
        }
        if let engineError = error as? LegadoEngineError {
            return classifyEngine(engineError)
        }
        // Lỗi của lớp luồng (facade): loại chưa hỗ trợ / script lạ ⇒ `unsupportedSyntax`; thiếu rule / không đọc được
        // `source.json` ⇒ `invalidSource`. Thông điệp của chúng không bắt đầu bằng "Chưa hỗ trợ" nên phải nhận theo kiểu.
        if let runtimeError = error as? LegadoRuntimeError {
            let failureClass = LegadoCorpusReport.FailureClass(rawValue: runtimeError.category.rawValue) ?? .other
            return make(failureClass, message: redact(runtimeError.localizedDescription))
        }
        if let urlError = error as? URLError {
            let failureClass: LegadoCorpusReport.FailureClass = urlError.code == .timedOut ? .timeout : .network
            let url = urlError.failingURL.map { " · " + redactURL($0.absoluteString) } ?? ""
            return make(failureClass, message: "URLError \(urlError.code.rawValue)\(url)")
        }
        if error is LegadoSourceError {
            return make(.invalidSource, message: redact(error.localizedDescription))
        }
        let text = redact(error.localizedDescription)
        return make(text.hasPrefix(unsupportedPrefix) ? .unsupportedSyntax : .other, message: text)
    }

    private static func classifyEngine(_ error: LegadoEngineError) -> Classification {
        switch error {
        case .unsupportedSyntax(let what):
            return make(.unsupportedSyntax, message: "\(unsupportedPrefix) \(redact(what))")
        case .httpStatus(let code, let url, _):
            return Classification(
                failureClass: .http,
                httpStatus: code,
                message: "HTTP \(code) · \(redactURL(url))",
                abandoned: false
            )
        case .timeout(let url):
            return make(.timeout, message: "Quá thời gian chờ · \(redactURL(url))")
        case .network(let url, let message):
            return make(.network, message: "\(redact(message)) · \(redactURL(url))")
        case .javaScript(let message):
            let text = redact(message)
            return make(text.contains(unsupportedPrefix) ? .unsupportedSyntax : .javaScript, message: text)
        case .noMatch(let what):
            return make(.noMatch, message: "Rule không khớp: \(redact(what))")
        case .missingBaseURL, .invalidURL:
            return make(.invalidSource, message: redact(error.localizedDescription))
        }
    }

    private static func make(_ failureClass: LegadoCorpusReport.FailureClass, message: String) -> Classification {
        Classification(failureClass: failureClass, httpStatus: nil, message: message, abandoned: false)
    }

    /// URL dừng **trước** khối option `,{…}` (khối đó mang header/thân request của nguồn — không được vào báo cáo).
    private static let urlPattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: "https?://[^\\s\"'<>]+?(?=,\\{|[\\s\"'<>]|$)",
        options: [.caseInsensitive]
    )

    /// URL rule của nguồn ⇒ chuỗi được phép ghi: URL JS (`@js:`/`<js>`) thành nhãn cố định; khối option `,{…}` (header,
    /// thân, method…) thành `,{…}`; phần URL qua `ExtensionDebugRedactor.url` (giá trị query thành `…`).
    static func redactURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("@js:") || lowered.contains("<js>") {
            return "(URL JS)"
        }
        guard let optionStart = trimmed.range(of: ",{") else {
            return ExtensionDebugRedactor.url(trimmed)
        }
        return ExtensionDebugRedactor.url(String(trimmed[..<optionStart.lowerBound])) + ",{…}"
    }

    /// Gom khoảng trắng, thay mọi URL (kèm khối option ngay sau nó) bằng bản redact, cắt `maxMessageLength` ký tự.
    static func redact(_ raw: String) -> String {
        var text = raw as NSString
        if let pattern = urlPattern {
            let matches = pattern.matches(in: raw, range: NSRange(location: 0, length: text.length))
            for match in matches.reversed() {
                let url = text.substring(with: match.range)
                var range = match.range
                var suffix = ""
                if let blockEnd = optionBlockEnd(in: text, from: match.range.location + match.range.length) {
                    range.length = blockEnd - range.location
                    suffix = ",{…}"
                }
                text = text.replacingCharacters(in: range, with: ExtensionDebugRedactor.url(url) + suffix) as NSString
            }
        }
        return ExtensionDebugRedactor.truncate(ExtensionDebugRedactor.message(text as String), limit: maxMessageLength)
    }

    /// `text` tại `start` bắt đầu bằng `,{` ⇒ vị trí ngay sau `}` đóng khối (cuối chuỗi nếu khối bị cắt dở); ngược lại
    /// `nil`. Đếm ngoặc, bỏ qua ngoặc nằm trong chuỗi `"…"`.
    private static func optionBlockEnd(in text: NSString, from start: Int) -> Int? {
        let comma: unichar = 0x2C
        let openBrace: unichar = 0x7B
        let closeBrace: unichar = 0x7D
        let quote: unichar = 0x22
        let backslash: unichar = 0x5C
        guard start + 1 < text.length,
              text.character(at: start) == comma,
              text.character(at: start + 1) == openBrace else {
            return nil
        }
        var depth = 0
        var inString = false
        var index = start + 1
        while index < text.length {
            let unit = text.character(at: index)
            if inString {
                if unit == backslash {
                    index += 2
                    continue
                }
                if unit == quote { inString = false }
            } else if unit == quote {
                inString = true
            } else if unit == openBrace {
                depth += 1
            } else if unit == closeBrace {
                depth -= 1
                if depth == 0 { return index + 1 }
            }
            index += 1
        }
        return text.length
    }
}
