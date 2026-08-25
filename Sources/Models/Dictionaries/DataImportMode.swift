import Foundation

/// Ba chế độ nhập dùng chung cho mọi màn có dữ liệu dạng **key–value / danh sách có khoá**.
///
/// Tồn tại vì chữ "Gộp" trong app đang mang **hai nghĩa trái ngược** tuỳ màn: `DictionaryCache`,
/// `JunkFilterManager`, `TranslateUtils.mergeTOCRules` hiểu "gộp" là *đè key trùng*, còn
/// `TTSReplacementManager` và `SearchEngineTransfer` hiểu là *giữ bản cũ*. Enum này buộc mỗi màn nói
/// rõ ai thắng khi trùng khoá (xem `Docs/CheckList/import-3-modes-checklist.md`).
///
/// Đặt ở tầng `Models` để cả `Services` và `Views` dùng được — thuần Foundation, không `import SwiftUI`.
public enum DataImportMode: String, CaseIterable, Sendable {
    /// Xoá sạch dữ liệu cũ, chỉ giữ nội dung file nhập.
    case replaceAll
    /// Khoá trùng → lấy giá trị **mới**; khoá chỉ có trong file → thêm; khoá chỉ có trên máy → giữ.
    case overwriteExisting
    /// Khoá trùng → giữ giá trị **cũ**; khoá chỉ có trong file → thêm; khoá chỉ có trên máy → giữ.
    case keepExisting

    /// Nhãn nút trong dialog. Không dùng chữ "Gộp" trần ở bất cứ đâu.
    public var actionTitle: String {
        switch self {
        case .replaceAll: return "Thay thế hoàn toàn"
        case .overwriteExisting: return "Đè nghĩa mới lên key trùng"
        case .keepExisting: return "Giữ nghĩa cũ, chỉ thêm key mới"
        }
    }

    public var explanation: String {
        switch self {
        case .replaceAll:
            return "Xoá sạch dữ liệu cũ, chỉ giữ nội dung file nhập."
        case .overwriteExisting:
            return "Key trùng lấy giá trị mới; key chỉ có trong file thì thêm; key chỉ có trên máy thì giữ."
        case .keepExisting:
            return "Key trùng giữ giá trị cũ; key chỉ có trong file thì thêm; key chỉ có trên máy thì giữ."
        }
    }

    /// Chỉ chế độ 1 mới là hành động phá dữ liệu, dùng để đặt `role: .destructive` trong dialog.
    public var isDestructive: Bool { self == .replaceAll }
}
