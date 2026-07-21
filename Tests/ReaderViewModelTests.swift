import XCTest
import SwiftData
@testable import FreeBook

@available(iOS 17.0, *)
final class ReaderViewModelTests: XCTestCase {

    override func tearDown() async throws {
        try? await BookBinManager.shared.deleteBinFile(for: "single-chapter-test-book")
        BookStorageManager.mockSaveError = nil
        BookStorageManager.mockFetchError = nil
    }

    @MainActor
    func testChapterCacheGetSet() {
        let cache = ChapterCache()

        // Ban đầu rỗng
        XCTAssertNil(cache.get(5))

        // Set placeholder
        _ = cache.setPlaceholder(5)
        let cached = cache.get(5)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.index, 5)
        XCTAssertEqual(cached?.state, .placeholder)

        // Cập nhật trạng thái
        cache.set(5, state: .loaded)
        XCTAssertEqual(cache.get(5)?.state, .loaded)
    }

    @MainActor
    func testChapterCacheQueueRelease() async {
        let cache = ChapterCache()
        _ = cache.setPlaceholder(10)
        cache.set(10, state: .loaded)

        // Đưa vào hàng đợi giải phóng trễ 1 giây
        cache.queueRelease(10, delaySeconds: 1)

        // Sau 0.2 giây vẫn còn
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNotNil(cache.get(10))

        // Sau 1.2 giây sẽ bị xóa
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertNil(cache.get(10))
    }

    actor TestTracker {
        var completedIndexes: [Int] = []
        func add(_ index: Int) {
            completedIndexes.append(index)
        }
        func get() -> [Int] {
            return completedIndexes
        }
    }

    actor ConcurrencyTracker {
        private var activeCount = 0
        private var maximumActiveCount = 0

        func begin() {
            activeCount += 1
            maximumActiveCount = max(maximumActiveCount, activeCount)
        }

        func finish() {
            activeCount -= 1
        }

        func maximum() -> Int {
            maximumActiveCount
        }
    }

    @MainActor
    func testSingleChapterReaderCoalescesRapidStepsToLatestTarget() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self,
            Chapter.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let book = Book(
            bookId: "single-chapter-test-book",
            title: "Test",
            author: "Author",
            coverUrl: "",
            desc: "",
            detailUrl: "https://example.com/book",
            sourceName: "Test",
            sourceUrl: "https://example.com",
            extensionPackageId: "test-extension"
        )
        context.insert(book)
        try context.save()

        var chapters: [Chapter] = []
        for index in 0..<30 {
            let content = "Nội dung chương \(index)"
            let (offset, length) = try await BookBinManager.shared.writeChapterContent(bookId: "single-chapter-test-book", content: content)
            let chapter = Chapter(
                id: "chapter-\(index)",
                bookId: "single-chapter-test-book",
                title: "Chương \(index + 1)",
                url: "https://example.com/chapter-\(index)",
                index: index,
                isCached: true,
                offset: offset,
                length: length
            )
            chapter.book = book
            context.insert(chapter)
            chapters.append(chapter)
        }
        book.chapters = chapters
        try context.save()

        let viewModel = ReaderViewModel(
            bookId: book.bookId,
            extensionPackageId: "window-test-extension",
            initialChapterIndex: 10,
            initialParagraphIndex: 0,
            totalChaptersCount: 30,
            modelContext: context
        )
        viewModel.setSpeculativePrefetchEnabled(false)
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(viewModel.displayedChapterIndex, 10)
        XCTAssertEqual(viewModel.loadState, .ready(chapterIndex: 10))

        for _ in 0..<4 {
            viewModel.stepChapter(by: 1, source: .nextButton, persistProgress: false)
        }

        XCTAssertEqual(viewModel.pendingNavigationIndex, 14)
        XCTAssertEqual(viewModel.displayedChapterIndex, 10)
        XCTAssertEqual(viewModel.currentProgress.chapterIndex, 10)
        XCTAssertEqual(viewModel.currentProgress.paragraphIndex, 0)
        try? await Task.sleep(nanoseconds: 650_000_000)

        XCTAssertEqual(viewModel.displayedChapterIndex, 14)
        XCTAssertEqual(viewModel.loadState, .ready(chapterIndex: 14))
        XCTAssertNil(viewModel.cache.get(11))
        XCTAssertNil(viewModel.cache.get(12))
        XCTAssertNil(viewModel.cache.get(13))
        XCTAssertEqual(viewModel.cache.get(14)?.state, .loaded)
        XCTAssertEqual(viewModel.currentProgress.chapterIndex, 10)
        XCTAssertEqual(viewModel.currentProgress.paragraphIndex, 0)

        let cachedTarget = viewModel.cache.setPlaceholder(15)
        cachedTarget.title = "Chương 16"
        cachedTarget.content = "Nội dung đã có trong RAM"
        viewModel.cache.set(15, state: .loaded)
        viewModel.stepChapter(by: 1, source: .nextButton, persistProgress: false)

        XCTAssertEqual(viewModel.displayedChapterIndex, 15)
        XCTAssertNil(viewModel.pendingNavigationIndex)

        await viewModel.shutdown()
    }

    @MainActor
    func testChapterListStoreMarksOnlyRequestedRowCached() async {
        let chapters = (0..<10_000).map { index in
            ChapterResult(
                name: "Chương \(index + 1)",
                url: "https://example.com/\(index)",
                host: "https://example.com"
            )
        }
        let store = ReaderChapterListStore(
            bookId: "online-book",
            modelContext: nil,
            onlineChapters: chapters,
            totalCount: 10_000,
            isAscending: true
        )

        // Verify totalCount
        XCTAssertEqual(store.totalCount, 10_000)

        // Verify item(at:)
        let item100 = store.item(at: 100)
        XCTAssertNotNil(item100)
        XCTAssertEqual(item100?.id, 100)
        XCTAssertEqual(item100?.index, 100)

        // Test markCached only updates a loaded state O(1)
        // 1. Force load page containing 7777 (page 77)
        _ = await store.jumpToChapter(index: 7_777)

        // Verify isCached is initially false
        let stateBefore = store.rowState(at: 7_777)
        XCTAssertFalse(stateBefore.isPlaceholder)
        XCTAssertFalse(stateBefore.isCached)

        // 2. Call markCached and verify loaded state is updated in O(1)
        store.markCached(index: 7_777)
        let stateAfter = store.rowState(at: 7_777)
        XCTAssertTrue(stateAfter.isCached)
    }

    func testSourceResponseErrorPreservesMessage() {
        let error = ExtensionManagerError.sourceResponse(message: "Nguồn đang giới hạn")
        XCTAssertEqual(error.localizedDescription, "Nguồn đang giới hạn")
    }

    func testPrefetchManagerQueueBehavior() async {
        let prefetcher = PrefetchManager()
        let tracker = TestTracker()

        let fetcher: (Int) async throws -> Void = { idx in
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            await tracker.add(idx)
        }

        // Enqueue 3 chương
        await prefetcher.updateQueue(withVisibleIndexes: [1, 2, 3], activeIndex: 1, fetcher: fetcher)

        // Đợi 0.5 giây để các worker chạy xong
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Xác nhận đã tải xong tất cả
        let completed = await tracker.get()
        XCTAssertTrue(completed.contains(1))
        XCTAssertTrue(completed.contains(2))
        XCTAssertTrue(completed.contains(3))
    }

    func testPrefetchManagerCancelBehavior() async {
        let prefetcher = PrefetchManager()
        let tracker = TestTracker()

        let fetcher: (Int) async throws -> Void = { idx in
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            await tracker.add(idx)
        }

        // Enqueue
        await prefetcher.updateQueue(withVisibleIndexes: [1, 2], activeIndex: 1, fetcher: fetcher)

        // Ngay lập tức cập nhật hàng đợi mới loại bỏ chương 2
        try? await Task.sleep(nanoseconds: 50_000_000)
        await prefetcher.updateQueue(withVisibleIndexes: [1], activeIndex: 1, fetcher: fetcher)

        // Đợi các task hoàn thành
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Chương 2 bị hủy và không xuất hiện trong danh sách hoàn thành
        let completed = await tracker.get()
        XCTAssertTrue(completed.contains(1))
        XCTAssertFalse(completed.contains(2))
    }

    func testPrefetchCancellationDoesNotExceedGlobalConcurrencyLimit() async {
        let firstReaderPrefetcher = PrefetchManager()
        let secondReaderPrefetcher = PrefetchManager()
        let tracker = ConcurrencyTracker()

        let cancellationInsensitiveFetcher: (Int) async throws -> Void = { _ in
            await tracker.begin()
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                    continuation.resume()
                }
            }
            await tracker.finish()
        }

        await firstReaderPrefetcher.updateQueue(
            withVisibleIndexes: [0, 1],
            activeIndex: 0,
            fetcher: cancellationInsensitiveFetcher
        )
        try? await Task.sleep(nanoseconds: 30_000_000)
        await firstReaderPrefetcher.cancelAll()

        await secondReaderPrefetcher.updateQueue(
            withVisibleIndexes: [2, 3],
            activeIndex: 2,
            fetcher: cancellationInsensitiveFetcher
        )
        try? await Task.sleep(nanoseconds: 550_000_000)

        let maximumActiveCount = await tracker.maximum()
        XCTAssertLessThanOrEqual(maximumActiveCount, 2)
        await firstReaderPrefetcher.cancelAll()
        await secondReaderPrefetcher.cancelAll()
    }

    func testRapidPrefetchUpdatesCoalescePendingChapters() async {
        let prefetcher = PrefetchManager()
        let tracker = TestTracker()

        let cancellationInsensitiveFetcher: (Int) async throws -> Void = { index in
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                    continuation.resume()
                }
            }
            await tracker.add(index)
        }

        await prefetcher.updateQueue(
            withVisibleIndexes: [10],
            activeIndex: 10,
            fetcher: cancellationInsensitiveFetcher
        )
        try? await Task.sleep(nanoseconds: 30_000_000)
        await prefetcher.updateQueue(
            withVisibleIndexes: [20],
            activeIndex: 20,
            fetcher: cancellationInsensitiveFetcher
        )
        try? await Task.sleep(nanoseconds: 30_000_000)
        await prefetcher.updateQueue(
            withVisibleIndexes: [30],
            activeIndex: 30,
            fetcher: cancellationInsensitiveFetcher
        )
        await prefetcher.updateQueue(
            withVisibleIndexes: [40],
            activeIndex: 40,
            fetcher: cancellationInsensitiveFetcher
        )

        try? await Task.sleep(nanoseconds: 700_000_000)

        let completed = await tracker.get()
        XCTAssertTrue(completed.contains(10))
        XCTAssertTrue(completed.contains(20))
        XCTAssertFalse(completed.contains(30))
        XCTAssertTrue(completed.contains(40))
        await prefetcher.cancelAll()
    }

    // FOCUSED TEST: Z-A Mapping
    @MainActor
    func testZAMapping() {
        let store = ReaderChapterListStore(
            bookId: "test-zamap-book",
            modelContext: nil,
            onlineChapters: [],
            totalCount: 300,
            isAscending: false
        )

        // Logical index mapped for DESC order via item(at:)
        XCTAssertEqual(store.item(at: 0)?.index, 299)
        XCTAssertEqual(store.item(at: 299)?.index, 0)
    }

    // FOCUSED TEST: Search Limit
    @MainActor
    func testSearchLimit() async throws {
        let chapters = (0..<500).map { index in
            ChapterResult(
                name: "Chương \(index + 1) test query match",
                url: "https://example.com/\(index)",
                host: "https://example.com"
            )
        }
        let store = ReaderChapterListStore(
            bookId: "test-search-book",
            modelContext: nil,
            onlineChapters: chapters,
            totalCount: 500,
            isAscending: true
        )

        store.performSearch(query: "match")

        // Wait up to 1 second for the async search task to finish
        for _ in 0..<20 {
            if !store.isSearching { break }
            try await Task.sleep(nanoseconds: 50 * 1_000_000) // 50ms
        }

        XCTAssertEqual(store.searchResults.count, 100) // Đảm bảo limit tối đa 100 kết quả
        XCTAssertEqual(store.searchResultStates.count, 100) // Verify separate search state
    }

    // FOCUSED TEST: DB Failure No File Deletion
    @MainActor
    func testNoFileDeleteOnDBFailure() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, configurations: configuration)
        let context = ModelContext(container)

        let bookId = "failed-db-book"
        let book = Book(
            bookId: bookId,
            title: "Failed Book",
            author: "Author",
            coverUrl: "",
            desc: "",
            detailUrl: "https://example.com/book",
            sourceName: "Test",
            sourceUrl: "https://example.com",
            extensionPackageId: "test-extension"
        )
        context.insert(book)
        try context.save()

        // Tạo file bin giả
        let (offset, length) = try await BookBinManager.shared.writeChapterContent(bookId: bookId, content: "test")
        let fileURL = await BookBinManager.shared.binFilePath(for: bookId)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // Giả lập lỗi Save DB thực tế bằng mock seam của BookStorageManager
        BookStorageManager.mockSaveError = NSError(domain: "MockSaveError", code: 500, userInfo: nil)

        var failed = false
        do {
            try BookStorageManager.shared.deleteBooks(bookIds: [bookId], context: context)
        } catch {
            failed = true
        }

        XCTAssertTrue(failed)

        // Chờ một khoảng thời gian ngắn để chắc chắn Task chạy nền nếu có kích hoạt
        try? await Task.sleep(nanoseconds: 100_000_000)

        // file vẫn tồn tại, không bị dọn dẹp và không bị đưa vào queue vì DB save lỗi
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // Reset mock error
        BookStorageManager.mockSaveError = nil

        // Cleanup file
        try? await BookBinManager.shared.deleteBinFile(for: bookId)
    }

    // FOCUSED TEST: Bounded Memory for 20k chapter book
    @MainActor
    func testBoundedMemoryFor20kChapters() async {
        let chapters = (0..<20_000).map { index in
            ChapterResult(
                name: "Chương \(index + 1)",
                url: "https://example.com/\(index)",
                host: "https://example.com"
            )
        }
        let store = ReaderChapterListStore(
            bookId: "test-20k-book",
            modelContext: nil,
            onlineChapters: chapters,
            totalCount: 20_000,
            isAscending: true
        )

        XCTAssertEqual(store.totalCount, 20_000)
        XCTAssertEqual(store.loadedRowStates.count, 0) // Lúc đầu chưa nạp trang nào

        // Nạp trang chứa dòng index 500
        store.loadPageIfNeeded(displayPosition: 500)

        // Đợi Task nạp trang
        try? await Task.sleep(nanoseconds: 150 * 1_000_000)

        // Trang page=5 chứa dòng 500. Cửa sổ trượt nạp trang 4, 5, 6.
        // Số lượng loaded states tối đa là 300
        XCTAssertLessThanOrEqual(store.loadedRowStates.count, 300)

        // Jump đến dòng 15,000
        _ = await store.jumpToChapter(index: 15_000)

        // Trang page=150 chứa dòng 15,000. Cửa sổ trượt nạp trang 149, 150, 151.
        // Các trang cũ đã bị evict, số lượng loaded states vẫn chỉ tối đa là 300.
        XCTAssertLessThanOrEqual(store.loadedRowStates.count, 300)
    }
}

