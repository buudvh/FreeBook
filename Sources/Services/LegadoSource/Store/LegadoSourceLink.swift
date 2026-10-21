import Foundation

/// Liên kết nhập nhanh nguồn Legado mở app từ ngoài (spec §12.2).
///
/// Tài liệu được phép không mô tả scheme nào (`[UNKNOWN]` U49); corpus có các dạng do nguồn tự dựng:
/// `legado://import/importonline?src=<URL tệp nguồn>`, `legado://import/addToBookshelf?src=<URL trang sách>`,
/// `yuedu://booksource/importonline?src=<URL đã encode>`. App chỉ đăng ký scheme `legado` (`project.yml`); `yuedu`
/// vẫn được nhận nếu iOS chuyển tới. Theo khuyến nghị an toàn của spec: **không** bao giờ nhập im lặng (View hỏi lại),
/// `src` chỉ nhận `http(s)`, tải tối đa 20 MB; `addToBookshelf` và dạng lạ ⇒ báo không hỗ trợ.
enum LegadoSourceLink {
    enum Action: Sendable, Equatable {
        /// Tải tệp nguồn ở URL rồi nhập như "Nhập nguồn từ URL".
        case importSources(url: String)
    }

    struct Issue: Error, Sendable, Equatable {
        let message: String
    }

    static let schemes: Set<String> = ["legado", "yuedu"]
    /// Trần tải của liên kết ngoài (spec §12.2 đề xuất 20 MB).
    static let maxDownloadBytes = 20 * 1024 * 1024

    /// `nil` = không phải liên kết nguồn Legado (scheme khác — để nơi khác xử lý).
    static func parse(_ url: URL) -> Result<Action, Issue>? {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else { return nil }
        let host = (url.host ?? "").lowercased()
        let path = url.path.split(separator: "/").map { $0.lowercased() }
        let action = path.last ?? ""
        guard host == "import" || host == "booksource" else {
            return .failure(Issue(message: "Liên kết \(scheme):// này chưa được hỗ trợ."))
        }
        switch action {
        case "importonline":
            guard let source = sourceParameter(in: url.absoluteString) else {
                return .failure(Issue(message: "Liên kết thiếu địa chỉ tệp nguồn (src)."))
            }
            guard isHTTPURL(source) else {
                return .failure(Issue(message: "Chỉ nhận địa chỉ tệp nguồn dạng http/https."))
            }
            return .success(.importSources(url: source))
        case "addtobookshelf":
            return .failure(Issue(message: "Liên kết \"thêm vào kệ\" của nguồn chưa được hỗ trợ — hãy tìm truyện trong app."))
        default:
            return .failure(Issue(message: "Liên kết \(scheme):// này chưa được hỗ trợ."))
        }
    }

    /// Giá trị `src`: lấy **nguyên phần sau** `src=` (URL nguồn có thể mang `&` của chính nó mà không encode), giải
    /// mã phần trăm một lần nếu chưa bắt đầu bằng `http`.
    static func sourceParameter(in absolute: String) -> String? {
        guard let marker = absolute.range(of: "?src=") ?? absolute.range(of: "&src=") else { return nil }
        var value = String(absolute[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.lowercased().hasPrefix("http"), let decoded = value.removingPercentEncoding {
            value = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.isEmpty ? nil : value
    }

    static func isHTTPURL(_ text: String) -> Bool {
        let lowered = text.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else { return false }
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? text
        guard let url = URL(string: text) ?? URL(string: encoded), let host = url.host else { return false }
        return !host.isEmpty
    }
}
