import Foundation
import UIKit

/// Thông tin phim trên màn khoá / Trung tâm điều khiển (1.3.764): dựng `VideoNowPlayingMetadata` (tên phim, "Tác giả ·
/// Tập N", bìa; phim 18+ = "Đang phát" + icon app) rồi giao `VideoNowPlayingCoordinator` ghi. Bìa nạp **một lần mỗi phim**
/// lúc `open`, cùng đường TTS dùng: bìa trên máy (`covers/`, đọc ngoài main) → chưa có thì tải về và lưu
/// (`ImageCacheManager.downloadAndSaveCover`) rồi ghi lại màn khoá. Phim 18+ không đọc, không tải bìa.
///
/// 18+ xét lại **mỗi lần ghi** (`RepositoryFilterPolicy.isNsfwBook`) ⇒ đánh dấu 18+ lúc đang phát là màn khoá đổi ngay ở
/// lần ghi kế tiếp.
extension VideoPlaybackSession {
    /// Bỏ qua khi video không giữ phiên (coordinator tự kiểm).
    func publishNowPlaying() {
        guard launch != nil, embedContent == nil, player.currentItem != nil else { return }
        let rate = player.timeControlStatus == .playing ? Double(player.rate) : 0
        VideoNowPlayingCoordinator.shared.publish(
            metadata: nowPlayingMetadata(),
            elapsed: currentPlaybackTime,
            duration: durationSeconds,
            rate: rate,
            defaultRate: Double(playbackRate),
            isPlaying: isPlaying,
            hasNextEpisode: canPlayNext
        )
    }

    /// Đang nạp item mới: màn khoá báo dừng với thông tin của tập mới.
    func publishNowPlayingLoading() {
        VideoNowPlayingCoordinator.shared.publishLoading(metadata: nowPlayingMetadata())
    }

    func nowPlayingMetadata() -> VideoNowPlayingMetadata {
        let isNsfw = launch.map {
            RepositoryFilterPolicy.isNsfwBook(bookId: $0.bookId, packageId: $0.extensionPackageId)
        } ?? false
        let playableCount = episodes.reduce(0) { $1.isSection ? $0 : $0 + 1 }
        let cover = nowPlayingCover.flatMap { $0.bookId == launch?.bookId ? $0.image : nil }
        return VideoNowPlayingMetadata.make(
            isNsfw: isNsfw,
            bookTitle: bookTitle,
            author: isNsfw ? "" : resolvedNowPlayingAuthor(),
            episodeLabel: currentEpisodeLabel,
            showsEpisode: playableCount >= 2,
            cover: cover
        )
    }

    /// Tác giả của lượt mở; trống ⇒ tác giả của `Book` (màn xem điền khi chi tiết về muộn hơn lúc bấm phát).
    private func resolvedNowPlayingAuthor() -> String {
        if nowPlayingAuthor.isEmpty, let author = fetchBook()?.author, !author.isEmpty {
            nowPlayingAuthor = author
        }
        return nowPlayingAuthor
    }

    // MARK: - Bìa

    /// Gọi khi `open` một phim mới (sau khi gán `launch`).
    func loadNowPlayingCover(for newLaunch: BookContentLaunch) {
        nowPlayingCoverTask?.cancel()
        nowPlayingCoverTask = nil
        nowPlayingCover = nil
        nowPlayingAuthor = newLaunch.bookAuthor ?? ""
        guard !RepositoryFilterPolicy.isNsfwBook(bookId: newLaunch.bookId, packageId: newLaunch.extensionPackageId) else {
            return
        }
        let bookId = newLaunch.bookId
        let packageId = newLaunch.extensionPackageId
        let coverUrl = (newLaunch.bookCoverUrl?.isEmpty == false ? newLaunch.bookCoverUrl : fetchBook()?.coverUrl) ?? ""
        nowPlayingCoverTask = Task { [weak self] in
            let local = await Task.detached(priority: .utility) {
                ImageCacheManager.shared.loadLocalCover(for: bookId)
            }.value
            guard !Task.isCancelled, let self, self.launch?.bookId == bookId else { return }
            if let local {
                self.applyNowPlayingCover(local, bookId: bookId)
                return
            }
            guard !coverUrl.isEmpty else { return }
            ImageCacheManager.shared.downloadAndSaveCover(urlStr: coverUrl, bookId: bookId, packageId: packageId) { image in
                guard let image else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        VideoPlaybackSession.shared.applyNowPlayingCover(image, bookId: bookId)
                    }
                }
            }
        }
    }

    /// Bìa về (đúng phim đang mở) ⇒ ghi lại màn khoá.
    private func applyNowPlayingCover(_ image: UIImage, bookId: String) {
        guard launch?.bookId == bookId else { return }
        nowPlayingCover = (bookId: bookId, image: image)
        if player.currentItem != nil {
            publishNowPlaying()
        } else {
            publishNowPlayingLoading()
        }
    }

    func resetNowPlayingCover() {
        nowPlayingCoverTask?.cancel()
        nowPlayingCoverTask = nil
        nowPlayingCover = nil
        nowPlayingAuthor = ""
    }
}