extension ReaderViewModelTests {
    @MainActor
    func testRepeatedSamePageRequestsFetchOnce() async {
        let store = ReaderChapterListStore(
            bookId: "test-dedup",
            modelContext: nil,
            onlineChapters: [],
            totalCount: 500,
            isAscending: true
        )

        let probe = TestProbe()
        store.pageLoaderSeam = { [probe] page in
            await probe.incrementFetch(page: page)
            var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
            let start = page * 100
            for i in start..<(start + 100) {
                data[i] = ("Chương \(i + 1)", "url-\(i)", false)
            }
            return data
        }

        for _ in 0..<20 {
            store.loadPageIfNeeded(displayPosition: 50)
        }

        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        let total = await probe.getTotalFetchCount()
        XCTAssertEqual(total, 2) // Page 0 and page 1 loaded once each
    }

    @MainActor
    func testMoveCenterPageRetainsOldUntilAtomicSwap() async {
        let store = ReaderChapterListStore(
            bookId: "test-atomic",
            modelContext: nil,
            onlineChapters: [],
            totalCount: 500,
            isAscending: true
        )

        let probe = TestProbe()
        store.pageLoaderSeam = { [probe] page in
            await probe.incrementFetch(page: page)
            if let delay = await probe.getDelay(page: page) {
                try? await Task.sleep(nanoseconds: delay)
            }
            var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
            let start = page * 100
            for i in start..<(start + 100) {
                data[i] = ("Chương \(i + 1)", "url-\(i)", false)
            }
            return data
        }

        store.loadPageIfNeeded(displayPosition: 150) // center page 1 -> pages 0,1,2
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertTrue(store.loadedRowStates.keys.contains(50))

        await probe.setDelay(page: 3, nanoseconds: 200 * 1_000_000) // page 3 has 200ms delay
        store.loadPageIfNeeded(displayPosition: 250) // center page 2 -> pages 1,2,3

        try? await Task.sleep(nanoseconds: 50 * 1_000_000)
        XCTAssertTrue(store.loadedRowStates.keys.contains(50), "Should retain page 0 until replacement window is complete")

        try? await Task.sleep(nanoseconds: 200 * 1_000_000)

        XCTAssertFalse(store.loadedRowStates.keys.contains(50))
        XCTAssertTrue(store.loadedRowStates.keys.contains(350))
        XCTAssertLessThanOrEqual(store.loadedRowStates.count, 300)
    }

