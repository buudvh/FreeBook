import Foundation

/// Kiểu hiển thị + số cột + cỡ dòng của một `BookListLayoutScope`. Số cột chỉ có nghĩa khi `mode.isGrid`, cỡ dòng
/// chỉ có nghĩa ở kiểu Danh sách.
struct BookListLayout: Equatable {
    var mode: BookListLayoutMode
    var columns: Int
    var rowSize: BookListRowSize = .default

    static let `default` = BookListLayout(mode: .list, columns: BookListLayoutPreferences.defaultColumns)
}
