import SwiftUI

struct BookCoverView: View {
    let bookId: String
    let coverUrl: String
    let width: CGFloat
    let height: CGFloat

    /// Ba cờ đọc thẳng khoá `UserDefaults` để bìa tự cập nhật khi đổi chế độ (không observe singleton).
    @AppStorage(EInkModeSettings.Key.enabled) private var isEInkEnabled = false
    @AppStorage(EInkModeSettings.Key.hideCovers) private var hideCovers = false
    @AppStorage(EInkModeSettings.Key.monochromeCovers) private var monochromeCovers = true

    @State private var localImage: UIImage? = nil

    var body: some View {
        Group {
            if isEInkEnabled && hideCovers {
                einkCoverPlaceholder
            } else {
                coverContent
                    // Bìa nhiều màu trên e-ink ra dải xám nhoè vì panel phải tự dither. Chuyển sang thang
                    // xám trước thì chữ trên bìa vẫn đọc được thay vì thành vệt.
                    .grayscale(isEInkEnabled && monochromeCovers ? 1 : 0)
                    .contrast(isEInkEnabled && monochromeCovers ? 1.35 : 1)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .onAppear {
            loadLocalImage()
        }
        .onChange(of: bookId) { _, _ in
            loadLocalImage()
        }
    }

    @ViewBuilder
    private var coverContent: some View {
        if let uiImage = localImage {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            AsyncImage(url: URL(string: coverUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .onAppear {
                            triggerSaveLocalCover()
                        }
                case .failure:
                    fallbackPlaceholder
                case .empty:
                    fallbackPlaceholder
                @unknown default:
                    fallbackPlaceholder
                }
            }
        }
    }

    /// Bìa e-ink: bỏ hẳn ảnh, thay bằng khung viền đen trên nền trắng.
    ///
    /// Không hiện chữ cái đầu của tên truyện như dự kiến ban đầu vì `BookCoverView` **không nhận `title`**
    /// — chỉ có `bookId` và `coverUrl`. Thêm tham số sẽ phải sửa mọi call site, không đáng cho một
    /// placeholder; nên giữ glyph sách như bản gốc, chỉ đổi nền xám mờ thành viền đen.
    private var einkCoverPlaceholder: some View {
        ZStack {
            EInkPalette.paper
            Image(systemName: "book.closed")
                .foregroundColor(EInkPalette.ink)
                .font(.system(size: min(width, height) * 0.35))
        }
        .frame(width: width, height: height)
        .overlay {
            Rectangle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth)
        }
    }

    private var fallbackPlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.15)
            Image(systemName: "book.closed")
                .foregroundColor(.secondary.opacity(0.5))
                .font(.system(size: min(width, height) * 0.35))
        }
        .frame(width: width, height: height)
    }

    private func loadLocalImage() {
        if let image = ImageCacheManager.shared.loadLocalCover(for: bookId) {
            self.localImage = image
        } else {
            self.localImage = nil
            // Nếu chưa có local, có thể tải ngầm luôn nếu có URL hợp lệ
            if !coverUrl.isEmpty {
                triggerSaveLocalCover()
            }
        }
    }

    private func triggerSaveLocalCover() {
        guard !coverUrl.isEmpty else { return }
        ImageCacheManager.shared.downloadAndSaveCover(urlStr: coverUrl, bookId: bookId) { image in
            if let image = image {
                DispatchQueue.main.async {
                    self.localImage = image
                }
            }
        }
    }
}