    @MainActor
    func testStaleGenerationCannotPublish() async {
        let store = ReaderChapterListStore(
            bookId: "test-stale",
            modelContext: nil,
            onlineChapters: [],
            totalCount: 1000,
            isAscending: true
        )

        let probe = TestProbe()
        store.pageLoaderSeam = { [probe] page in
            await probe.incrementFetch(page: page)
            try? await Task.sleep(nanoseconds: 150 * 1_000_000)
            var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
            let start = page * 100
            for i in start..<(start + 100) {
                data[i] = ("Chương \(i + 1)", "url-\(i)", false)
            }
            return data
        }

        store.loadPageIfNeeded(displayPosition: 150)
        store.updateSortOrder(isAscending: false) // Increments currentGeneration

        try? await Task.sleep(nanoseconds: 200 * 1_000_000)

        XCTAssertEqual(store.loadedRowStates.count, 0)
    }

    @MainActor
    func testFailureClearsInFlightAndRetrySucceeds() async {
        let store = ReaderChapterListStore(
            bookId: "test-retry",
            modelContext: nil,
            onlineChapters: [],
            totalCount: 500,
            isAscending: true
        )

        let probe = TestProbe()
        await probe.setShouldFail(true)
        store.pageLoaderSeam = { [probe] page in
            await probe.incrementFetch(page: page)
            if await probe.getShouldFail() {
                return nil
            }
            var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
            let start = page * 100
            for i in start..<(start + 100) {
                data[i] = ("Chương \(i + 1)", "url-\(i)", false)
            }
            return data
        }

        store.loadPageIfNeeded(displayPosition: 150)
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertEqual(store.loadedRowStates.count, 0)

        await probe.setShouldFail(false)
        store.loadPageIfNeeded(displayPosition: 150)
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertGreaterThan(store.loadedRowStates.count, 0)
    }

