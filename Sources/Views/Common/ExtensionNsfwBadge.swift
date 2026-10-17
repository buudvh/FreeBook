import SwiftUI

/// Nhãn "18+" (chữ trắng, nền đỏ) đặt ở góc trên-phải icon của tiện ích NSFW (`RepositoryFilterPolicy.isNsfwSource`).
/// Cỡ chữ co theo cỡ icon nhưng không nhỏ hơn 7pt để còn đọc được ở icon 14pt.
struct ExtensionNsfwBadge: View {
    let iconSize: CGFloat

    var body: some View {
        Text("18+")
            .font(.system(size: max(7, iconSize * 0.28), weight: .heavy))
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, max(2, iconSize * 0.06))
            .padding(.vertical, 1)
            .background(Color.red, in: Capsule())
            .offset(x: iconSize * 0.2, y: -iconSize * 0.2)
            .accessibilityLabel(Text("Nội dung 18+"))
    }
}
