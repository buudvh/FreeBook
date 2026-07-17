import SwiftUI
import SwiftData
import Combine
import Observation

@available(iOS 17.0, *)
@MainActor
class ReaderViewModel: ObservableObject {
    @Published var tabSelection: Int = 0
    @Published var activeChapterIndex: Int = 0
    @Published var visibleIndexes: [Int] = []

    /// Window chapter đang được render trong một ScrollView duy nhất.
    @Published var stableIndexes: [Int] = []
    @Published var readingContext: ReadingContext

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
    private var lastActiveIndex: Int = 0
    private var memoryWarningSubscription: AnyCancellable?
    private var cachedLocalBook: Book? = nil
    private var cachedExt: Extension? = nil
    private var cachedSortedChapters: [Chapter]? = nil

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
        self.tabSelection = initialChapterIndex
        self.lastActiveIndex = initialChapterIndex

        setupSubscriptions()
        updateVisibleChaptersWindow()
        // Lần đầu khởi tạo: stableIndexes đồng bộ ngay với visibleIndexes
        self.stableIndexes = self.visibleIndexes
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

    func updateActiveLocationFromScroll(chapterIndex: Int, paragraphIndex: Int) {
        guard chapterIndex >= 0 && chapterIndex < totalChaptersCount else { return }
        if chapterIndex != activeChapterIndex {
            lastActiveIndex = activeChapterIndex
            activeChapterIndex = chapterIndex
            tabSelection = chapterIndex
            slideWindow(toAdjacent: chapterIndex)
        }
        updateProgress(chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
    }

    func jumpToChapter(_ index: Int, paragraphIndex: Int = -1) {
        guard index >= 0 && index < totalChaptersCount else { return }
        lastActiveIndex = activeChapterIndex
        activeChapterIndex = index
        tabSelection = index
        currentProgress = ReadingProgress(chapterIndex: index, paragraphIndex: paragraphIndex)
        readingContext = ReadingContext(bookId: bookId, chapterIndex: index, paragraphIndex: paragraphIndex)
        saveProgressImmediately()
        replaceWindow(center: index)
    }

    func onBookChanged() {
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
        let keepSet = Set(visibleIndexes)
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
        applyWindow(window, cancelPrefetch: false)
    }

    private func replaceWindow(center: Int) {
        let window = ReaderWindowManager(totalChaptersCount: totalChaptersCount).replaceWindow(center: center)
        applyWindow(window)
    }

    private func applyWindow(_ window: Set<Int>) {
        syncVisibleIndexes(window)
        enqueuePrefetch(window)
        scheduleReleaseOldChapters(window)
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
        Task {
            await prefetcher.updateQueue(withVisibleIndexes: window, activeIndex: activeIdx) { [weak self] index in
                guard let self = self else { return }
                do {
                    try await self.loadChapterContentFromExtension(index)
                } catch {
                    await MainActor.run {
                        self.cache.set(index, state: .failed(message: "Không tải được chương: \(error.localizedDescription)"))
                    }
                    throw error
                }
            }
        }
    }

    private func scheduleReleaseOldChapters(_ window: Set<Int>) {
        cache.queueReleaseAllNonVisible(keepIndexes: window)
    }

    // Tải nội dung chương và bóc tách
    func loadChapterContentFromExtension(_ index: Int) async throws {
        guard index >= 0 && index < totalChaptersCount else { return }

        // Nếu chương đã được tải xong trong RAM cache, bỏ qua không làm gì cả
        if let cached = cache.cache[index], cached.state == .loaded {
            return
        }

        // 1. Xác định Title và URL của chương
        let title: String
        let urlString: String

        if localBook != nil {
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
                    let cleanedContent = cleanBlankLines(in: content.cleanHTML())
                    await processAndSaveChapter(index: index, originalTitle: title, originalContent: cleanedContent)
                    return
                }
            }
        }