    @MainActor
    func testRowStateReadDoesNotMutateAndItemBounds() {
        let store = ReaderChapterListStore(
            bookId: "test-bounds",
            modelContext: nil,
            onlineChapters: [],
            totalCount: 100,
            isAscending: true
        )

        XCTAssertNil(store.item(at: -1))
        XCTAssertNil(store.item(at: 100))
        XCTAssertNotNil(store.item(at: 0))
        XCTAssertNotNil(store.item(at: 99))

        XCTAssertEqual(store.loadedRowStates.count, 0)
        let state = store.rowState(at: 50)
        XCTAssertTrue(state.isPlaceholder)
        XCTAssertEqual(store.loadedRowStates.count, 0)
    }

    @MainActor
    func testPrefetchWarmsCacheAndDoesNotPublish() async {
        let store = ReaderChapterListStore(
            bookId: "test-prefetch",
            modelContext: nil,
            onlineChapters: [],
            totalCount: 500,
            isAscending: true
        )

        let probe = TestProbe()
        store.pageLoaderSeam = { [probe] page in
            await probe.incrementFetch(page: page)
            var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
            let start = page * 100
            for i in start..<(start + 100) {
                data[i] = ("Chương \(i + 1)", "url-\(i)", false)
            }
            return data
        }

        // Prefetch page 2 (does not trigger center target page load)
        store.prefetchPageIfNeeded(page: 2)
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        // Prefetch only warms pageCache and does NOT publish to loadedRowStates!
        let total = await probe.getTotalFetchCount()
        XCTAssertEqual(total, 1)
        XCTAssertEqual(store.loadedRowStates.count, 0)
    }

