import SwiftUI

/// Một dòng truyện trên Kệ sách / trong bộ sưu tập.
///
/// Ghim và badge chương mới nằm **cạnh** `BookListItemView` chứ không nhét vào trong: view đó dùng
/// chung với Khám phá / chia sẻ truyện, sửa nó là đổi cả những màn không liên quan.
struct ShelfBookRowView: View {
    let book: Book
    let extensions: [Extension]

    var body: some View {
        let ext = extensions.first(where: { $0.packageId == book.extensionPackageId })
        HStack(spacing: 8) {
            BookListItemView(
                item: book,
                extensionLocalPath: ext?.localPath ?? "",
                extensionIconUrl: ext?.iconUrl
            )

            if book.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .accessibilityLabel("Đang ghim đầu kệ")
            }

            NewChapterBadgeView(bookId: book.bookId)
        }
    }
}
