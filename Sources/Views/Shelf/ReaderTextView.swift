import SwiftUI
import UIKit

struct ReaderTextView: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let theme: ReaderTheme
    let onSelectionChange: (String, String, Int) -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = ReaderUITextView()
        context.coordinator.parentTextView = textView
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        
        // Sửa lỗi hiển thị chữ tràn/vỡ dòng
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Đăng ký custom menu item cho iOS 15 trở xuống
        let menuItem = UIMenuItem(title: "Dịch", action: #selector(ReaderUITextView.customDefineAction))
        UIMenuController.shared.menuItems = [menuItem]
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
        AppLogger.shared.log("text: \(text)")
        uiView.font = UIFont.systemFont(ofSize: CGFloat(fontSize))
        uiView.textColor = UIColor(theme.textColor)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ReaderTextView
        weak var parentTextView: UITextView?
        
        init(_ parent: ReaderTextView) {
            self.parent = parent
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            // Không làm gì ở đây để tránh tự động nhảy sheet dịch lập tức khi mới bôi đen
        }
        
        // Cấu hình Edit Menu cho iOS 16+
        @available(iOS 16.0, *)
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            let customAction = UIAction(title: "Dịch") { [weak self] _ in
                if let selectedText = textView.text(in: textView.selectedTextRange!) {
                    self?.triggerCustomDefine(text: selectedText)
                }
            }
            var actions = suggestedActions
            actions.insert(customAction, at: 0)
            return UIMenu(children: actions)
        }
        
        func triggerCustomDefine(text: String) {
            guard let textView = parentTextView else { return }
            let fullText = textView.text ?? ""
            let nsRange = textView.selectedRange
            let fullNSString = fullText as NSString
            
            // Quét ngược tìm đầu câu
            var startLoc = nsRange.location
            while startLoc > 0 {
                let char = fullNSString.substring(with: NSRange(location: startLoc - 1, length: 1))
                if char == "。" || char == "！" || char == "？" || char == "\n" || char == "\r" || char == "." || char == "!" || char == "?" {
                    break
                }
                startLoc -= 1
            }
            
            // Quét xuôi tìm cuối câu
            var endLoc = nsRange.location + nsRange.length
            let totalLen = fullNSString.length
            while endLoc < totalLen {
                let char = fullNSString.substring(with: NSRange(location: endLoc, length: 1))
                if char == "。" || char == "！" || char == "？" || char == "\n" || char == "\r" || char == "." || char == "!" || char == "?" {
                    break
                }
                endLoc += 1
            }
            
            let sentenceRange = NSRange(location: startLoc, length: endLoc - startLoc)
            let surroundingSentence = fullNSString.substring(with: sentenceRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let offsetInSentence = max(0, nsRange.location - startLoc)
            
            parent.onSelectionChange(text, surroundingSentence, offsetInSentence)
        }
    }
}

// MARK: - Subclass UITextView to support custom action selector

class ReaderUITextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(customDefineAction) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
    
    @objc func customDefineAction() {
        if let range = self.selectedTextRange,
           let text = self.text(in: range),
           let delegate = self.delegate as? ReaderTextView.Coordinator {
            delegate.triggerCustomDefine(text: text)
        }
    }
}
