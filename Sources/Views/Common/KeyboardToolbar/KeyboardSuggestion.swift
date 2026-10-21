import UIKit

/// Một chip trên **hàng gợi ý** của thanh công cụ bàn phím (`KeyboardSuggestionRowView`). Bấm chip là chèn `text` tại
/// con trỏ của ô đang gõ — đang bôi đen thì thay đoạn đó, như gõ phím.
///
/// `replacingPrefix` khác rỗng khi gợi ý được lọc theo phần **gõ dở** sát trước con trỏ (vd gõ `<h` ⇒ chip `<hv>` thay
/// luôn `<h`). Lúc chèn, thanh đọc lại đúng đoạn đó trên ô rồi mới thay — lệch (chữ đã đổi) thì chỉ chèn tại con trỏ.
struct KeyboardSuggestion: Identifiable, Equatable {
    enum Style: Equatable {
        case normal
        /// Bấm vẫn chèn được nhưng hiện mờ (vd token đang tắt ở Cấu hình token rule).
        case dimmed
        /// Đã có trong ô — hiện kèm dấu ✓.
        case used
        /// Bắt buộc phải có mà ô chưa có — hiện đỏ.
        case missing
    }

    /// Chuỗi chèn vào ô, cũng là chữ hiện trên chip. Mỗi danh sách gợi ý không có hai chip trùng chữ.
    let text: String
    let replacingPrefix: String
    let style: Style
    let accessibilityLabel: String

    var id: String { text }
}

/// Ô nhập (`UITextField`/`UITextView`) tự cấp hàng gợi ý cho thanh công cụ bàn phím. Ô thường không cài protocol này nên
/// thanh giữ nguyên một tầng.
@MainActor
protocol KeyboardSuggestionSource: AnyObject {
    /// Gợi ý theo chữ + con trỏ **hiện tại** của ô. `nil` = ô không có hàng gợi ý. Thanh chỉ quyết định hiện hay ẩn hàng
    /// lúc ô **bắt đầu gõ** (đổi chiều cao bàn phím giữa chừng là giật), sau đó `nil` chỉ làm hàng trống.
    func currentKeyboardSuggestions() -> [KeyboardSuggestion]?
    /// Thanh gán closure này lúc gắn vào ô và gỡ khi ô thôi gõ; ô gọi nó mỗi khi chữ, con trỏ hoặc nguồn gợi ý đổi.
    var keyboardSuggestionsDidChange: (() -> Void)? { get set }
}
