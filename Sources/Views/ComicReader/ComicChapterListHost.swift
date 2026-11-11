import SwiftUI

/// Vỏ **không trạng thái** của `ComicChapterListSheet` (1.3.843), cùng khuôn `ReaderChapterListHost`: sheet mục lục đang mở
/// thì mỗi lượt vẽ lại của `ComicReaderView` (ảnh tải xong, dịch xong tên chương, đổi trạng thái dịch ảnh…) dựng lại
/// closure nội dung sheet. `ComicReaderView` bọc `.equatable()` nên khi đầu vào không đổi thì mục lục không tính lại.
///
/// `==` đặt ở **vỏ** (không `@State`, không đọc store): sheet thật bên trong không `Equatable` nên ô tìm, đảo thứ tự và
/// các `@State` khác vẫn cập nhật bình thường (bài học lỗi 1.3.510 của Reader). `==` so mọi đầu vào giá trị, `Book` và
/// `extensionText` so theo identity, closure bỏ qua. Thêm thuộc tính mới thì thêm vào `==`.
///
/// `extensionText` (tên chương dịch bằng tiện ích): từng hàng tự đọc store trong `body` của nó ⇒ bản dịch về chỉ vẽ lại
/// hàng đang hiện, vỏ không đổi.
struct ComicChapterListHost: View, Equatable {
    let chapters: [ComicChapterEntry]
    let currentIndex: Int
    let downloadedIndexes: Set<Int>
    let isTranslationEnabled: Bool
    let extensionText: ComicExtensionTextTranslation
    let book: Book?
    let launch: BookContentLaunch
    @Binding var isAscending: Bool
    let onSelect: (Int) -> Void
    let onOpenBookDetail: (String) -> Void

    var body: some View {
        ComicChapterListSheet(
            chapters: chapters,
            currentIndex: currentIndex,
            downloadedIndexes: downloadedIndexes,
            isTranslationEnabled: isTranslationEnabled,
            extensionText: extensionText,
            book: book,
            launch: launch,
            isAscending: $isAscending,
            onSelect: onSelect,
            onOpenBookDetail: onOpenBookDetail
        )
    }

    static func == (lhs: ComicChapterListHost, rhs: ComicChapterListHost) -> Bool {
        lhs.chapters == rhs.chapters &&
            lhs.currentIndex == rhs.currentIndex &&
            lhs.downloadedIndexes == rhs.downloadedIndexes &&
            lhs.isTranslationEnabled == rhs.isTranslationEnabled &&
            lhs.extensionText === rhs.extensionText &&
            lhs.book === rhs.book &&
            lhs.launch == rhs.launch &&
            lhs.isAscending == rhs.isAscending
    }
}
