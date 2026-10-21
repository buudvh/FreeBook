import SwiftUI
import UIKit

/// Gắn `KeyboardTextToolbarView` lên **mọi** ô nhập của app — cài một lần ở tầng UIKit, không sửa từng màn.
///
/// SwiftUI chỉ có `.toolbar { ToolbarItemGroup(placement: .keyboard) }` theo từng màn (và từng sheet), mà app có hơn
/// 80 ô nhập ở ~50 file. Vì vậy nghe `textDidBeginEditingNotification` của `UITextField` và `UITextView` — mọi
/// `TextField`, `TextEditor`, `.searchable`, ô trong hộp thoại và ô UIKit tự viết đều đi qua đây — rồi gán
/// `inputAccessoryView` cho đúng ô vừa bắt đầu gõ và `reloadInputViews()`. Thanh nằm **trên** thanh gợi ý chữ của
/// bàn phím (thanh gợi ý thuộc về bàn phím nên không mất).
///
/// Không gắn cho: ô mật khẩu / API key (`isSecureTextEntry` — Sao chép sẽ đưa khoá ra bộ nhớ tạm), trình sửa mã Script
/// (`CodeEditorTextView` — lỡ Xoá hay `AA` là hỏng cả file). Ô nhập trong trang web (`WKWebView`) không dùng hai lớp này
/// nên không có thanh; WebKit có thanh ‹ › Xong của nó.
///
/// Ô của SwiftUI (`TextField`/`TextEditor`) tự quản accessory nội bộ: gán thẳng không ăn (lỗi 1.3.548 — thanh không
/// hiện ở đâu cả) ⇒ đi đường `KeyboardAccessoryOverride` (thay getter theo lớp). Bản 1.3.548 còn bỏ qua mọi ô "đã có
/// accessory của người khác" — chính accessory nội bộ đó — nên đã bỏ điều kiện này (app không có màn nào tự gắn accessory).
///
/// Hai thanh (hai `UIInputView`) dùng chung cho mọi ô, chung một model: chỉ một ô làm first responder tại một thời điểm,
/// model được trỏ lại vào ô mới mỗi lần bắt đầu gõ. Thanh 46pt cho ô thường, thanh 82pt (thêm hàng gợi ý) cho ô cài
/// `KeyboardSuggestionSource`. **Mỗi thanh cố định chiều cao từ lúc tạo** (1.3.559): bản 1.3.556 dùng một thanh rồi đổi
/// chiều cao 46 ↔ 82pt theo ô, và iOS giữ chiều cao đo lần đầu ⇒ ở màn thêm rule hàng xoá · sao chép · dán bị đẩy xuống
/// sau thanh gợi ý chữ của bàn phím.
@MainActor
final class KeyboardTextToolbarInstaller: NSObject {
    static let shared = KeyboardTextToolbarInstaller()

    private let model = KeyboardTextToolbarModel()
    /// Khoá = có hàng gợi ý hay không. Giữ cả hosting controller để view SwiftUI không bị giải phóng.
    private var hostingControllers: [Bool: UIHostingController<KeyboardTextToolbarView>] = [:]
    private var accessoryViews: [Bool: UIInputView] = [:]
    private var isObserving = false
    private var loggedClasses = Set<String>()
    private var loggedHeightMismatches = Set<CGFloat>()

    private override init() {
        super.init()
    }

