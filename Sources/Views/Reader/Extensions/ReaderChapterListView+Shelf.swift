import SwiftUI

/// Nút icon thêm/bỏ kệ ở đầu hàng nút của header danh sách chương. Luồng (xác nhận khi bỏ, mời chọn bộ sưu tập khi
/// thêm) nằm ở `ShelfToggleFlowModifier`, gắn ở `body` của view gốc.
///
/// Truyện chưa có bản ghi `Book` thì ẩn nút — mở Reader từ màn Chi tiết luôn tạo bản ghi trước khi vào. Đọc
/// `localBook.isOnShelf` ngay trong view thật (không ở `ReaderChapterListHost`) để icon đổi theo Observation.
extension ReaderChapterListView {

    @ViewBuilder
    internal var shelfToggleButton: some View {
        if let book = localBook {
            let isOnShelf = book.isOnShelf
            Button {
                ShelfToggleFlowModifier.toggle(
                    book,
                    in: modelContext,
                    isConfirmingRemoval: $isConfirmingShelfRemoval,
                    collectionPickerBook: $collectionPickerBook
                )
            } label: {
                Image(systemName: ShelfToggleFlowModifier.iconName(isOnShelf: isOnShelf))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isOnShelf ? .red : theme.textColor)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(ShelfToggleFlowModifier.accessibilityLabel(isOnShelf: isOnShelf))
        }
    }
}
