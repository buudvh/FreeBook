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

struct ReaderNavigationCommit: Equatable {
    let generation: Int
    let chapterIndex: Int
    let paragraphIndex: Int
    let direction: ReaderNavigationDirection
    let source: ReaderNavigationSource
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
    @Published var tabSelection: Int = 0
    @Published var activeChapterIndex: Int = 0
    @Published var visibleIndexes: [Int] = []

    /// Window chapter đang được render trong một ScrollView duy nhất.
    @Published var stableIndexes: [Int] = []
    @Published var readingContext: ReadingContext
    @Published private(set) var displayedChapterIndex: Int
    @Published private(set) var pendingNavigationIndex: Int?
    @Published private(set) var navigationFailure: ReaderChapterLoadFailure?
    @Published private(set) var navigationCommit: ReaderNavigationCommit?
    @Published private(set) var isRetryingNavigation = false

    /// Giu lai de tuong thich voi caller cu; Infinite Reader thay window ngay.
    private(set) var pendingWindowSlide: Bool = false

    // Vị trí đọc hiện tại trên RAM
    @Published var currentProgress: ReadingProgress
    private var lastSavedProgress: ReadingProgress?

    let bookId: String
    let extensionPackageId: String
    @Published var totalChaptersCount: Int

    let cache = ChapterCache()
    let prefetcher = PrefetchManager()
    let repository: ReadingProgressRepository
    let modelContext: ModelContext

    private var dbSaveTask: Task<Void, Never>? = nil
    private var prefetchQueueTask: Task<Void, Never>? = nil
    private var settledPrefetchTask: Task<Void, Never>? = nil
    private var navigationDebounceTask: Task<Void, Never>? = nil
    private var navigationWorkerTask: Task<Void, Never>? = nil
    private var queuedNavigation: ReaderNavigationRequest?
    private var navigationGeneration = 0
    private var speculativePrefetchEnabled = true
    private var lastActiveIndex: Int = 0
    private var memoryWarningSubscription: AnyCancellable?
    private var cachedLocalBook: Book? = nil
    private var cachedExt: Extension? = nil
    private var cachedSortedChapters: [Chapter]? = nil
    var onChapterCached: ((Int) -> Void)?

    func getSortedChapters() -> [Chapter] {
        if let cached = cachedSortedChapters {
            return cached
        }
        guard let book = localBook else { return [] }
        let sorted = book.chapters.sorted(by: { $0.index < $1.index })
        self.cachedSortedChapters = sorted
        return sorted
    }

