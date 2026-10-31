import SwiftUI

/// Phần hình của `VideoPlayerIconButton` — dùng lại làm nhãn cho `Menu`.
struct VideoPlayerIconLabel: View {
    let systemName: String
    var isActive = false
    var width: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isActive ? Color.accentColor : Color.white)
            .frame(width: width, height: 38)
            .contentShape(Rectangle())
    }
}
