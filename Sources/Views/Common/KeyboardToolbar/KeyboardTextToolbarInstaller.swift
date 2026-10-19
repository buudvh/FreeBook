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
/// Một thanh (một `UIInputView`) dùng chung cho mọi ô: chỉ một ô làm first responder tại một thời điểm, model được trỏ
/// lại vào ô mới mỗi lần bắt đầu gõ.
@MainActor
final class KeyboardTextToolbarInstaller: NSObject {
    static let shared = KeyboardTextToolbarInstaller()

    private let model = KeyboardTextToolbarModel()
    private var hostingController: UIHostingController<KeyboardTextToolbarView>?
    private var accessoryView: UIInputView?
    private var isObserving = false
    private var loggedClasses = Set<String>()

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

    @objc private func textFieldDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? UITextField, !field.isSecureTextEntry else { return }
        attachAccessory(to: field, current: field.inputAccessoryView) { field.inputAccessoryView = $0 }
        model.attach(to: field)
    }

    @objc private func textViewDidBeginEditing(_ notification: Notification) {
        guard let textView = notification.object as? UITextView,
              textView.isEditable,
              !textView.isSecureTextEntry,
              !(textView is CodeEditorTextView) else { return }
        attachAccessory(to: textView, current: textView.inputAccessoryView) { textView.inputAccessoryView = $0 }
        model.attach(to: textView)
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
    private func attachAccessory(to input: UIView, current: UIView?, assign: (UIView) -> Void) {
        let accessory = sharedAccessoryView()
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
    }

    /// Log chẩn đoán **một lần mỗi lớp ô** (app chạy qua LiveContainer, log là kênh duy nhất để biết đường nào đã dùng).
    private func logOnce(cls: AnyClass, previous: UIView?, method: String) {
        let name = NSStringFromClass(cls)
        guard !loggedClasses.contains(name) else { return }
        loggedClasses.insert(name)
        let previousName = previous.map { NSStringFromClass(type(of: $0)) } ?? "nil"
        AppLogger.shared.log("⌨️ [KeyboardToolbar] lớp ô \(name), accessory sẵn có \(previousName): \(method)")
    }

    private func sharedAccessoryView() -> UIInputView {
        if let accessoryView { return accessoryView }

        let host = UIHostingController(rootView: KeyboardTextToolbarView(model: model))
        host.view.backgroundColor = .clear

        let width = UIScreen.main.bounds.width
        let container = UIInputView(frame: CGRect(x: 0, y: 0, width: width, height: 46), inputViewStyle: .keyboard)
        container.allowsSelfSizing = true
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.view.heightAnchor.constraint(equalToConstant: 46)
        ])

        hostingController = host
        accessoryView = container
        return container
    }
}
