import SwiftUI

/// Nội dung một **sheet hành động kiểu hub** (`HubStyleActionSheet`, anh Bửu duyệt mockup 2026-11-11): dòng đầu tiêu đề +
/// chú thích bên phải, rồi các dòng dạng ô như sheet hub. Dùng cho nút "+" của Chi tiết truyện và của Kệ sách.
///
/// Chụp giá trị **lúc bấm nút** (tiêu đề, trạng thái kệ…): sheet đóng ngay khi chạm một dòng nên không cần theo dõi đổi.
struct HubStyleActionSheetContent: Identifiable {
    /// Một dòng của sheet.
    struct Item: Identifiable {
        let id: String
        let title: String
        /// Dòng phụ dưới tên (`nil` ⇒ chỉ một dòng).
        var detail: String?
        let systemImage: String
        /// Màu icon (vd xanh lá cho "Đã ở kệ"); `nil` ⇒ màu chữ chính.
        var tint: Color?
        /// Dòng mở một bước kế tiếp (trang, bộ chọn…) ⇒ có `›` cuối dòng.
        var showsChevron = false
        /// Chạy **sau khi** sheet đóng xong.
        let action: @MainActor () -> Void
    }

    let id = UUID()
    let title: String
    /// Chữ nhỏ bên phải tiêu đề (vd "Ch. 128/1.204"); `nil` ⇒ không có.
    var caption: String?
    let items: [Item]
}
