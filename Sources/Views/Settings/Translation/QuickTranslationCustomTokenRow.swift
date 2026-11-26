import SwiftUI

/// Một hàng của màn **Token tùy chọn** (`QuickTranslationCustomTokenListView`, 1.3.1063), kiểu `QuickTranslationSurnameRow`:
/// dòng 1 cú pháp `<@tên>` `.headline` chữ đều, dòng 2 "mô tả · N từ" `.subheadline` màu phụ (+ "đang tắt", hàng tắt mờ
/// 50%), cụm icon `[Tắt/Bật] [Xoá]`. Chạm thân hàng mở danh sách từ; không bọc cả hàng trong `Button`.
struct QuickTranslationCustomTokenRow: View {
    let token: QuickTranslationCustomToken
    let onOpen: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    private var subtitle: String {
        var parts = [token.displayTitle, "\(token.entries.count) từ"]
        if !token.isEnabled { parts.append("đang tắt") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: token.syntax)
                        .font(.system(.headline, design: .monospaced))
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .opacity(token.isEnabled ? 1 : 0.5)

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }

            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: token.isEnabled ? "pause.circle" : "play.circle")
                        .foregroundColor(token.isEnabled ? .orange : .green)
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(token.isEnabled ? "Tắt token \(token.syntax)" : "Bật token \(token.syntax)")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Xoá token \(token.syntax)")
            }
        }
        .padding(.vertical, 2)
        .accessibilityAction(named: "Mở danh sách từ") { onOpen() }
    }
}
