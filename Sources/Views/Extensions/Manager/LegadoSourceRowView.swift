import SwiftUI

/// Một dòng nguồn Legado: tên đã dịch QT; chip loại, nhóm (dịch), "Cần đăng nhập", "Chưa hỗ trợ"; URL một dòng;
/// công tắc bật/tắt và nút 🗑 giống dòng tiện ích ở tab "Tất cả tiện ích". Dòng đang tắt chữ mờ hơn.
struct LegadoSourceRowView: View {
    let summary: LegadoSourceSummary
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.displayName)
                    .font(.headline)
                    .lineLimit(2)

                chipRow

                Text(summary.bookSourceUrl)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .opacity(summary.isEnabled ? 1 : 0.45)

            Spacer(minLength: 4)

            Toggle("", isOn: Binding(
                get: { summary.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .accessibilityLabel(summary.isEnabled ? "Tắt \(summary.displayName)" : "Bật \(summary.displayName)")

            ExtensionRowTrashButton(accessibilityLabel: "Xoá nguồn \(summary.displayName)", action: onDelete)
        }
        .padding(.vertical, 4)
    }

    /// Tối đa số chip nhóm hiện trên dòng; phần còn lại gộp thành "+N".
    private static let maxGroupChips = 2

    private var chipRow: some View {
        // Không dùng ScrollView ngang: nó giành cử chỉ vuốt chuyển tab của `TabView(.page)`.
        let groups = summary.translatedGroups
        return HStack(spacing: 6) {
            chip(summary.kind.label, tint: summary.kind == .text ? .purple : .blue, weight: .semibold)
            ForEach(Array(groups.prefix(Self.maxGroupChips).enumerated()), id: \.offset) { _, group in
                chip(group, tint: .green, weight: .regular)
            }
            if groups.count > Self.maxGroupChips {
                chip("+\(groups.count - Self.maxGroupChips)", tint: .green, weight: .regular)
            }
            if summary.needsLogin {
                chip("Cần đăng nhập", tint: .orange, weight: .semibold)
            }
            if !LegadoSourcePolicy.isSupportedInCurrentPhase(summary.kind) {
                chip("Chưa hỗ trợ", tint: .red, weight: .semibold)
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
}
