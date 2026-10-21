import SwiftUI

/// Thẻ đầu màn **Chi tiết nguồn Legado**: tên dịch QT, "<tên gốc> · Phiên bản N", chip loại / nhóm / "Cần đăng nhập",
/// URL nguồn, ghi chú 2 dòng có "Xem thêm", rồi hàng nút tròn có nhãn **Trình duyệt · Đăng nhập · Xoá** (cùng dáng
/// thẻ đầu của màn Cấu hình tiện ích).
///
/// Thiếu nút nào (`nil`) thì các nút còn lại giãn đều; nút Đăng nhập chỉ có khi nguồn khai `loginUrl`. Mọi nút dùng
/// `.buttonStyle(.borderless)`: trong một dòng của `Form`, nút kiểu mặc định khiến chạm đâu cũng bấm mọi nút của dòng.
struct LegadoSourceDetailHeaderCard: View {
    let summary: LegadoSourceSummary
    /// Ghi chú nguồn (`bookSourceComment`) — có thể là HTML.
    let comment: String
    var onOpenBrowser: (() -> Void)? = nil
    var onLogin: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.displayName)
                    .font(.headline)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                chipRow
                Text(summary.bookSourceUrl)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if !commentText.isEmpty {
                ExpandableTextView(text: commentText, lineLimit: 2, font: .footnote, foregroundColor: .secondary)
            }

            actionRow
        }
        .padding(.vertical, 4)
        .buttonStyle(.borderless)
    }

    // MARK: - Thông tin

    /// Tên gốc (khác tên dịch) · phiên bản.
    private var subtitle: String {
        let version = "Phiên bản \(summary.version)"
        guard summary.name != summary.displayName, !summary.name.isEmpty else { return version }
        return "\(summary.name) · \(version)"
    }

    private var commentText: String {
        comment.cleanHTML().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            chip(summary.kind.label, tint: summary.kind == .text ? .purple : .blue, weight: .semibold)
            ForEach(Array(summary.translatedGroups.prefix(3).enumerated()), id: \.offset) { _, group in
                chip(group, tint: .green, weight: .regular)
            }
            if summary.translatedGroups.count > 3 {
                chip("+\(summary.translatedGroups.count - 3)", tint: .green, weight: .regular)
            }
            if summary.needsLogin {
                chip("Cần đăng nhập", tint: .orange, weight: .semibold)
            }
        }
        .lineLimit(1)
    }

    private func chip(_ text: String, tint: Color, weight: Font.Weight) -> some View {
        Text(text)
            .font(.system(size: 9, weight: weight))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12))
            .foregroundColor(tint)
            .cornerRadius(4)
    }

    // MARK: - Hàng nút

    private var actionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            if let onOpenBrowser {
                actionButton(title: "Trình duyệt", systemImage: "safari", action: onOpenBrowser)
            }
            if let onLogin {
                actionButton(title: "Đăng nhập", systemImage: "person.badge.key", action: onLogin)
            }
            if let onDelete {
                actionButton(title: "Xoá", systemImage: "trash", iconColor: .red, titleColor: .red, action: onDelete)
            }
        }
    }

    /// Nút tròn 44pt + nhãn nhỏ bên dưới, chia đều chiều ngang (không dùng `Label` — trong `Form` iOS dàn lệch).
    private func actionButton(
        title: String,
        systemImage: String,
        iconColor: Color = .primary,
        titleColor: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: { action() }) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemFill), in: Circle())
                Text(title)
                    .font(.caption)
                    .foregroundColor(titleColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }
}
