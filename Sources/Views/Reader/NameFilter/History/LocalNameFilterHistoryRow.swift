import SwiftUI

/// Một hàng của trang **Lịch sử lọc** (mockup H2 / H5, https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2): dòng 1 "giờ bắt
/// đầu · phạm vi" ("10:20 · chương 1–87 (dừng)"); dòng 2 theo trạng thái (`LocalNameFilterHistorySnapshot.Status`):
/// - đã lưu ⇒ "✓ Đã lưu X / Y" (✓ xanh) — chỉ xem, không chevron;
/// - chưa lưu, còn gói ⇒ "● Chưa lưu · lọc được Y" (● cam) + chevron — chạm mở lại màn duyệt;
/// - chưa lưu, gói đã bị xoá ⇒ "Chưa lưu · lọc được Y · Gói tạm đã bị xoá", chữ mờ, không chevron.
/// - lần không ra màn duyệt (mockup H2 bản 8 — nền sẫm `inactiveFill` do trang gắn, không chevron, chạm không mở gì):
///   "— Không ra name nào", "✕ Lỗi: <lý do ngắn>" (đỏ, `shortFailureReason`), "⊘ Đã huỷ" (phạm vi kèm "(huỷ)"),
///   "⚠ Bị ngắt — app thoát lúc đang lọc" (cam), "Đang lọc…".
/// Chế độ chọn nhiều (H5): vòng tích ở đầu hàng, không chevron. Chạm / vuốt do trang lo (`LocalNameFilterHistoryView`).
///
/// Giờ / ngày ghi kiểu 24 giờ cố định (không theo kiểu giờ của máy) — các hàm `…Text` dùng chung cho tiêu đề nhóm ngày,
/// hàng "Lịch sử lọc" của sheet và hộp hỏi xoá.
struct LocalNameFilterHistoryRow: View {
    /// Nền sẫm của lần không ra màn duyệt (thay ô mờ `AppGlassSheetModifier.rowFill` của sheet kính).
    static let inactiveFill = Color.black.opacity(0.28)

    let entry: LocalNameFilterHistoryEntry
    let status: LocalNameFilterHistorySnapshot.Status
    let isSelecting: Bool
    let isSelected: Bool

    private var isOpenable: Bool {
        if case .unsaved = status { return true }
        return false
    }

    private var isDraftGone: Bool {
        status == .draftGone
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "\(Self.timeText(entry.startedAt)) · \(entry.scopeText)")
                    .foregroundColor(.primary)
                    .lineLimit(1)
                statusLine
                    .font(.footnote)
                    .lineLimit(1)
            }
            .opacity(isDraftGone ? 0.5 : 1)
            Spacer(minLength: 8)
            if isOpenable && !isSelecting {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusLine: Text {
        switch status {
        case .saved(let count):
            return Text(verbatim: "✓").foregroundColor(.green).bold()
                + Text(verbatim: " Đã lưu \(count) / \(entry.filteredCount)").foregroundColor(.secondary)
        case .unsaved:
            return Text(verbatim: "●").foregroundColor(.orange)
                + Text(verbatim: " Chưa lưu · lọc được \(entry.filteredCount)").foregroundColor(.secondary)
        case .draftGone:
            return Text(verbatim: "Chưa lưu · lọc được \(entry.filteredCount) · Gói tạm đã bị xoá")
                .foregroundColor(.secondary)
        case .noNames:
            return Text(verbatim: "— Không ra name nào").foregroundColor(.secondary)
        case .failed(let message):
            return Text(verbatim: "✕ Lỗi: \(Self.shortFailureReason(message))").foregroundColor(.red)
        case .cancelled:
            return Text(verbatim: "⊘ Đã huỷ").foregroundColor(.secondary)
        case .interrupted:
            return Text(verbatim: "⚠ Bị ngắt — app thoát lúc đang lọc").foregroundColor(.orange)
        case .running:
            return Text(verbatim: "Đang lọc…").foregroundColor(.secondary)
        }
    }

    /// Lý do ngắn của lời lỗi bộ lọc: phần trước dấu ":" / " — " đầu tiên (bỏ chi tiết kỹ thuật), chữ đầu viết thường —
    /// "Không tải được model nhận diện tên: …" ⇒ "không tải được model nhận diện tên". Rỗng ⇒ "không rõ".
    static func shortFailureReason(_ message: String) -> String {
        var reason = message.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [": ", " — "] {
            if let range = reason.range(of: separator) {
                reason = String(reason[..<range.lowerBound])
            }
        }
        reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = reason.first else { return "không rõ" }
        return first.lowercased() + reason.dropFirst()
    }

    // MARK: - Giờ / ngày (24 giờ cố định)

    /// "10:20".
    static func timeText(_ date: Date) -> String {
        let calendar = Calendar.current
        return String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }

    /// "27/11"; khác năm nay ⇒ "27/11/2025".
    static func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        let day = String(format: "%02d/%02d", calendar.component(.day, from: date), calendar.component(.month, from: date))
        let year = calendar.component(.year, from: date)
        return year == calendar.component(.year, from: Date()) ? day : "\(day)/\(year)"
    }

    /// "28/11 11:46" — hàng "Lịch sử lọc" của sheet ("Lần gần nhất …").
    static func stampText(_ date: Date) -> String {
        "\(dayText(date)) \(timeText(date))"
    }

    /// Hôm nay ⇒ "10:20", ngày khác ⇒ "27/11 22:14" — hộp hỏi "Xoá lần lọc …?".
    static func shortStampText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? timeText(date) : stampText(date)
    }
}
