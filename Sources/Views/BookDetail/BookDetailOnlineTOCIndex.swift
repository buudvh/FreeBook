import Foundation

/// Chỉ mục tên chương online đã dịch cho ô "Tìm kiếm chương..." của BookDetail.
/// Dựng MỘT lần ngoài main (Task.detached) khi mục lục online / bật dịch / generation dịch đổi,
/// để mỗi phím gõ không phải dịch lại toàn bộ tên chương trên main (cache tên 1024 entry bị đẩy hết
/// với mục lục dài). Chưa dựng xong thì caller tạm khớp tên gốc.
struct BookDetailOnlineTOCIndex {
    /// Khoá xác định chỉ mục còn đúng: so `generation`/`bookId` trước, mảng nguồn sau
    /// (Array `==` có fast path khi chung buffer nên thường O(1)).
    struct Key: Equatable {
        let generation: Int
        let bookId: String
        let source: [ChapterResult]
    }

    private var readyKey: Key?
    private var translatedTitles: [String] = []
    private(set) var pendingKey: Key?
    private var pendingTask: Task<Void, Never>?

    var isBuilding: Bool { pendingTask != nil }

    /// Tên đã dịch (thẳng hàng với `onlineChapters`) khi chỉ mục khớp `key`; ngược lại `nil`.
    func titles(for key: Key) -> [String]? {
        readyKey == key ? translatedTitles : nil
    }

    /// Ghi nhận lượt dựng mới, huỷ lượt cũ (nếu có).
    mutating func start(key: Key, task: Task<Void, Never>) {
        pendingTask?.cancel()
        pendingKey = key
        pendingTask = task
    }

    mutating func finish(key: Key, titles: [String]) {
        readyKey = key
        translatedTitles = titles
        pendingKey = nil
        pendingTask = nil
    }

    mutating func cancelBuild() {
        pendingTask?.cancel()
        pendingKey = nil
        pendingTask = nil
    }

    /// Dịch toàn bộ tên chương ngoài main, cùng hàm `translateChapterTitle` mà bộ lọc cũ gọi từng phím gõ,
    /// nên kết quả khớp y hệt. Trả `nil` khi bị huỷ; huỷ task gọi lan xuống task detached.
    static func translateTitles(_ names: [String], bookId: String) async -> [String]? {
        let worker = Task.detached(priority: .userInitiated) { () -> [String]? in
            var titles: [String] = []
            titles.reserveCapacity(names.count)
            for name in names {
                if Task.isCancelled { return nil }
                titles.append(TranslateUtils.translateChapterTitle(name, bookId: bookId))
            }
            return titles
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
