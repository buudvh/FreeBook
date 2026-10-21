import Foundation

/// Một bước của lượt gỡ lỗi từng bước (spec §12.3) — bản chụp **bất biến** đi từ bộ chạy lên View.
///
/// Chỉ giữ trong bộ nhớ của màn gỡ lỗi; không ghi log file, không gửi ra ngoài. URL hiển thị nguyên văn trên màn hình;
/// bản **sao chép** báo cáo bỏ giá trị query (`LegadoDebugReportFormatter`).
struct LegadoDebugStep: Sendable, Identifiable, Equatable {
    enum Kind: String, Sendable {
        case search
        case explore
        case detail
        case toc
        case content

        var title: String {
            switch self {
            case .search: return "Tìm kiếm"
            case .explore: return "Khám phá"
            case .detail: return "Chi tiết"
            case .toc: return "Mục lục"
            case .content: return "Nội dung"
            }
        }
    }

    enum Status: Sendable, Equatable {
        case running
        case passed
        /// Chạy xong nhưng không có gì để đi tiếp (0 mục / không có link / nội dung rỗng).
        case empty
        case failed
        case cancelled
    }

    /// Một vết request (`LegadoEngineRequestRecord` của engine) rút gọn cho View — kiểu riêng để màn hình không phụ
    /// thuộc trực tiếp chữ ký của engine.
    struct Request: Sendable, Equatable {
        let method: String
        let url: String
        let finalUrl: String
        let statusCode: Int?
        let charset: String?
        let byteCount: Int
        let durationMs: Int
        let viaWebView: Bool
        let bodySnippet: String
        let errorMessage: String?
    }

    struct Field: Sendable, Equatable {
        let name: String
        let value: String
    }

    struct LogLine: Sendable, Equatable {
        /// `LegadoEngineDiagnostics.Kind.rawValue`.
        let kind: String
        let message: String
    }

    let id: Int
    let kind: Kind
    var status: Status
    /// URL / từ khoá đầu vào của bước.
    var input: String
    var durationMs: Int = 0
    /// Số mục (tìm/khám phá/mục lục), 1/0 (chi tiết có tên), số ký tự (nội dung).
    var count: Int?
    /// Nhãn đếm riêng của bước (vd "Số ảnh: 12" cho nguồn tranh); `nil` ⇒ View tự dựng theo loại bước.
    var countText: String?
    /// Trường trích được của mục đầu (tên trường → giá trị đã rút gọn 200 ký tự, `"(rỗng)"` khi trống).
    var fields: [Field] = []
    var requests: [Request] = []
    var logs: [LogLine] = []
    var unsupported: [String] = []
    var errorMessage: String?
    /// `LegadoRuntimeError.categoryName(of:)`: `http`, `noMatch`, `javaScript`, `timeout`…
    var errorCategory: String?
    /// Rule chính của bước (tên khoá → rule nguyên văn) — hiện khi bước rỗng / lỗi.
    var rule: Field?

    var isFailure: Bool { status == .failed }

    /// HTML/thân của request **cuối** (engine đã cắt tối đa 4 KB) — nút "Xem HTML trang".
    var lastBodySnippet: String {
        requests.last(where: { !$0.bodySnippet.isEmpty })?.bodySnippet ?? ""
    }

    /// Rút gọn giá trị trường cho thẻ bước.
    static func clip(_ text: String, limit: Int = 200) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(rỗng)" }
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}
