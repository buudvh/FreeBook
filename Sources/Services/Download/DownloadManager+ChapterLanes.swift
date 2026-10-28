import Foundation

/// Vòng lấy nội dung chương của tác vụ tải **và** tác vụ xuất truyện chữ (1.3.624), tách khỏi
/// `DownloadManager.executeTask` để thêm nghỉ giữa các lần tải và tải nhiều luồng (`DownloadSpeedSettings`).
///
/// - **Luồng**: tối đa `laneCount` chương đang tải cùng lúc. Mỗi luồng có `ExportContentProvider` +
///   `BookDownloadWorker` riêng, vì worker giữ một `JSExecutor` và hai lượt gọi xen nhau trên cùng executor là hỏng.
///   Luồng 0 dùng worker sẵn có của tác vụ. Worker của luồng thêm được đăng ký vào `activeWorkers` để `cancelTask`
///   dừng được JS đang chạy.
/// - Nguồn Legado và tác vụ chưa cài tiện ích luôn chạy 1 luồng.
/// - **Thứ tự**: kết quả được xếp lại theo mục lục trước khi gọi `onAcquired`, nên bản xuất ghi chương đúng thứ tự
///   và tiến độ tăng dần như cũ. Một chương chậm chỉ cho các luồng khác chạy trước tối đa `2 × laneCount` chương
///   (`lookaheadPerLane`), nên bộ đệm chờ không phình theo độ dài truyện.
/// - **Nghỉ**: luồng vừa tải một chương từ mạng (`uncachedAttempt` tăng) thì nghỉ `delay` **trước** chương kế tiếp
///   của nó. Kết quả vẫn được giao ngay (tiến độ không trễ) và không có lượt nghỉ thừa sau chương cuối. Chương đã có
///   trong máy không làm luồng phải nghỉ, để xuất ebook truyện đã tải không chậm đi.
/// - **Huỷ**: `Task.sleep` / `acquire` ném `CancellationError`, caller `markCancelled` như trước.
/// - **Lỗi liên tiếp**: đủ `DownloadFailureStreak.limit` chương lỗi liền nhau theo thứ tự mục lục thì ném
///   `DownloadFailureStreak.LimitReached`, caller `markFailed`. Chương bị bỏ qua vì "Chỉ xuất chương đã tải" không
///   tính là lỗi.
/// - Mặc định (1 luồng, không nghỉ) giữ đúng thứ tự thao tác cũ: lấy một chương, xử lý xong rồi mới tới chương sau.
extension DownloadManager {

    /// Kết quả một luồng trả về cho vòng điều phối.
    /// Số chương mỗi luồng được chạy trước chương đang chờ giao.
    private static let lookaheadPerLane = 2

    struct ChapterLaneResult: Sendable {
        let position: Int
        let lane: Int
        let acquisition: ExportContentProvider.Acquisition
        /// Chương vừa rồi phải tải từ mạng ⇒ luồng này nghỉ trước chương kế tiếp.
        let fetchedFromNetwork: Bool
    }

    func acquireChaptersInOrder(
        _ chapters: [StoredChapterSnapshot],
        taskId: UUID,
        primaryWorker: BookDownloadWorker?,
        extensionSnapshot: Extension?,
        speed: DownloadSpeedSettings,
        makeProvider: (BookDownloadWorker?) -> ExportContentProvider,
        onAcquired: (StoredChapterSnapshot, ExportContentProvider.Acquisition) async throws -> Void
    ) async throws -> ExportContentProvider.Tally {
        let settings = speed.clamped
        var laneCount = min(settings.laneCount, max(1, chapters.count))
        if primaryWorker == nil || primaryWorker?.isLegadoSource == true || extensionSnapshot == nil {
            laneCount = 1
        }

        var extraWorkers: [BookDownloadWorker] = []
        if laneCount > 1, let ext = extensionSnapshot {
            extraWorkers = (1..<laneCount).map { _ in
                BookDownloadWorker(localPath: ext.localPath, downloadUrl: ext.downloadUrl, configJson: ext.configJson)
            }
            let registered = extraWorkers
            await MainActor.run {
                self.activeWorkers[taskId, default: []].append(contentsOf: registered)
            }
            AppLogger.shared.log("📥 [DownloadManager] Tác vụ \(taskId) tải \(laneCount) luồng, nghỉ \(settings.delayTitle)")
        }

        let providers = [makeProvider(primaryWorker)] + extraWorkers.map { makeProvider($0) }
        do {
            try await runChapterLanes(
                chapters,
                providers: providers,
                delayNanoseconds: settings.delayNanoseconds,
                onAcquired: onAcquired
            )
        } catch {
            if let stop = error as? DownloadFailureStreak.LimitReached {
                AppLogger.shared.log("❌ [DownloadManager] Tác vụ \(taskId) dừng: \(stop.message)")
            }
            await cleanUpLaneWorkers(extraWorkers)
            throw error
        }
        await cleanUpLaneWorkers(extraWorkers)

        var tally = ExportContentProvider.Tally()
        for provider in providers {
            tally.add(provider.tally)
        }
        return tally
    }

