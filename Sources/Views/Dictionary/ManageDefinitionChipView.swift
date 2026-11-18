import SwiftUI

/// Một nghĩa dạng viên con nhộng trong màn "Quản lý nghĩa từ" (kiểu chip từ 1.3.981).
///
/// - Bấm thân chip ⇒ chọn để sửa (màn cha mở ô sửa dưới nhóm). Chip đã xoá thì bấm thân cũng là hoàn tác.
/// - Nút tròn góc trên phải: `xmark` xoá nhanh (xoá mềm), chip đã xoá thì đổi thành `arrow.uturn.backward` để hoàn tác.
/// - Chip đứng đầu nhóm tô màu nhấn: đó là nghĩa được dùng khi dịch (`TranslateUtils.getFirstMeaning`).
///
/// Nút góc nằm **trong** khung layout của chip (chip lùi `badgeInset` ở trên/phải) chứ không nhô ra ngoài như
/// `ChipCornerBadge`: nút này bấm được, mà phần nhô ra ngoài khung thì chip kế bên che mất vùng chạm.
struct ManageDefinitionChipView: View {
    /// Chip lùi vào chừng này ở trên/phải để chừa chỗ cho nút góc.
    static let badgeInset: CGFloat = 6
    static let chipHeight: CGFloat = 32
    private static let badgeDiameter: CGFloat = 18
    private static let badgeHitSize: CGFloat = 26
    private static let maxChipWidth: CGFloat = 240

    let text: String
    let isPrimary: Bool
    let isSelected: Bool
    let isDeleted: Bool
    let onTap: () -> Void
    let onToggleDeleted: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) { label }
                .buttonStyle(.plain)
                .padding(.top, Self.badgeInset)
                .padding(.trailing, Self.badgeInset)
                .accessibilityLabel(chipAccessibilityLabel)

            Button(action: onToggleDeleted) { badge }
                .buttonStyle(.plain)
                .accessibilityLabel(isDeleted ? "Hoàn tác xoá nghĩa" : "Xoá nghĩa")
        }
    }

    private var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var label: some View {
        Text(isBlank ? "Nghĩa…" : text)
            .font(.subheadline)
            .strikethrough(isDeleted)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundColor(textColor)
            .padding(.horizontal, 12)
            // Chip ngắn vẫn phải rộng hơn vùng chạm của nút góc, không thì không còn chỗ để bấm chọn.
            .frame(minWidth: 44, maxWidth: Self.maxChipWidth)
            .frame(height: Self.chipHeight)
            .background(fillColor, in: Capsule())
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(Capsule())
    }

    private var badge: some View {
        Image(systemName: isDeleted ? "arrow.uturn.backward" : "xmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(isDeleted ? .green : Color(white: 0.85))
            .frame(width: Self.badgeDiameter, height: Self.badgeDiameter)
            .background(Color(white: 0.25), in: Circle())
            .frame(width: Self.badgeHitSize, height: Self.badgeHitSize, alignment: .topTrailing)
            .contentShape(Rectangle())
    }

    private var textColor: Color {
        if isDeleted || isBlank { return .secondary }
        return isPrimary ? .accentColor : .primary
    }

    private var fillColor: Color {
        if isDeleted { return .clear }
        return isPrimary ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.1)
    }

    private var borderColor: Color {
        if isDeleted { return Color.primary.opacity(0.15) }
        if isSelected { return Color.accentColor.opacity(0.9) }
        return isPrimary ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.22)
    }

    private var chipAccessibilityLabel: String {
        let name = isBlank ? "Nghĩa trống" : text
        if isDeleted { return "\(name), đã xoá" }
        return isPrimary ? "\(name), nghĩa đang dùng khi dịch" : name
    }
}
