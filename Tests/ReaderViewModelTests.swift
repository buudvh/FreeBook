import XCTest
import SwiftData
@testable import FreeBook

@available(iOS 17.0, *)
final class ReaderViewModelTests: XCTestCase {

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
    func testVerticalReaderSlidesRenderedWindowPastTrailingBuffer() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self,
            Chapter.self,
            configurations: configuration
        )
        let viewModel = ReaderViewModel(
            bookId: "window-test-book",
            extensionPackageId: "window-test-extension",
            initialChapterIndex: 10,
            initialParagraphIndex: 0,
            totalChaptersCount: 30,
            modelContext: ModelContext(container)
        )

        XCTAssertEqual(viewModel.stableIndexes, [9, 10, 11, 12])
        XCTAssertEqual(viewModel.cache.get(10)?.state, .loading)
        XCTAssertEqual(viewModel.cache.get(11)?.state, .placeholder)
        XCTAssertEqual(viewModel.cache.get(12)?.state, .placeholder)

        viewModel.updateActiveLocationFromScroll(chapterIndex: 12, paragraphIndex: 0)

        XCTAssertEqual(viewModel.stableIndexes, [11, 12, 13, 14])
        XCTAssertTrue(viewModel.stableIndexes.contains(13))

        viewModel.jumpToChapter(20, persistProgress: false)

        XCTAssertEqual(viewModel.stableIndexes, [19, 20, 21, 22])
        XCTAssertEqual(viewModel.cache.get(20)?.state, .loading)
        XCTAssertEqual(viewModel.cache.get(21)?.state, .placeholder)
        XCTAssertEqual(viewModel.cache.get(22)?.state, .placeholder)
        XCTAssertEqual(viewModel.currentProgress.chapterIndex, 12)
        XCTAssertEqual(viewModel.currentProgress.paragraphIndex, 0)

        await viewModel.shutdown()
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
}
