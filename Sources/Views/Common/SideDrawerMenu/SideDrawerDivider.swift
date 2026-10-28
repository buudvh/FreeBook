import SwiftUI

/// Vạch ngăn nhóm trong ngăn kéo — dải tối dày như vạch nhóm của menu hệ thống (thay `Divider()` trong `Menu`).
struct SideDrawerDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.28))
            .frame(height: 6)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
