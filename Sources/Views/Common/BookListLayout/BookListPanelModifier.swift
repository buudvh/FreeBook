import SwiftUI

/// Kiểu Danh sách dạng **panel bo góc**: mỗi truyện là một khối nền `secondarySystemBackground` bo 12pt, các khối cách
/// nhau 8pt, không vạch ngăn. Dùng chung cho Kệ sách / Lịch sử / Bộ sưu tập (`ShelfBooksLayoutView`), Tìm trên kệ,
/// Khám phá + Thể loại (`DiscoveryNovelsLayoutView`), Tìm trong một nguồn (`SearchSingleSourceResultsView`) và khung
/// chờ danh sách của Khám phá.
///
/// - Kệ sách / Lịch sử / Bộ sưu tập vẫn là `List` (giữ vuốt ngang, tiêu đề nhóm dính): hàng bỏ nền + vạch của `List`
///   (`bookListPanelRowChrome`), panel tự vẽ nền bên trong lề 4/16.
/// - Danh sách **tải vô hạn từ nguồn** (Khám phá / Thể loại / Xem thêm, Tìm trong một nguồn, Tất cả bình luận) dựng bằng
///   `ScrollView` + `LazyVStack(spacing: stackSpacing)` + `bookListPanelStackPadding()` (1.3.822): hàng cao thấp khác
///   nhau (tên / mô tả 1–2 dòng) nên `List` chỉ ước chừng chiều cao hàng đã cuộn qua, mỗi lần nối trang nó tính lại và
///   chỉnh vị trí cuộn ⇒ nội dung nhảy lên ~1 hàng (kiểu lưới `LazyVGrid` không bị — anh Bửu thử). Lề + khoảng cách giữ
///   đúng như `List` (4 + 4 giữa hai panel, 16 hai bên).
/// - Nền vẽ bằng `.background(_:in:)` chứ **không** `clipShape`: ghim chéo nhô ra ngoài góc bìa vẫn phải thấy.
/// - Đệm ngang 10, dọc 8 (nấc gọn 1–2: dọc 6) để bìa không dính mép panel.
///
/// Hàng gắn cử chỉ **bên ngoài** (Kệ: `onTapGesture`) dùng thẳng `bookListPanelRow(_:)`. Hàng là `Button`/link thì đặt
/// `bookListPanel(_:)` trong label (cả panel bấm được) và `bookListPanelRowChrome()` ngoài nút.
struct BookListPanelModifier: ViewModifier {
    let rowSize: BookListRowSize

    static let cornerRadius: CGFloat = 12
    /// Khoảng giữa hai panel của danh sách dựng bằng `LazyVStack` = 4 + 4 lề hàng của `List`.
    static let stackSpacing: CGFloat = 8

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

    /// Lề quanh `LazyVStack(spacing: BookListPanelModifier.stackSpacing)` của danh sách panel ngoài `List` (1.3.822):
    /// 16 hai bên, 4 trên / dưới — khớp `bookListPanelRowChrome()`.
    func bookListPanelStackPadding() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 4)
    }

    /// Panel + thuộc tính hàng — cho hàng gắn cử chỉ bên ngoài.
    func bookListPanelRow(_ rowSize: BookListRowSize = .default) -> some View {
        bookListPanel(rowSize).bookListPanelRowChrome()
    }
}
