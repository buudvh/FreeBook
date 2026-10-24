import Foundation
import SwiftData

/// Tác vụ tải **video** — rẽ từ `executeMediaTaskIfNeeded` (`DownloadManager+Comic`), không bao giờ chạm pipeline chữ.
///
/// - Tải **tuần tự** từng tập (chủ ý, tránh bị nguồn chặn) qua `VideoEpisodeDownloadPipeline` vào `VideoOfflineStore`;
///   mỗi phim chỉ một tác vụ video chạy một lúc (`runNextTasksIfNeeded`).
/// - Tập bắt đầu: sidecar `VideoDownloadRequestStore` ("Tải tập này") → `startFromCurrent` (so `index` thật của tập với
///   `Book.currentChapterIndex`) → đầu mục lục; rồi `limit`. Bỏ dòng tiêu đề nhóm (`isSection`).
/// - Bỏ qua tập đã có manifest **cùng URL tập**. Còn dưới `videoMinimumFreeBytes` ⇒ dừng tác vụ.
/// - Tiến độ theo tập + dòng phụ `mediaDetail` (phần trăm/dung lượng của tập đang tải, ≤ 1 lần/giây).
/// - Huỷ ⇒ bỏ bản dở của tập đang tải; lỗi / app khởi động lại ⇒ giữ bản dở để lần thử sau tải tiếp.
extension DownloadManager {
    /// Video rất nặng — còn dưới mức này thì không bắt đầu tập mới.
    static let videoMinimumFreeBytes: Int64 = 1_073_741_824

    enum VideoEnqueueResult {
        case queued
        case alreadyQueued
        case alreadyDownloaded
    }

    /// "Tải tập này": tác vụ `limit 1` bắt đầu đúng tập. Tập đã tải / đang chờ / đang tải ⇒ không thêm.
    @MainActor
    func enqueueVideoEpisode(book: Book, episodeIndex: Int, container: ModelContainer) -> VideoEnqueueResult {
        let bookId = book.bookId
        if VideoOfflineStore.manifest(bookId: bookId, episodeIndex: episodeIndex) != nil {
            return .alreadyDownloaded
        }
        if VideoOfflineLibrary.shared.isDownloading(bookId: bookId, episodeIndex: episodeIndex) {
            return .alreadyQueued
        }
        let isQueued = tasks.contains { task in
            task.bookId == bookId && task.isActive && task.limit.limitValue == 1
                && VideoDownloadRequestStore.startEpisode(taskId: task.id) == episodeIndex
        }
        if isQueued { return .alreadyQueued }

        let taskId = UUID()
        VideoDownloadRequestStore.setStartEpisode(episodeIndex, taskId: taskId)
        enqueueTask(
            book: book,
            taskType: .download,
            startFromCurrent: false,
            limit: ChapterLimitOption(rawValue: 1),
            translate: false,
            container: container,
            taskId: taskId
        )
        AppLogger.shared.log("📥 [VideoOffline] Thêm tập \(episodeIndex) vào hàng đợi tải")
        return .queued
    }

