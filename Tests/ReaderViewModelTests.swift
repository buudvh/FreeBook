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
}