    /// Gọi một lần khi root view xuất hiện (cạnh `KeyboardDismissGesture.activate()`); các lần sau là no-op.
    func activate() {
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(textFieldDidBeginEditing(_:)),
                           name: UITextField.textDidBeginEditingNotification, object: nil)
        center.addObserver(self, selector: #selector(textViewDidBeginEditing(_:)),
                           name: UITextView.textDidBeginEditingNotification, object: nil)
        center.addObserver(self, selector: #selector(textFieldDidEndEditing(_:)),
                           name: UITextField.textDidEndEditingNotification, object: nil)
        center.addObserver(self, selector: #selector(textViewDidEndEditing(_:)),
                           name: UITextView.textDidEndEditingNotification, object: nil)
        center.addObserver(self, selector: #selector(textDidChange(_:)),
                           name: UITextField.textDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(textDidChange(_:)),
                           name: UITextView.textDidChangeNotification, object: nil)
    }

    // MARK: - Notification

    // `model.attach` đi **trước** `attachAccessory`: chọn thanh 46pt hay 82pt theo `model.showsSuggestionRow` của ô này.
    @objc private func textFieldDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? UITextField, !field.isSecureTextEntry else { return }
        model.attach(to: field)
        attachAccessory(to: field, current: field.inputAccessoryView) { field.inputAccessoryView = $0 }
    }

    @objc private func textViewDidBeginEditing(_ notification: Notification) {
        guard let textView = notification.object as? UITextView,
              textView.isEditable,
              !textView.isSecureTextEntry,
              !(textView is CodeEditorTextView) else { return }
        model.attach(to: textView)
        attachAccessory(to: textView, current: textView.inputAccessoryView) { textView.inputAccessoryView = $0 }
    }

    @objc private func textFieldDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? UITextField else { return }
        model.detach(from: field)
    }

    @objc private func textViewDidEndEditing(_ notification: Notification) {
        guard let textView = notification.object as? UITextView else { return }
        model.detach(from: textView)
    }

    @objc private func textDidChange(_ notification: Notification) {
        model.refresh()
    }

    // MARK: - Thanh

    /// Gắn thanh vào ô vừa bắt đầu gõ. Lớp UIKit thường: gán `inputAccessoryView` rồi đọc lại — đọc lại không ra thanh
    /// (getter bị override) thì chuyển sang thay getter. Lớp nội bộ SwiftUI: luôn thay getter, vì SwiftUI có thể gán đè
    /// accessory của nó ở lượt cập nhật sau dù lần gán đầu có ăn.
    ///
    /// Ô chuyển từ thanh này sang thanh kia (vd ô Bản dịch rule lúc mẫu chưa / đã có token) đi đúng các nhánh dưới: gán
    /// lại hoặc `install` lại associated object, nên getter trả thanh mới.
    private func attachAccessory(to input: UIView, current: UIView?, assign: (UIView) -> Void) {
        let includesSuggestionRow = model.showsSuggestionRow
        let accessory = accessoryView(includesSuggestionRow: includesSuggestionRow)
        guard let cls = object_getClass(input) else { return }
        var method = "đã gắn sẵn"
        if KeyboardAccessoryOverride.isPatched(input) {
            KeyboardAccessoryOverride.install(accessory, on: input)
            method = "thay getter (lớp đã vá)"
        } else if KeyboardAccessoryOverride.isSwiftUIClass(cls) {
            method = KeyboardAccessoryOverride.install(accessory, on: input) ? "thay getter" : "❌ không thay được getter"
        } else if current !== accessory {
            assign(accessory)
            if input.inputAccessoryView === accessory {
                method = "gán thẳng"
            } else {
                method = KeyboardAccessoryOverride.install(accessory, on: input)
                    ? "thay getter (gán không ăn)" : "❌ gán không ăn, không thay được getter"
            }
        }
        if input.inputAccessoryView !== accessory {
            method += " — ❌ getter vẫn không trả thanh"
        }
        input.reloadInputViews()
        logOnce(cls: cls, previous: current, method: method)
        checkHeightLater(of: accessory, includesSuggestionRow: includesSuggestionRow, cls: cls)
    }

    /// Chẩn đoán cho lỗi 1.3.556 (chưa kiểm chứng được trên máy — nguyên nhân mới là suy luận): đợi bàn phím trượt lên
    /// xong rồi so chiều cao thật của thanh với chiều cao đã đặt. Chỉ log khi **lệch**, có `❌` nên ghi cả lúc tắt log,
    /// mỗi chiều cao một lần.
    private func checkHeightLater(of accessory: UIInputView, includesSuggestionRow: Bool, cls: AnyClass) {
        let expected = KeyboardTextToolbarView.height(includesSuggestionRow: includesSuggestionRow)
        let name = NSStringFromClass(cls)
        Task { @MainActor [weak self, weak accessory] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, let accessory, accessory.window != nil else { return }
            let actual = accessory.bounds.height
            guard abs(actual - expected) > 0.5, !self.loggedHeightMismatches.contains(expected) else { return }
            self.loggedHeightMismatches.insert(expected)
            AppLogger.shared.log("❌ [KeyboardToolbar] thanh cao \(actual)pt, cần \(expected)pt (ô \(name))")
        }
    }

    /// Log chẩn đoán **một lần mỗi lớp ô** (app chạy qua LiveContainer, log là kênh duy nhất để biết đường nào đã dùng).
    private func logOnce(cls: AnyClass, previous: UIView?, method: String) {
        let name = NSStringFromClass(cls)
        guard !loggedClasses.contains(name) else { return }
        loggedClasses.insert(name)
        let previousName = previous.map { NSStringFromClass(type(of: $0)) } ?? "nil"
        AppLogger.shared.log("⌨️ [KeyboardToolbar] lớp ô \(name), accessory sẵn có \(previousName): \(method)")
    }

    /// Tạo lười, mỗi loại một lần, chiều cao đặt **một lần** lúc tạo và không bao giờ đổi.
    private func accessoryView(includesSuggestionRow: Bool) -> UIInputView {
        if let existing = accessoryViews[includesSuggestionRow] { return existing }

        let host = UIHostingController(
            rootView: KeyboardTextToolbarView(model: model, includesSuggestionRow: includesSuggestionRow)
        )
        host.view.backgroundColor = .clear
        // Accessory nằm sát mép dưới màn hình lúc bàn phím trượt lên: để hosting tính vùng an toàn thì SwiftUI đệm
        // thêm khoảng trống và đẩy thanh lệch khỏi bàn phím.
        host.safeAreaRegions = []

        let width = UIScreen.main.bounds.width
        let height = KeyboardTextToolbarView.height(includesSuggestionRow: includesSuggestionRow)
        let container = UIInputView(frame: CGRect(x: 0, y: 0, width: width, height: height), inputViewStyle: .keyboard)
        container.allowsSelfSizing = true
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.view.heightAnchor.constraint(equalToConstant: height)
        ])

        hostingControllers[includesSuggestionRow] = host
        accessoryViews[includesSuggestionRow] = container
        return container
    }
}
