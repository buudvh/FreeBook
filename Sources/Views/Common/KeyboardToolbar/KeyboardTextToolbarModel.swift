import Combine
import UIKit

/// Trạng thái + hành động của thanh công cụ trên bàn phím, trỏ vào **ô đang gõ** (`UITextField` / `UITextView`).
///
/// Mọi thao tác sửa chữ đi qua `UITextInput` **như gõ phím** (`insertText` / `deleteBackward` trên vùng chọn): binding
/// của SwiftUI `TextField`/`TextEditor`, target `.editingChanged` của ô UIKit tự viết (vd `URLBarTextField`) và hoàn
/// tác hệ thống (lắc máy) đều nhận như khi người dùng tự gõ — gán thẳng `text` thì không.
///
/// Luật nút (đã chốt với người dùng): `aa…AA` định dạng **cả ô**, Sao chép lấy **cả ô**, Xoá xoá **cả ô**, Dán
/// **chèn tại con trỏ** (đang bôi đen thì thay đoạn đó).
///
/// Hàng gợi ý (1.3.556) chỉ có khi ô đang gõ cài `KeyboardSuggestionSource`; chip cũng chèn qua `insertText` như Dán.
@MainActor
final class KeyboardTextToolbarModel: ObservableObject {
    @Published private(set) var isEmpty = true
    /// Ẩn nhóm `aa…AA` ở ô tìm kiếm / URL (xem `showsCaseGroup(for:)`).
    @Published private(set) var showsCaseGroup = true
    @Published private(set) var tapOutsideDismisses = KeyboardDismissPreference.tapOutsideDismisses
    /// Chốt lúc ô **bắt đầu gõ**, không đổi giữa chừng. Chỉ `KeyboardTextToolbarInstaller` đọc (đồng bộ) để chọn thanh
    /// 46pt hay 82pt; view không đọc cờ này nên không cần `@Published`.
    private(set) var showsSuggestionRow = false
    @Published private(set) var suggestions: [KeyboardSuggestion] = []

    private weak var input: (UIView & UITextInput)?
    private weak var suggestionSource: KeyboardSuggestionSource?
    private var refreshTimer: Timer?

    // MARK: - Gắn / gỡ

    func attach(to input: UIView & UITextInput) {
        self.input = input
        showsCaseGroup = Self.showsCaseGroup(for: input)
        tapOutsideDismisses = KeyboardDismissPreference.tapOutsideDismisses
        attachSuggestionSource(input as? KeyboardSuggestionSource)
        refresh()
        startRefreshTimer()
    }

    func detach(from input: UIView & UITextInput) {
        guard self.input === input else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        // Không xoá `suggestions` ở đây: accessory còn hiện trong lúc bàn phím trượt xuống, ô kế tiếp tự đặt lại.
        suggestionSource?.keyboardSuggestionsDidChange = nil
        suggestionSource = nil
    }

