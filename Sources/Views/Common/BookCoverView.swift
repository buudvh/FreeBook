import SwiftUI

struct BookCoverView: View {
    let bookId: String
    let coverUrl: String
    let width: CGFloat
    let height: CGFloat
    /// Host của sách/item: ghép bìa đã lưu dạng tương đối hoặc `//` (resolve lúc hiển thị, không backfill) và làm
    /// `Referer`. Rỗng ⇒ `source` của tiện ích theo `extensionPackageId` (`CoverRequestResolver`).
    var host: String? = nil
    /// Tiện ích nguồn. Rỗng (sách local, chỗ gọi không biết nguồn) ⇒ chỉ tải được bìa tuyệt đối, không `Referer`.
    var extensionPackageId: String = ""

    @Environment(\.displayScale) private var displayScale
    @State private var localImage: UIImage? = nil
    /// bookId đã kiểm tra đĩa xong (có hay không có file). Chưa khớp `bookId` = đang kiểm tra.
    @State private var checkedBookId: String? = nil
    /// bookId đang có lượt tải bìa do view này khởi động — đổi cỡ khung chạy lại `.task` không tải lần hai.
    @State private var downloadingBookId: String? = nil
    /// bookId mà view đang hiển thị, đọc qua @State nên luôn mới — closure của `.task`/`Task`
    /// giữ bản sao struct cũ, so với `bookId` trong đó sẽ không phát hiện được sách đã đổi.
    @State private var activeBookId: String? = nil

    var body: some View {
        Group {
            // Không còn `AsyncImage`: nó không gửi được `Referer` (CDN chặn hotlink trả 403) và tải trùng với
            // `downloadCover`. Chưa có bìa local thì hiện placeholder tới khi `ImageCacheManager` tải + ghi xong.
            if let uiImage = localImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                fallbackPlaceholder
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .onAppear {
            showCachedImageIfAvailable()
        }
        .onChange(of: bookId) { _, _ in
            showCachedImageIfAvailable()
        }
        // Khóa theo cả cỡ pixel: khung đổi cỡ (xoay ngang/dọc) thì dựng lại thumbnail đúng cỡ, không kéo giãn ảnh nhỏ.
        .task(id: "\(bookId)|\(Int(pixelSize.width))x\(Int(pixelSize.height))") {
            await loadLocalImage()
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

    /// Kích thước pixel thật của khung bìa — thumbnail được downsample đúng cỡ này.
    private var pixelSize: CGSize {
        let scale = max(displayScale, 1)
        return CGSize(width: (width * scale).rounded(.up), height: (height * scale).rounded(.up))
    }

    /// Chỉ tra cache RAM (không I/O) nên gọi đồng bộ được: trúng cache thì hiện ngay, không nháy.
    @MainActor
    private func showCachedImageIfAvailable() {
        activeBookId = bookId
        if let cached = ImageCacheManager.shared.cachedCoverThumbnail(for: bookId, pixelSize: pixelSize) {
            localImage = cached
            checkedBookId = bookId
        } else if checkedBookId != bookId {
            // Sách mới chưa kiểm tra đĩa: bỏ ảnh của sách cũ, hiện placeholder chờ `.task`.
            localImage = nil
        }
    }

    /// Đọc + giải mã bìa local ở luồng nền. Không có file thì tải ngầm (kèm `Referer`) rồi ghi đĩa.
    @MainActor
    private func loadLocalImage() async {
        let requestedId = bookId
        let size = pixelSize
        let scale = displayScale
        activeBookId = requestedId
        if let cached = ImageCacheManager.shared.cachedCoverThumbnail(for: requestedId, pixelSize: size) {
            localImage = cached
            checkedBookId = requestedId
            return
        }

        let image = await Task.detached(priority: .userInitiated) {
            ImageCacheManager.shared.loadCoverThumbnail(for: requestedId, pixelSize: size, scale: scale)
        }.value
        // Task bị hủy (đổi cỡ/đổi sách): bỏ kết quả cũ để không đè thumbnail sai cỡ của lượt mới.
        guard !Task.isCancelled, requestedId == activeBookId else { return }
        localImage = image
        checkedBookId = requestedId

        // Nếu chưa có local, có thể tải ngầm luôn nếu có URL hợp lệ
        if image == nil {
            await downloadCover(for: requestedId)
        }
    }

    /// `ImageCacheManager` đã gộp lượt tải trùng bookId; cờ `downloadingBookId` chặn `.task` chạy lại (đổi cỡ
    /// khung) xếp thêm lượt chờ khi lượt trước còn đang bay.
    @MainActor
    private func downloadCover(for requestedId: String) async {
        let urlStr = CoverRequestResolver.displayURL(coverUrl, itemHost: host, packageId: extensionPackageId)
        guard !urlStr.isEmpty, downloadingBookId != requestedId else { return }
        downloadingBookId = requestedId
        let referer = CoverRequestResolver.referer(itemHost: host, packageId: extensionPackageId)
        let downloaded: UIImage? = await withCheckedContinuation { continuation in
            ImageCacheManager.shared.downloadAndSaveCover(urlStr: urlStr, bookId: requestedId, referer: referer,
                                                          packageId: extensionPackageId) { image in
                continuation.resume(returning: image)
            }
        }
        if downloadingBookId == requestedId {
            downloadingBookId = nil
        }
        guard let downloaded, requestedId == activeBookId else { return }

        // Dựng thumbnail từ file vừa ghi (cất luôn vào cache RAM) thay vì vẽ ảnh full-res trên main.
        let size = pixelSize
        let scale = displayScale
        let thumbnail = await Task.detached(priority: .userInitiated) {
            ImageCacheManager.shared.loadCoverThumbnail(for: requestedId, pixelSize: size, scale: scale)
        }.value
        guard requestedId == activeBookId else { return }
        localImage = thumbnail ?? downloaded
        checkedBookId = requestedId
    }
}
