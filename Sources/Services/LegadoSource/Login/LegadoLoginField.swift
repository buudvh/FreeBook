import Foundation

/// Một mục của form đăng nhập dựng từ `loginUi` (spec §10.3).
struct LegadoLoginField: Sendable, Identifiable, Equatable {
    enum Kind: String, Sendable {
        /// Ô nhập một dòng (`text`, và `input` — U36); `hint` là chữ mờ.
        case text
        /// Ô nhập che ký tự.
        case password
        /// Danh sách chọn từ `chars`; đổi giá trị ⇒ chạy `action` (nếu có).
        case select
        /// Nút hiện phần tử hiện tại của `chars`; bấm ⇒ phần tử kế (vòng) rồi chạy `action` (nếu có).
        case toggle
        /// Nút chạy `action` (URL ⇒ mở trình duyệt; JS ⇒ `LegadoLoginService.runAction`).
        case button
        /// Nhãn tĩnh.
        case title
    }

    /// Vị trí trong `loginUi` (ổn định trong một lần dựng form).
    let id: Int
    /// Khoá dữ liệu (thông tin đăng nhập lưu theo `name`).
    let name: String
    /// Nhãn hiển thị: `viewName` đã đánh giá, lỗi/không có ⇒ `name`.
    let label: String
    let kind: Kind
    /// Mã JS (hoặc URL `http(s)`) chạy khi bấm/đổi giá trị; `nil` khi không có.
    let action: String?
    /// Lựa chọn của `select`/`toggle`.
    let chars: [String]
    let defaultValue: String?
    /// `hint`/`placeholder`.
    let hint: String?
    let style: LegadoFlexStyle
    /// Giá trị khởi đầu: thông tin đã lưu cùng `name` → `default` → phần tử đầu của `chars` (select/toggle) → `""`.
    var value: String

    /// Mục có giá trị đưa vào thông tin đăng nhập (không phải nút/nhãn).
    var carriesValue: Bool {
        kind != .button && kind != .title
    }

    /// `action` là URL `http(s)` ⇒ UI mở trình duyệt tại đó thay vì chạy JS.
    var actionURL: String? {
        guard let action else { return nil }
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        return LegadoURLResolver.hasHTTPScheme(trimmed) ? trimmed : nil
    }

    /// `toggle`: giá trị kế tiếp (vòng) trong `chars`.
    var nextToggleValue: String {
        guard !chars.isEmpty else { return value }
        guard let index = chars.firstIndex(of: value) else { return chars[0] }
        return chars[(index + 1) % chars.count]
    }
}
