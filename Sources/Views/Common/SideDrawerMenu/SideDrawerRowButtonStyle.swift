import SwiftUI

/// Kiểu nút của hàng ngăn kéo: không tô màu nhấn (màu nhấn của app là trắng), chỉ sáng nền nhẹ khi đang nhấn.
struct SideDrawerRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.1) : Color.clear)
    }
}
