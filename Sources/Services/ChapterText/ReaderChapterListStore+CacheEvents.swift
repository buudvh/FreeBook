import Foundation

/// Icon "đã tải" của mục lục Reader đổi ngay khi chương có nội dung trên máy (1.3.713).
///
/// Trước đây chỉ hai đường gọi `markCached(index:)` (nút tải lẻ, Reader tự tải chương đang đọc). Tải cả truyện
/// (`DownloadManager` → `ExportContentProvider`) và TTS đọc trước ghi cờ thẳng vào `ChapterStore` mà không báo ai; store
/// lại sống suốt phiên Reader và không nạp lại trang đã có khi mở lại sheet ⇒ icon sai tới khi thoát Reader.
///
/// Giờ store nghe `ChapterDownloadEventCenter` (actor `ChapterStore` phát sau mỗi lần ghi cờ) suốt đời của nó — sheet
/// đang đóng thì mở lại vẫn đúng. Đánh dấu **tại chỗ**: chỉ bật `isCached` của đúng hàng (`@Observable` ⇒ chỉ hàng đó
/// vẽ lại); không gán lại `loadedRowStates`, không `reloadAllPages()` — một chương một lần nạp lại là nháy hàng giữ chỗ
/// và nhảy cuộn. Chỉ số cũng được nhớ trong `freshlyCachedIndices` để hàng dựng **sau** đó (trang đã nạp sẵn trong
/// `pageCache`, trang đang nạp dở đọc DB trước lúc ghi, kết quả tìm kiếm) cũng đúng; tập này xoá ở
/// `setupPlaceholderRows()` vì lượt nạp DB mới đã thấy cờ.
extension ReaderChapterListStore {

    /// Gọi một lần lúc tạo store; `deinit` huỷ Task ⇒ stream kết thúc ⇒ tự gỡ đăng ký.
    func startObservingCacheEvents() {
        let stream = ChapterDownloadEventCenter.shared.chapterIndices(bookId: bookId)
        cacheEventTask = Task { [weak self] in
            for await indices in stream {
                self?.markCached(indices: indices)
            }
        }
    }

    /// `indices` là chỉ số **logic** (thứ tự mục lục), không phải vị trí hiển thị.
    func markCached(indices: [Int]) {
        var marked = Set<Int>()
        for index in indices where index >= 0 && index < totalCount {
            freshlyCachedIndices.insert(index)
            marked.insert(index)
            let displayPos = isAscending ? index : (totalCount - 1 - index)
            if let state = loadedRowStates[displayPos], state.index == index, !state.isCached {
                state.isCached = true
            }
        }
        guard !marked.isEmpty, !searchResultStates.isEmpty else { return }
        for state in searchResultStates.values where !state.isCached && marked.contains(state.index) {
            state.isCached = true
        }
    }

    /// Kết quả tìm dựng từ DB có thể đọc trước lúc chương được ghi — áp lại các chương đã được báo.
    func applyFreshlyCached(to states: some Sequence<ReaderChapterRowState>) {
        guard !freshlyCachedIndices.isEmpty else { return }
        for state in states where !state.isCached && freshlyCachedIndices.contains(state.index) {
            state.isCached = true
        }
    }
}