    internal func executeVideoDownload(_ task: DownloadTask, extensionSnapshot: Extension?, container: ModelContainer) async {
        let taskId = task.id
        guard let ext = extensionSnapshot else {
            AppLogger.shared.log("❌ [DownloadManager] Tiện ích \(task.extensionPackageId) chưa cài, không tải được video")
            await markFailed(taskId: taskId, error: "Tiện ích nguồn chưa được cài đặt.")
            return
        }

        let prepared: VideoTaskEpisodes
        do {
            prepared = try await videoEpisodesToDownload(task, container: container)
        } catch {
            AppLogger.shared.log("❌ [DownloadManager] Không chuẩn bị được danh sách tập: \(error.localizedDescription)")
            await markFailed(taskId: taskId, error: error.localizedDescription)
            return
        }

        let episodes = prepared.episodes
        let total = episodes.count
        await updateProgress(taskId: taskId, progress: 0, total: total)
        let initialEpisodes = episodes.map { VideoEpisodeProgress(index: $0.index, title: $0.title, state: .waiting) }
        await MainActor.run { self.setVideoEpisodes(taskId: taskId, initialEpisodes) }
        let client = VideoOfflineHTTPClient()
        defer { client.invalidate() }
        let quality = VideoDownloadQuality.current
        let rememberedServer = UserDefaults.standard.string(forKey: "videoServer.\(task.bookId)")
        AppLogger.shared.log("📥 [VideoOffline] Bắt đầu tải \(total) tập «\(task.bookTitle)» (\(quality.title))")

        var downloadedCount = 0
        var skippedCount = 0
        var failedCount = 0
        var lastErrorMessage: String?

        for (offset, episode) in episodes.enumerated() {
            if await isComicTaskCancelled(taskId) {
                await MainActor.run { self.cancelWaitingVideoEpisodes(taskId: taskId) }
                await markCancelled(taskId: taskId)
                return
            }

            if let manifest = VideoOfflineStore.manifest(bookId: task.bookId, episodeIndex: episode.index),
               manifest.episodeUrl == episode.url {
                skippedCount += 1
                await MainActor.run {
                    self.updateVideoEpisode(taskId: taskId, episodeIndex: episode.index, state: .alreadyDownloaded, mediaDetail: nil)
                }
            } else {
                if let free = VideoOfflineStore.availableCapacity(), free < Self.videoMinimumFreeBytes {
                    AppLogger.shared.log("❌ [VideoOffline] Bộ nhớ trống còn \(free / 1_048_576) MB — dừng tác vụ")
                    await markFailed(taskId: taskId, error: "Bộ nhớ máy còn dưới 1 GB — đã dừng (tải xong \(downloadedCount) tập).")
                    return
                }
                let label = episode.title.isEmpty ? "Tập \(episode.index + 1)" : episode.title
                let key = VideoOfflineLibrary.EpisodeKey(bookId: task.bookId, episodeIndex: episode.index)
                await MainActor.run {
                    VideoOfflineLibrary.shared.markDownloading(key, true)
                    self.updateVideoEpisode(taskId: taskId, episodeIndex: episode.index,
                                            state: .downloading(fraction: 0, bytes: 0), mediaDetail: "\(label): 0%")
                }
                let reporter = VideoDownloadDetailReporter(manager: self, taskId: taskId, episodeIndex: episode.index, label: label)
                let pipeline = VideoEpisodeDownloadPipeline(
                    bookId: task.bookId,
                    bookTitle: task.bookTitle,
                    bookUrl: prepared.bookUrl,
                    bookHost: prepared.bookHost,
                    ext: ext,
                    quality: quality,
                    rememberedServerTitle: rememberedServer,
                    client: client,
                    progress: { fraction, bytes in reporter.report(fraction: fraction, bytes: bytes) }
                )
                var wasCancelled = false
                let finalState: VideoEpisodeProgress.State
                do {
                    let manifest = try await pipeline.run(episode)
                    downloadedCount += 1
                    finalState = .done(bytes: manifest.totalBytes)
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        wasCancelled = true
                        finalState = .cancelled
                        VideoOfflineStore.discardPartialEpisode(bookId: task.bookId, episodeIndex: episode.index)
                    } else {
                        failedCount += 1
                        finalState = .failed(error.localizedDescription)
                        lastErrorMessage = "\(label): \(error.localizedDescription)"
                        AppLogger.shared.log("❌ [VideoOffline] Lỗi tải tập \(episode.index) của «\(task.bookTitle)»: \(error.localizedDescription)")
                    }
                }
                let didCancel = wasCancelled
                await MainActor.run {
                    let library = VideoOfflineLibrary.shared
                    library.markDownloading(key, false)
                    library.refresh(bookId: task.bookId)
                    self.updateVideoEpisode(taskId: taskId, episodeIndex: episode.index, state: finalState, mediaDetail: nil)
                    if didCancel { self.cancelWaitingVideoEpisodes(taskId: taskId) }
                }
                if wasCancelled {
                    await markCancelled(taskId: taskId)
                    return
                }
            }

            await updateProgress(taskId: taskId, progress: offset + 1, total: total)
        }

