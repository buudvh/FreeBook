import Foundation

/// Tắt công tắc NSFW lúc phim 18+ đang phát ⇒ **không dừng** (đảo luật dừng hẳn của 1.3.740): phim đang ở màn xem / cửa sổ
/// nhỏ thì thu vào hub và phát tiếp (`VideoLeaveToHubCoordinator.collapseToHub` — View đóng màn), rồi tắt tiếng nếu
/// `VideoMutePolicy.shouldStartMuted` (tuỳ chọn «Không» ⇒ giữ tiếng). Đang ở hub sẵn ⇒ chỉ áp tắt tiếng. Hub vẫn hiện dòng
/// Video của phim 18+ đang phát dù NSFW đã tắt (còn chỗ điều khiển / tắt phim).
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
        let mutes = VideoMutePolicy.shouldStartMuted(bookId: playing.bookId, packageId: playing.extensionPackageId)
        let place = isScreenAttached ? "thu vào hub" : "đang ở hub"
        let sound = mutes ? "tắt tiếng" : "giữ tiếng"
        AppLogger.shared.log("🔞 [VideoPlayer] Tắt NSFW lúc đang phát phim 18+ ⇒ \(place), \(sound) theo «\(VideoMutePolicy.current.title)»")
        if mutes {
            setMuted(true)
        }
        if isScreenAttached {
            VideoLeaveToHubCoordinator.shared.collapseToHub(reason: .nsfwTurnedOff)
        }
    }
}
