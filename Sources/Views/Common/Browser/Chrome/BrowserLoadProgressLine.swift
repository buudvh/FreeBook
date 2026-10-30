import SwiftUI

/// Vạch tiến độ 2pt dưới dải tab của trình duyệt người dùng (mockup 2026-10-30): rãnh mờ luôn hiện như một đường ngăn,
/// phần đã nạp tô đậm chỉ khi tab đang tải. Dùng `.primary` để vẫn thấy được nếu màn ở giao diện sáng.
struct BrowserLoadProgressLine: View {
    let isLoading: Bool
    let progress: Double

    /// Không bao giờ vẽ thanh rỗng khi vừa bắt đầu tải (WebKit báo 0 trong khoảnh khắc đầu).
    private static let minimumVisibleFraction = 0.05

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary)
                    .scaleEffect(x: fraction, y: 1, anchor: .leading)
                    .opacity(isLoading ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: progress)
                    .animation(.easeOut(duration: 0.25), value: isLoading)
            }
            .accessibilityHidden(true)
    }

    private var fraction: CGFloat {
        CGFloat(min(max(progress, Self.minimumVisibleFraction), 1))
    }
}
