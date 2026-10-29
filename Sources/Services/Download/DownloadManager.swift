import Foundation
import SwiftData

/// Số chương của một tác vụ tải/xuất. Cố ý là **struct** chứ không phải enum để nhận được mọi con số
/// người dùng kéo tay ở mục "Tuỳ chọn" (1...1000), trong khi `rawValue` vẫn mang đúng nghĩa cũ:
/// `0` = tất cả, số dương = số chương. Nhờ đó `DownloadTaskModel.limitRaw` không cần đổi schema và
/// tác vụ lưu từ bản trước 1.3.263 đọc lại vẫn đúng.
public struct ChapterLimitOption: RawRepresentable, Hashable, Codable, CaseIterable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Tải/xuất từ chương bắt đầu tới hết mục lục.
    public static let all = ChapterLimitOption(rawValue: 0)

    /// Mốc "Tuỳ chọn" trong picker — chỉ là nhãn để mở thanh kéo. Giá trị này **không bao giờ**
    /// được đưa vào hàng đợi; View phải quy đổi sang số chương thật trước khi enqueue.
    public static let custom = ChapterLimitOption(rawValue: -1)

    /// Dải cho phép của thanh kéo "Tuỳ chọn".
    public static let customRange = 1...1000

    /// Các mốc sẵn hiện trong picker (không gồm "Tuỳ chọn").
    public static let allCases: [ChapterLimitOption] = [
        .all,
        ChapterLimitOption(rawValue: 50),
        ChapterLimitOption(rawValue: 100),
        ChapterLimitOption(rawValue: 200),
        ChapterLimitOption(rawValue: 500),
        ChapterLimitOption(rawValue: 1000)
    ]

    public var title: String {
        title(noun: "chương")
    }

    /// Nhãn theo danh từ của mục lục: "chương" (truyện) hoặc "tập" (video).
    public func title(noun: String) -> String {
        if rawValue < 0 { return "Tuỳ chọn" }
        if rawValue == 0 { return "Tất cả" }
        return "\(rawValue) \(noun)"
    }

    /// `nil` nghĩa là không giới hạn. Giá trị âm (mốc "Tuỳ chọn" lỡ rơi xuống đây) cũng coi là
    /// không giới hạn để không bao giờ tải 0 chương.
    public var limitValue: Int? {
        rawValue > 0 ? rawValue : nil
    }

    public init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Loại tác vụ. `rawValue` được ghi vào `DownloadTaskModel.taskTypeRaw`, nên đây cũng là chỗ **định dạng
/// xuất được lưu bền** — không cần thêm cột mới vào schema SwiftData. Giữ nguyên hai raw value cũ để tác vụ
/// đã lưu trước 1.3.253 vẫn đọc lại đúng.
public enum TaskType: String, Codable, Identifiable {
    case download = "Tải truyện"
    case exportTxt = "Xuất ebook TXT"
    case exportEpub = "Xuất ebook EPUB"
    case exportFb2 = "Xuất ebook FB2"
    case exportMobi = "Xuất ebook MOBI"
    case exportCbz = "Xuất truyện tranh CBZ"
    case exportPdf = "Xuất truyện tranh PDF"
    case exportVideo = "Xuất video"
    public var id: String { self.rawValue }

    /// Định dạng cần render; `nil` nghĩa là tác vụ chỉ tải/cache chứ không tạo file.
    public var exportFormat: BookExportFormat? {
        switch self {
        case .download: return nil
        case .exportTxt: return .txt
        case .exportEpub: return .epub3
        case .exportFb2: return .fb2
        case .exportMobi: return .mobi
        case .exportCbz: return .cbz
        case .exportPdf: return .pdf
        case .exportVideo: return .video
        }
    }

    public var isExport: Bool { exportFormat != nil }
}

public enum TaskStatus: String, Codable {
    case pending = "Đang chờ"
    case running = "Đang chạy"
    case completed = "Hoàn thành"
    case failed = "Thất bại"
    case cancelled = "Đã hủy"
}

