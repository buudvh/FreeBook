import Foundation
import Observation

/// ViewModel của màn đọc truyện tranh cuộn dọc (`ComicReaderView`).
///
/// - Danh sách ảnh **không** đi qua pipeline chữ (`ChapterContentRepository`, normalizer, dịch, TTS).
/// - Nguồn ảnh của chương: ưu tiên bản tải offline (`ComicOfflineStore`), không có mới gọi
///   `SourceRuntime.comicPages`. Danh sách ảnh của chương kế được nạp trước.
/// - Tiến độ = **chỉ số ảnh**, ghi qua `ReadingProgressStore.checkpoint` (owner `.reader`): debounce 3 giây,
///   flush khi đổi chương, khi app vào nền và khi đóng màn. Không ghi SwiftData trực tiếp.
@MainActor
@Observable
final class ComicReaderViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case empty
        /// Chữ lỗi + link "Mở link lỗi" (fetch lỗi của script → URL chương) — link mất cùng lúc với trạng thái lỗi.
        case failed(String, link: SourceErrorLink?)
    }

    let launch: BookContentLaunch

    private(set) var chapters: [ComicChapterEntry] = []
    private(set) var chapterIndex: Int
    private(set) var pages: [ComicPageSource] = []
    private(set) var loadState: LoadState = .loading
    /// Ảnh trên cùng đang hiện (0-based) — cũng là giá trị lưu vào `paragraphIndex`.
    private(set) var currentPageIndex = 0
    /// Tăng mỗi lần nạp chương. View dùng làm `id` của ScrollView và để bỏ sự kiện của hàng thuộc lần nạp cũ.
    private(set) var loadGeneration = 0
    /// Ảnh cần cuộn tới ngay sau khi nạp (khôi phục tiến độ). View cuộn xong gọi `didFinishRestoringScroll()`.
    private(set) var pendingScrollPage: Int?
    private(set) var downloadedChapterIndexes: Set<Int> = []
    @ObservationIgnored private(set) var hasStarted = false

    @ObservationIgnored private var extensionSnapshot: Extension?
    @ObservationIgnored private var bookHost: String?
    @ObservationIgnored private var currentChapterUrl = ""
    /// Tỉ lệ cao/rộng đã đo của ảnh trong chương hiện tại — hàng bị dựng lại vẫn giữ đúng chiều cao.
    /// Không observe: cập nhật mỗi lần một ảnh tải xong, observe sẽ vẽ lại cả danh sách.
    @ObservationIgnored private var aspectRatios: [Int: CGFloat] = [:]
    @ObservationIgnored private var visiblePages: Set<Int> = []
    @ObservationIgnored private var isRestoringScroll = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var prefetch: (chapterIndex: Int, task: Task<[ComicPageSource], Error>)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lastSavedProgress: (chapterIndex: Int, pageIndex: Int)?

    private static let saveDebounceNanoseconds: UInt64 = 3_000_000_000

    init(launch: BookContentLaunch) {
        self.launch = launch
        self.chapterIndex = max(0, launch.chapterIndex)
    }

    // MARK: - Thuộc tính dẫn xuất

    var currentChapter: ComicChapterEntry? {
        chapters.first { $0.index == chapterIndex }
    }

    var previousChapterIndex: Int? {
        neighborChapterIndex(of: chapterIndex, offset: -1)
    }

    var nextChapterIndex: Int? {
        neighborChapterIndex(of: chapterIndex, offset: 1)
    }

    // MARK: - Vòng đời

    /// Gọi một lần từ `.task` của View. `saved` đọc từ `Book` lúc mở màn (`nil` nếu sách chưa có trong thư viện).
    func start(saved: (chapterIndex: Int, page: Int, chapterTitle: String)?, bookHost: String?) async {
        guard !hasStarted else { return }
        hasStarted = true
        self.bookHost = Self.nonEmpty(bookHost) ?? Self.nonEmpty(launch.onlineChapters.first?.host)
        extensionSnapshot = ExtensionLibraryRepository.snapshot(packageId: launch.extensionPackageId)
        await loadTableOfContents()
        // Chỉ số mở là dòng tiêu đề nhóm ("Đọc ngay" ở tập đầu, tiến độ cũ) ⇒ chương thường kế tiếp.
        chapterIndex = ComicChapterEntry.openableIndex(chapterIndex, in: chapters)
        refreshDownloadedChapters()
        loadChapter(chapterIndex, restoringPage: restorePage(saved: saved), releaseRunners: false)
    }

    /// `initialParagraphIndex`: `>= 0` = đúng ảnh đó; `nil` (Kệ) = tiến độ đã lưu nếu cùng chương; âm (BookDetail
    /// vẫn truyền -1 qua `BookContentDestination`) = đầu chương, trừ khi tiến độ đã lưu đúng của chương này. BookDetail gọi
    /// `setCurrentChapterIndex` trước khi mở — đổi chỉ số chương nhưng giữ `currentChapterPage`/`currentChapterTitle`
    /// của chương cũ — nên với -1 phải so thêm tên chương đã lưu, nếu không sẽ nhảy tới ảnh của chương trước.
    private func restorePage(saved: (chapterIndex: Int, page: Int, chapterTitle: String)?) -> Int {
        if let requested = launch.initialParagraphIndex, requested >= 0 { return requested }
        guard let saved, saved.chapterIndex == chapterIndex, saved.page > 0 else { return 0 }
        if launch.initialParagraphIndex == nil { return saved.page }
        guard let title = Self.nonEmpty(saved.chapterTitle), title == currentChapter?.title else { return 0 }
        return saved.page
    }

    /// Đóng màn: ghi tiến độ, huỷ việc đang chạy, giải phóng executor script ảnh và cache ảnh trên RAM.
    func shutdown() {
        flushProgress()
        loadTask?.cancel()
        loadTask = nil
        prefetch?.task.cancel()
        prefetch = nil
        Task {
            await ComicImageLoader.shared.releaseScriptRunners()
            await ComicImageLoader.shared.clearMemoryCache()
        }
    }

    // MARK: - Điều hướng chương

    func openChapter(_ requestedIndex: Int) {
        let index = ComicChapterEntry.openableIndex(requestedIndex, in: chapters)
        guard index != chapterIndex || loadState != .loaded else { return }
        flushProgress()
        loadChapter(index, restoringPage: 0, releaseRunners: true)
    }

    func retry() {
        loadChapter(chapterIndex, restoringPage: currentPageIndex, releaseRunners: false)
    }

    private func loadChapter(_ index: Int, restoringPage page: Int, releaseRunners: Bool) {
        loadTask?.cancel()
        saveTask?.cancel()
        saveTask = nil
        chapterIndex = index
        pages = []
        aspectRatios = [:]
        visiblePages = []
        isRestoringScroll = false
        pendingScrollPage = nil
        currentPageIndex = max(0, page)
        currentChapterUrl = chapters.first { $0.index == index }.map { resolvedChapterUrl($0) } ?? ""
        loadState = .loading
        loadGeneration += 1
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            // Executor script ảnh sống theo một chương: rời chương thì giải phóng trước khi nạp chương mới.
            if releaseRunners {
                await ComicImageLoader.shared.releaseScriptRunners()
            }
            await self?.performLoad(index: index, restoringPage: page, generation: generation)
        }
    }

    private func performLoad(index: Int, restoringPage page: Int, generation: Int) async {
        do {
            let sources = try await resolvePages(chapterIndex: index)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            pages = sources
            guard !sources.isEmpty else {
                AppLogger.shared.log("⚠️ [ComicReader] Chương \(index) không có ảnh nào")
                loadState = .empty
                return
            }
            let target = min(max(0, page), sources.count - 1)
            currentPageIndex = target
            isRestoringScroll = target > 0
            pendingScrollPage = target > 0 ? target : nil
            loadState = .loaded
            // Ghi ngay vị trí mở chương (debounce) để sách vào Lịch sử dù người dùng chưa cuộn.
            scheduleCheckpoint()
            prefetchNextChapter(after: index)
        } catch is CancellationError {
            return
        } catch {
            // Không log lại: `comicPages` đã log ❌ (`ExtensionManagerError.sourceResponse`), lỗi của màn này log ở `readerError`.
            guard generation == loadGeneration, !Task.isCancelled else { return }
            let link = SourceErrorLink.resolve(from: error, fallback: currentChapterUrl, host: bookHost)
            loadState = .failed(error.localizedDescription, link: link)
        }
    }

    // MARK: - Nguồn ảnh

    private func resolvePages(chapterIndex index: Int) async throws -> [ComicPageSource] {
        if let pending = prefetch, pending.chapterIndex == index {
            prefetch = nil
            // Prefetch lỗi/bị huỷ ⇒ nạp lại trực tiếp để báo lỗi thật cho người dùng.
            if let sources = try? await pending.task.value {
                return sources
            }
        }
        return try await fetchPages(chapterIndex: index, interactive: true)
    }

    private func fetchPages(chapterIndex index: Int, interactive: Bool = false) async throws -> [ComicPageSource] {
        if let offline = offlinePages(chapterIndex: index) {
            AppLogger.shared.log("📖 [ComicReader] Chương \(index): \(offline.count) ảnh từ bản offline")
            return offline
        }
        guard let chapter = chapters.first(where: { $0.index == index }) else {
            throw Self.readerError("Không tìm thấy chương \(index + 1) trong mục lục")
        }
        guard let ext = extensionSnapshot, !ext.localPath.isEmpty else {
            throw Self.readerError(LocalMediaPackage.missingSourceMessage(packageId: launch.extensionPackageId, fallback: "Chưa cài tiện ích nguồn của truyện này"))
        }
        let host = ExtensionHostResolver.chapterHost(chapterHost: chapter.host, bookHost: bookHost, packageId: ext.packageId)
        let sources = try await SourceRuntime.shared.comicPages(
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            url: chapter.url,
            host: host,
            configJson: ext.configJson,
            context: sourceContext(for: chapter, interactive: interactive)
        )
        AppLogger.shared.log("📖 [ComicReader] Chương \(index): \(sources.count) ảnh từ tiện ích")
        return sources
    }

    /// Bản tải offline của chương (nếu đủ manifest): mỗi ảnh là URL `file://` kèm kích thước đã lưu.
    private func offlinePages(chapterIndex index: Int) -> [ComicPageSource]? {
        let bookId = launch.bookId
        guard let manifest = ComicOfflineStore.manifest(bookId: bookId, chapterIndex: index),
              !manifest.pages.isEmpty else {
            return nil
        }
        // Manifest của URL chương khác (nguồn đổi đường dẫn) ⇒ coi như chưa tải. So cả dạng chỉ dùng host chương —
        // đúng công thức `DownloadManager+Comic` ghi manifest. Không có trong mục lục ⇒ vẫn đọc bản offline.
        if let chapter = chapters.first(where: { $0.index == index }),
           manifest.chapterUrl != resolvedChapterUrl(chapter),
           manifest.chapterUrl != JSExecutor.cleanAndResolveUrl(chapter.url, host: chapter.host) {
            AppLogger.shared.log("⚠️ [ComicReader] Bản offline chương \(index) không khớp URL chương hiện tại — đọc online")
            return nil
        }
        return manifest.pages.map { page in
            ComicPageSource(
                link: ComicOfflineStore.pageFileURL(bookId: bookId, chapterIndex: index, file: page.file).absoluteString,
                fallbacks: [],
                script: nil,
                width: page.width,
                height: page.height,
                referer: nil,
                headers: [:]
            )
        }
    }

    /// URL chương đã resolve (host chương, rỗng thì host sách) — nguồn `Referer` mặc định của ảnh.
    private func resolvedChapterUrl(_ chapter: ComicChapterEntry) -> String {
        JSExecutor.cleanAndResolveUrl(chapter.url, host: Self.nonEmpty(chapter.host) ?? bookHost)
    }

    private func prefetchNextChapter(after index: Int) {
        guard let next = neighborChapterIndex(of: index, offset: 1) else { return }
        if prefetch?.chapterIndex == next { return }
        prefetch?.task.cancel()
        let task: Task<[ComicPageSource], Error> = Task { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchPages(chapterIndex: next)
        }
        prefetch = (chapterIndex: next, task: task)
    }

    private func refreshDownloadedChapters() {
        downloadedChapterIndexes = ComicOfflineStore.downloadedChapterIndexes(bookId: launch.bookId)
    }

    /// Yêu cầu tải ảnh thứ `pageIndex` của chương hiện tại. `nil` khi chỉ số đã lệch (hàng lazy dựng trễ
    /// đúng lúc `pages` vừa bị xoá để nạp chương khác).
    func imageRequest(at pageIndex: Int) -> ComicImageRequest? {
        guard pages.indices.contains(pageIndex) else { return nil }
        return ComicImageRequest(
            source: pages[pageIndex],
            chapterUrl: currentChapterUrl,
            extensionLocalPath: extensionSnapshot?.localPath ?? "",
            downloadUrl: extensionSnapshot?.downloadUrl ?? "",
            configJson: extensionSnapshot?.configJson ?? "{}"
        )
    }

    // MARK: - Kích thước ảnh

    /// Tỉ lệ cao/rộng dùng dựng khung trước khi ảnh tải xong: đã đo > `width/height` của nguồn > 4:3 (khung 3:4).
    func aspectRatio(at pageIndex: Int) -> CGFloat {
        if let measured = aspectRatios[pageIndex] {
            return measured
        }
        if pages.indices.contains(pageIndex),
           let width = pages[pageIndex].width, let height = pages[pageIndex].height,
           width > 0, height > 0 {
            return CGFloat(height) / CGFloat(width)
        }
        return 4.0 / 3.0
    }

    func recordAspectRatio(_ ratio: CGFloat, at pageIndex: Int, generation: Int) {
        guard generation == loadGeneration, ratio.isFinite, ratio > 0 else { return }
        aspectRatios[pageIndex] = ratio
    }

    // MARK: - Theo dõi ảnh đang hiện

    func pageDidAppear(_ pageIndex: Int, generation: Int) {
        guard generation == loadGeneration else { return }
        visiblePages.insert(pageIndex)
        updateCurrentPage()
    }

    func pageDidDisappear(_ pageIndex: Int, generation: Int) {
        guard generation == loadGeneration else { return }
        visiblePages.remove(pageIndex)
        updateCurrentPage()
    }

    /// Không tính lại ngay ở đây: hàng ngay trên ảnh đích có thể vẫn nằm trong tập đang hiện, tính lại sẽ
    /// lùi tiến độ một ảnh sau mỗi lần mở lại. Ảnh hiện tại chỉ đổi ở sự kiện xuất hiện/biến mất kế tiếp.
    func didFinishRestoringScroll() {
        pendingScrollPage = nil
        isRestoringScroll = false
    }

    private func updateCurrentPage() {
        guard !isRestoringScroll, let top = visiblePages.min(), top != currentPageIndex else { return }
        currentPageIndex = top
        scheduleCheckpoint()
    }

    // MARK: - Tiến độ

    private func scheduleCheckpoint() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.saveDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flushProgress()
        }
    }

    /// Ghi ngay vị trí hiện tại (bỏ qua nếu chưa nạp xong chương hoặc không có gì mới).
    func flushProgress() {
        saveTask?.cancel()
        saveTask = nil
        guard loadState == .loaded, !pages.isEmpty else { return }
        let page = min(currentPageIndex, pages.count - 1)
        if let last = lastSavedProgress, last.chapterIndex == chapterIndex, last.pageIndex == page {
            return
        }
        lastSavedProgress = (chapterIndex: chapterIndex, pageIndex: page)
        let snapshot = ReadingProgressSnapshot(
            bookId: launch.bookId,
            chapterIndex: chapterIndex,
            paragraphIndex: page,
            chapterTitle: currentChapter?.title
        )
        Task {
            do {
                try await ReadingProgressStore.shared.checkpoint(snapshot)
            } catch {
                AppLogger.shared.log("❌ [ComicReader] Lỗi lưu tiến độ chương \(snapshot.chapterIndex): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Mục lục

    private func loadTableOfContents() async {
        let stored: [StoredChapterSnapshot]
        do {
            stored = try await ChapterStore.shared.fetchOrderedTOC(bookId: launch.bookId)
        } catch {
            AppLogger.shared.log("❌ [ComicReader] Lỗi đọc mục lục đã lưu: \(error.localizedDescription)")
            stored = []
        }
        if !stored.isEmpty {
            chapters = stored.map {
                ComicChapterEntry(index: $0.index, title: $0.title, titleTrans: $0.titleTrans, url: $0.url, host: $0.host, isSection: $0.isSection)
            }
        } else {
            chapters = launch.onlineChapters.enumerated().map { offset, chapter in
                ComicChapterEntry(index: offset, title: chapter.name, titleTrans: nil, url: chapter.url, host: chapter.host, isSection: chapter.isSection)
            }
        }
        if chapters.isEmpty {
            AppLogger.shared.log("⚠️ [ComicReader] Truyện chưa có mục lục — chỉ đọc được chương đã tải offline")
        }
    }

    /// Chương thường liền trước/sau — bỏ qua dòng tiêu đề nhóm (nút chuyển chương, prefetch).
    private func neighborChapterIndex(of index: Int, offset: Int) -> Int? {
        ComicChapterEntry.neighborIndex(of: index, step: offset, in: chapters)
    }

    // MARK: - Tiện ích

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func readerError(_ message: String) -> NSError {
        AppLogger.shared.log("❌ [ComicReader] \(message)")
        return NSError(domain: "ComicReader", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
