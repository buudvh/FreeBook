import SwiftUI
import SwiftData
import Combine
import Observation

enum ReaderNavigationSource: Equatable {
    case history
    case previousButton
    case nextButton
    case chapterList
    case ttsSync
    case reload

    var isImmediate: Bool {
        switch self {
        case .history, .ttsSync, .reload:
            return true
        case .previousButton, .nextButton, .chapterList:
            return false
        }
    }
}

enum ReaderNavigationDirection: Equatable {
    case backward
    case none
    case forward
}

enum ReaderLoadState: Equatable {
    case bootstrapping
    case loading(chapterIndex: Int)
    case ready(chapterIndex: Int)
    case failed(chapterIndex: Int?, message: String)
}

enum ReaderLoadError: LocalizedError {
    case noChapters
    case invalidChapterIndex(Int, total: Int)
    case missingChapterSnapshot(Int)
    case missingExtension
    case timedOut

    var errorDescription: String? {
        switch self {
        case .noChapters:
            return "Không tìm thấy chương để đọc"
        case .invalidChapterIndex(let index, let total):
            return "Chương \(index + 1) nằm ngoài danh sách \(total) chương"
        case .missingChapterSnapshot(let index):
            return "Chưa có dữ liệu cho chương \(index + 1)"
        case .missingExtension:
            return "Không tìm thấy tiện ích bóc tách"
        case .timedOut:
            return "Tải chương quá thời gian cho phép"
        }
    }
}

struct ReaderNavigationCommit: Equatable {
    let generation: Int
    let chapterIndex: Int
    let paragraphIndex: Int
    let direction: ReaderNavigationDirection
    let source: ReaderNavigationSource
    let animateContent: Bool
}

struct ReaderChapterLoadFailure: Equatable {
    let generation: Int
    let targetChapterIndex: Int
    let chapterTitle: String
    let sourceMessage: String
    let source: ReaderNavigationSource
    let paragraphIndex: Int
    let persistProgress: Bool
    let forceRefresh: Bool
}

private struct ReaderNavigationRequest: Equatable {
    let generation: Int
    let chapterIndex: Int
    let paragraphIndex: Int
    let direction: ReaderNavigationDirection
    let source: ReaderNavigationSource
    let persistProgress: Bool
    let forceRefresh: Bool
}

@available(iOS 17.0, *)
@MainActor
class ReaderViewModel: ObservableObject {
    @Published var readingContext: ReadingContext
    @Published private(set) var displayedChapterIndex: Int
    @Published private(set) var pendingNavigationIndex: Int? = nil
    @Published private(set) var navigationFailure: ReaderChapterLoadFailure?
    @Published private(set) var navigationCommit: ReaderNavigationCommit?
    @Published private(set) var isRetryingNavigation = false
    @Published private(set) var loadState: ReaderLoadState = .bootstrapping

    // Vị trí đọc hiện tại trên RAM
    @Published var currentProgress: ReadingProgress
    private var lastSavedProgress: ReadingProgress?

    let bookId: String
    let extensionPackageId: String
    @Published var totalChaptersCount: Int

    let cache = ChapterCache()
    let prefetcher = PrefetchManager()
    let progressStore = ReadingProgressStore.shared
    let modelContext: ModelContext

