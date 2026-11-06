import SwiftUI

/// Chữ hiển thị chung của trang Báo cáo kiểm tra (hàng danh sách + màn chi tiết): giờ, số đếm, nhãn trạng thái.
enum CheckReportFormatter {
    /// `06/11 14:32` (năm khác năm nay ⇒ thêm năm).
    static func dateText(_ date: Date?) -> String {
        guard let date else { return "Không rõ giờ" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        formatter.dateFormat = sameYear ? "dd/MM HH:mm" : "dd/MM/yyyy HH:mm"
        return formatter.string(from: date)
    }

    /// Dòng số đếm: `1240 nguồn · Đạt 812 · Lỗi 301` / `12 tiện ích · Đạt đủ 9 · Có lỗi 3`.
    static func countsText(_ summary: CheckReportSummary) -> String {
        if summary.status == .unreadable { return "Không đọc được file" }
        let scope: String
        if summary.status == .interrupted || summary.status == .running || summary.completed < summary.total {
            scope = "xong \(summary.completed)/\(summary.total) \(summary.kind.unitName)"
        } else {
            scope = "\(summary.total) \(summary.kind.unitName)"
        }
        switch summary.kind {
        case .legado:
            var parts = [scope, "Đạt \(summary.passed)", "Lỗi \(summary.failed)"]
            if summary.skipped > 0 { parts.append("Bỏ qua \(summary.skipped)") }
            return parts.joined(separator: " · ")
        case .script:
            return [scope, "Đạt đủ \(summary.passed)", "Có lỗi \(summary.failed)"].joined(separator: " · ")
        }
    }

    static func sizeText(_ bytes: Int64) -> String {
        BackupSizeEstimator.format(bytes)
    }

    /// `38 phút`, `2 giờ 5 phút`, `45 giây`.
    static func durationText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) giây" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) phút" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) giờ" : "\(minutes / 60) giờ \(rest) phút"
    }

    /// Nhãn trạng thái; `nil` khi lượt đã xong bình thường.
    static func statusBadge(_ status: CheckReportSummary.Status) -> (text: String, color: Color)? {
        switch status {
        case .running: return (text: "Đang chạy", color: Color.accentColor)
        case .interrupted: return (text: "Dở · app đã thoát", color: Color.orange)
        case .cancelled: return (text: "Đã dừng", color: Color.secondary)
        case .unreadable: return (text: "File hỏng", color: Color.red)
        case .finished: return nil
        }
    }
}
