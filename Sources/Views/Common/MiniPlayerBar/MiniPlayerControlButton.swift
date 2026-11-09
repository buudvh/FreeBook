import SwiftUI

/// Nút điều khiển của thanh phát mini (`MiniPlayerBarChrome`): icon 17 pt nửa đậm màu trắng, vùng chạm cao 44 pt (rộng
/// mặc định 38 pt). `showsProgress` ⇒ vòng xoay trắng thay icon (đang tải).
struct MiniPlayerControlButton: View {
    let systemImage: String
    let label: String
    var width: CGFloat = 38
    var showsProgress = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if showsProgress {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: width, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
