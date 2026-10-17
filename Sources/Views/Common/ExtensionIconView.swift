import SwiftUI

struct ExtensionIconView: View {
    let localPath: String
    let iconUrl: String?
    let size: CGFloat
    
    var body: some View {
        if let uiImage = ExtensionIconImageCache.shared.icon(forExtensionAt: localPath) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .cornerRadius(size * 0.18)
        } else if let url = resolvedIconURL {
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
    
    /// Icon tuyệt đối dùng nguyên văn; icon tương đối hoặc `//` thì ghép `source` của tiện ích (hợp đồng extension).
    /// Chỉ tra `source` khi thật sự cần ghép — có thể phải đọc `plugin.json` từ đĩa, mà hàm này chạy trong `body`.
    private var resolvedIconURL: URL? {
        guard let raw = iconUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if CoverRequestResolver.isAbsolute(raw) {
            return URL(string: raw)
        }
        let resolved = ExtensionURLFormatter.resolveAssetURL(raw, host: ExtensionHostResolver.sourceUrl(localPath: localPath))
        guard CoverRequestResolver.isAbsolute(resolved) else { return nil }
        return URL(string: resolved)
    }

    private var fallbackIcon: some View {
        Image(systemName: "puzzlepiece.extension")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.7, height: size * 0.7)
            .padding(size * 0.15)
            .background(Color.white.opacity(0.12))
            .foregroundColor(.white)
            .cornerRadius(size * 0.18)
    }
}
