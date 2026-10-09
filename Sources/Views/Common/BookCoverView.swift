import SwiftUI

struct BookCoverView: View {
    let bookId: String
    let coverUrl: String
    let width: CGFloat
    let height: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var localImage: UIImage? = nil
    /// bookId đã kiểm tra đĩa xong (có hay không có file). Chưa khớp `bookId` = đang kiểm tra:
    /// chỉ hiện placeholder, chưa mount `AsyncImage` để bìa đã có trên đĩa không bị tải mạng.
    @State private var checkedBookId: String? = nil
    /// bookId đang có lượt tải bìa do view này khởi động, chặn lượt thứ hai từ nhánh `.success`.
    @State private var downloadingBookId: String? = nil
    /// bookId mà view đang hiển thị, đọc qua @State nên luôn mới — closure của `.task`/`Task`
    /// giữ bản sao struct cũ, so với `bookId` trong đó sẽ không phát hiện được sách đã đổi.
    @State private var activeBookId: String? = nil

    var body: some View {
        Group {
            if let uiImage = localImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if checkedBookId == bookId {
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

    /// Đọc + giải mã bìa local ở luồng nền. Không có file thì mới mount `AsyncImage` và tải ngầm.
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

    @MainActor
    private func triggerSaveLocalCover() {
        let requestedId = bookId
        Task { @MainActor in
            await downloadCover(for: requestedId)
        }
    }

    /// `ImageCacheManager` đã gộp lượt tải trùng bookId; cờ `downloadingBookId` chỉ để nhánh
    /// `.success` của `AsyncImage` khỏi gọi lại khi lượt tải sớm còn đang bay.
    @MainActor
    private func downloadCover(for requestedId: String) async {
        let urlStr = coverUrl
        guard !urlStr.isEmpty, downloadingBookId != requestedId else { return }
        downloadingBookId = requestedId
        let downloaded: UIImage? = await withCheckedContinuation { continuation in
            ImageCacheManager.shared.downloadAndSaveCover(urlStr: urlStr, bookId: requestedId) { image in
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
