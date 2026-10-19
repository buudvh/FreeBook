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
/// (`CodeEditorTextView` — lỡ Xoá hay `AA` là hỏng cả file), ô đã có accessory riêng. Ô nhập trong trang web
/// (`WKWebView`) không dùng hai lớp này nên không có thanh; WebKit có thanh ‹ › Xong của nó.
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
        guard canAttach(currentAccessory: field.inputAccessoryView) else { return }
        let accessory = sharedAccessoryView()
        if field.inputAccessoryView !== accessory {
            field.inputAccessoryView = accessory
            field.reloadInputViews()
        }
        model.attach(to: field)
    }

    @objc private func textViewDidBeginEditing(_ notification: Notification) {
        guard let textView = notification.object as? UITextView,
              textView.isEditable,
              !textView.isSecureTextEntry,
              !(textView is CodeEditorTextView) else { return }
        guard canAttach(currentAccessory: textView.inputAccessoryView) else { return }
        let accessory = sharedAccessoryView()
        if textView.inputAccessoryView !== accessory {
            textView.inputAccessoryView = accessory
            textView.reloadInputViews()
        }
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

    /// Ô đã có accessory **của người khác** thì để nguyên — không giành thanh của màn tự làm riêng.
    private func canAttach(currentAccessory: UIView?) -> Bool {
        currentAccessory == nil || currentAccessory === accessoryView
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
