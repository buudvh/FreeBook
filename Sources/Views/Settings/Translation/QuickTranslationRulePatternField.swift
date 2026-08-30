import SwiftUI
import UIKit

/// Ô nhập **mẫu** rule, bọc `UITextView` chỉ vì một lý do: lấy được **vị trí con trỏ thật**.
///
/// Vì sao không dùng `TextField`: iOS 17 không cho SwiftUI đọc hay ghi vùng chọn của `TextField`
/// (`TextSelection` chỉ có từ iOS 18). Không có con trỏ thật thì bảng nút token chỉ chèn được vào
/// **cuối** mẫu — đúng lỗi báo lại sau 1.3.288. Dải chip vẫn giữ vai trò chọn token để sửa `:min-max`,
/// nhưng con trỏ nay do chính ô nhập cấp và hai chiều đồng bộ với nhau.
///
/// Quy đổi đơn vị nằm **đúng ở biên này**: model của màn nhập đếm theo **ký tự** (`Array(pattern)`),
/// còn UIKit dùng `NSRange` UTF-16. Hai chiều đổi qua `String.Index`, không giả định 1 ký tự = 1 unit.
///
/// `isScrollEnabled = false` + `sizeThatFits` là cách để một `UITextView` tự cao theo nội dung trong
/// một hàng `Form`; bật scroll là mất chiều cao nội tại và hàng sẽ sập về 0.
struct QuickTranslationRulePatternField: UIViewRepresentable {
    @Binding var text: String
    /// Con trỏ (`length == 0`) hoặc vùng chọn, theo chỉ số ký tự.
    @Binding var selectionStart: Int
    @Binding var selectionLength: Int
    /// Bật khi bản nháp được khôi phục và ô này đang là ô gõ — giữ bàn phím qua lượt dựng lại sheet.
    let autoFocus: Bool
    let onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.font = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
            weight: .regular
        )
        view.adjustsFontForContentSizeCategory = true
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.smartInsertDeleteType = .no
        view.text = text
        context.coordinator.apply(selection: utf16Range(in: text), to: view)
        if autoFocus {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            context.coordinator.apply(text: text, to: view)
        }
        let wanted = utf16Range(in: text)
        // Điều kiện thứ hai chặn vòng lặp cập nhật khi quy đổi ký tự ⇄ UTF-16 không tròn (chuỗi có
        // ký tự ngoài BMP): range vừa do chính coordinator báo lên thì không áp lại.
        if view.selectedRange != wanted, wanted != context.coordinator.lastReportedRange {
            context.coordinator.apply(selection: wanted, to: view)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, 22))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Quy đổi ký tự ⇄ UTF-16

    private func utf16Range(in string: String) -> NSRange {
        let start = Self.utf16Offset(ofCharacterIndex: selectionStart, in: string)
        let end = Self.utf16Offset(ofCharacterIndex: selectionStart + max(0, selectionLength), in: string)
        return NSRange(location: start, length: max(0, end - start))
    }

    static func utf16Offset(ofCharacterIndex index: Int, in string: String) -> Int {
        let clamped = min(max(0, index), string.count)
        let position = string.index(string.startIndex, offsetBy: clamped)
        return position.utf16Offset(in: string)
    }

    static func characterIndex(ofUTF16Offset offset: Int, in string: String) -> Int {
        let clamped = min(max(0, offset), string.utf16.count)
        let position = String.Index(utf16Offset: clamped, in: string)
        return string.distance(from: string.startIndex, to: position)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: QuickTranslationRulePatternField
        /// Range cuối cùng đã báo lên SwiftUI — dùng để nhận ra "echo" của chính mình.
        private(set) var lastReportedRange: NSRange?
        private var isApplying = false

        init(parent: QuickTranslationRulePatternField) {
            self.parent = parent
        }

        func apply(text: String, to view: UITextView) {
            isApplying = true
            view.text = text
            isApplying = false
        }

        func apply(selection: NSRange, to view: UITextView) {
            isApplying = true
            view.selectedRange = selection
            isApplying = false
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplying else { return }
            parent.text = textView.text ?? ""
            report(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplying else { return }
            report(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }

        private func report(_ textView: UITextView) {
            let string = textView.text ?? ""
            let range = textView.selectedRange
            lastReportedRange = range
            let start = QuickTranslationRulePatternField.characterIndex(ofUTF16Offset: range.location, in: string)
            let end = QuickTranslationRulePatternField.characterIndex(
                ofUTF16Offset: range.location + range.length,
                in: string
            )
            parent.selectionStart = start
            parent.selectionLength = max(0, end - start)
        }
    }
}
