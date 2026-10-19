import Foundation

/// Kiểu hiển thị + số cột của một `BookListLayoutScope`. Số cột chỉ có nghĩa khi `mode.isGrid`.
struct BookListLayout: Equatable {
    var mode: BookListLayoutMode
    var columns: Int

    static let `default` = BookListLayout(mode: .list, columns: BookListLayoutPreferences.defaultColumns)
}