        AppLogger.shared.log("📊 [DownloadManager] Tác vụ video \(taskId) xong: tải \(downloadedCount), có sẵn \(skippedCount), lỗi \(failedCount)/\(total) tập")
        if failedCount > 0 {
            let detail = lastErrorMessage.map { " (\($0))" } ?? ""
            await markFailed(taskId: taskId, error: "Lỗi tải \(failedCount)/\(total) tập\(detail)")
        } else {
            await markCompleted(taskId: taskId)
        }
    }

    // MARK: - Trạng thái từng tập (chỉ hiển thị, không ghi CSDL)

    /// Danh sách tập của lượt chạy này (mục "Chi tiết tập" ở tab Tải); thử lại tác vụ thì dựng lại.
    @MainActor
    internal func setVideoEpisodes(taskId: UUID, _ episodes: [VideoEpisodeProgress]) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].videoEpisodes = episodes
        tasks[index].mediaDetail = nil
    }

    /// Đổi trạng thái một tập và dòng phụ "Tập 4: 45% · 210 MB" (`mediaDetail`, `nil` khi tập không còn đang tải) trong
    /// **một** lần ghi `tasks` — tránh phát `@Published` hai lần mỗi nhịp tiến độ.
    @MainActor
    internal func updateVideoEpisode(taskId: UUID, episodeIndex: Int, state: VideoEpisodeProgress.State, mediaDetail: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var task = tasks[index]
        if let position = task.videoEpisodes.firstIndex(where: { $0.index == episodeIndex }) {
            // Nhịp tiến độ đến muộn (Task riêng của reporter) không được kéo tập đã xong/lỗi/huỷ về "đang tải".
            if case .downloading = state {
                switch task.videoEpisodes[position].state {
                case .waiting, .downloading: break
                default: return
                }
            }
            task.videoEpisodes[position].state = state
        }
        task.mediaDetail = mediaDetail
        guard task.videoEpisodes != tasks[index].videoEpisodes || task.mediaDetail != tasks[index].mediaDetail else { return }
        tasks[index] = task
    }

    /// Tác vụ bị huỷ: các tập còn chờ chuyển thành "Đã huỷ" (không còn lượt nào tải chúng).
    @MainActor
    internal func cancelWaitingVideoEpisodes(taskId: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var episodes = tasks[index].videoEpisodes
        var changed = false
        for position in episodes.indices where episodes[position].state == .waiting {
            episodes[position].state = .cancelled
            changed = true
        }
        guard changed else { return }
        tasks[index].videoEpisodes = episodes
        tasks[index].mediaDetail = nil
    }

    // MARK: - Danh sách tập

    struct VideoTaskEpisodes {
        let episodes: [StoredChapterSnapshot]
        let bookHost: String?
        let bookUrl: String?
    }

    /// Mục lục tập cần tải — ChapterStore trước, SwiftData sau (như truyện tranh); cũng đẩy phim lên kệ nếu chưa nằm ở đâu.
    private func videoEpisodesToDownload(_ task: DownloadTask, container: ModelContainer) async throws -> VideoTaskEpisodes {
        let context = ModelContext(container)
        let allBooks = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        guard let book = allBooks.first(where: { $0.bookId == task.bookId }) else {
            throw NSError(domain: "DownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy phim trong cơ sở dữ liệu."])
        }
        if !book.isOnShelf && !book.isHistory {
            book.isOnShelf = true
            try? context.save()
        }

        // Đọc hết từ `@Model` trước `await` (context không được dùng chéo luồng).
        let currentIndex = book.currentChapterIndex
        let bookHost = book.host
        let bookUrl: String? = book.detailUrl.isEmpty ? nil : book.detailUrl
        let legacyEpisodes = book.chapters.sorted(by: { $0.index < $1.index }).map { ch in
            StoredChapterSnapshot(
                id: ch.id,
                bookId: ch.bookId,
                title: ch.title,
                url: ch.url,
                index: ch.index,
                host: ch.host,
                titleTrans: ch.titleTrans,
                isCached: ch.isCached,
                offset: ch.offset,
                length: ch.length
            )
        }

        let storeEpisodes = (try? await ChapterStore.shared.fetchOrderedTOC(bookId: task.bookId)) ?? []
        let playable = (storeEpisodes.isEmpty ? legacyEpisodes : storeEpisodes).filter { !$0.isSection }
        guard !playable.isEmpty else {
            throw NSError(domain: "DownloadManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Phim chưa có tập nào."])
        }

        var selected = playable
        let startIndex = VideoDownloadRequestStore.startEpisode(taskId: task.id) ?? (task.startFromCurrent ? currentIndex : nil)
        if let startIndex {
            guard let position = playable.firstIndex(where: { $0.index >= startIndex }) else {
                throw NSError(domain: "DownloadManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tập bắt đầu trong mục lục."])
            }
            selected = Array(playable[position...])
        }
        if let limit = task.limit.limitValue {
            selected = Array(selected.prefix(limit))
        }
        return VideoTaskEpisodes(episodes: selected, bookHost: bookHost, bookUrl: bookUrl)
    }

    // MARK: - Dòng tiến độ trong tập

    /// Gom báo tiến độ của bộ tải (gọi từ thread nền, có thể rất dày) thành ≤ 1 lần/giây lên MainActor.
    final class VideoDownloadDetailReporter: @unchecked Sendable {
        private static let interval: CFAbsoluteTime = 1
        private let lock = NSLock()
        private var lastReportAt: CFAbsoluteTime = 0
        private weak var manager: DownloadManager?
        private let taskId: UUID
        private let episodeIndex: Int
        private let label: String

        init(manager: DownloadManager, taskId: UUID, episodeIndex: Int, label: String) {
            self.manager = manager
            self.taskId = taskId
            self.episodeIndex = episodeIndex
            self.label = label
        }

        func report(fraction: Double, bytes: Int64) {
            let now = CFAbsoluteTimeGetCurrent()
            let shouldSend: Bool = lock.withLock {
                guard now - lastReportAt >= Self.interval else { return false }
                lastReportAt = now
                return true
            }
            guard shouldSend else { return }
            let clamped = min(1, max(0, fraction))
            let percent = Int((clamped * 100).rounded())
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            let detail = "\(label): \(percent)% · \(size)"
            let id = self.taskId
            let episode = self.episodeIndex
            let owner = self.manager
            Task { @MainActor in
                owner?.updateVideoEpisode(taskId: id, episodeIndex: episode,
                                          state: .downloading(fraction: clamped, bytes: bytes), mediaDetail: detail)
            }
        }
    }
}
