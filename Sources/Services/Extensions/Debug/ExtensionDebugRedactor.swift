import Foundation

/// Cổng duy nhất biến dữ liệu thô thành chuỗi được phép hiện/gửi đi.
///
/// Chính sách redact của Phase 0, cố ý **allowlist** chứ không blacklist:
/// * URL: giữ scheme + host + path, **mọi giá trị query bị thay bằng `…`** (giữ lại tên khoá vì tên
///   khoá là thứ giúp đọc trace, còn giá trị mới là chỗ chứa token/session).
/// * Header, cookie, request/response body, nội dung chương, `configJson`, localStorage: **không bao
///   giờ** đi vào event ở MVP. Vì thế ở đây không có hàm nào nhận header hay body — thiếu hàm là
///   cách rẻ nhất để không ai vô tình gọi.
/// * Mọi chuỗi tự do (console, message lỗi, stack) bị chặn độ dài, và stack bị bỏ path tuyệt đối.
public enum ExtensionDebugRedactor {
    public static let maxMessageLength = 600
    public static let maxStackLength = 1200
    public static let maxURLLength = 300

    /// Giữ lại tên khoá query, thay giá trị bằng `…`. Chuỗi không phân tích được thì cắt ở `?`.
    public static func url(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else {
            let head = trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
            return truncate(String(head ?? ""), limit: maxURLLength)
        }
        components.user = nil
        components.password = nil
        components.fragment = nil
        if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.map { URLQueryItem(name: $0.name, value: "…") }
        }
        let rendered = components.string ?? trimmed
        return truncate(rendered, limit: maxURLLength)
    }

    public static func message(_ raw: String) -> String {
        truncate(collapseWhitespace(raw), limit: maxMessageLength)
    }

    /// Stack của JavaScriptCore có thể chứa path tuyệt đối trong sandbox — bỏ phần thư mục, giữ tên
    /// file cuối cùng để vẫn đọc được frame.
    public static func stack(_ raw: String) -> String {
        let stripped = raw
            .components(separatedBy: .newlines)
            .map { line -> String in
                guard let range = line.range(of: "/", options: .backwards) else { return line }
                return String(line[range.upperBound...])
            }
            .joined(separator: "\n")
        return truncate(stripped, limit: maxStackLength)
    }

    /// Hash nội dung script làm `sourceRevision`. Cắt 12 ký tự đầu: đủ để so khớp bản nháp mà không
    /// làm mỗi event dài thêm 64 ký tự.
    public static func revision(of scriptContent: String) -> String {
        String(scriptContent.sha256().prefix(12))
    }

    public static func truncate(_ raw: String, limit: Int) -> String {
        guard raw.count > limit else { return raw }
        return String(raw.prefix(limit)) + "… (+\(raw.count - limit))"
    }

    private static func collapseWhitespace(_ raw: String) -> String {
        raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
