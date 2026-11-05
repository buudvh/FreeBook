import SwiftUI

/// **Đề xuất** của màn xem, kiểu bảng tin: mỗi nhóm đề xuất của nguồn (`detail.suggests`) một tiêu đề, xếp liền nhau; mỗi
/// phim là một thẻ to (`VideoWatchSuggestCard`). Nhóm chỉ tải khi cuộn tới (nằm trong `LazyVStack` của màn); nhóm **cuối**
/// nạp thêm trang khi tới thẻ cuối — không có nút "Xem thêm". Nhóm giữa chỉ một trang để nhóm sau còn được thấy.
///
/// Bấm phim ⇒ `onSelect` (màn đổi sang phim đó tại chỗ nếu là phim); `⋮` › "Mở trang chi tiết" ⇒ `onOpenDetail`.
struct VideoWatchSuggestFeed: View {
    let model: VideoWatchModel
    let onSelect: (VideoWatchRequest) -> Void
    let onOpenDetail: (VideoWatchRequest) -> Void

    var body: some View {
        let categories = model.suggests.filter { !$0.script.isEmpty }
        ForEach(Array(categories.enumerated()), id: \.element.id) { offset, category in
            VideoWatchSuggestSection(
                category: category,
                model: model,
                loadsMore: offset == categories.count - 1,
                onSelect: onSelect,
                onOpenDetail: onOpenDetail
            )
            // Đổi phim mà nhóm trùng id (input không chứa link phim) ⇒ vẫn dựng bộ nạp mới.
            .id("\(model.bookId)#\(category.id)")
        }
    }
}