public struct DownloadTask: Identifiable {
    public let id: UUID
    public let bookId: String
    public let bookTitle: String
    public let bookCoverUrl: String
    public let taskType: TaskType
    public var status: TaskStatus
    public var progressCount: Int
    public var totalCount: Int
    public var errorMessage: String?
    public var isCancelled: Bool = false

    public let extensionPackageId: String
    public let detailUrl: String
    public let startFromCurrent: Bool
    public let limit: ChapterLimitOption
    public let translate: Bool
    public let onlyExportCached: Bool
    public var exportFilePath: String? = nil
    /// Giai đoạn của tác vụ xuất (`nil` với tác vụ tải). Trạng thái tạm thời, không lưu CSDL.
    public var exportStage: ExportStage? = nil
    /// Tổng kết `đã xuất/thiếu/lỗi` khi bản xuất không đủ chương. Cũng là trạng thái tạm thời.
    public var exportSummary: String? = nil
    /// Tiến độ bên trong tập phim đang tải ("Tập 4: 45% · 210 MB"). Trạng thái tạm thời, không lưu CSDL.
    public var mediaDetail: String? = nil
    /// Trạng thái từng tập của tác vụ video (mục "Chi tiết tập" ở tab Tải). Trạng thái tạm thời, không lưu CSDL.
    public var videoEpisodes: [VideoEpisodeProgress] = []

    /// Tác vụ tải của sách video (`DownloadManager+Video`). Loại suy lúc chạy, không lưu.
    public var isVideoDownload: Bool {
        taskType == .download && ExtensionContentKind.resolve(packageId: extensionPackageId) == .video
    }

    /// Nhãn hiển thị của loại tác vụ — `taskType.rawValue` được lưu bền nên không đổi, chỉ đổi chữ hiện ra.
    public var displayTypeName: String {
        isVideoDownload ? "Tải video" : taskType.rawValue
    }

    /// Danh từ của một mục tiến độ: "tập" (tải/xuất video) hoặc "chương".
    public var unitNoun: String {
        isVideoTask ? "tập" : "chương"
    }
}

public final class DownloadManager: ObservableObject {
    public static let shared = DownloadManager()

    /// Khoảng coalesce `save()` của task store, tính bằng giây — xem `DownloadManager+TaskStore.swift`.
    internal static let taskSaveCoalesceInterval: CFAbsoluteTime = 1.0
    /// Khoảng phát `@Published tasks` khi tiến độ nhảy từng chương ⇒ tối đa ~10 lần/giây, giá trị cuối luôn phát.
    internal static let progressPublishInterval: CFAbsoluteTime = 0.1

    @Published public var tasks: [DownloadTask] = []
    public var cancelledTaskIds: Set<UUID> = []
    internal var container: ModelContainer?
    /// Context dùng lại cho mọi CRUD của task. Tạo `ModelContext` mới ở từng lần cập nhật tiến độ là một trong
    /// ba nguồn chậm chính của vòng lặp tải/xuất (hai nguồn còn lại: fetch toàn bảng và `save()` mỗi chương).
    internal var taskContext: ModelContext?
    internal var lastTaskSaveAt: CFAbsoluteTime = 0
    internal var lastProgressPublishAt: [UUID: CFAbsoluteTime] = [:]

    private init() {}

    public func enqueueTask(
        book: Book,
        taskType: TaskType,
        startFromCurrent: Bool,
        limit: ChapterLimitOption,
        translate: Bool,
        onlyExportCached: Bool = false,
        container: ModelContainer,
        taskId: UUID = UUID()
    ) {
        let bookId = book.bookId
        let title = book.title
        let cover = book.coverUrl
        let extPkgId = book.extensionPackageId
        let detailUrl = book.detailUrl

        let newTask = DownloadTask(
            id: taskId,
            bookId: bookId,
            bookTitle: title,
            bookCoverUrl: cover,
            taskType: taskType,
            status: .pending,
            progressCount: 0,
            totalCount: 0,
            extensionPackageId: extPkgId,
            detailUrl: detailUrl,
            startFromCurrent: startFromCurrent,
            limit: limit,
            translate: translate,
            onlyExportCached: onlyExportCached
        )

        self.container = container

        let dbModel = DownloadTaskModel(
            id: taskId,
            bookId: bookId,
            bookTitle: title,
            bookCoverUrl: cover,
            taskTypeRaw: taskType.rawValue,
            statusRaw: TaskStatus.pending.rawValue,
            progressCount: 0,
            totalCount: 0,
            extensionPackageId: extPkgId,
            detailUrl: detailUrl,
            startFromCurrent: startFromCurrent,
            limitRaw: limit.rawValue,
            translate: translate,
            onlyExportCached: onlyExportCached
        )

        if let context = taskStoreContext() {
            context.insert(dbModel)
            try? context.save()
            lastTaskSaveAt = CFAbsoluteTimeGetCurrent()
        }

        self.tasks.append(newTask)
        self.runNextTasksIfNeeded(container: container)
    }

