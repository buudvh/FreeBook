import Foundation

/// Ghép URL tương đối, tách khối option `,{…}`, chuẩn hoá URL để so (spec §1.4, §2.15, §3.7, §5.6).
///
/// Ghép bằng thao tác chuỗi theo RFC 3986 thay vì `URL(string:relativeTo:)`: Foundation (iOS 17+) tự mã hoá ký tự
/// không phải ASCII bằng UTF-8, làm hỏng từ khoá phải mã hoá GBK ở bước sau (§3.8).
enum LegadoURLResolver {
    // MARK: - URL gốc của nguồn (§1.4)

    /// `bookSourceUrl` → URL gốc: trim, bỏ phần từ `#` đầu tiên. Không phải `http(s)://` ⇒ `""` (nguồn tự dựng URL bằng JS).
    static func sourceBaseURL(_ key: String) -> String {
        var text = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return hasHTTPScheme(text) ? text : ""
    }

    static func hasHTTPScheme(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// Có scheme RFC 3986 (`http:`, `data:`, `javascript:`…).
    static func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.unicodeScalars.first, CharacterSet.letters.contains(first), first.isASCII else { return false }
        return scheme.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "+-.".unicodeScalars.contains($0)) }
    }

    // MARK: - Khối option

    /// Tách khối option `,{…}` **ở cuối** chuỗi (ngoài `{{…}}`). Không có ⇒ `option == nil`.
    static func splitOption(_ text: String) -> (url: String, option: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(trimmed.utf8)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == LegadoRuleScanner.brace, index + 1 < bytes.count, bytes[index + 1] == LegadoRuleScanner.brace,
               let end = LegadoRuleScanner.balancedEnd(bytes, from: index) {
                index = end
                continue
            }
            if byte == UInt8(ascii: ",") {
                var brace = index + 1
                while brace < bytes.count, bytes[brace] == 0x20 || bytes[brace] == 0x0A || bytes[brace] == 0x0D || bytes[brace] == 0x09 {
                    brace += 1
                }
                if brace < bytes.count, bytes[brace] == LegadoRuleScanner.brace,
                   let end = LegadoRuleScanner.balancedEnd(bytes, from: brace),
                   bytes[end...].allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
                    let url = LegadoRuleScanner.string(bytes, 0, index).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (url, LegadoRuleScanner.string(bytes, brace, end))
                }
            }
            index += 1
        }
        return (trimmed, nil)
    }

    // MARK: - Ghép URL

    /// Ghép `reference` với `base` (bỏ fragment của base). `base` không phải URL ⇒ trả nguyên `reference`.
    static func absolute(_ reference: String, base: String) -> String {
        let ref = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if ref.isEmpty { return "" }
        if hasScheme(ref) { return ref }
        guard let parts = BaseParts(base) else { return ref }
        if ref.hasPrefix("//") { return parts.scheme + ":" + ref }
        if ref.hasPrefix("/") { return parts.origin + removeDotSegments(in: ref) }
        if ref.hasPrefix("?") { return parts.origin + parts.path + ref }
        if ref.hasPrefix("#") { return parts.origin + parts.path + parts.query + ref }
        let directory: String
        if let slash = parts.path.lastIndex(of: "/") {
            directory = String(parts.path[...slash])
        } else {
            directory = "/"
        }
        return parts.origin + removeDotSegments(in: directory + ref)
    }

    /// Trường URL (§2.15): trim; khối option giữ nguyên; `javascript:…`, `#`, rỗng ⇒ `""`; `data:`/`http(s)` giữ nguyên.
    static func absoluteFieldURL(_ raw: String, base: String, fallbackBase: String) -> String {
        let split = splitOption(raw)
        let url = split.url
        let lower = url.lowercased()
        if url.isEmpty || url == "#" || lower.hasPrefix("javascript:") { return "" }
        if lower.hasPrefix("data:") { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        let effectiveBase = BaseParts(base) != nil ? base : fallbackBase
        let resolved = absolute(url, base: effectiveBase)
        guard let option = split.option else { return resolved }
        return resolved + "," + option
    }

    /// Chuẩn hoá để so trùng trong phân trang (§5.6): bỏ khối option, bỏ fragment; phân biệt hoa thường path/query.
    static func normalizedForComparison(_ url: String) -> String {
        var text = splitOption(url).url
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        if let parts = BaseParts(text) {
            return parts.scheme.lowercased() + "://" + parts.authority.lowercased() + parts.path + parts.query
        }
        return text
    }

    /// Host của URL (hoặc của `bookSourceUrl`); chuỗi không scheme thì thử như host trần.
    static func host(of url: String) -> String? {
        let base = splitOption(url).url
        let candidate = hasHTTPScheme(base) ? sourceBaseURL(base) : "http://" + base
        return BaseParts(candidate).map { parts in
            var authority = parts.authority
            if let at = authority.lastIndex(of: "@") { authority = String(authority[authority.index(after: at)...]) }
            if let colon = authority.lastIndex(of: ":"), !authority.hasSuffix("]") { authority = String(authority[..<colon]) }
            return authority.lowercased()
        }.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Nội bộ

    private struct BaseParts {
        var scheme: String
        var authority: String
        var path: String
        var query: String

        var origin: String { scheme + "://" + authority }

        init?(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = trimmed.range(of: "://") else { return nil }
            let schemeText = String(trimmed[..<separator.lowerBound])
            guard !schemeText.isEmpty, !schemeText.contains("/"), !schemeText.contains(" ") else { return nil }
            var rest = String(trimmed[separator.upperBound...])
            if let hash = rest.firstIndex(of: "#") { rest = String(rest[..<hash]) }
            let authorityEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" }) ?? rest.endIndex
            let remainder = String(rest[authorityEnd...])
            var pathText = remainder
            var queryText = ""
            if let question = remainder.firstIndex(of: "?") {
                pathText = String(remainder[..<question])
                queryText = String(remainder[question...])
            }
            scheme = schemeText
            authority = String(rest[..<authorityEnd])
            path = pathText.isEmpty ? "/" : pathText
            query = queryText
        }
    }

    /// Bỏ `.`/`..` trong phần path (giữ nguyên query sau `?`).
    private static func removeDotSegments(in reference: String) -> String {
        var path = reference
        var suffix = ""
        if let question = reference.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            path = String(reference[..<question])
            suffix = String(reference[question...])
        }
        guard path.contains("./") || path.hasSuffix("/.") || path.hasSuffix("/..") else { return path + suffix }
        var output: [String] = []
        let segments = path.components(separatedBy: "/")
        for (index, segment) in segments.enumerated() {
            if segment == "." {
                if index == segments.count - 1 { output.append("") }
                continue
            }
            if segment == ".." {
                if output.count > 1 { output.removeLast() }
                if index == segments.count - 1 { output.append("") }
                continue
            }
            output.append(segment)
        }
        var joined = output.joined(separator: "/")
        if !joined.hasPrefix("/") { joined = "/" + joined }
        return joined + suffix
    }
}
