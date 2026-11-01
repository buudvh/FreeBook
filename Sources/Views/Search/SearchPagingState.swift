import Foundation

/// Trạng thái tải thêm trang của "tìm trong một nguồn" (`SearchView+Paging`).
///
/// Mỗi lượt `performSearch` (từ khoá mới, tìm mọi nguồn, chip loại, thử lại…) và nút xoá ô tìm gọi `reset()`: `searchId`
/// tăng, lượt tải thêm đang chạy bị huỷ, kết quả về muộn của lượt cũ bị bỏ. Dừng phân trang khi: token trang kế rỗng,
/// token trùng token vừa dùng, trang không thêm link mới nào (sau khi lọc trùng), hoặc đã tải `maxPages` trang.
struct SearchPagingState {
    static let maxPages = 50
    /// Trang sau lỗi: tự thử lại tối đa `maxRetries` lần, cách nhau `retryDelayNanoseconds`, rồi dừng im lặng.
    static let maxRetries = 3
    static let retryDelayNanoseconds: UInt64 = 2_000_000_000
    /// Đối số `page` của trang 1 (tiện ích riêng của FreeBook có thể `parseInt(page)`).
    static let firstPageToken = "1"

    private(set) var searchId = 0
    /// Nguồn + từ khoá của lượt đang phân trang; `nil` khi chưa có trang 1 (hoặc đã `reset()`).
    private(set) var ext: Extension?
    private(set) var query = ""
    /// Token trang kế sẽ gửi cho `execute(query, page)`; `nil` ⇒ hết trang.
    private(set) var nextToken: String?
    /// Token vừa dùng cho trang gần nhất (trang 1 = `firstPageToken`).
    private(set) var lastToken = ""
    private(set) var pagesLoaded = 0
    /// Đang tải (kể cả lúc chờ thử lại) ⇒ chặn lượt tải thêm chồng nhau.
    var isLoadingMore = false
    var loadTask: Task<Void, Never>?

    var canLoadMore: Bool {
        ext != nil && nextToken != nil && pagesLoaded < Self.maxPages
    }

    mutating func reset() {
        loadTask?.cancel()
        loadTask = nil
        searchId += 1
        ext = nil
        query = ""
        nextToken = nil
        lastToken = ""
        pagesLoaded = 0
        isLoadingMore = false
    }

    /// Trang 1 đã hiện `shownCount` kết quả.
    mutating func didLoadFirstPage(ext: Extension, query: String, shownCount: Int, nextToken: String?) {
        self.ext = ext
        self.query = query
        pagesLoaded = 1
        lastToken = Self.firstPageToken
        self.nextToken = shownCount > 0 ? Self.validNextToken(nextToken, after: lastToken) : nil
    }

    /// Trang tải bằng `usedToken` đã thêm `addedCount` link mới.
    mutating func didLoadPage(usedToken: String, addedCount: Int, nextToken: String?) {
        pagesLoaded += 1
        lastToken = usedToken
        isLoadingMore = false
        loadTask = nil
        self.nextToken = addedCount > 0 ? Self.validNextToken(nextToken, after: usedToken) : nil
    }

    /// Trang sau lỗi hết lượt thử lại: dừng phân trang của lượt này (không báo lỗi lên màn).
    mutating func stop() {
        nextToken = nil
        isLoadingMore = false
        loadTask = nil
    }

    private static func validNextToken(_ token: String?, after usedToken: String) -> String? {
        guard let token, !token.isEmpty, token != usedToken else { return nil }
        return token
    }
}
