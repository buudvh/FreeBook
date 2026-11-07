import SwiftUI

/// Nút "+" nổi góc dưới phải của các màn danh sách (1.3.636) — thay mục "Thêm…" trong ngăn kéo / nút "+" trên header.
/// Cùng cỡ 52pt, cùng nền kính (`FloatingGlassBackground`) và cùng chỗ với nút tai nghe trong Reader. `systemImage`
/// đổi icon cho nút nổi cùng kiểu khác (kính lúp / ✕ của danh sách chương trong sheet Hẹn giờ TTS); mặc định "+".
///
/// Trang đủ điều kiện có nút Home nổi (`FloatingHomePlacement`) ⇒ nút "+" thành **menu xổ** (`FloatingActionMenu`):
/// bấm "+" ⇒ pill hành động gốc (chữ = `accessibilityLabel`, vd "Thêm từ mới") và pill "Về trang gốc" **dưới cùng**.
/// Trang không đủ điều kiện ⇒ bấm một chạm như cũ. Mọi nút nổi kiểu này đăng ký trang với `FloatingHomeRegistry` nên
/// tiêu đề không vẽ thêm Home tròn riêng (nút icon khác "+" thì không có Home, tránh hai nút đè một chỗ).
struct FloatingAddButton: View {
    let accessibilityLabel: String
    var systemImage: String = "plus"
    let action: () -> Void

    var body: some View {
        FloatingHomeReader(role: .addButton) { placement in
            if systemImage == "plus", let home = placement?.homeAction {
                FloatingActionMenu(
                    accessibilityLabel: accessibilityLabel,
                    items: [
                        FloatingActionItem(id: "floating-add", title: accessibilityLabel, systemImage: systemImage) {
                            action()
                        },
                        .home(home)
                    ]
                )
            } else {
                FloatingRoundButton(systemImage: systemImage, accessibilityLabel: accessibilityLabel) {
                    action()
                }
            }
        }
        .padding(.trailing, FloatingRoundButton.trailingInset)
        .padding(.bottom, FloatingRoundButton.bottomInset)
    }
}

extension View {
    /// Gắn nút "+" nổi. Dùng `safeAreaInset` (không phải `overlay`) để cuộn tới cuối thì hàng cuối nằm **trên** nút,
    /// không bị nút che mất icon Xoá; danh sách vẫn cuộn xuyên qua vùng dưới nút như thường. Menu xổ (khi trang có Home)
    /// vẽ đè lên trên nút nên vùng inset luôn chỉ 52 + 12.
    func floatingAddButton(
        _ accessibilityLabel: String,
        systemImage: String = "plus",
        action: @escaping () -> Void
    ) -> some View {
        safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            FloatingAddButton(accessibilityLabel: accessibilityLabel, systemImage: systemImage, action: action)
        }
    }
}
