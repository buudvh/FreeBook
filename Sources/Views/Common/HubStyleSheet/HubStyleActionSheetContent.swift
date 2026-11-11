import SwiftUI

/// Nội dung một **sheet hành động kiểu hub** (`HubStyleActionSheet`, anh Bửu duyệt mockup 2026-11-11): dòng đầu tiêu đề +
/// chú thích bên phải, rồi các dòng dạng ô như sheet hub. Dùng cho nút "+" của Chi tiết truyện và của Kệ sách.
///
/// Chụp giá trị **lúc bấm nút** (tiêu đề, trạng thái kệ…): sheet đóng ngay khi chạm một dòng nên không cần theo dõi đổi.
/// Dòng có `page` thì chạm ⇒ **chuyển trang ngay trong sheet** (như sheet hub sang "Tác vụ AI"), sheet lớn lên nấc large.
struct HubStyleActionSheetContent: Identifiable {
    /// Đóng sheet **xong** rồi chạy việc kèm theo — dù sheet nằm trên viên thuốc hay là sheet lùi của màn.
    typealias CloseSheet = (_ then: @escaping @MainActor () -> Void) -> Void

    /// Trang con của một dòng: tiêu đề giữa header (nút ‹ bên trái) + nội dung tự dựng, nhận `CloseSheet` để đóng sheet rồi
    /// làm việc (vd mở Chi tiết). Nội dung nằm trong `NavigationStack` của sheet và được gắn nút ‹.
    struct Page {
        let title: String
        let content: (_ close: @escaping CloseSheet) -> AnyView
    }

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
        /// Có ⇒ chạm chuyển sang trang con (không đóng sheet, `action` không chạy).
        var page: Page?
        /// Chạy **sau khi** sheet đóng xong.
        let action: @MainActor () -> Void
    }

    let id = UUID()
    let title: String
    /// Chữ nhỏ bên phải tiêu đề (vd "Ch. 128/1.204"); `nil` ⇒ không có.
    var caption: String?
    let items: [Item]
}
