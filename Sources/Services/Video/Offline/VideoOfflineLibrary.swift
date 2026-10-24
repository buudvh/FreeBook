import Foundation
import Observation

/// Nguồn sự thật **phía UI** cho bản tải video: tóm tắt theo sách (tập đã tải, dung lượng, còn file không) và các tập
/// đang nằm trong lượt tải. Trình phát (chip "Bản tải", menu tập), trang chi tiết (nút xoá) và sheet nhấn giữ trên kệ
/// đều đọc ở đây — `body` không tự đọc đĩa.
///
/// Đĩa chỉ được đọc trong `refresh(bookId:)` (ngoài main). Bộ tải gọi `refresh` sau mỗi tập lưu xong; xoá qua các hàm
/// ở đây để tóm tắt luôn khớp.
@MainActor
@Observable
final class VideoOfflineLibrary {
    static let shared = VideoOfflineLibrary()

    struct EpisodeKey: Hashable, Sendable {
        let bookId: String
        let episodeIndex: Int
    }

    enum DeleteError: LocalizedError {
        case episodeDownloading

        var errorDescription: String? {
            switch self {
            case .episodeDownloading: return "Tập này đang được tải — huỷ tác vụ trong tab Tải trước."
            }
        }
    }

    private(set) var summaries: [String: VideoOfflineStore.BookSummary] = [:]
    /// Tập đang được một tác vụ tải (`DownloadManager+Video`).
    private(set) var downloadingEpisodes: Set<EpisodeKey> = []
    @ObservationIgnored private var refreshGenerations: [String: Int] = [:]

    private init() {}

    // MARK: - Đọc

    func summary(bookId: String) -> VideoOfflineStore.BookSummary {
        summaries[bookId] ?? .empty
    }

    func isDownloaded(bookId: String, episodeIndex: Int) -> Bool {
        summary(bookId: bookId).completedEpisodes.contains(episodeIndex)
    }

    func isDownloading(bookId: String, episodeIndex: Int) -> Bool {
        downloadingEpisodes.contains(EpisodeKey(bookId: bookId, episodeIndex: episodeIndex))
    }

    /// Đọc lại tóm tắt từ đĩa (ngoài main). Lượt mới hơn của cùng sách thắng.
    func refresh(bookId: String) {
        guard !bookId.isEmpty else { return }
        let generation = (refreshGenerations[bookId] ?? 0) + 1
        refreshGenerations[bookId] = generation
        Task.detached(priority: .utility) {
            let summary = VideoOfflineStore.summary(bookId: bookId)
            await MainActor.run {
                let library = VideoOfflineLibrary.shared
                guard library.refreshGenerations[bookId] == generation else { return }
                if library.summaries[bookId] != summary {
                    library.summaries[bookId] = summary
                }
            }
        }
    }

    // MARK: - Trạng thái đang tải (bộ tải gọi)

    func markDownloading(_ key: EpisodeKey, _ isDownloading: Bool) {
        if isDownloading {
            downloadingEpisodes.insert(key)
        } else {
            downloadingEpisodes.remove(key)
        }
    }

    // MARK: - Xoá

    /// Xoá bản tải một tập (trọn vẹn hoặc dở). Tập đang được tải thì từ chối.
    func deleteEpisode(bookId: String, episodeIndex: Int) async throws {
        guard !isDownloading(bookId: bookId, episodeIndex: episodeIndex) else { throw DeleteError.episodeDownloading }
        try await Task.detached(priority: .userInitiated) {
            try VideoOfflineStore.deleteEpisode(bookId: bookId, episodeIndex: episodeIndex)
        }.value
        AppLogger.shared.log("🗑️ [VideoOffline] Xoá bản tải tập \(episodeIndex)")
        refresh(bookId: bookId)
    }

    /// Xoá hết bản tải của một phim (giữ phim trên kệ): huỷ tác vụ tải của phim trước, rồi xoá thư mục.
    func deleteAll(bookId: String) async throws {
        DownloadManager.shared.cancelTasksForBook(bookId: bookId)
        try await Task.detached(priority: .userInitiated) {
            try VideoOfflineStore.deleteBook(bookId: bookId)
        }.value
        AppLogger.shared.log("🗑️ [VideoOffline] Xoá hết bản tải của phim")
        refresh(bookId: bookId)
    }
}
