import SwiftUI

/// Vạch tiến độ 2 pt ở mép trên thanh phát mini (`MiniPlayerBarChrome`), màu nhấn (`.tint`), chừa hai đầu nửa bán kính bo
/// góc để không bị cắt ở góc bo. `fraction` ngoài 0…1 bị kẹp.
struct MiniPlayerProgressLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.tint)
                .frame(width: proxy.size.width * CGFloat(min(1, max(0, fraction))), height: 2)
        }
        .frame(height: 2)
        .padding(.horizontal, MiniPlayerBarChrome.cornerRadius / 2)
        .accessibilityHidden(true)
    }
}
