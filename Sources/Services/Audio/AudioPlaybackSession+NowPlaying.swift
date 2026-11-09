import Foundation
import UIKit

/// Thông tin bài đang nghe trên màn khoá / Trung tâm điều khiển: dựng `AudioNowPlayingMetadata` (tên bài, nghệ sĩ / tác
/// giả album, tên album, bìa vuông; nguồn 18+ = "Đang phát" + icon app) rồi giao `AudioNowPlayingCoordinator` ghi (bỏ qua
/// khi nhạc không giữ phiên). Bìa nạp **một lần mỗi album**, như phim: bìa trên máy (`covers/`, đọc ngoài main) → chưa có
/// thì tải về và lưu (`ImageCacheManager.downloadAndSaveCover`); cắt vuông ngoài main. Nguồn 18+ không đọc, không tải bìa.
extension AudioPlaybackSession {
    func publishNowPlaying() {
        guard isActive, player.currentItem != nil else { return }
        let rate = player.timeControlStatus == .playing ? Double(player.rate) : 0
        AudioNowPlayingCoordinator.shared.publish(
            metadata: nowPlayingMetadata(),
            contentId: bookId,
            elapsed: currentPlaybackTime,
            duration: durationSeconds,
            rate: rate,
            defaultRate: Double(playbackRate),
            isPlaying: isPlaying,
            hasNextTrack: hasNextTrack
        )
    }

    /// Đang nạp bài mới: màn khoá báo dừng với thông tin của bài mới.
    func publishNowPlayingLoading() {
        AudioNowPlayingCoordinator.shared.publishLoading(metadata: nowPlayingMetadata(), contentId: bookId, hasNextTrack: hasNextTrack)
    }

    func nowPlayingMetadata() -> AudioNowPlayingMetadata {
        let nsfw = RepositoryFilterPolicy.isNsfwBook(bookId: bookId, packageId: packageId)
        let cover = nowPlayingCover.flatMap { $0.bookId == bookId ? $0.image : nil }
        return AudioNowPlayingMetadata.make(
            isNsfw: nsfw,
            trackTitle: currentTrack?.displayTitle ?? "",
            artist: currentTrack?.artist ?? "",
            albumAuthor: albumAuthor,
            albumTitle: albumTitle,
            cover: cover
        )
    }

    // MARK: - Bìa

    /// Nạp bìa của album đang mở (gọi lặp an toàn: đã có / đang nạp thì thôi). Nguồn 18+ ⇒ không đọc, không tải.
    func loadNowPlayingCover() {
        guard isActive, nowPlayingCover?.bookId != bookId, coverTask == nil,
              !RepositoryFilterPolicy.isNsfwBook(bookId: bookId, packageId: packageId) else { return }
        let targetBookId = bookId
        let targetPackageId = packageId
        let url = coverUrl
        coverTask = Task { [weak self] in
            let local = await Task.detached(priority: .utility) {
                ImageCacheManager.shared.loadLocalCover(for: targetBookId).map { AudioPlaybackSession.squareCropped($0) }
            }.value
            guard !Task.isCancelled, let self, self.bookId == targetBookId else { return }
            self.coverTask = nil
            if let local {
                self.applyNowPlayingCover(local, bookId: targetBookId)
                return
            }
            guard !url.isEmpty else { return }
            ImageCacheManager.shared.downloadAndSaveCover(urlStr: url, bookId: targetBookId, packageId: targetPackageId) { image in
                guard let image else { return }
                let square = AudioPlaybackSession.squareCropped(image)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        AudioPlaybackSession.shared.applyNowPlayingCover(square, bookId: targetBookId)
                    }
                }
            }
        }
    }

    /// Bìa về (đúng album đang mở) ⇒ ghi lại màn khoá.
    private func applyNowPlayingCover(_ image: UIImage, bookId targetBookId: String) {
        guard bookId == targetBookId else { return }
        nowPlayingCover = (bookId: targetBookId, image: image)
        if player.currentItem != nil {
            publishNowPlaying()
        } else {
            publishNowPlayingLoading()
        }
    }

    /// Cắt giữa thành hình vuông (bìa album trên màn khoá); ảnh đã gần vuông (lệch < 5%) giữ nguyên.
    nonisolated static func squareCropped(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let side = min(width, height)
        guard side > 0, abs(width - height) / side >= 0.05 else { return image }
        let rect = CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side).integral
        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
