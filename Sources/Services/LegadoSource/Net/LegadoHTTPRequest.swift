import Foundation

/// Request đã dựng xong từ một rule URL (spec §3.2): URL tuyệt đối đã mã hoá, phương thức, header đã gộp, thân.
/// Cookie từ kho **chưa** gộp ở đây — `LegadoEngineSession.perform` thêm lúc gửi (theo host của từng chặng chuyển hướng).
struct LegadoHTTPRequest {
    var url: String
    var method: String = "GET"
    var headers: [(name: String, value: String)] = []
    var body: Data?
    /// Bảng mã khai trong option (dùng để mã hoá request và là gợi ý thứ hai khi giải mã phản hồi, §4.5).
    var charset: String?
    var useWebView = false
    /// Giây chờ thêm sau khi WebView tải xong (`webViewDelayTime`).
    var webViewDelay: TimeInterval = 0
    /// Số lần thử lại khi lỗi mạng tạm thời (§4.3): mặc định 1, option `retry` ghi đè.
    var retryCount = 1
    var timeout: TimeInterval = 15
    /// `false` cho `java.get/post/head` (§4.7): trả nguyên phản hồi 3xx.
    var followRedirects = true
    var type: String?
    /// `sourceRegex` (spec §9.4): chỉ có tác dụng khi `useWebView` — URL tài nguyên đầu tiên trang request mà khớp
    /// **toàn chuỗi** regex này trở thành thân phản hồi.
    var sourceRegex: String?

    /// `data:` URL (spec §13.1): giải tại chỗ, không gửi mạng.
    var isDataURL: Bool {
        url.lowercased().hasPrefix("data:")
    }

    func header(_ name: String) -> String? {
        LegadoHeaderParser.value(name, in: headers)
    }

    mutating func setHeader(_ name: String, _ value: String) {
        headers = LegadoHeaderParser.merge(headers, [(name: name, value: value)])
    }

    /// `URLRequest` cho một chặng; `cookieHeader` (nếu có) gộp với header `Cookie` viết tay (bản viết tay thắng khoá trùng).
    func urlRequest(url target: URL, method overrideMethod: String? = nil, includeBody: Bool = true,
                    cookieHeader: String?) -> URLRequest {
        var request = URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = overrideMethod ?? method
        request.httpShouldHandleCookies = false
        for pair in headers where pair.name.caseInsensitiveCompare("Cookie") != .orderedSame {
            request.setValue(pair.value, forHTTPHeaderField: pair.name)
        }
        let manual = self.header("Cookie")
        if let merged = Self.mergeCookies(jar: cookieHeader, manual: manual), !merged.isEmpty {
            request.setValue(merged, forHTTPHeaderField: "Cookie")
        }
        if includeBody, let body, request.httpMethod != "GET", request.httpMethod != "HEAD" {
            request.httpBody = body
        }
        return request
    }

    /// Cookie kho + cookie viết tay: khoá trùng thì bản viết tay thắng (§4.2, U19).
    static func mergeCookies(jar: String?, manual: String?) -> String? {
        guard let jar, !jar.isEmpty else { return manual }
        guard let manual, !manual.isEmpty else { return jar }
        var pairs: [(String, String)] = []
        func add(_ text: String) {
            for piece in text.components(separatedBy: ";") {
                let trimmed = piece.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let name = trimmed.components(separatedBy: "=").first ?? trimmed
                if let index = pairs.firstIndex(where: { $0.0 == name }) {
                    pairs[index] = (name, trimmed)
                } else {
                    pairs.append((name, trimmed))
                }
            }
        }
        add(jar)
        add(manual)
        return pairs.map { $0.1 }.joined(separator: "; ")
    }
}
