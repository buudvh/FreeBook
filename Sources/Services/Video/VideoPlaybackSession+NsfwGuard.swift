import Foundation

/// Tắt công tắc NSFW ⇒ dừng hẳn phim 18+ đang phát (1.3.740), dù phim đang ở màn trình phát, thu nhỏ vào hub hay PiP.
/// Tắt NSFW thì hub ẩn mục Video của phim 18+ — để phim chạy nền là không còn chỗ điều khiển.
///
/// Theo dõi `UserDefaults.didChangeNotification` của hệ thống (bắn cho **mọi** lần ghi, trên luồng ghi) ⇒ nhận trên main,
/// chỉ xử lý lúc khoá `RepositoryFilterPolicy.includeNsfwDefaultsKey` thật sự chuyển từ bật sang tắt. "18+" =
/// `RepositoryFilterPolicy.isNsfwBook` (phim tự đánh dấu hoặc nguồn NSFW), cùng luật với nút Home của màn xem.
extension VideoPlaybackSession {
    func installNsfwGuard() {
        guard nsfwDefaultsObserver == nil else { return }
        lastIncludesNsfw = RepositoryFilterPolicy.includesNsfwPreference
        nsfwDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDefaultsChangeForNsfw()
            }
        }
    }

    private func handleDefaultsChangeForNsfw() {
        let includes = RepositoryFilterPolicy.includesNsfwPreference
        guard includes != lastIncludesNsfw else { return }
        lastIncludesNsfw = includes
        guard !includes, let playing = launch,
              RepositoryFilterPolicy.isNsfwBook(bookId: playing.bookId, packageId: playing.extensionPackageId) else { return }
        AppLogger.shared.log("🔞 [VideoPlayer] Tắt NSFW lúc đang phát phim 18+ ⇒ dừng hẳn")
        stop()
    }
}