        // 3. Tải từ Extension
        guard let ext = ext else {
            cache.set(index, state: .failed(message: "Không tìm thấy tiện ích bóc tách!"))
            return
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
        let cleanedContent = cleanBlankLines(in: content.cleanHTML())

        // Lưu vào DB
        if localBook != nil {
            let sorted = getSortedChapters()
            if index < sorted.count {
                let chap = sorted[index]
                chap.content = cleanedContent
                chap.isCached = true
                Task {
                    try? modelContext.save()
                }
            }
        } else {
            saveOnlineBookIfNeeded(currentIndex: index, cleanedContent: cleanedContent, title: title, url: urlString)
        }

        try Task.checkCancellation()
        await processAndSaveChapter(index: index, originalTitle: title, originalContent: cleanedContent)
    }

    private func saveOnlineBookIfNeeded(currentIndex: Int, cleanedContent: String, title: String, url: String) {
        guard let bookTitle = bookTitle, localBook == nil else { return }

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
        try? modelContext.save()
        self.cachedSortedChapters = chaps.sorted(by: { $0.index < $1.index })
    }

    // Xử lý dịch thuật và lưu vào RAM Cache
    private func processAndSaveChapter(index: Int, originalTitle: String, originalContent: String) async {
        guard !Task.isCancelled else { return }

        // FIX 3: Trong khoảng thời gian swipe đang diễn ra, visibleIndexes chưa được
        // update (deferred đến commitWindowSlide). Vì vậy check cả activeChapterIndex
        // để chương đang swipe đến không bị guard out sớm trước khi tải xong.
        let isRelevant = visibleIndexes.contains(index) || index == activeChapterIndex
        guard isRelevant else { return }

        let isTranslationEnabled = self.isTranslationEnabled
        let bookId = self.bookId

        // Chuyển tác vụ dịch thuật và phân tích dòng xuống luồng chạy nền (Task.detached)
        let (translatedTitle, translatedContent, items) = await Task.detached(priority: .userInitiated) {
            var transTitle = originalTitle
            var transContent = originalContent

            if isTranslationEnabled {
                if TranslateUtils.containsChinese(originalTitle) {
                    transTitle = TranslateUtils.translateChapterTitle(originalTitle, bookId: bookId)
                }
                if TranslateUtils.containsChinese(originalContent) {
                    transContent = TranslateUtils.translateContent(originalContent, bookId: bookId)
                }
            }

            // Cắt dòng đoạn văn
            let originalLines = originalContent.components(separatedBy: "\n")
            let translatedLines = transContent.components(separatedBy: "\n")
            var paragraphItems: [ParagraphItem] = []

            let showTitleKey = "showChapterTitle_\(bookId)"
            let showTitle = UserDefaults.standard.object(forKey: showTitleKey) != nil ? UserDefaults.standard.bool(forKey: showTitleKey) : true

            if showTitle {
                paragraphItems.append(ParagraphItem(id: -1, original: originalTitle, translated: transTitle, isTitle: true))
            }

            let maxLines = max(originalLines.count, translatedLines.count)
            for i in 0..<maxLines {
                let orig = i < originalLines.count ? originalLines[i] : ""
                let trans = i < translatedLines.count ? translatedLines[i] : ""
                paragraphItems.append(ParagraphItem(id: i, original: orig, translated: trans, isTitle: false))
            }

            return (transTitle, transContent, paragraphItems)
        }.value

        guard !Task.isCancelled else { return }

        // FIX 3: Kiểm tra lại sau khi tác vụ nền hoàn thành — vẫn check cả activeChapterIndex
        let isStillRelevant = visibleIndexes.contains(index) || index == activeChapterIndex
        guard isStillRelevant else { return }

        // Lưu vào cache trên MainActor
        if let cached = cache.cache[index] {
            cached.originalTitle = originalTitle
            cached.originalContent = originalContent
            cached.title = translatedTitle
            cached.content = translatedContent
            cached.paragraphItems = items
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

        for idx in visibleIndexes {
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
        for idx in visibleIndexes {
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
    private func cleanBlankLines(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let cleaned = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return cleaned.joined(separator: "\n")
    }

    deinit {
        memoryWarningSubscription?.cancel()
    }
}
