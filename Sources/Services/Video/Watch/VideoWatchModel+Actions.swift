import Foundation
import SwiftData

/// Hành động của hàng nút + nút Home trên màn xem phim. Mọi ghi SwiftData đi qua `BookTransactionCoordinator` /
/// `ChapterContentRepository` (`ensureBook`); toast thuộc tầng View nên hàm trả kết quả, không tự báo.
extension VideoWatchModel {
    enum ShelfOutcome: Equatable {
        /// Vừa lên kệ — View mời chọn bộ sưu tập theo `bookId`.
        case added(bookId: String)
        case removed
        case failed(String)
    }

    // MARK: - Trên kệ

    /// Bật / tắt "Trên kệ". Bỏ kệ = `removeFromShelf` (phim về Lịch sử như bấm "Bỏ khỏi kệ" ở Kệ) — **không** xoá `Book`
    /// (đang phát thì phiên phát còn giữ nó) và không dùng `setOnShelf(false)` (hạ cả cờ Lịch sử ⇒ phim biến khỏi cả hai
    /// tab). Phim chưa có `Book` ⇒ tạo luôn trên kệ cùng mục lục đủ (`ensureBook(isOnShelf: true)`).
    func toggleShelf() async -> ShelfOutcome {
        guard !isRunningAction else { return .failed("Đang xử lý, thử lại sau giây lát.") }
        isRunningAction = true
        defer {
            isRunningAction = false
            refreshResumePoint()
        }
        let context = modelContainer.mainContext
        if let book = fetchBook() {
            let targetId = book.bookId
            let result = book.isOnShelf
                ? BookTransactionCoordinator.shared.removeFromShelf(bookId: targetId, in: context)
                : BookTransactionCoordinator.shared.setOnShelf(bookId: targetId, isOnShelf: true, in: context)
            switch result {
            case .success:
                let added = fetchBook()?.isOnShelf == true
                AppLogger.shared.log("🎬 [VideoWatch] \(added ? "Thêm phim vào kệ" : "Bỏ phim khỏi kệ") (bookId=\(targetId))")
                return added ? .added(bookId: targetId) : .removed
            case .failure(let error):
                AppLogger.shared.log("❌ [VideoWatch] Không đổi được trạng thái kệ: \(error.localizedDescription)")
                return .failed(error.localizedDescription)
            }
        }
        guard let created = await ensureBook(isOnShelf: true) else {
            return .failed(phase == .ready ? "Không lưu được phim." : "Chưa tải xong danh sách tập.")
        }
        if !created.isOnShelf {
            // `Book` có sẵn từ nơi khác (đua với Chi tiết cùng link) ⇒ bật cờ kệ của bản đó.
            if case .failure(let error) = BookTransactionCoordinator.shared.setOnShelf(bookId: created.bookId, isOnShelf: true, in: context) {
                AppLogger.shared.log("❌ [VideoWatch] Không thêm được phim vào kệ: \(error.localizedDescription)")
                return .failed(error.localizedDescription)
            }
        }
        AppLogger.shared.log("🎬 [VideoWatch] Thêm phim vào kệ (tạo mới, bookId=\(created.bookId))")
        return .added(bookId: created.bookId)
    }

    // MARK: - Tải

    /// `Book` để mở sheet tải nhiều tập. Phim chưa lưu ⇒ tạo trên kệ như nút "Tải" của Chi tiết. `nil` = chưa có mục lục.
    func bookForDownload() async -> Book? {
        guard !isRunningAction else { return nil }
        isRunningAction = true
        defer {
            isRunningAction = false
            refreshResumePoint()
        }
        let book = await ensureBook(isOnShelf: true)
        if book == nil {
            AppLogger.shared.log("❌ [VideoWatch] Chưa tạo được phim để tải (chưa có mục lục, bookId=\(bookId))")
        }
        return book
    }

    // MARK: - Chia sẻ

    /// Link chi tiết tuyệt đối để chia sẻ: link tương đối ghép host (của `Book` / item / chi tiết). Không phải http(s) ⇒
    /// `nil` (nút ẩn).
    var shareURL: URL? {
        let resolved = ExtensionURLFormatter.resolveAssetURL(request.detailUrl, host: ExtensionHostResolver.nonEmpty(host))
        let lower = resolved.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        return URL(string: resolved)
    }

    // MARK: - Home

    /// Phần dịch vụ của nút Home (View lo đóng màn + chuyển tab sau đó):
    /// 1. Phim **đang phát** là 18+ (`RepositoryFilterPolicy.isNsfwBook`) ⇒ dừng hẳn — tắt NSFW xong hub ẩn mục Video của
    ///    nguồn NSFW, để chạy nền là không còn chỗ điều khiển. Phim thường ⇒ View thu nhỏ, phim phát tiếp ở hub.
    /// 2. Công tắc NSFW chung đang bật ⇒ tắt.
    func prepareGoHome() {
        if let playing = session.launch,
           RepositoryFilterPolicy.isNsfwBook(bookId: playing.bookId, packageId: playing.extensionPackageId) {
            AppLogger.shared.log("🏠 [VideoWatch] Nút Home: phim đang phát là 18+ ⇒ dừng hẳn")
            session.stop()
        }
        if RepositoryFilterPolicy.includesNsfwPreference {
            AppLogger.shared.log("🏠 [VideoWatch] Nút Home: tắt công tắc NSFW")
            UserDefaults.standard.set(false, forKey: RepositoryFilterPolicy.includeNsfwDefaultsKey)
        }
    }

    // MARK: - Dịch

    /// Bật dịch cho phim này (theo truyện → nguồn), như màn Chi tiết.
    var isTranslationEnabled: Bool {
        TranslationConfigStore.shared.isTranslationEnabled(
            bookId: bookId,
            packageId: request.packageId,
            isChineseSourceHint: ExtensionLibraryRepository.snapshot(packageId: request.packageId)?.isChineseSource
        )
    }

    /// Tên phim / thể loại / mô tả ngắn: dịch khi bật dịch và còn chữ Hán, như `translateMetaIfNeeded` của Chi tiết.
    func meta(_ text: String) -> String {
        guard isTranslationEnabled, TranslateUtils.containsChinese(text) else { return text }
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }
}
