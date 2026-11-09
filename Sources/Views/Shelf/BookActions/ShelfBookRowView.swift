import SwiftUI

/// Một dòng truyện trên Kệ sách / trong bộ sưu tập.
///
/// Ghim (góc trên trái bìa, `CoverPinBadge`) và badge chương mới gắn **bên ngoài** `BookListItemView` chứ không
/// nhét vào trong: view đó dùng chung với Khám phá / chia sẻ truyện, sửa nó là đổi cả những màn không liên quan.
struct ShelfBookRowView: View {
    let book: Book
    let extensions: [Extension]
    var rowSize: BookListRowSize = .default

    var body: some View {
        let ext = extensions.first(where: { $0.packageId == book.extensionPackageId })
        let kind = ExtensionContentKind.resolve(packageId: book.extensionPackageId)
        // Cùng cỡ bìa với `BookListItemView` (album âm thanh bìa vuông).
        let coverHeight = rowSize.coverHeight(for: kind)
        HStack(spacing: 8) {
            BookListItemView(
                item: book,
                rowSize: rowSize,
                extensionLocalPath: ext?.localPath ?? "",
                extensionIconUrl: ext?.iconUrl
            )
            // Badge truyện tranh/video/âm thanh ở góc dưới phải bìa (cỡ bìa theo `rowSize`). Bìa nằm giữa theo chiều dọc
            // của dòng nên khung cùng cỡ căn `.leading` trùng đúng bìa.
            .overlay(alignment: .leading) {
                BookKindBadge(kind: kind)
                    .padding(2)
                    .frame(width: rowSize.coverWidth, height: coverHeight, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            }
            // Ghim chéo nhô nhẹ ra ngoài góc trên trái bìa (cùng khung cỡ bìa như badge loại).
            .overlay(alignment: .leading) {
                if book.isPinned {
                    CoverPinBadge(diameter: CoverPinBadge.diameter(forCoverWidth: rowSize.coverWidth))
                        .offset(x: -5, y: -5)
                        .frame(width: rowSize.coverWidth, height: coverHeight, alignment: .topLeading)
                }
            }

            NewChapterBadgeView(bookId: book.bookId)
        }
    }
}