    // Đọc tiến hay đọc lùi để tối ưu hàng đợi prefetch
    private var isReadingForward: Bool {
        activeChapterIndex >= lastActiveIndex
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
        self.totalChaptersCount = totalChaptersCount
        self.modelContext = modelContext
        self.repository = ReadingProgressRepository(container: modelContext.container)
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
        self.activeChapterIndex = initialChapterIndex
        self.displayedChapterIndex = initialChapterIndex
        self.tabSelection = initialChapterIndex
        self.lastActiveIndex = initialChapterIndex

        setupSubscriptions()
        self.visibleIndexes = [initialChapterIndex]
        self.stableIndexes = [initialChapterIndex]
        _ = cache.setPlaceholder(initialChapterIndex)
        requestChapter(
            index: initialChapterIndex,
            paragraphIndex: initialParagraphIndex,
            source: .history,
            persistProgress: false
        )
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
            try await repository.saveProgress(bookId: bookId, progress: progressToSave)
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
                try await repository.saveProgress(bookId: bookId, progress: progressToSave)
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
        guard index >= 0, index < totalChaptersCount else { return }

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

        activeChapterIndex = index
        tabSelection = index
        pendingNavigationIndex = index
        if source != .reload {
            navigationFailure = nil
        }
        isRetryingNavigation = source == .reload
        visibleIndexes = [index]
        stableIndexes = [index]
        queuedNavigation = request

        Task { await prefetcher.cancelAll() }
        navigationDebounceTask?.cancel()
        navigationDebounceTask = nil

        if cache.get(index)?.state == .loaded, !forceRefresh {
            queuedNavigation = nil
            commitNavigation(request)
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
                try await loadChapterContentFromExtension(
                    request.chapterIndex,
                    forceRefresh: request.forceRefresh
                )
                guard request.generation == navigationGeneration else { continue }
                guard cache.get(request.chapterIndex)?.state == .loaded else {
                    let message = cache.get(request.chapterIndex)?.state.failureMessage ?? "Không tải được chương"
                    failNavigation(request, message: message)
                    continue
                }
                commitNavigation(request)
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

    private func commitNavigation(_ request: ReaderNavigationRequest) {
        guard request.generation == navigationGeneration else { return }
        displayedChapterIndex = request.chapterIndex
        activeChapterIndex = request.chapterIndex
        tabSelection = request.chapterIndex
        pendingNavigationIndex = nil
        navigationFailure = nil
        isRetryingNavigation = false
        visibleIndexes = [request.chapterIndex]
        stableIndexes = [request.chapterIndex]

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
            source: request.source
        )
        scheduleSettledPrefetch(after: request.chapterIndex, within: [request.chapterIndex + 1])
    }

    private func failNavigation(_ request: ReaderNavigationRequest, message: String) {
        guard request.generation == navigationGeneration else { return }
        pendingNavigationIndex = request.chapterIndex
        isRetryingNavigation = false
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
            let chapters = getSortedChapters()
            if chapters.indices.contains(index) { return chapters[index].title }
        } else if onlineChapters.indices.contains(index) {
            return onlineChapters[index].name
        }
        return "Chương \(index + 1)"
    }

    func onTabSelectionChanged(newIndex: Int, immediate: Bool = false) {
        guard newIndex != activeChapterIndex, newIndex >= 0, newIndex < totalChaptersCount else { return }

        self.lastActiveIndex = self.activeChapterIndex
        self.activeChapterIndex = newIndex
        self.tabSelection = newIndex

        self.currentProgress = ReadingProgress(chapterIndex: newIndex, paragraphIndex: 0)
        self.readingContext = ReadingContext(bookId: bookId, chapterIndex: newIndex, paragraphIndex: 0)

        if immediate {
            saveProgressImmediately()
            replaceWindow(center: newIndex)
        } else {
            slideWindow(toAdjacent: newIndex)
        }
    }

    func commitWindowSlide() {
        pendingWindowSlide = false
        saveProgressImmediately()
        updateVisibleChaptersWindow()
        self.stableIndexes = self.visibleIndexes
    }