    private func runChapterLanes(
        _ chapters: [StoredChapterSnapshot],
        providers: [ExportContentProvider],
        delayNanoseconds: UInt64,
        onAcquired: (StoredChapterSnapshot, ExportContentProvider.Acquisition) async throws -> Void
    ) async throws {
        let window = providers.count * Self.lookaheadPerLane
        try await withThrowingTaskGroup(of: ChapterLaneResult.self) { group in
            var nextToLaunch = 0
            var nextToEmit = 0
            var freeLanes = Array(providers.indices.reversed())
            var finished: [Int: ExportContentProvider.Acquisition] = [:]
            var restingLanes = Set<Int>()
            var failureStreak = DownloadFailureStreak()

            while nextToEmit < chapters.count {
                while nextToLaunch < chapters.count, nextToLaunch - nextToEmit < window, let lane = freeLanes.popLast() {
                    try Task.checkCancellation()
                    let position = nextToLaunch
                    let chapter = chapters[position]
                    let provider = providers[lane]
                    let restsFirst = restingLanes.remove(lane) != nil && delayNanoseconds > 0
                    group.addTask {
                        if restsFirst {
                            try await Task.sleep(nanoseconds: delayNanoseconds)
                        }
                        let attemptsBefore = provider.tally.uncachedAttempt
                        let acquisition = try await provider.acquire(chapter: chapter)
                        return ChapterLaneResult(
                            position: position,
                            lane: lane,
                            acquisition: acquisition,
                            fetchedFromNetwork: provider.tally.uncachedAttempt > attemptsBefore
                        )
                    }
                    nextToLaunch += 1
                }

                guard let result = try await group.next() else { break }
                freeLanes.append(result.lane)
                if result.fetchedFromNetwork {
                    restingLanes.insert(result.lane)
                }
                finished[result.position] = result.acquisition
                while let acquisition = finished.removeValue(forKey: nextToEmit) {
                    let chapter = chapters[nextToEmit]
                    try await onAcquired(chapter, acquisition)
                    nextToEmit += 1
                    switch acquisition {
                    case .failed:
                        if failureStreak.recordFailure(chapterIndex: chapter.index) {
                            // Đang huỷ thì JS bị ngắt cũng trả `.failed` — báo "Đã hủy", không báo dừng vì lỗi.
                            try Task.checkCancellation()
                            throw DownloadFailureStreak.LimitReached(message: failureStreak.stopMessage(noun: "chương"))
                        }
                    case .content:
                        failureStreak.recordSuccess()
                    case .skippedUncached:
                        break
                    }
                }
            }
        }
        // Huỷ lúc các chương cuối còn đang tải: JS bị ngắt có thể trả `.failed` thay vì ném `CancellationError`,
        // nên chốt lại ở đây để tác vụ báo "Đã hủy" thay vì hoàn thành/thất bại.
        try Task.checkCancellation()
    }

    /// Nhả executor của worker luồng thêm. Worker luồng 0 và mục `activeWorkers` của tác vụ do `executeTask` dọn khi
    /// tác vụ kết thúc.
    private func cleanUpLaneWorkers(_ workers: [BookDownloadWorker]) async {
        guard !workers.isEmpty else { return }
        for worker in workers {
            await worker.cleanup()
        }
    }
}
