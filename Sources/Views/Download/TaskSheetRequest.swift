import Foundation

/// Yêu cầu mở `TaskOptionsSheet` — **gộp** sách + loại tác vụ (+ cờ "chỉ xuất chương đã tải") vào một item cho
/// `.sheet(item:)` (1.3.654).
///
/// Trước đó mỗi màn giữ hai state rời (`selectedBookForTask` + `selectedTaskType`) và closure của sheet đọc
/// `selectedTaskType` riêng. SwiftUI có thể dựng nội dung sheet bằng giá trị cũ ở lần mở đầu — mặc định `.download` —
/// nên bấm "Xuất video" lại ra sheet "Tải video" và tạo tác vụ tải (người dùng báo). Đi kèm trong item thì nội dung
/// sheet luôn đúng loại vừa chọn.
struct TaskSheetRequest: Identifiable {
    let id = UUID()
    let book: Book
    let taskType: TaskType
    var defaultOnlyExportCached = false
}