    func updateActiveLocationFromScroll(
        chapterIndex: Int,
        paragraphIndex: Int,
        persistProgress: Bool = true
    ) {
        guard chapterIndex >= 0 && chapterIndex < totalChaptersCount else { return }
        if chapterIndex != activeChapterIndex {
            lastActiveIndex = activeChapterIndex
            activeChapterIndex = chapterIndex
            tabSelection = chapterIndex
            slideWindow(toAdjacent: chapterIndex)
        }
        if persistProgress {
            updateProgress(chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
        }
    }

    func jumpToChapter(
        _ index: Int,
        paragraphIndex: Int = -1,
        persistProgress: Bool = true
    ) {
        requestChapter(
            index: index,
            paragraphIndex: paragraphIndex,
            source: .chapterList,
            persistProgress: persistProgress
        )
    }

    func onBookChanged() {
        settledPrefetchTask?.cancel()
        settledPrefetchTask = nil
        Task {
            await prefetcher.cancelAll()
            cache.clearAll()
            self.visibleIndexes.removeAll()
            self.stableIndexes.removeAll()
            self.pendingWindowSlide = false
            self.activeChapterIndex = 0
            self.tabSelection = 0
            self.lastActiveIndex = 0
            self.readingContext = ReadingContext(bookId: self.bookId, chapterIndex: 0, paragraphIndex: -1)
            self.cachedLocalBook = nil
            self.cachedExt = nil
            self.cachedSortedChapters = nil
        }
    }

    private func handleMemoryWarning() {
        let keepSet = Set([displayedChapterIndex, pendingNavigationIndex].compactMap { $0 })
        cache.releaseAllNonVisible(keepIndexes: keepSet)
    }

    // Phân rã quản lý Cửa sổ trượt
    func updateVisibleChaptersWindow() {
        clampActiveIndex()
        replaceWindow(center: activeChapterIndex)
    }

    private func clampActiveIndex() {
        guard totalChaptersCount > 0 else { return }
        if activeChapterIndex >= totalChaptersCount {
            activeChapterIndex = totalChaptersCount - 1
            tabSelection = totalChaptersCount - 1
        }
    }

    func computeWindowRange() -> Set<Int> {
        ReaderWindowManager(totalChaptersCount: totalChaptersCount).open(center: activeChapterIndex)
    }

    private func slideWindow(toAdjacent center: Int) {
        let window = ReaderWindowManager(totalChaptersCount: totalChaptersCount).slide(toAdjacent: center)
        applyWindow(window, center: center)
        stableIndexes = visibleIndexes
    }

    private func replaceWindow(center: Int) {
        let window = ReaderWindowManager(totalChaptersCount: totalChaptersCount).replaceWindow(center: center)
        applyWindow(window, center: center)
        stableIndexes = visibleIndexes
    }

    private func applyWindow(_ window: Set<Int>, center: Int) {
        syncVisibleIndexes(window)
        enqueuePrefetch([center])
        scheduleSettledPrefetch(after: center, within: window)
        scheduleReleaseOldChapters(window)
    }

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
                guard !Task.isCancelled, self.activeChapterIndex == center else { return }

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

    private func syncVisibleIndexes(_ window: Set<Int>) {
        self.visibleIndexes = Array(window).sorted()
        for idx in visibleIndexes {
            _ = cache.setPlaceholder(idx)
        }
    }

    func enqueuePrefetch(_ window: Set<Int>) {
        for idx in window {
            if idx == activeChapterIndex {
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

        let activeIdx = activeChapterIndex
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

    private func scheduleReleaseOldChapters(_ window: Set<Int>) {
        cache.queueReleaseAllNonVisible(keepIndexes: window)
    }

    // Tải nội dung chương và bóc tách
    func loadChapterContentFromExtension(_ index: Int, forceRefresh: Bool = false) async throws {
        guard index >= 0 && index < totalChaptersCount else { return }

        // Nếu chương đã được tải xong trong RAM cache, bỏ qua không làm gì cả
        if !forceRefresh, let cached = cache.cache[index], cached.state == .loaded {
            return
        }

        // 1. Xác định Title và URL của chương
        let title: String
        let urlString: String

        if !forceRefresh, localBook != nil {
            let sorted = getSortedChapters()
            guard index < sorted.count else { return }
            let chap = sorted[index]
            title = chap.title
            urlString = chap.url
        } else {
            guard index < onlineChapters.count else { return }
            let chap = onlineChapters[index]
            title = chap.name
            urlString = chap.url
        }

        // Cập nhật trạng thái loading
        cache.set(index, state: .loading)

        // 2. Kiểm tra Cache Local trước
        if localBook != nil {
            let sorted = getSortedChapters()
            if index < sorted.count {
                let chap = sorted[index]
                if chap.isCached, let content = chap.content, !content.isEmpty {
                    let cleanedContent = normalizeLineEndings(in: content.cleanHTML())
                    await processAndSaveChapter(index: index, originalTitle: title, originalContent: cleanedContent)
                    return
                }
            }
        }

        // 3. Tải từ Extension
        guard let ext = ext else {
            let message = "Không tìm thấy tiện ích bóc tách!"
            cache.set(index, state: .failed(message: message))
            throw NSError(
                domain: "ReaderViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        var chapHost: String? = nil
        if index < onlineChapters.count {
            chapHost = onlineChapters[index].host
        } else if localBook != nil {
            let sorted = getSortedChapters()
            if index < sorted.count {
                chapHost = sorted[index].host
            }
        }

        let content = try await ExtensionManager.shared.chap(
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            url: urlString,
            host: chapHost,
            configJson: ext.configJson
        )

        try Task.checkCancellation()
        let cleanedContent = normalizeLineEndings(in: content.cleanHTML())

        // Lưu vào DB
        if localBook != nil {
            let sorted = getSortedChapters()
            if index < sorted.count {
                let chap = sorted[index]
                let previousContent = chap.content
                let wasCached = chap.isCached
                chap.content = cleanedContent
                chap.isCached = true
                do {
                    try modelContext.save()
                    onChapterCached?(index)
                } catch {
                    chap.content = previousContent
                    chap.isCached = wasCached
                    #if DEBUG
                    AppLogger.shared.log("[ReaderViewModel] Không thể lưu cache chương \(index): \(error.localizedDescription)")
                    #endif
                }
            }
        } else {
            if saveOnlineBookIfNeeded(currentIndex: index, cleanedContent: cleanedContent, title: title, url: urlString) {
                onChapterCached?(index)
            }
        }

        try Task.checkCancellation()
        await processAndSaveChapter(index: index, originalTitle: title, originalContent: cleanedContent)
    }

    private func saveOnlineBookIfNeeded(currentIndex: Int, cleanedContent: String, title: String, url: String) -> Bool {
        guard let bookTitle = bookTitle, localBook == nil else { return false }

        // Tạo sách mới trong database
        let newBook = Book(
            bookId: bookId,
            title: bookTitle,
            author: bookAuthor ?? "Không rõ",
            coverUrl: bookCoverUrl ?? "",
            desc: bookDesc ?? "",
            detailUrl: bookDetailUrl ?? "",
            sourceName: bookSourceName ?? "Không rõ",
            sourceUrl: bookDetailUrl ?? "",
            extensionPackageId: extensionPackageId,
            currentChapterIndex: currentIndex,
            currentChapterTitle: title,
            isOnShelf: false,
            isHistory: true,
            host: onlineChapters.first?.host
        )

        // Nạp các chương
        var chaps: [Chapter] = []
        for (i, c) in onlineChapters.enumerated() {
            let chapId = "\(bookId)_\(c.url)"
            let chap = Chapter(
                id: chapId,
                title: c.name,
                url: c.url,
                index: i,
                content: i == currentIndex ? cleanedContent : nil,
                isCached: i == currentIndex,
                host: c.host
            )
            chaps.append(chap)
        }
        newBook.chapters = chaps
        modelContext.insert(newBook)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(newBook)
            return false
        }
        self.cachedLocalBook = newBook
        self.cachedSortedChapters = chaps.sorted(by: { $0.index < $1.index })
        return true
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
            ReaderParagraphBuilder.build(
                originalTitle: originalTitle,
                originalContent: originalContent,
                isTranslationEnabled: isTranslationEnabled,
                showTitle: showTitle,
                bookId: bookId
            )
        }.value

        guard !Task.isCancelled else { return }

        // Lưu vào cache trên MainActor
        if let cached = cache.cache[index] {
            cached.originalTitle = originalTitle
            cached.originalContent = originalContent
            cached.title = result.translatedTitle
            cached.content = result.translatedContent
            cached.paragraphItems = result.paragraphItems
            cached.state = .loaded
        }

        // Thông báo TTSManager cập nhật cachedContent cho chương này trong chaptersQueue,
        // để advanceToNextChapter có thể dùng ngay mà không fetch lại mạng.
        if TTSManager.shared.playingBookId == bookId {
            TTSManager.shared.updateChapterCache(at: index, content: originalContent)
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

    // Tiền xử lý chữ
    private func normalizeLineEndings(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    deinit {
        memoryWarningSubscription?.cancel()
    }
}
