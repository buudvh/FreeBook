import Foundation

/// Cách đăng nhập của một nguồn (spec §10.2), suy ra từ `loginUrl` + `loginUi`.
enum LegadoLoginMode: Equatable, Sendable {
    /// Không có đăng nhập (`loginUrl` rỗng, rác `{"url":"null"}`, chú thích…): ẩn mục "Đăng nhập".
    case none
    /// Trình duyệt đăng nhập tại `url` (đã ghép với `bookSourceUrl`); đóng ⇒ nhập cookie vào kho của nguồn.
    case web(url: String)
    /// Form gốc từ `loginUi` (có thể không có ô nào — U35). `hasLoginFunction`: JS có định nghĩa `login` ⇒ hiện nút
    /// "Đăng nhập"; không có (nguồn dùng `loginUi` làm menu cài đặt) ⇒ chỉ các nút của nguồn.
    case form(hasLoginFunction: Bool)

    /// Phân loại theo bảng §10.2.
    static func resolve(loginUrl rawURL: String, loginUi rawUi: String, baseURL: String) -> LegadoLoginMode {
        let loginUrl = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let loginUi = rawUi.trimmingCharacters(in: .whitespacesAndNewlines)
        if isScript(loginUrl) {
            let code = LegadoEngineSession.strippedScript(loginUrl)
            let hasLogin = definesLoginFunction(code)
            if !loginUi.isEmpty { return .form(hasLoginFunction: hasLogin) }
            return hasLogin ? .form(hasLoginFunction: true) : .none
        }
        if isURL(loginUrl) {
            let resolved = LegadoURLResolver.hasHTTPScheme(loginUrl)
                ? loginUrl : LegadoURLResolver.absolute(loginUrl, base: baseURL)
            return LegadoURLResolver.hasHTTPScheme(resolved) ? .web(url: resolved) : .none
        }
        return .none
    }

    /// "JS": có tiền tố `@js:`/`<js>`, hoặc (sau khi bóc) chứa `function`, `=>`, `java.`, `source.`, `eval(`, khai báo biến.
    static func isScript(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("@js:") || lower.hasPrefix("<js>") { return true }
        if isURL(text) { return false }
        let markers = ["function", "=>", "java.", "source.", "eval(", "var ", "let ", "const "]
        return markers.contains { lower.contains($0) }
    }

    /// "URL": `http(s)://…`, `/…`, hoặc `tên.php|html|htm|asp|aspx…`.
    static func isURL(_ text: String) -> Bool {
        if LegadoURLResolver.hasHTTPScheme(text) || text.hasPrefix("/") { return true }
        return text.range(of: #"^[\w.\-]+\.(php|html?|aspx?)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// JS có định nghĩa hàm `login` (khai báo hàm, gán hàm/mũi tên, hoặc phương thức rút gọn).
    static func definesLoginFunction(_ code: String) -> Bool {
        let patterns = [
            #"function\s+login\s*\("#,
            #"\blogin\s*[:=]\s*(async\s+)?(function\b|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)"#,
            #"(^|[\s;{,])login\s*\([^)]*\)\s*\{"#
        ]
        return patterns.contains { code.range(of: $0, options: .regularExpression) != nil }
    }
}
