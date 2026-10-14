import SwiftUI

/// Một mục của **nút hub nổi** (1.3.524): lối tắt tới một việc đang chạy nền mà người dùng có thể quay lại.
///
/// Hub thay ba widget nổi cũ (Trợ lý AI, Trình duyệt thu nhỏ, Thông báo) bằng **một** nút. Mỗi mục chỉ có mặt
/// khi điều kiện của nó đúng — `FloatingHubPresentationReader` là nơi duy nhất quyết định điều đó; type này chỉ
/// mô tả mục trông ra sao.
///
/// `detail` là dòng phụ trong menu ("Đang quét: Batch 3/12", "2 tab", "5 chưa đọc"). Nó **không** đi vào
/// `FloatingHubPresentationReader.ButtonState`, nên tiêu đề AI đổi theo từng batch không làm vẽ lại nút.
struct FloatingHubItem: Equatable, Identifiable {
    /// Loại mục. Thứ tự khai báo là **thứ tự hiển thị cố định** trong menu: AI → Trình duyệt → Thông báo.
    enum Kind: Int, CaseIterable {
        case ai
        case browser
        case notifications

        var title: String {
            switch self {
            case .ai:
                return "Trợ lý AI"
            case .browser:
                return "Trình duyệt"
            case .notifications:
                return "Thông báo"
            }
        }

        /// Glyph SF Symbols của mục. Chuông có chấm khi còn thông báo chưa đọc, chuông trơn khi mục chỉ có mặt
        /// vì đang chạy tác vụ (sao lưu / khôi phục / tải model).
        func systemImage(unreadCount: Int) -> String {
            switch self {
            case .ai:
                return "sparkles"
            case .browser:
                return "safari"
            case .notifications:
                return unreadCount > 0 ? "bell.badge.fill" : "bell"
            }
        }

        /// AI giữ màu tím quen thuộc của widget AI cũ; hai mục kia theo màu chữ hệ thống.
        var tint: Color {
            switch self {
            case .ai:
                return .purple
            case .browser, .notifications:
                return .primary
            }
        }
    }

    let kind: Kind
    /// Dòng phụ một dòng trong menu.
    let detail: String

    var id: Kind { kind }
}
