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
    /// `false` ⇒ bìa tải về chỉ giữ trong RAM của view (1.3.762) — trang Chi tiết của truyện chưa lưu, `bookId` ngẫu nhiên
    /// mỗi lần mở: ghi `covers/` là thành file mồ côi vĩnh viễn. Không ghi đĩa, không vào cache thumbnail dùng chung.
    /// Đổi sang `true` (truyện vừa được lưu) ⇒ `.task` chạy lại, tải + ghi file như thường.
    var persistsCover: Bool = true
    /// Báo kích thước (điểm) của ảnh bìa mỗi khi ảnh hiển thị đổi — thumbnail giữ tỉ lệ ảnh gốc, nên nơi dùng biết
    /// bìa ngang hay dọc (`BookDetailHeroView`). `nil` ở mọi chỗ khác.
    var onImageSize: ((CGSize) -> Void)? = nil

    @Environment(\.displayScale) private var displayScale
    @State private var localImage: UIImage? = nil
    /// bookId đã kiểm tra đĩa xong (có hay không có file). Chưa khớp `bookId` = đang kiểm tra.
    @State private var checkedBookId: String? = nil
    /// "bookId|persistsCover" của lượt tải bìa do view này khởi động — đổi cỡ khung chạy lại `.task` không tải lần hai,
    /// còn đổi sang lưu đĩa thì vẫn tải được dù lượt chỉ RAM chưa xong.
    @State private var downloadingKey: String? = nil
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
        .onChange(of: localImage?.size, initial: true) { _, size in
            if let size, let onImageSize {
                onImageSize(size)
            }
        }
        // Khóa theo cả cỡ pixel: khung đổi cỡ (xoay ngang/dọc) thì dựng lại thumbnail đúng cỡ, không kéo giãn ảnh nhỏ.
        .task(id: "\(bookId)|\(Int(pixelSize.width))x\(Int(pixelSize.height))|\(persistsCover)") {
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
        // Đĩa chưa có file mà đang hiện bìa của chính sách này (bìa chỉ RAM, vừa đổi sang lưu đĩa / đổi cỡ khung) ⇒ giữ
        // ảnh đang hiện tới khi lượt tải xong, khỏi nháy placeholder.
        if image != nil || checkedBookId != requestedId {
            localImage = image
        }
        checkedBookId = requestedId

        // Nếu chưa có local, có thể tải ngầm luôn nếu có URL hợp lệ
        if image == nil {
            await downloadCover(for: requestedId)
        }
    }

    /// `ImageCacheManager` đã gộp lượt tải trùng bookId; cờ `downloadingKey` chặn `.task` chạy lại (đổi cỡ
    /// khung) xếp thêm lượt chờ khi lượt trước còn đang bay.
    @MainActor
    private func downloadCover(for requestedId: String) async {
        let urlStr = CoverRequestResolver.displayURL(coverUrl, itemHost: host, packageId: extensionPackageId)
        let key = "\(requestedId)|\(persistsCover)"
        guard !urlStr.isEmpty, downloadingKey != key else { return }
        downloadingKey = key
        defer {
            if downloadingKey == key { downloadingKey = nil }
        }
        let referer = CoverRequestResolver.referer(itemHost: host, packageId: extensionPackageId)
        guard persistsCover else {
            await showTransientCover(for: requestedId, urlStr: urlStr, referer: referer)
            return
        }
        let downloaded: UIImage? = await withCheckedContinuation { continuation in
            ImageCacheManager.shared.downloadAndSaveCover(urlStr: urlStr, bookId: requestedId, referer: referer,
                                                          packageId: extensionPackageId) { image in
                continuation.resume(returning: image)
            }
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

    /// Bìa chỉ RAM (`persistsCover == false`): giải mã thẳng byte tải về ra thumbnail đúng cỡ khung ở luồng nền — không
    /// ghi `covers/`, không cất vào cache thumbnail dùng chung (lướt nhiều truyện không đẩy bìa trên Kệ ra khỏi cache).
    @MainActor
    private func showTransientCover(for requestedId: String, urlStr: String, referer: String?) async {
        let packageId = extensionPackageId
        let data: Data? = await withCheckedContinuation { continuation in
            ImageCacheManager.shared.fetchTransientCoverData(urlStr: urlStr, bookId: requestedId, referer: referer,
                                                             packageId: packageId) { data in
                continuation.resume(returning: data)
            }
        }
        guard let data, requestedId == activeBookId else { return }
        let size = pixelSize
        let scale = displayScale
        let thumbnail = await Task.detached(priority: .userInitiated) {
            CoverThumbnailCache.makeThumbnail(data: data, pixelSize: size, scale: scale)
        }.value
        guard let thumbnail, requestedId == activeBookId else { return }
        localImage = thumbnail
        checkedBookId = requestedId
    }
}
