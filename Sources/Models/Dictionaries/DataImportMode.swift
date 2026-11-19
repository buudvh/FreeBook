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

    /// Tên lựa chọn trong popup chọn cách nhập (`DataImportModePopup`, 1.3.982 — chữ của anh Bửu: "thay thế toàn bộ",
    /// "gộp", "chỉ thêm vào những key chưa có"). "Gộp" ở đây **luôn** nghĩa là đè key trùng; dòng `explanation` đi kèm
    /// nói rõ ai thắng khi trùng khoá nên không còn lẫn với nghĩa "giữ bản cũ" của vài màn cũ.
    public var actionTitle: String {
        switch self {
        case .replaceAll: return "Thay thế toàn bộ"
        case .overwriteExisting: return "Gộp"
        case .keepExisting: return "Chỉ thêm key mới"
        }
    }

    /// Một dòng mô tả dưới tên lựa chọn.
    public var explanation: String {
        switch self {
        case .replaceAll:
            return "Xoá danh sách cũ, chỉ giữ dữ liệu trong file mới."
        case .overwriteExisting:
            return "Vế trái trùng thì lấy nghĩa mới đè lên; chưa có thì thêm vào."
        case .keepExisting:
            return "Chỉ thêm vế trái chưa có; key đã có giữ nguyên nghĩa cũ."
        }
    }

    /// Chỉ chế độ 1 mới là hành động phá dữ liệu, dùng để đặt `role: .destructive` trong dialog.
    public var isDestructive: Bool { self == .replaceAll }
}
