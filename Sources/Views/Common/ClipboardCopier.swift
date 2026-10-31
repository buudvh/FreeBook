import UIKit

/// Sao chép chữ vào bộ nhớ tạm **kèm toast "Đã sao chép"** — dùng chung cho nút sao chép của thanh công cụ bàn phím,
/// các nút sao chép cạnh ô nhập (`TextFieldClipboardButtons`, `clipboardToolbar` của Từ điển / Trí nhớ AI / Cài đặt AI)
/// và các nút sao chép khác chưa có phản hồi riêng. Bấm sao chép không đổi gì trên màn ⇒ thiếu toast thì người dùng
/// không biết đã chép hay chưa.
///
/// Toast **không** ghi vào Trung tâm thông báo (`recordsInInbox: false`): phản hồi tức thời, không đáng lưu, không tăng
/// badge chưa đọc. Nút sao chép mới thì gọi qua đây thay vì gán thẳng `UIPasteboard.general.string`.
@MainActor
enum ClipboardCopier {
    static func copy(_ text: String, message: String = "Đã sao chép") {
        UIPasteboard.general.string = text
        ToastManager.shared.show(message: message, type: .success, recordsInInbox: false)
    }
}
