import SwiftUI
import UIKit

/// Ô nhập địa chỉ của trình duyệt bypass: chạm vào là **bôi đen toàn bộ** URL
/// đang có để gõ đè ngay, không phải xoá tay từng ký tự.
///
/// Phải bọc `UITextField` vì SwiftUI `TextField` (iOS 17) không có API chọn hết
/// văn bản khi nhận focus.
struct URLBarTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    /// Bật khi ô đang được gõ — dùng để chặn observer URL của WebView ghi đè
    /// những gì người dùng đang nhập.
    @Binding var isEditing: Bool
    let onSubmit: () -> Void
    /// Tự lấy focus ngay khi ô được dựng (thanh dưới của trình duyệt: chạm tên miền ⇒ đổi sang ô này và bật bàn phím
    /// luôn, không bắt chạm lần hai). Hoãn một vòng runloop để ô đã vào cửa sổ; `textFieldDidBeginEditing` vẫn bôi đen
    /// toàn bộ như khi người dùng tự chạm.
    var becomesFirstResponderOnAppear: Bool = false

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.text = text
        field.font = .systemFont(ofSize: 15)
        field.textColor = .label
        // Màu nhấn của app là trắng ⇒ vùng bôi đen cả URL lúc chạm sẽ trắng đè chữ trắng. Gán xanh hệ thống tường minh.
        field.tintColor = .systemBlue
        // Bàn phím thường (không phải bàn phím URL): ô vừa nhập địa chỉ vừa gõ từ khoá tìm Google.
        field.keyboardType = .default
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.returnKeyType = .go
        field.clearsOnBeginEditing = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleEditingChanged(_:)),
            for: .editingChanged
        )
        if becomesFirstResponderOnAppear {
            DispatchQueue.main.async { [weak field] in
                _ = field?.becomeFirstResponder()
            }
        }
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isEditing = $isEditing
        context.coordinator.onSubmit = onSubmit
        uiView.placeholder = placeholder
        // Chỉ ghi lại khi khác thật, nếu không sẽ phá caret và vùng đang bôi đen.
        if uiView.text != text {
            uiView.text = text
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        let intrinsic = uiView.intrinsicContentSize
        return CGSize(width: proposal.width ?? intrinsic.width, height: intrinsic.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isEditing: $isEditing, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var isEditing: Binding<Bool>
        var onSubmit: () -> Void

        init(text: Binding<String>, isEditing: Binding<Bool>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.isEditing = isEditing
            self.onSubmit = onSubmit
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isEditing.wrappedValue = true
            // Đặt selection ngay trong callback bị UIKit ghi đè bằng caret cuối
            // chuỗi, nên phải hoãn một vòng run loop.
            DispatchQueue.main.async {
                // Dùng `selectedTextRange` thay cho `selectAll(nil)` để không bật
                // kèm menu Cut/Copy/Paste của hệ thống.
                textField.selectedTextRange = textField.textRange(
                    from: textField.beginningOfDocument,
                    to: textField.endOfDocument
                )
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isEditing.wrappedValue = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            onSubmit()
            return true
        }

        @objc func handleEditingChanged(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
        }
    }
}
