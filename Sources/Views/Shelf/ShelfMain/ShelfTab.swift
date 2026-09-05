import Foundation

/// Bốn tab của Kệ sách, theo **đúng thứ tự hiển thị**.
///
/// Có kiểu riêng thay vì `Int` trần vì số tab là **hợp đồng liên màn**: `SearchView` gửi nó qua
/// `userInfo["shelfTab"]` của notification `sourceChangedNavigateToShelf`, và `ShelfView+BookImport`
/// nhảy về tab Kệ sách sau khi nhập truyện. Trước 1.3.332 cả hai đầu đều viết số trần, nên đảo thứ tự
/// tab là đổi ngầm nghĩa của payload — đúng lớp lỗi mà `06_event_graph` đã cảnh báo.
///
/// `rawValue` vẫn là số để đi qua `NotificationCenter` và để `.tag()` của `Picker`/`TabView` giữ nguyên
/// hình dạng cũ.
enum ShelfTab: Int, CaseIterable, Identifiable {
    case downloads = 0
    case collections = 1
    case shelf = 2
    case history = 3

    var id: Int { rawValue }

    /// Nhãn trên `Picker` phân loại — ngắn để bốn segment vừa một dòng.
    var pickerTitle: String {
        switch self {
        case .downloads: return "Downloads"
        case .collections: return "Bộ Sưu Tập"
        case .shelf: return "Kệ Sách"
        case .history: return "Lịch Sử"
        }
    }

    var navigationTitle: String {
        switch self {
        case .downloads: return "Downloads"
        case .collections: return "Bộ Sưu Tập"
        case .shelf: return "Kệ Sách"
        case .history: return "Lịch Sử Đọc"
        }
    }

    /// Tab hiện dưới dạng **nút icon** thay cho pill chữ; `nil` ⇒ hiện `pickerTitle`.
    ///
    /// Downloads và Bộ Sưu Tập thu về icon để nhường chiều ngang cho hai tab dùng nhiều nhất. Đây là
    /// quyết định trình bày, **không** đụng `rawValue` — payload `userInfo["shelfTab"]` giữ nguyên.
    var iconName: String? {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .collections: return "square.grid.2x2"
        case .shelf, .history: return nil
        }
    }

    var isIconOnly: Bool { iconName != nil }
}
