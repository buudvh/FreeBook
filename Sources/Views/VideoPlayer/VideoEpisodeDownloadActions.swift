import SwiftUI

/// Thao tác tải / xoá bản tải **một tập** từ trình phát (menu `⋯`, nhấn giữ ô tập): gọi `VideoPlaybackSession+Offline`
/// rồi báo toast — toast thuộc tầng View (Services không được gọi `ToastManager`). Trạng thái "đã tải" đọc từ
/// `VideoOfflineLibrary` (đọc trong `body` ⇒ tự vẽ lại khi tải xong / xoá).
@MainActor
struct VideoEpisodeDownloadActions {
    let session: VideoPlaybackSession

    func isDownloaded(_ episode: VideoPlaybackSession.Episode) -> Bool {
        guard let bookId = session.launch?.bookId else { return false }
        return VideoOfflineLibrary.shared.isDownloaded(bookId: bookId, episodeIndex: episode.index)
    }

    func download(_ episode: VideoPlaybackSession.Episode) {
        let name = episode.displayTitle
        switch session.requestEpisodeDownload(episode) {
        case .queued:
            ToastManager.shared.show(message: "Đã thêm \(name) vào hàng đợi tải", type: .success)
        case .alreadyQueued:
            ToastManager.shared.show(message: "\(name) đang trong hàng đợi tải", type: .info)
        case .alreadyDownloaded:
            ToastManager.shared.show(message: "\(name) đã được tải về máy", type: .info)
        case .unavailable:
            ToastManager.shared.show(message: "Chưa tải được: phim chưa có trong thư viện.", type: .error)
        }
    }

    func deleteDownload(_ episode: VideoPlaybackSession.Episode) {
        let name = episode.displayTitle
        Task {
            do {
                try await session.deleteEpisodeDownload(episode)
                ToastManager.shared.show(message: "Đã xoá bản tải \(name)", type: .success)
            } catch {
                ToastManager.shared.show(message: error.localizedDescription, type: .error)
            }
        }
    }

    /// Đọc lại tóm tắt bản tải của phim đang mở (gọi khi màn danh sách tập hiện).
    func refresh() {
        guard let bookId = session.launch?.bookId else { return }
        VideoOfflineLibrary.shared.refresh(bookId: bookId)
    }
}
