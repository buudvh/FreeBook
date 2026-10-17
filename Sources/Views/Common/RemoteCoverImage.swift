import SwiftUI

/// Ảnh bìa / ảnh mục từ mạng qua `CoverImageLoader` (kèm `Referer` + UA iPhone Safari, cache RAM + đĩa, downsample
/// theo cỡ khung). Dùng thay `AsyncImage` cho ảnh do tiện ích trả về — `AsyncImage` không gửi được header nên CDN
/// chặn hotlink trả 403.
///
/// - Khung do caller quyết định (`.frame`, `.aspectRatio`…): view là `Color.clear` co giãn theo khung; ảnh phủ và bị
///   cắt theo khung (`.fill`) hoặc nằm gọn trong khung (`.fit`).
/// - Placeholder trung tính khi đang tải hoặc lỗi.
/// - Tải trong `.task(id:)` nên tự huỷ khi view biến mất hoặc URL / `referer` / cỡ đổi.
/// - `referer` nhận host item, `source` của tiện ích hay URL bất kỳ — loader tự chuẩn hoá về origin + "/".
struct RemoteCoverImage: View {
    let url: String
    let referer: String?
    let contentMode: ContentMode

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    /// URL của `image` — ô được dùng lại cho item khác thì không hiện bìa của item trước.
    @State private var imageURL: String?

    /// Làm tròn cỡ pixel lên bội số này: khung đổi vài điểm không kích hoạt tải/giải mã lại.
    private static let pixelBucket: CGFloat = 32

    init(url: String, referer: String?, contentMode: ContentMode = .fill) {
        self.url = url
        self.referer = referer
        self.contentMode = contentMode
    }

    var body: some View {
        Color.clear
            .overlay {
                GeometryReader { proxy in
                    let pixelSize = Self.pixelSize(for: proxy.size, scale: displayScale)
                    content(size: proxy.size, pixelSize: pixelSize)
                        .task(id: "\(url)|\(referer ?? "")|\(pixelSize)") {
                            await load(pixelSize: pixelSize)
                        }
                }
            }
            .clipped()
    }

    @ViewBuilder
    private func content(size: CGSize, pixelSize: Int) -> some View {
        if let shown = displayedImage(pixelSize: pixelSize) {
            Image(uiImage: shown)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(width: size.width, height: size.height)
        } else {
            placeholder(size: size)
        }
    }

    private func placeholder(size: CGSize) -> some View {
        ZStack {
            Color.gray.opacity(0.15)
            Image(systemName: "photo")
                .font(.system(size: max(10, min(size.width, size.height) * 0.28)))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .frame(width: size.width, height: size.height)
    }

    /// Ảnh đã nạp cho đúng URL này; chưa có thì tra RAM của loader (không I/O) để cuộn lại không nháy placeholder.
    private func displayedImage(pixelSize: Int) -> UIImage? {
        if imageURL == url, let image {
            return image
        }
        guard pixelSize > 1 else { return nil }
        return CoverImageLoader.shared.cachedImage(url: url, maxPixelSize: pixelSize)
    }

    @MainActor
    private func load(pixelSize: Int) async {
        let requestedURL = url
        guard pixelSize > 1, !requestedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if imageURL != requestedURL {
            image = nil
            imageURL = nil
        }
        let loaded = await CoverImageLoader.shared.image(url: requestedURL, referer: referer, maxPixelSize: pixelSize)
        guard !Task.isCancelled, let loaded else { return }
        image = loaded
        imageURL = requestedURL
    }

    /// Cạnh dài của khung theo pixel, làm tròn lên `pixelBucket`. Khung chưa có cỡ ⇒ 0 (chưa tải).
    private static func pixelSize(for size: CGSize, scale: CGFloat) -> Int {
        let longest = max(size.width, size.height) * max(scale, 1)
        guard longest.isFinite, longest >= 1 else { return 0 }
        return Int((longest / pixelBucket).rounded(.up) * pixelBucket)
    }
}
