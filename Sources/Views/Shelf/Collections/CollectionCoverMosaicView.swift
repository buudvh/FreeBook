import SwiftUI

/// Ảnh ghép bìa của một bộ sưu tập: một bìa lớn bên trái, hai bìa nhỏ xếp dọc bên phải.
///
/// Nhận `books` đã **chọn sẵn tối đa 3 quyển** (xem `CollectionGridCardView.previewBooks`) chứ không tự
/// lọc/sắp — view này thuần trình bày, không đụng quan hệ SwiftData.
///
/// Bìa dựng bằng `BookCoverView` để dùng đúng đường cache local + fallback `book.closed` sẵn có, không
/// mở đường tải ảnh thứ hai.
struct CollectionCoverMosaicView: View {
    let books: [Book]
    /// Tổng số truyện trong bộ — quyết định badge "còn N truyện nữa".
    let totalCount: Int
    let size: CGFloat

    private let gap: CGFloat = 2

    private var leadingWidth: CGFloat { (size * 0.62).rounded() }
    private var trailingWidth: CGFloat { max(0, size - leadingWidth - gap) }
    private var smallHeight: CGFloat { max(0, (size - gap) / 2) }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch books.count {
        case 0:
            placeholder
        case 1:
            cover(books[0], width: size, height: size)
        case 2:
            HStack(spacing: gap) {
                cover(books[0], width: leadingWidth, height: size)
                cover(books[1], width: trailingWidth, height: size)
            }
        default:
            HStack(spacing: gap) {
                cover(books[0], width: leadingWidth, height: size)
                VStack(spacing: gap) {
                    cover(books[1], width: trailingWidth, height: smallHeight)
                    cover(books[2], width: trailingWidth, height: smallHeight)
                        .overlay(alignment: .bottomTrailing) { overflowBadge }
                }
            }
        }
    }

    private func cover(_ book: Book, width: CGFloat, height: CGFloat) -> some View {
        BookCoverView(
            bookId: book.bookId,
            coverUrl: book.coverUrl,
            width: width,
            height: height
        )
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "folder")
                .font(.system(size: size * 0.28, weight: .light))
                .foregroundColor(.secondary.opacity(0.45))
        }
    }

    /// Số truyện **chưa hiện**, không phải tổng — bộ 40 quyển hiện 3 bìa và badge "37+".
    @ViewBuilder
    private var overflowBadge: some View {
        if totalCount > 3 {
            Text("\(totalCount - 3)+")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(4)
        }
    }
}