    /// Mọi worker của tác vụ đang chạy — một cho mỗi luồng tải (`DownloadManager+ChapterLanes`).
    internal var activeWorkers: [UUID: [BookDownloadWorker]] = [:]
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    public var maxConcurrentTasks: Int = 2

    public func cancelTask(taskId: UUID) {
        cancelledTaskIds.insert(taskId)
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].status = .cancelled
            tasks[index].isCancelled = true

            updateTaskInDB(taskId: taskId) { model in
                model.statusRaw = TaskStatus.cancelled.rawValue
                model.isCancelled = true
            }
        }

        if let handle = activeTasks.removeValue(forKey: taskId) {
            handle.cancel()
        }
        if let workers = activeWorkers.removeValue(forKey: taskId) {
            Task {
                for worker in workers {
                    await worker.cancel()
                }
            }
        }

        if let container = self.container {
            runNextTasksIfNeeded(container: container)
        }
    }

    public func cancelTasksForBook(bookId: String) {
        let tasksToCancel = tasks.filter { $0.bookId == bookId && ($0.status == .running || $0.status == .pending) }
        for t in tasksToCancel {
            cancelTask(taskId: t.id)
        }
    }

    internal func runNextTasksIfNeeded(container: ModelContainer) {
        let runningCount = tasks.filter { $0.status == .running }.count
        let availableSlots = max(0, maxConcurrentTasks - runningCount)
        guard availableSlots > 0 else { return }

        // Video: mỗi phim chỉ một tác vụ chạy một lúc — tải tuần tự (chủ ý), hai tác vụ không ghi chung thư mục tập, và
        // bản xuất không đọc tập mà lượt tải lại đang xoá (`isVideoTask` gồm cả xuất video).
        var busyVideoBooks = Set(tasks.filter { $0.status == .running && $0.isVideoTask }.map(\.bookId))
        var pendingIndices: [Int] = []
        for (offset, task) in tasks.enumerated() where task.status == .pending {
            guard pendingIndices.count < availableSlots else { break }
            if task.isVideoTask {
                guard !busyVideoBooks.contains(task.bookId) else { continue }
                busyVideoBooks.insert(task.bookId)
            }
            pendingIndices.append(offset)
        }

        for index in pendingIndices {
            tasks[index].status = .running
            let taskToRun = tasks[index]
            let taskId = taskToRun.id

            let taskHandle = Task.detached(priority: .background) {
                await self.executeTask(taskToRun, container: container)
            }
            self.activeTasks[taskId] = taskHandle
        }
    }

    private func executeTask(_ task: DownloadTask, container: ModelContainer) async {
        let bgContext = ModelContext(container)
        let taskId = task.id

        // 2. Tiện ích đã cài: đọc bảng chụp `nonisolated` của repository (không qua SwiftData, không await).
        let bgExt = ExtensionLibraryRepository.snapshot(packageId: task.extensionPackageId)

        let worker: BookDownloadWorker?
        if let bgExt = bgExt {
            worker = BookDownloadWorker(
                localPath: bgExt.localPath,
                downloadUrl: bgExt.downloadUrl,
                configJson: bgExt.configJson
            )
        } else {
            worker = nil
        }
        await MainActor.run {
            if let worker = worker {
                self.activeWorkers[taskId, default: []].append(worker)
            }
        }

        defer {
            Task {
                await worker?.cleanup()
                await MainActor.run {
                    self.activeWorkers.removeValue(forKey: taskId)
                    self.activeTasks.removeValue(forKey: taskId)
                    self.runNextTasksIfNeeded(container: container)
                }
            }
        }

        // Truyện tranh/video không đi pipeline chữ: rẽ sau `defer` để slot tác vụ vẫn được nhả (`DownloadManager+Comic`).
        if await executeMediaTaskIfNeeded(task, extensionSnapshot: bgExt, container: container) {
            return
        }

        // Renderer ghi dần bản xuất ra đĩa. Khai ngoài `do` để mọi nhánh lỗi/huỷ đều dọn được file tạm.
        var renderer: ExportRenderer?

        do {
            // 1. Fetch Book by filtering in memory to avoid SwiftData #Predicate compiler bugs
            let allBooks = (try? bgContext.fetch(FetchDescriptor<Book>())) ?? []
            guard let bgBook = allBooks.first(where: { $0.bookId == task.bookId }) else {
                throw NSError(domain: "DownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy truyện trong cơ sở dữ liệu."])
            }

            // Chỉ đẩy truyện lên kệ khi nó chưa nằm ở đâu (không kệ, không lịch sử) — tôn trọng lựa chọn hiển thị của người dùng
            if !bgBook.isOnShelf && !bgBook.isHistory {
                bgBook.isOnShelf = true
                try? bgContext.save()
            }

            // 3. Prepare chapters to process via ChapterStore or SwiftData
            let sortedChapters: [StoredChapterSnapshot]
            if let storeChaps = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bgBook.bookId), !storeChaps.isEmpty {
                sortedChapters = storeChaps
            } else {
                sortedChapters = bgBook.chapters.sorted(by: { $0.index < $1.index }).map { ch in
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
            }

            let startIdx = DownloadStartChapterStore.startPosition(
                in: sortedChapters,
                taskId: taskId,
                startFromCurrent: task.startFromCurrent,
                currentIndex: bgBook.currentChapterIndex
            )

            guard startIdx < sortedChapters.count else {
                throw NSError(domain: "DownloadManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Chỉ mục chương bắt đầu vượt quá số lượng chương hiện có."])
            }

            let limitVal = task.limit.limitValue
            let endIdx = limitVal == nil ? sortedChapters.count : min(startIdx + limitVal!, sortedChapters.count)
            let chapsToProcess = Array(sortedChapters[startIdx..<endIdx])

            let total = chapsToProcess.count
            await self.updateProgress(taskId: taskId, progress: 0, total: total)

            let exportFormat = task.taskType.exportFormat
            if let exportFormat {
                // Bìa lấy trực tiếp từ file JPEG đã cache (`loadLocalCover` trả `UIImage`, ở đây cần bytes).
                var coverData: Data? = nil
                if exportFormat.supportsCover {
                    coverData = try? Data(contentsOf: ImageCacheManager.shared.localCoverURL(for: bgBook.bookId))
                }
                let request = BookExportRequest(
                    format: exportFormat,
                    bookId: bgBook.bookId,
                    bookTitle: bgBook.title,
                    author: bgBook.author,
                    desc: bgBook.desc,
                    coverJpegData: coverData,
                    translate: task.translate,
                    cacheOnly: task.onlyExportCached,
                    plannedChapterCount: total
                )
                renderer = try ExportRendererFactory.makeRenderer(for: request)
                await self.updateExportStage(taskId: taskId, stage: .fetchingChapters)
            }

            // Cùng một provider cho tải và xuất: khác biệt duy nhất là `skipUncached`. Mỗi luồng tải một provider
            // (`DownloadManager+ChapterLanes`); kết quả về đúng thứ tự mục lục.
            let bookId = bgBook.bookId
            let bookHost = bgBook.host
            let packageId = bgBook.extensionPackageId
            let skipUncached = exportFormat != nil && task.onlyExportCached
            let bookContext = SourceRuntimeContext(bookId: bookId, bookUrl: bgBook.detailUrl, bookName: bgBook.title, bookAuthor: bgBook.author)
            var processedCount = 0

            let tally = try await acquireChaptersInOrder(
                chapsToProcess,
                taskId: taskId,
                primaryWorker: worker,
                extensionSnapshot: bgExt,
                speed: DownloadSpeedSettings.load(packageId: task.extensionPackageId),
                makeProvider: { laneWorker in
                    ExportContentProvider(
                        bookId: bookId,
                        worker: laneWorker,
                        skipUncached: skipUncached,
                        bookHost: bookHost,
                        packageId: packageId,
                        bookContext: bookContext
                    )
                }
            ) { chapter, acquisition in
                if case .content(let originalContent) = acquisition, renderer != nil {
                    var titleToExport = chapter.title
                    var contentToExport = originalContent

                    if task.translate {
                        titleToExport = TranslateUtils.translateChapterTitle(titleToExport, bookId: bookId)
                        contentToExport = TranslateUtils.translateContent(contentToExport, bookId: bookId)
                    }

                    let payload = ExportChapterPayload(
                        ordinal: (renderer?.writtenChapterCount ?? 0) + 1,
                        title: titleToExport,
                        content: contentToExport
                    )
                    try renderer?.append(payload)
                }

                processedCount += 1
                await self.updateProgress(taskId: taskId, progress: processedCount, total: total)
            }

            // 4. Save and finish outcome
            AppLogger.shared.log("📊 [DownloadManager] Tác vụ \(taskId) hoàn tất xử lý: cachedCount=\(tally.cached), savedCount=\(tally.saved), skippedUncachedCount=\(tally.skippedUncached), uncachedAttemptCount=\(tally.uncachedAttempt), failedCount=\(tally.failed)")
            let renderedChapterCount = renderer?.writtenChapterCount ?? 0
            let outcome = DownloadTaskOutcomeCalculator.calculateOutcome(
                isExport: renderer != nil,
                uncachedAttemptCount: tally.uncachedAttempt,
                savedCount: tally.saved,
                failedCount: tally.failed,
                skippedUncachedCount: tally.skippedUncached,
                renderedChapterCount: renderedChapterCount
            )

            switch outcome {
            case .completed:
                if let renderer {
                    await self.updateExportStage(taskId: taskId, stage: .renderingFile)
                    let artifact = try renderer.finish()
                    // Chỉ báo hoàn thành khi file **thật sự** nằm trên đĩa — trước đây chỉ cần
                    // `finish()` không ném là đã đánh `completed`.
                    guard artifact.exists else {
                        throw ExportRenderError.cannotCreateFile(artifact.fileURL.path)
                    }
                    let summary = DownloadTaskOutcomeCalculator.exportSummary(
                        plannedCount: total,
                        renderedChapterCount: renderedChapterCount,
                        skippedUncachedCount: tally.skippedUncached,
                        failedCount: tally.failed
                    )
                    await self.markExportCompleted(taskId: taskId, artifact: artifact, summary: summary)
                } else {
                    await self.markCompleted(taskId: taskId)
                }
            case .failed(let message):
                renderer?.discard()
                await self.markFailed(taskId: taskId, error: message)
            }

        } catch is CancellationError {
            renderer?.discard()
            await self.markCancelled(taskId: taskId)
        } catch {
            renderer?.discard()
            await self.markFailed(taskId: taskId, error: error.localizedDescription)
        }
    }

    /// Mở lại share sheet cho một bản xuất đã hoàn thành (nút "Chia sẻ" trên trình theo dõi).
    ///
    /// Chỉ **phát event**: `DownloadManager` không còn tự đi tìm `rootViewController` nữa, việc trình bày
    /// thuộc `ExportShareCoordinator` ở tầng Views.
    @MainActor
    public func shareExportedFile(taskId: UUID) {
        guard let task = tasks.first(where: { $0.id == taskId }),
              let path = task.exportFilePath,
              FileManager.default.fileExists(atPath: path) else {
            DownloadPresentationEventCenter.shared.send(.showToast(message: "Tệp xuất không tồn tại hoặc đã bị xóa.", type: .error))
            return
        }
        DownloadPresentationEventCenter.shared.send(
            .exportReady(filePath: path, bookTitle: task.bookTitle)
        )
    }
}
