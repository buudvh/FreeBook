import Foundation

/// Tóm tắt một file báo cáo kiểm tra cho trang danh sách — bản sao bất biến, dựng ngoài main (`CheckReportCatalog`).
struct CheckReportSummary: Identifiable, Sendable, Hashable {
    enum Status: Sendable, Hashable {
        /// Lượt đang chạy trong phiên app này — không xoá được.
        case running
        /// File còn `state: running` nhưng không còn lượt nào chạy: app đã thoát (hoặc bị iOS tắt) giữa chừng.
        case interrupted
        case finished
        case cancelled
        /// Không giải mã được (file hỏng / định dạng lạ) — vẫn xoá được.
        case unreadable
    }

    let kind: CheckReportKind
    let fileName: String
    let byteCount: Int64
    /// Tên phạm vi do màn kiểm tra đặt; `nil` ở báo cáo cũ / lượt từ Debug server.
    let title: String?
    let startedAt: Date?
    let finishedAt: Date?
    let status: Status
    /// Số nguồn/tiện ích của lượt và số đã có kết quả.
    let total: Int
    let completed: Int
    /// Legado: nguồn đạt / lỗi / bỏ qua. JS: tiện ích đạt đủ / có lỗi (không có bỏ qua).
    let passed: Int
    let failed: Int
    let skipped: Int

    var id: String { kind.rawValue + "/" + fileName }

    var isDeletable: Bool { status != .running }

    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return status == .unreadable ? fileName : "\(total) \(kind.unitName)"
    }

    /// Ngày giờ bắt đầu (file hỏng ⇒ đọc từ tên file).
    var displayDate: Date? {
        startedAt ?? CheckReportStore.date(fromFileName: fileName)
    }

    /// Thời gian chạy (giây) khi lượt đã kết thúc.
    var durationSeconds: Int? {
        guard let startedAt, let finishedAt else { return nil }
        return max(0, Int(finishedAt.timeIntervalSince(startedAt)))
    }
}
