import SwiftUI

/// Mục lục nhiều trang kiểu "cuộn vô cực": cuộn tới cuối danh sách (nút "Tải thêm" hiện ra ở danh sách hàng; ô cuối
/// của tab đang mở ở lưới tập video) thì tự gọi tải các trang còn lại, không bắt bấm nút.
///
/// Giới hạn để không thành vòng lặp gọi mạng nguồn (nguồn có thể chặn):
/// - Tối đa **một lần** cho mỗi lần dựng tab Mục lục (`didAutoLoadMoreChapters`; đổi tab rồi quay lại là dựng lại).
/// - Màn đang báo lỗi (`tocErrorMessage`, gồm cả lỗi của chính lượt tự gọi) thì không tự gọi — nút "Tải thêm" còn
///   nguyên làm nút thử lại thủ công, nên lượt tự gọi lỗi không bao giờ tự gọi lại.
/// - Đang tải dở thì `BookDetailView.startBackgroundRemainingPagesLoading` tự bỏ qua, không gọi chồng.
/// - Chỉ khi danh sách đang hiện là phần mục lục lấy từ nguồn (`isShowingPartialTOC`). Sách đã lưu mục lục đầy đủ
///   trên máy thì danh sách vốn đủ; nút ở cuối lúc đó là "lấy lại các trang sau từ nguồn" ⇒ giữ bấm tay.
extension BookDetailTOCView {
    func autoLoadMoreChaptersIfNeeded() {
        guard !didAutoLoadMoreChapters,
              tocPages.count > 1, !remainingPagesLoaded,
              tocErrorMessage.isEmpty,
              isShowingPartialTOC else { return }
        didAutoLoadMoreChapters = true
        onLoadMoreChapters()
    }

    /// Mục lục lưu trên máy không dài hơn phần đã lấy từ nguồn (trang 1, hoặc thêm vài trang của lượt tải dở).
    /// Đang tìm kiếm thì `filteredOnlineChapters` đã bị lọc, không so được ⇒ chỉ tính khi chưa có mục lục lưu.
    private var isShowingPartialTOC: Bool {
        chapterSnapshots.isEmpty
            || (appliedSearchQuery.isEmpty && chapterSnapshots.count <= filteredOnlineChapters.count)
    }
}
