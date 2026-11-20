import SwiftUI

/// Nhãn "NSFW" (chữ trắng, nền đỏ) đặt ở góc trên-phải icon của tiện ích NSFW (`RepositoryFilterPolicy.isNsfwSource`).
/// Cỡ chữ co theo cỡ icon (hệ số 0,22 — bốn chữ nên nhỏ hơn 0,28 của nhãn "18+" cũ) nhưng không nhỏ hơn 7pt để còn đọc
/// được ở icon 14pt.
struct ExtensionNsfwBadge: View {
    let iconSize: CGFloat

    var body: some View {
        Text("NSFW")
            .font(.system(size: max(7, iconSize * 0.22), weight: .heavy))
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, max(2, iconSize * 0.06))
            .padding(.vertical, 1)
            .background(Color.red, in: Capsule())
            .offset(x: iconSize * 0.25, y: -iconSize * 0.2)
            .accessibilityLabel(Text("Nội dung nhạy cảm"))
    }
}