    private var dbSaveTask: Task<Void, Never>? = nil
    private var prefetchQueueTask: Task<Void, Never>? = nil
    private var settledPrefetchTask: Task<Void, Never>? = nil
    private var navigationDebounceTask: Task<Void, Never>? = nil
    private var navigationWorkerTask: Task<Void, Never>? = nil
    private var bootstrapTimeoutTask: Task<Void, Never>? = nil
    private var queuedNavigation: ReaderNavigationRequest?
    private var navigationGeneration = 0
    private let bootstrapChapterIndex: Int
    private let bootstrapParagraphIndex: Int
    private var speculativePrefetchEnabled = true
    private var memoryWarningSubscription: AnyCancellable?
    private var cachedLocalBook: Book? = nil
    private var cachedExt: Extension? = nil
    var onChapterCached: ((Int) -> Void)?
    public func fetchChapter(at index: Int) -> Chapter? {
        var descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate<Chapter> { $0.bookId == bookId && $0.index == index }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    public func fetchChaptersMetadata(isTranslationEnabled: Bool) -> [TTSChapterInfo] {
        var descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate<Chapter> { $0.bookId == bookId }
        )
        descriptor.sortBy = [SortDescriptor(\.index, order: .forward)]
        do {
            let chapters = try modelContext.fetch(descriptor)
            return chapters.map { chap in
                let titleToUse: String
                if isTranslationEnabled && TranslateUtils.containsChinese(chap.title) {
                    titleToUse = TranslateUtils.translateChapterTitle(chap.title, bookId: bookId)
                } else {
                    titleToUse = chap.title
                }
                return TTSChapterInfo(
                    title: titleToUse,
                    url: chap.url,
                    index: chap.index,
                    host: chap.host
                )
            }
        } catch {
            return []
        }
    }

    // Lấy danh sách chương online nếu đang đọc trực tuyến
    var onlineChapters: [ChapterResult] = []
    var isTranslationEnabled: Bool = false

    // Các thông tin bổ sung để tạo sách online khi cần
    var bookTitle: String?
    var bookAuthor: String?
    var bookCoverUrl: String?
    var bookDesc: String?
    var bookDetailUrl: String?
    var bookSourceName: String?

    private var localBook: Book? {
        if let cached = cachedLocalBook {
            return cached
        }
        let descriptor = FetchDescriptor<Book>()
        let allBooks = (try? modelContext.fetch(descriptor)) ?? []
        cachedLocalBook = allBooks.first(where: { $0.bookId == bookId })
        return cachedLocalBook
    }

    private var ext: Extension? {
        if let cached = cachedExt {
            return cached
        }
        let descriptor = FetchDescriptor<Extension>()
        let allExts = (try? modelContext.fetch(descriptor)) ?? []
        cachedExt = allExts.first(where: { $0.packageId == extensionPackageId })
        return cachedExt
    }

    init(
        bookId: String,
        extensionPackageId: String,
        initialChapterIndex: Int,
        initialParagraphIndex: Int,
        totalChaptersCount: Int,
        modelContext: ModelContext,
        onlineChapters: [ChapterResult] = [],
        isTranslationEnabled: Bool = false,
        bookTitle: String? = nil,
        bookAuthor: String? = nil,
        bookCoverUrl: String? = nil,
        bookDesc: String? = nil,
        bookDetailUrl: String? = nil,
        bookSourceName: String? = nil
    ) {
        self.bookId = bookId
        self.extensionPackageId = extensionPackageId
        self.bootstrapChapterIndex = initialChapterIndex
        self.bootstrapParagraphIndex = initialParagraphIndex
        self.modelContext = modelContext

        // @Query in ReaderView may still be empty on the first frame. Resolve the
        // complete local Book snapshot here before bootstrapping the chapter load:
        // this makes the local-first path independent of a later SwiftUI update.
        let localBookSnapshot: Book? = {
            var descriptor = FetchDescriptor<Book>(
                predicate: #Predicate<Book> { book in
                    book.bookId == bookId
                }
            )
            descriptor.fetchLimit = 1
            return (try? modelContext.fetch(descriptor))?.first
        }()
        let localChapterCount: Int = {
            if let bId = localBookSnapshot?.bookId {
                var descriptor = FetchDescriptor<Chapter>(
                    predicate: #Predicate<Chapter> { $0.bookId == bId }
                )
                return (try? modelContext.fetchCount(descriptor)) ?? 0
            }
            return 0
        }()
        self.cachedLocalBook = localBookSnapshot
        let resolvedLocalChapterCount = max(totalChaptersCount, max(localChapterCount, onlineChapters.count))
        self.totalChaptersCount = resolvedLocalChapterCount
        self.onlineChapters = onlineChapters
        self.isTranslationEnabled = isTranslationEnabled
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.bookCoverUrl = bookCoverUrl
        self.bookDesc = bookDesc
        self.bookDetailUrl = bookDetailUrl
        self.bookSourceName = bookSourceName

