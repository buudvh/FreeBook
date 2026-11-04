import SwiftUI

/// Chip lọc của màn Kiểm tra tiện ích hàng loạt, theo kiểu `ExtensionKindFilterBar` (màu nhấn người dùng chọn, chỉ dùng
/// dạng mờ).
struct ExtensionCheckFilterChip: View {
    let item: ExtensionCheckFilter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(item.label)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .accentColor : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