    /// Một accessory dùng chung cho mọi ô ⇒ ô **không** có gợi ý cũng phải đặt lại hàng về ẩn, nếu không nó giữ chip của
    /// ô rule vừa gõ trước đó.
    private func attachSuggestionSource(_ source: KeyboardSuggestionSource?) {
        if suggestionSource !== source {
            suggestionSource?.keyboardSuggestionsDidChange = nil
        }
        suggestionSource = source
        // Ô có thể báo ngay trong `updateUIView` (bảng token / nút ✕ trong form đổi chữ khi bàn phím đang mở) — publish
        // lúc SwiftUI đang cập nhật view là hành vi không xác định ⇒ dời sang lượt runloop sau. Guard của
        // `refreshSuggestions` làm lượt muộn vô hại nếu ô đã thôi gõ.
        source?.keyboardSuggestionsDidChange = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.refreshSuggestions()
            }
        }
        let initial = source?.currentKeyboardSuggestions()
        showsSuggestionRow = initial != nil
        suggestions = initial ?? []
    }

    /// Ô báo lên qua `keyboardSuggestionsDidChange` mỗi lần chữ/con trỏ đổi, nên không cần timer 0,5 s của `refresh()`
    /// (với ô Bản dịch rule, mỗi lượt là một lần phân tích lại mẫu).
    private func refreshSuggestions() {
        guard showsSuggestionRow, let suggestionSource else { return }
        let next = suggestionSource.currentKeyboardSuggestions() ?? []
        if next != suggestions {
            suggestions = next
        }
    }

    /// Đọc lại `isEmpty`. Đổi chữ bằng code (nút ↺, chip token của rule, binding SwiftUI) **không** bắn
    /// `textDidChange`, nên ngoài notification còn một timer 0,5 s chạy đúng lúc có ô đang gõ.
    func refresh() {
        let empty = currentText.isEmpty
        if empty != isEmpty {
            isEmpty = empty
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    // MARK: - Hành động

    func applyCase(_ style: String) {
        guard let input else { return }
        commitMarkedText(input)
        let text = currentText
        guard !text.isEmpty else { return }
        let formatted = TextCaseFormatter.format(text, style: style)
        guard formatted != text else { return }
        selectAll(input)
        input.insertText(formatted)
        refresh()
    }

    func clear() {
        guard let input else { return }
        commitMarkedText(input)
        guard !currentText.isEmpty else { return }
        selectAll(input)
        input.deleteBackward()
        refresh()
    }

    func copy() {
        guard let input else { return }
        commitMarkedText(input)
        let text = currentText
        guard !text.isEmpty else { return }
        // Nút sao chép không đổi gì trên ô ⇒ toast báo đã chép (không lưu vào Trung tâm thông báo).
        ClipboardCopier.copy(text)
    }

    func paste() {
        guard let input else { return }
        commitMarkedText(input)
        guard var clip = UIPasteboard.general.string, !clip.isEmpty else { return }
        // Ô một dòng: xuống dòng thành dấu cách (dán "\n" vào `UITextField` dễ bị coi là phím Return).
        if input is UITextField {
            clip = clip.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
            guard !clip.isEmpty else { return }
        }
        input.insertText(clip)
        refresh()
    }

    /// Chèn chip gợi ý tại con trỏ / thay vùng đang bôi đen. Có `replacingPrefix` (phần gõ dở như `<h`) thì chọn lùi đúng
    /// đoạn đó rồi mới chèn — chỉ khi chữ trên ô còn khớp, lệch thì chèn tại con trỏ như chip thường.
    func applySuggestion(_ suggestion: KeyboardSuggestion) {
        guard let input else { return }
        commitMarkedText(input)
        let prefix = suggestion.replacingPrefix
        if !prefix.isEmpty,
           let selected = input.selectedTextRange, selected.isEmpty,
           let start = input.position(from: selected.start, offset: -prefix.utf16.count),
           let range = input.textRange(from: start, to: selected.start),
           input.text(in: range) == prefix {
            input.selectedTextRange = range
        }
        input.insertText(suggestion.text)
        refresh()
    }

    func dismissKeyboard() {
        if let input {
            commitMarkedText(input)
            input.resignFirstResponder()
        } else {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    func setTapOutsideDismisses(_ value: Bool) {
        KeyboardDismissPreference.setTapOutsideDismisses(value)
        tapOutsideDismisses = value
    }

    // MARK: - Tiện ích

    private var currentText: String {
        if let field = input as? UITextField { return field.text ?? "" }
        if let textView = input as? UITextView { return textView.text ?? "" }
        return ""
    }

    /// Telex/VNI/pinyin giữ chữ đang gõ dở ở dạng **marked text** (gạch chân). Chốt nó trước mọi thao tác, nếu không
    /// chọn hết + chèn sẽ đè lên vùng đang soạn và làm lặp/vỡ ký tự.
    private func commitMarkedText(_ input: UIView & UITextInput) {
        if input.markedTextRange != nil {
            input.unmarkText()
        }
    }

    private func selectAll(_ input: UIView & UITextInput) {
        if let range = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument) {
            input.selectedTextRange = range
        }
    }

    /// Ô tìm kiếm / URL không cần đổi hoa thường: `.searchable` (`UISearchTextField`), ô bàn phím URL / tìm web
    /// (thanh URL trình duyệt, ô `source` của plugin.json) và ô có phím Return "Tìm" (`.submitLabel(.search)` — mọi ô
    /// tìm kiếm tự dựng bằng `TextField` phải gắn modifier này).
    private static func showsCaseGroup(for input: UIView & UITextInput) -> Bool {
        if input is UISearchTextField { return false }
        let keyboardType: UIKeyboardType
        let returnKeyType: UIReturnKeyType
        if let field = input as? UITextField {
            keyboardType = field.keyboardType
            returnKeyType = field.returnKeyType
        } else if let textView = input as? UITextView {
            keyboardType = textView.keyboardType
            returnKeyType = textView.returnKeyType
        } else {
            return true
        }
        if keyboardType == .URL || keyboardType == .webSearch { return false }
        return returnKeyType != .search
    }
}
