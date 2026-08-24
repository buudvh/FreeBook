import UIKit

/// Bấm ra ngoài ô nhập là tắt bàn phím — cài **một lần cho toàn app** ở tầng `UIWindow`.
///
/// SwiftUI không có công tắc nào làm việc này: `.scrollDismissesKeyboard` chỉ phản ứng khi *kéo*
/// danh sách, còn gắn `.onTapGesture` vào từng màn thì phải sửa hàng chục view và sẽ ăn mất touch
/// của nút bên dưới. Vì vậy đặt một `UITapGestureRecognizer` lên chính window:
///
/// - `cancelsTouchesInView = false` để nút/hàng danh sách bên dưới vẫn nhận touch như thường —
///   một tap vừa bấm được nút vừa tắt bàn phím.
/// - `shouldRecognizeSimultaneouslyWith` trả `true`, nếu không recognizer này sẽ chặn pan của
///   scroll view và tap chọn hàng của `List`.
/// - `shouldReceive touch` bỏ qua touch rơi vào chính ô nhập (kể cả subview như nút clear của
///   `UITextField`), nếu không bấm vào ô đang gõ lại tự tắt bàn phím.
///
/// Chỉ cài lên window ở level `.normal` (mirror cách lọc của `VisibleBrowserTabManager`): window của
/// TTS widget, widget trình duyệt và toast nằm ở level quanh `.alert` và hit-test passthrough, còn
/// bàn phím sống trong window hệ thống riêng nên tap vào bàn phím không bao giờ chạm recognizer này.
///
/// Cài trễ theo `keyboardWillShowNotification` thay vì lúc khởi động: lúc `App.init` chưa có window
/// nào, và cách này phủ luôn window sinh ra sau (scene mới, LiveContainer).
@MainActor
final class KeyboardDismissGesture: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissGesture()

    /// Đánh dấu recognizer của mình để không cài trùng lên cùng một window.
    private static let gestureName = "FreeBookKeyboardDismissTap"

    private var isObserving = false

    private override init() {
        super.init()
    }

    /// Gọi một lần khi root view xuất hiện; các lần sau là no-op.
    func activate() {
        guard !isObserving else { return }
        isObserving = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow() {
        installIfNeeded()
    }

    private func installIfNeeded() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows where window.windowLevel == .normal && !window.isHidden {
                let alreadyInstalled = window.gestureRecognizers?.contains {
                    $0.name == Self.gestureName
                } ?? false
                guard !alreadyInstalled else { continue }

                let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
                tap.name = Self.gestureName
                tap.cancelsTouchesInView = false
                tap.delaysTouchesBegan = false
                tap.delaysTouchesEnded = false
                tap.delegate = self
                window.addGestureRecognizer(tap)
            }
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        gesture.view?.endEditing(true)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard let touched = touch.view else { return true }
        return !isEditableTextInput(touched)
    }

    /// Leo ngược cây view: touch thật sự thường nằm ở subview của ô nhập, không phải ô nhập.
    ///
    /// Chỉ tính ô **đang nhập được** — `ReaderUITextView` là `UITextView` chỉ đọc nên tap vào chữ
    /// trong trình đọc vẫn tắt được bàn phím.
    private func isEditableTextInput(_ view: UIView) -> Bool {
        var node: UIView? = view
        while let current = node {
            if let field = current as? UITextField {
                return field.isEnabled
            }
            if let textView = current as? UITextView {
                return textView.isEditable
            }
            if current is UISearchBar {
                return true
            }
            node = current.superview
        }
        return false
    }
}
