import SwiftUI

/// Ngăn cách nhóm trong ngăn kéo — khoảng trống trong suốt 12pt (thay `Divider()` trong `Menu`), không vẽ vạch.
struct SideDrawerDivider: View {
    var body: some View {
        Color.clear
            .frame(height: 12)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