    @MainActor
    func testSameGenerationOlderWindowStalePrevention() async {
        let store = ReaderChapterListStore(
            bookId: "test-window-stale",
            modelContext: nil,
            onlineChapters: [],
            totalCount: 1000,
            isAscending: true
        )

        let probe = TestProbe()
        store.pageLoaderSeam = { [probe] page in
            await probe.incrementFetch(page: page)
            if let delay = await probe.getDelay(page: page) {
                try? await Task.sleep(nanoseconds: delay)
            }
            var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
            let start = page * 100
            for i in start..<(start + 100) {
                data[i] = ("Chương \(i + 1)", "url-\(i)", false)
            }
            return data
        }

        // 1. Establish an initial active window (page 0, center target displayPos 50)
        store.loadPageIfNeeded(displayPosition: 50)
        try? await Task.sleep(nanoseconds: 50 * 1_000_000)
        XCTAssertNotNil(store.loadedRowStates[50])

        // 2. Start an older request (displayPos 150 requires page 0,1,2). Page 2 is delayed by 300ms.
        await probe.setDelay(page: 2, nanoseconds: 300 * 1_000_000)
        store.loadPageIfNeeded(displayPosition: 150)
        try? await Task.sleep(nanoseconds: 50 * 1_000_000)

        // 3. Start a newer request (displayPos 450 requires page 3,4,5). Pages 3,4,5 have no delay.
        store.loadPageIfNeeded(displayPosition: 450)

        // Wait for newer request to complete
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)
        XCTAssertNotNil(store.loadedRowStates[450])

