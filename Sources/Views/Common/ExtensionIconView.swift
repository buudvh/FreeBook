import SwiftUI

struct ExtensionIconView: View {
    let localPath: String
    let iconUrl: String?
    let size: CGFloat

    @AppStorage(EInkModeSettings.Key.enabled) private var isEInkEnabled = false
    @AppStorage(EInkModeSettings.Key.monochromeCovers) private var monochromeCovers = true
    @AppStorage(EInkModeSettings.Key.paperColor) private var paperColorRaw = EInkModeSettings.EInkPaperColor.gray.rawValue
    private var paper: Color {
        EInkPalette.paperColor(for: EInkModeSettings.EInkPaperColor(rawValue: paperColorRaw) ?? .gray)
    }

    var body: some View {
        content
            // Icon tiện ích là ảnh nhiều màu; trên e-ink chuyển thang xám trước để panel khỏi phải tự
            // dither, giữ cho hình còn nhận ra được.
            .grayscale(isEInkEnabled && monochromeCovers ? 1 : 0)
            .contrast(isEInkEnabled && monochromeCovers ? 1.35 : 1)
    }

    @ViewBuilder
    private var content: some View {
        if let uiImage = ExtensionIconImageCache.shared.icon(forExtensionAt: localPath) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .cornerRadius(size * 0.18)
        } else if let iconUrl = iconUrl, let url = URL(string: iconUrl) {
            AsyncImage(url: url) { image in
                image.resizable()
            } placeholder: {
                fallbackIcon
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .cornerRadius(size * 0.18)
        } else {
            fallbackIcon
        }
    }

    /// Bản gốc là nền `accentColor.opacity(0.1)` + icon accent. Trên e-ink nền 10% gần như vô hình, nên
    /// đổi thành **nền trắng + viền đen** để ô icon vẫn tách khỏi danh sách.
    private var fallbackIcon: some View {
        Image(systemName: "puzzlepiece.extension")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.7, height: size * 0.7)
            .padding(size * 0.15)
            .background(isEInkEnabled ? paper : Color.accentColor.opacity(0.1))
            .foregroundColor(isEInkEnabled ? EInkPalette.ink : .accentColor)
            .cornerRadius(size * 0.18)
            .overlay {
                if isEInkEnabled {
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth)
                }
            }
    }
}