        let initial = ReadingProgress(chapterIndex: initialChapterIndex, paragraphIndex: initialParagraphIndex)
        self.currentProgress = initial
        self.lastSavedProgress = initial
        self.readingContext = ReadingContext(bookId: bookId, chapterIndex: initialChapterIndex, paragraphIndex: initialParagraphIndex)
        self.displayedChapterIndex = initialChapterIndex

        Task {
            await progressStore.configure(container: modelContext.container)
            await progressStore.claim(bookId: bookId, owner: .reader)
            await ChapterContentRepository.shared.configure(container: modelContext.container)
        }

        setupSubscriptions()
        _ = cache.setPlaceholder(max(initialChapterIndex, 0))
        if self.totalChaptersCount > 0 {
            bootstrapReader()
        } else {
            scheduleBootstrapTimeout()
        }
    }

    func updateChapterSnapshot(totalCount: Int, onlineChapters: [ChapterResult]) {
        // A late/empty @Query update must not erase a valid count resolved directly
        // from ModelContext during Reader bootstrap.
        guard totalCount > 0 else { return }
        if !onlineChapters.isEmpty {
            self.onlineChapters = onlineChapters
        }
        cachedLocalBook = nil
        totalChaptersCount = totalCount
        if case .bootstrapping = loadState {
            bootstrapReader()
        } else if case .failed(_, _) = loadState,
                  cache.get(displayedChapterIndex)?.state != .loaded {
            bootstrapReader()
        }
    }

    private func bootstrapReader() {
        guard totalChaptersCount > 0 else {
            loadState = .bootstrapping
            scheduleBootstrapTimeout()
            return
        }
        bootstrapTimeoutTask?.cancel()
        bootstrapTimeoutTask = nil
        let index = min(max(bootstrapChapterIndex, 0), totalChaptersCount - 1)
        displayedChapterIndex = index
        requestChapter(
            index: index,
            paragraphIndex: bootstrapParagraphIndex,
            source: .history,
            persistProgress: false
        )
    }

    private func scheduleBootstrapTimeout() {
        guard bootstrapTimeoutTask == nil else { return }
        bootstrapTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self, self.totalChaptersCount == 0 else { return }
            self.loadState = .failed(chapterIndex: nil, message: ReaderLoadError.noChapters.localizedDescription)
        }
    }

    private func setupSubscriptions() {
        memoryWarningSubscription = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleMemoryWarning()
                }
            }
    }

    // Cập nhật vị trí đọc trên RAM
    func updateProgress(chapterIndex: Int, paragraphIndex: Int) {
        let newProgress = ReadingProgress(chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
        guard !newProgress.isSameLocation(as: currentProgress) else { return }

        self.currentProgress = newProgress
        self.readingContext = ReadingContext(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
        Task { await progressStore.record(progressSnapshot(newProgress, owner: .reader)) }

        // Chi luu dia va cap nhat cache khi dich chuyen tu 3 doan van tro len
        if shouldScheduleSave(newProgress) {
            cache.setScrollParagraph(chapterIndex, paragraphIndex: paragraphIndex)
            triggerDebounceDBSave()
        }
    }

    private func shouldScheduleSave(_ newProgress: ReadingProgress) -> Bool {
        guard let last = lastSavedProgress else { return true }
        if newProgress.chapterIndex != last.chapterIndex { return true }
        if abs(newProgress.paragraphIndex - last.paragraphIndex) >= 3 { return true }
        return false
    }

    private func triggerDebounceDBSave() {
        dbSaveTask?.cancel()
        dbSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 3 * 1_000_000_000) // Debounce 3 giây
                guard !Task.isCancelled else { return }
                await saveProgressToDatabase(force: false)
            } catch {
                // Task bị hủy khi cuộn tiếp
            }
        }
    }

    func saveProgressToDatabase(force: Bool = false) async {
        let progressToSave = currentProgress
        if !force {
            guard !progressToSave.isSameLocation(as: lastSavedProgress ?? progressToSave) else { return }
        }

        do {
            await progressStore.record(progressSnapshot(progressToSave, owner: .reader))
            try await progressStore.flush(bookId: bookId)
            self.lastSavedProgress = progressToSave
        } catch {
            #if DEBUG
            AppLogger.shared.log("❌ [ReaderViewModel] Lỗi ghi DB: \(error.localizedDescription)")
            #endif
        }
    }

    func saveProgressImmediately() {
        dbSaveTask?.cancel()
        dbSaveTask = nil

        let progressToSave = currentProgress
        guard !progressToSave.isSameLocation(as: lastSavedProgress ?? progressToSave) else { return }

        Task(priority: .high) {
            do {
                await progressStore.record(progressSnapshot(progressToSave, owner: .reader))
                try await progressStore.flush(bookId: bookId)
                self.lastSavedProgress = progressToSave
            } catch {
                #if DEBUG
                AppLogger.shared.log("❌ [ReaderViewModel] Lỗi ghi đĩa khẩn cấp: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func stepChapter(
        by offset: Int,
        source: ReaderNavigationSource,
        persistProgress: Bool = true
    ) {
        guard offset != 0 else { return }
        let baseIndex = pendingNavigationIndex ?? displayedChapterIndex
        requestChapter(
            index: baseIndex + offset,
            paragraphIndex: -1,
            source: source,
            persistProgress: persistProgress
        )
    }

    func requestChapter(
        index: Int,
        paragraphIndex: Int = -1,
        source: ReaderNavigationSource,
        persistProgress: Bool = true,
        forceRefresh: Bool = false
    ) {
        guard totalChaptersCount > 0 else {
            loadState = .bootstrapping
            scheduleBootstrapTimeout()
            return
        }
        guard index >= 0, index < totalChaptersCount else {
            let error = ReaderLoadError.invalidChapterIndex(index, total: totalChaptersCount)
            loadState = .failed(chapterIndex: index, message: error.localizedDescription)
            return
        }

        settledPrefetchTask?.cancel()
        settledPrefetchTask = nil
        navigationGeneration += 1

        let direction: ReaderNavigationDirection
        if index > displayedChapterIndex {
            direction = .forward
        } else if index < displayedChapterIndex {
            direction = .backward
        } else {
            direction = .none
        }

        let request = ReaderNavigationRequest(
            generation: navigationGeneration,
            chapterIndex: index,
            paragraphIndex: paragraphIndex,
            direction: direction,
            source: source,
            persistProgress: persistProgress,
            forceRefresh: forceRefresh
        )

        pendingNavigationIndex = index
        loadState = .loading(chapterIndex: index)
        if source != .reload {
            navigationFailure = nil
        }
        isRetryingNavigation = source == .reload
        queuedNavigation = request

        Task { await prefetcher.cancelAll() }
        navigationDebounceTask?.cancel()
        navigationDebounceTask = nil

        if cache.get(index)?.state == .loaded, !forceRefresh {
            queuedNavigation = nil
            commitNavigation(request, origin: .memory)
            return
        }

        if source.isImmediate {
            startNavigationWorkerIfNeeded()
        } else {
            navigationDebounceTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    self?.startNavigationWorkerIfNeeded()
                } catch {
                    return
                }
            }
        }
    }

    func retryPendingNavigation() {
        guard let failure = navigationFailure, !isRetryingNavigation else { return }
        cache.remove(failure.targetChapterIndex)
        requestChapter(
            index: failure.targetChapterIndex,
            paragraphIndex: failure.paragraphIndex,
            source: .reload,
            persistProgress: failure.persistProgress,
            forceRefresh: failure.forceRefresh
        )
    }

    func reloadDisplayedChapter() {
        let index = displayedChapterIndex
        cache.remove(index)
        requestChapter(
            index: index,
            paragraphIndex: currentProgress.chapterIndex == index ? currentProgress.paragraphIndex : -1,
            source: .reload,
            persistProgress: false,
            forceRefresh: true
        )
    }

    func setSpeculativePrefetchEnabled(_ enabled: Bool) {
        speculativePrefetchEnabled = enabled
        if !enabled {
            settledPrefetchTask?.cancel()
            settledPrefetchTask = nil
            Task { await prefetcher.cancelAll() }
        } else {
            scheduleSettledPrefetch(after: displayedChapterIndex, within: [displayedChapterIndex + 1])
        }
    }

    private func startNavigationWorkerIfNeeded() {
        guard navigationWorkerTask == nil else { return }
        navigationWorkerTask = Task { [weak self] in
            guard let self else { return }
            await self.runNavigationWorker()
        }
    }

    private func runNavigationWorker() async {
        while let request = queuedNavigation {
            queuedNavigation = nil
            do {
                await prefetcher.cancelAll()
                let origin = try await loadChapterContentFromExtension(
                    request.chapterIndex,
                    forceRefresh: request.forceRefresh
                )
                guard request.generation == navigationGeneration else { continue }
                guard cache.get(request.chapterIndex)?.state == .loaded else {
                    let message = cache.get(request.chapterIndex)?.state.failureMessage ?? "Không tải được chương"
                    failNavigation(request, message: message)
                    continue
                }
                commitNavigation(request, origin: origin)
            } catch is CancellationError {
                guard request.generation == navigationGeneration else { continue }
                failNavigation(request, message: "Yêu cầu tải chương đã bị hủy")
            } catch {
                guard request.generation == navigationGeneration else { continue }
                failNavigation(request, message: error.localizedDescription)
            }
        }

        navigationWorkerTask = nil
        if queuedNavigation != nil {
            startNavigationWorkerIfNeeded()
        }
    }

    private func commitNavigation(
        _ request: ReaderNavigationRequest,
        origin: ChapterContentOrigin
    ) {
        guard request.generation == navigationGeneration else { return }
        displayedChapterIndex = request.chapterIndex
        pendingNavigationIndex = nil
        navigationFailure = nil
        isRetryingNavigation = false
        loadState = .ready(chapterIndex: request.chapterIndex)

        if request.persistProgress {
            currentProgress = ReadingProgress(
                chapterIndex: request.chapterIndex,
                paragraphIndex: request.paragraphIndex
            )
            readingContext = ReadingContext(
                bookId: bookId,
                chapterIndex: request.chapterIndex,
                paragraphIndex: request.paragraphIndex
            )
            saveProgressImmediately()
        }

        navigationCommit = ReaderNavigationCommit(
            generation: request.generation,
            chapterIndex: request.chapterIndex,
            paragraphIndex: request.paragraphIndex,
            direction: request.direction,
            source: request.source,
            animateContent: origin == .extensionFetch && request.source != .ttsSync
        )
        scheduleSettledPrefetch(after: request.chapterIndex, within: [request.chapterIndex + 1])
    }

    private func failNavigation(_ request: ReaderNavigationRequest, message: String) {
        guard request.generation == navigationGeneration else { return }
        pendingNavigationIndex = request.chapterIndex
        isRetryingNavigation = false
        loadState = .failed(chapterIndex: request.chapterIndex, message: message)
        cache.set(request.chapterIndex, state: .failed(message: message))
        navigationFailure = ReaderChapterLoadFailure(
            generation: request.generation,
            targetChapterIndex: request.chapterIndex,
            chapterTitle: chapterTitle(at: request.chapterIndex),
            sourceMessage: message,
            source: request.source,
            paragraphIndex: request.paragraphIndex,
            persistProgress: request.persistProgress,
            forceRefresh: request.forceRefresh
        )
    }

    func chapterTitle(at index: Int) -> String {
        if localBook != nil {
            if let chap = fetchChapter(at: index) { return chap.title }
        } else if onlineChapters.indices.contains(index) {
            return onlineChapters[index].name
        }
        return "Chương \(index + 1)"
    }


    private func handleMemoryWarning() {
        let keepSet = Set([displayedChapterIndex, pendingNavigationIndex].compactMap { $0 })
        cache.releaseAllNonVisible(keepIndexes: keepSet)
    }

    // Phân rã quản lý Cửa sổ trượt

    private func scheduleSettledPrefetch(after center: Int, within window: Set<Int>) {
        settledPrefetchTask?.cancel()
        settledPrefetchTask = nil

        guard speculativePrefetchEnabled else { return }
        let nextIndex = center + 1
        guard nextIndex < totalChaptersCount else { return }
        guard window.contains(nextIndex) else { return }

        settledPrefetchTask = Task { [weak self] in
            guard let self else { return }

            // Do not overlap speculative traffic with the selected chapter request.
            // Rapid jumps cancel this loop before any adjacent request is enqueued.
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled, self.displayedChapterIndex == center else { return }

                guard let state = self.cache.get(center)?.state else { continue }
                switch state {
                case .loaded:
                    self.enqueuePrefetch([nextIndex])
                    return
                case .failed:
                    return
                default:
                    continue
                }
            }
        }
    }

    func enqueuePrefetch(_ window: Set<Int>) {
        for idx in window {
            if idx == displayedChapterIndex {
                let cached = cache.cache[idx] ?? cache.setPlaceholder(idx)
                if cached.state != .loaded && cached.state != .loading {
                    cached.state = .loading
                }
            } else {
                if let cached = cache.cache[idx], cached.state == .placeholder {
                    cached.state = .prefetching
                }
            }
        }

        let activeIdx = displayedChapterIndex
        prefetchQueueTask?.cancel()
        prefetchQueueTask = Task {
            await prefetcher.updateQueue(withVisibleIndexes: window, activeIndex: activeIdx) { [weak self] index in
                guard let self = self else { return }
                do {
                    try await self.loadChapterContentFromExtension(index)
                } catch is CancellationError {
                    return
                } catch {
                    await MainActor.run {
                        self.cache.set(index, state: .failed(message: "Không tải được chương: \(error.localizedDescription)"))
                    }
                    throw error
                }
            }
        }
    }

    func shutdown(saveProgress: Bool = true) async {
        dbSaveTask?.cancel()
        dbSaveTask = nil
        prefetchQueueTask?.cancel()
        prefetchQueueTask = nil
        settledPrefetchTask?.cancel()
        settledPrefetchTask = nil
        navigationDebounceTask?.cancel()
        navigationDebounceTask = nil
        navigationWorkerTask?.cancel()
        navigationWorkerTask = nil
        queuedNavigation = nil
        await prefetcher.cancelAll()
        if saveProgress {
            await saveProgressToDatabase(force: true)
        }
        cache.clearAll()
    }

    // Tải nội dung chương và bóc tách
    @discardableResult
    func loadChapterContentFromExtension(
        _ index: Int,
        forceRefresh: Bool = false
    ) async throws -> ChapterContentOrigin {
        guard index >= 0 && index < totalChaptersCount else {
            throw ReaderLoadError.invalidChapterIndex(index, total: totalChaptersCount)
        }

        let title: String
        let urlString: String
        let chapterHost: String?
        let bookMetadata: BookMetadataSnapshot?

        if localBook != nil {
            guard let chap = fetchChapter(at: index) else {
                throw ReaderLoadError.missingChapterSnapshot(index)
            }
            title = chap.title
            urlString = chap.url
            chapterHost = chap.host
            bookMetadata = nil
        } else {
            guard index < onlineChapters.count else {
                throw ReaderLoadError.missingChapterSnapshot(index)
            }
            let chap = onlineChapters[index]
            title = chap.name
            urlString = chap.url
            chapterHost = chap.host
            bookMetadata = makeBookMetadataSnapshot()
        }

        cache.set(index, state: .loading)
        let extensionInfo = ext.map {
            TTSExtensionInfo(
                packageId: $0.packageId,
                localPath: $0.localPath,
                downloadUrl: $0.downloadUrl,
                configJson: $0.configJson
            )
        }
        await ChapterContentRepository.shared.configure(container: modelContext.container)
        let result = try await ChapterContentRepository.shared.load(
            ChapterContentRequest(
                bookId: bookId,
                chapterIndex: index,
                title: title,
                url: urlString,
                host: chapterHost,
                bookMetadata: bookMetadata,
                extensionInfo: extensionInfo,
                forceRefresh: forceRefresh
            )
        )

        try Task.checkCancellation()
        let cleanedContent = result.document.text.content
        if result.origin == .extensionFetch {
            cachedLocalBook = nil
            onChapterCached?(index)
        }

        await processAndSaveChapter(index: index, originalTitle: title, originalContent: cleanedContent)
        return result.origin
    }

    private func progressSnapshot(
        _ progress: ReadingProgress,
        owner: ReadingProgressOwner
    ) -> ReadingProgressSnapshot {
        ReadingProgressSnapshot(
            bookId: bookId,
            chapterIndex: progress.chapterIndex,
            paragraphIndex: progress.paragraphIndex,
            chapterTitle: chapterTitle(at: progress.chapterIndex),
            owner: owner,
            recordedAt: Date()
        )
    }

    private func makeBookMetadataSnapshot() -> BookMetadataSnapshot? {
        guard localBook == nil, let title = bookTitle, !title.isEmpty else {
            return nil
        }

        return BookMetadataSnapshot(
            bookId: bookId,
            title: title,
            author: bookAuthor ?? "Không rõ",
            coverUrl: bookCoverUrl ?? "",
            desc: bookDesc ?? "",
            detailUrl: bookDetailUrl ?? "",
            sourceName: bookSourceName ?? "Không rõ",
            sourceUrl: bookDetailUrl ?? "",
            extensionPackageId: extensionPackageId,
            host: onlineChapters.first?.host,
            chapters: onlineChapters.enumerated().map { index, chapter in
                ChapterMetadataSnapshot(
                    title: chapter.name,
                    url: chapter.url,
                    index: index,
                    host: chapter.host
                )
            }
        )
    }

    // Xử lý dịch thuật và lưu vào RAM Cache
    private func processAndSaveChapter(index: Int, originalTitle: String, originalContent: String) async {
        guard !Task.isCancelled else { return }

        let isTranslationEnabled = self.isTranslationEnabled
        let bookId = self.bookId
        let showTitleKey = "showChapterTitle_\(bookId)"
        let showTitle = UserDefaults.standard.object(forKey: showTitleKey) != nil
            ? UserDefaults.standard.bool(forKey: showTitleKey)
            : true

        // Chuyển tác vụ dịch thuật và phân tích dòng xuống luồng chạy nền (Task.detached)
        let result = await Task.detached(priority: .userInitiated) {
            let normalizedText = ChapterTextNormalizer.normalize(originalContent)
            return ReaderParagraphBuilder.build(
                originalTitle: originalTitle,
                normalizedText: normalizedText,
                isTranslationEnabled: isTranslationEnabled,
                showTitle: showTitle,
                bookId: bookId
            )
        }.value

        guard !Task.isCancelled else { return }

        // Lưu vào cache trên MainActor
        if let cached = cache.cache[index] {
            cached.originalTitle = originalTitle
            cached.originalContent = ChapterTextNormalizer.normalize(originalContent).content
            cached.title = result.translatedTitle
            cached.content = result.translatedContent
            cached.paragraphItems = result.paragraphItems
            cached.state = .loaded
        }

    }

    // Bật/tắt dịch thuật nhanh từ RAM
    func toggleTranslation(enabled: Bool) {
        self.isTranslationEnabled = enabled

        for idx in Set([displayedChapterIndex, pendingNavigationIndex].compactMap { $0 }) {
            if let cached = cache.cache[idx], cached.state == .loaded {
                let origTitle = cached.originalTitle
                let origContent = cached.originalContent

                Task {
                    await processAndSaveChapter(index: idx, originalTitle: origTitle, originalContent: origContent)
                }
            }
        }
    }

    // Cập nhật lại giao diện các đoạn văn (ví dụ khi ẩn/hiện tiêu đề chương)
    func refreshParagraphItems() {
        for idx in Set([displayedChapterIndex, pendingNavigationIndex].compactMap { $0 }) {
            if let cached = cache.cache[idx], cached.state == .loaded {
                let origTitle = cached.originalTitle
                let origContent = cached.originalContent

                Task {
                    await processAndSaveChapter(index: idx, originalTitle: origTitle, originalContent: origContent)
                }
            }
        }
    }

    deinit {
        memoryWarningSubscription?.cancel()
    }
}
