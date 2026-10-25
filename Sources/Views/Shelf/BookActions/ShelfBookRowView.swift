import SwiftUI

/// Một dòng truyện trên Kệ sách / trong bộ sưu tập.
///
/// Ghim và badge chương mới nằm **cạnh** `BookListItemView` chứ không nhét vào trong: view đó dùng
/// chung với Khám phá / chia sẻ truyện, sửa nó là đổi cả những màn không liên quan.
struct ShelfBookRowView: View {
    let book: Book
    let extensions: [Extension]
    var rowSize: BookListRowSize = .default

    var body: some View {
        let ext = extensions.first(where: { $0.packageId == book.extensionPackageId })
        HStack(spacing: 8) {
            BookListItemView(
                item: book,
                rowSize: rowSize,
                extensionLocalPath: ext?.localPath ?? "",
                extensionIconUrl: ext?.iconUrl
            )
            // Badge truyện tranh/video ở góc dưới phải bìa (cỡ bìa theo `rowSize`). Bìa nằm giữa theo chiều dọc của
            // dòng nên khung cùng cỡ căn `.leading` trùng đúng bìa.
            .overlay(alignment: .leading) {
                BookKindBadge(kind: ExtensionContentKind.resolve(packageId: book.extensionPackageId))
                    .padding(2)
                    .frame(width: rowSize.coverWidth, height: rowSize.coverHeight, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            }

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