        // 4. Clear delay so older request completes
        await probe.setDelay(page: 2, nanoseconds: 0)
        try? await Task.sleep(nanoseconds: 200 * 1_000_000)

        // Verify older request did not overwrite the newer request
        XCTAssertNil(store.loadedRowStates[150])
        XCTAssertNotNil(store.loadedRowStates[450])
    }

    @MainActor
    func testCollisionSafePersistenceWithRealAPI() async throws {
        let schema = Schema([Book.self, Chapter.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let store = ChapterPersistenceStore(container: container)

        let book = Book(bookId: "real-test-book", title: "Original Title")
        context.insert(book)
        try context.save()

        let chap0 = ChapterMetadataSnapshot(title: "Chap 1", url: "dup-url", index: 0, host: "host")
        let chap1 = ChapterMetadataSnapshot(title: "Chap 2 Duplicate URL", url: "dup-url", index: 1, host: "host")
        let chap2 = ChapterMetadataSnapshot(title: "Chap 3 Empty URL", url: "", index: 2, host: "host")
        let chap3 = ChapterMetadataSnapshot(title: "Chap 4 Empty URL 2", url: "", index: 3, host: "host")

        let snapshot = BookMetadataSnapshot(
            bookId: "real-test-book",
            title: "Book Title",
            author: "Author",
            coverUrl: "cover",
            desc: "desc",
            detailUrl: "detail",
            sourceName: "src",
            sourceUrl: "src-url",
            extensionPackageId: "pkg",
            host: "host",
            chapters: [chap0, chap1, chap2, chap3]
        )

        try await store.ensureBook(snapshot)

        var desc = FetchDescriptor<Chapter>(predicate: #Predicate<Chapter> { $0.bookId == "real-test-book" })
        desc.sortBy = [SortDescriptor(\.index)]
        let chapsFirstPass = try context.fetch(desc)
        XCTAssertEqual(chapsFirstPass.count, 4)
        XCTAssertEqual(chapsFirstPass[0].url, "dup-url")
        XCTAssertEqual(chapsFirstPass[1].url, "dup-url")
        XCTAssertEqual(chapsFirstPass[2].url, "")
        XCTAssertEqual(chapsFirstPass[3].url, "")

        let ids = Set(chapsFirstPass.map { $0.id })
        XCTAssertEqual(ids.count, 4)

        let normalId = Chapter.generateId(bookId: "real-test-book", url: "dup-url", index: 0)
        XCTAssertEqual(chapsFirstPass[0].id, normalId)
        XCTAssertNotEqual(chapsFirstPass[1].id, normalId)

        let initialId1 = chapsFirstPass[1].id

        try await store.ensureBook(snapshot)
        let chapsSecondPass = try context.fetch(desc)
        XCTAssertEqual(chapsSecondPass.count, 4)
        XCTAssertEqual(chapsSecondPass[0].id, normalId)
        XCTAssertEqual(chapsSecondPass[1].id, initialId1)

        let chap0Updated = ChapterMetadataSnapshot(title: "Chap 1 New URL", url: "new-url", index: 0, host: "host")
        let chap1StillDup = ChapterMetadataSnapshot(title: "Chap 2 Dup Still", url: "dup-url", index: 1, host: "host")

        let snapshotUpdated = BookMetadataSnapshot(
            bookId: "real-test-book",
            title: "Book Title",
            author: "Author",
            coverUrl: "cover",
            desc: "desc",
            detailUrl: "detail",
            sourceName: "src",
            sourceUrl: "src-url",
            extensionPackageId: "pkg",
            host: "host",
            chapters: [chap0Updated, chap1StillDup, chap2, chap3]
        )

        try await store.ensureBook(snapshotUpdated)

        let chapsThirdPass = try context.fetch(desc)
        XCTAssertEqual(chapsThirdPass.count, 4)
        XCTAssertEqual(chapsThirdPass[0].url, "new-url")
        XCTAssertEqual(chapsThirdPass[1].url, "dup-url")
        XCTAssertEqual(chapsThirdPass[1].id, initialId1, "Unchanged pre-existing duplicate row must keep its ID unchanged")
    }

    @MainActor
    func testPageCacheEvictionAndBounding() async {
        let store = ReaderChapterListStore(
            bookId: "test-eviction",
            modelContext: nil,
            onlineChapters: [],
            totalCount: 1000, // 10 pages
            isAscending: true
        )

        let probe = TestProbe()
        store.pageLoaderSeam = { [probe] page in
            await probe.incrementFetch(page: page)
            var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
            let start = page * 100
            for i in start..<(start + 100) {
                data[i] = ("Chương \(i + 1)", "url-\(i)", false)
            }
            return data
        }

        for p in 0...7 {
            store.prefetchPageIfNeeded(page: p)
            try? await Task.sleep(nanoseconds: 10 * 1_000_000)
        }

        XCTAssertLessThanOrEqual(store.pageCacheCount, 5)
    }

    @MainActor
    func testNormalLoadAndPrefetchDoesNotToggleLoading() async {
        let store = ReaderChapterListStore(
            bookId: "test-loading",
            modelContext: nil,
            onlineChapters: [],
            totalCount: 500,
            isAscending: true
        )

        let probe = TestProbe()
        store.pageLoaderSeam = { [probe] page in
            await probe.incrementFetch(page: page)
            var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
            let start = page * 100
            for i in start..<(start + 100) {
                data[i] = ("Chương \(i + 1)", "url-\(i)", false)
            }
            return data
        }

        store.prefetchPageIfNeeded(page: 2)
        XCTAssertFalse(store.isLoadingPage)

        store.loadPageIfNeeded(displayPosition: 150)
        XCTAssertFalse(store.isLoadingPage)

        try? await Task.sleep(nanoseconds: 100 * 1_000_000)
        XCTAssertFalse(store.isLoadingPage)
    }

    @MainActor
    func testSortChangeResetsCoordinatorAndCanReloadSamePage() async {
        let store = ReaderChapterListStore(
            bookId: "test-sort-reset",
            modelContext: nil,
            onlineChapters: [],
            totalCount: 500,
            isAscending: true
        )

        let probe = TestProbe()
        store.pageLoaderSeam = { [probe] page in
            await probe.incrementFetch(page: page)
            var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
            let start = page * 100
            for i in start..<(start + 100) {
                data[i] = ("Chương \(i + 1)", "url-\(i)", false)
            }
            return data
        }

        // 1. Initial page load (page 0 and 1 loaded)
        store.loadPageIfNeeded(displayPosition: 50)
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)
        XCTAssertNotNil(store.loadedRowStates[50])

        // 2. Change sort order (should trigger reset and clear states)
        store.updateSortOrder(isAscending: false)
        XCTAssertNil(store.loadedRowStates[50])

        // 3. Request the same display position (50) again, which corresponds to index 449 now in descending order
        store.loadPageIfNeeded(displayPosition: 50)
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        // Under descending, logical index 449 (displayPosition 50) is loaded (page 0 -> loadedRowStates 0..199).
        XCTAssertNotNil(store.loadedRowStates[50])
        XCTAssertEqual(store.rowState(at: 50).index, 449)
        XCTAssertLessThanOrEqual(store.loadedRowStates.count, 300)
    }
}

actor TestProbe {
    private var fetchCounts: [Int: Int] = [:]
    private var delayMap: [Int: UInt64] = [:]
    private var shouldFail = false

    func incrementFetch(page: Int) {
        fetchCounts[page, default: 0] += 1
    }

    func getFetchCount(page: Int) -> Int {
        return fetchCounts[page, default: 0]
    }

    func getTotalFetchCount() -> Int {
        return fetchCounts.values.reduce(0, +)
    }

    func setDelay(page: Int, nanoseconds: UInt64) {
        delayMap[page] = nanoseconds
    }

    func getDelay(page: Int) -> UInt64? {
        return delayMap[page]
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func getShouldFail() -> Bool {
        return shouldFail
    }
}
