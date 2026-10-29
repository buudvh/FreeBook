import SwiftUI

/// Kiểu Danh sách dạng **panel bo góc**: mỗi truyện là một khối nền `secondarySystemBackground` bo 12pt, các khối cách
/// nhau 8pt, không vạch ngăn. Dùng chung cho Kệ sách / Lịch sử / Bộ sưu tập (`ShelfBooksLayoutView`), Tìm trên kệ,
/// Khám phá + Thể loại (`DiscoveryNovelsLayoutView`), Tìm trong một nguồn (`SearchSingleSourceResultsView`) và khung
/// chờ danh sách của Khám phá.
///
/// - Vẫn là `List` (giữ vuốt ngang, kéo làm mới, tiêu đề nhóm dính, `scrollTo`): hàng bỏ nền + vạch của `List`
///   (`bookListPanelRowChrome`), panel tự vẽ nền bên trong lề 4/16.
/// - Nền vẽ bằng `.background(_:in:)` chứ **không** `clipShape`: ghim chéo nhô ra ngoài góc bìa vẫn phải thấy.
/// - Đệm ngang 10, dọc 8 (nấc gọn 1–2: dọc 6) để bìa không dính mép panel.
///
/// Hàng gắn cử chỉ **bên ngoài** (Kệ: `onTapGesture`) dùng thẳng `bookListPanelRow(_:)`. Hàng là `Button`/link thì đặt
/// `bookListPanel(_:)` trong label (cả panel bấm được) và `bookListPanelRowChrome()` ngoài nút.
struct BookListPanelModifier: ViewModifier {
    let rowSize: BookListRowSize

    static let cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, rowSize.isCompact ? 6 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }
}

extension View {
    /// Nền + đệm của panel (không đụng thuộc tính hàng của `List`).
    func bookListPanel(_ rowSize: BookListRowSize = .default) -> some View {
        modifier(BookListPanelModifier(rowSize: rowSize))
    }

    /// Thuộc tính hàng `List` của kiểu panel: ẩn vạch, nền trong suốt, lề 4 trên/dưới + 16 hai bên. Gắn cả cho hàng
    /// sentinel / hàng phụ để danh sách không còn vạch nào.
    func bookListPanelRowChrome() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    /// Panel + thuộc tính hàng — cho hàng gắn cử chỉ bên ngoài.
    func bookListPanelRow(_ rowSize: BookListRowSize = .default) -> some View {
        bookListPanel(rowSize).bookListPanelRowChrome()
    }
}
