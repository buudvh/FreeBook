import Foundation

/// Kiểu hiển thị của một danh sách truyện (Kệ, Lịch sử, Bộ sưu tập, Tìm trên kệ, tab danh mục Khám phá,
/// màn Thể loại). Lưu theo `BookListLayoutScope` trong `BookListLayoutPreferences`.
enum BookListLayoutMode: String, CaseIterable, Identifiable {
    /// Hàng ngang bìa nhỏ + chữ — kiểu duy nhất trước khi có tuỳ chọn, giữ làm mặc định.
    case list
    /// Lưới: bìa ở trên, tên + dòng phụ ở dưới.
    case grid
    /// Lưới chỉ bìa: tên đè lên dải mờ ở đáy bìa.
    case coverOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: return "Danh sách"
        case .grid: return "Lưới"
        case .coverOnly: return "Chỉ bìa"
        }
    }

    var symbolName: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        case .coverOnly: return "photo.on.rectangle"
        }
    }

    /// Hai kiểu lưới dựng bằng `ScrollView` + `LazyVGrid` và có số cột.
    var isGrid: Bool { self != .list }
}
