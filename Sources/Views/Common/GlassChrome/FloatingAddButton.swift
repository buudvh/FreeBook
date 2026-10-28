import SwiftUI

/// Nút "+" nổi góc dưới phải của các màn danh sách (1.3.636) — thay mục "Thêm…" trong ngăn kéo / nút "+" trên header.
/// Cùng cỡ 52pt, cùng nền kính (`FloatingGlassBackground`) và cùng chỗ với nút tai nghe trong Reader.
struct FloatingAddButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background { FloatingGlassBackground() }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
    }
}

extension View {
    /// Gắn nút "+" nổi. Dùng `safeAreaInset` (không phải `overlay`) để cuộn tới cuối thì hàng cuối nằm **trên** nút,
    /// không bị nút che mất icon Xoá; danh sách vẫn cuộn xuyên qua vùng dưới nút như thường.
    func floatingAddButton(_ accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            FloatingAddButton(accessibilityLabel: accessibilityLabel, action: action)
        }
    }
}
