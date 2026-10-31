import SwiftUI

/// Dải báo nhỏ "Tự dịch QT · theo …" ngay dưới dải tab (mockup 2026-10-30, màn "Mới 1"): viên kính có chấm xanh, hiện
/// theo `BypassBrowserTab.translateHint` — store tự xoá chữ sau 2 s nên dải tự ẩn theo giá trị, view không hẹn giờ riêng.
/// Không nhận chạm: chỉ để đọc, không che thao tác trên trang.
struct BrowserTranslateHintBanner: View {
    let text: String?

    /// Xanh hệ thống của mockup (`#0a84ff`).
    private static let dotColor = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)

    var body: some View {
        ZStack {
            if let text {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Self.dotColor)
                        .frame(width: 8, height: 8)
                        .background(
                            Circle()
                                .fill(Self.dotColor.opacity(0.18))
                                .frame(width: 16, height: 16)
                        )
                    Text(text)
                        .font(.system(size: 11.5))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background { BrowserGlassCapsuleBackground(outlineOpacity: 0.14) }
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: text)
        .allowsHitTesting(false)
    }
}
