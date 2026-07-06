import SwiftUI
import UIKit

struct ReaderTextView: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let lineSpacing: Double
    let theme: ReaderTheme
    let highlightRange: NSRange?
    @Binding var triggerGetVisibleIndex: UUID?
    let onGetVisibleIndex: (Int) -> Void
    let onSelectionChange: (String, String, Int, Int) -> Void
    let onSpeakFromHere: (Int) -> Void

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {

        guard let width = proposal.width else {
            return nil
        }

        let size = uiView.sizeThatFits(
            CGSize(width: width,
                height: .greatestFiniteMagnitude)
        )

        return CGSize(width: width, height: ceil(size.height))
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = AutoSizingTextView()
        context.coordinator.parentTextView = textView
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Đăng ký custom menu item cho iOS 15 trở xuống
        let menuItem = UIMenuItem(title: "Dịch", action: #selector(ReaderUITextView.customDefineAction))
        let ttsItem = UIMenuItem(title: "Đọc từ đây", action: #selector(ReaderUITextView.customSpeakAction))
        UIMenuController.shared.menuItems = [menuItem, ttsItem]
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        
        let attributedText = NSMutableAttributedString(string: text)
        attributedText.addAttribute(.font, value: UIFont.systemFont(ofSize: CGFloat(fontSize)), range: fullRange)
        attributedText.addAttribute(.foregroundColor, value: UIColor(theme.textColor), range: fullRange)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(lineSpacing)
        attributedText.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        
        // Tô màu nền cho đoạn văn đang đọc (Highlight)
        if let highlight = highlightRange, highlight.location != NSNotFound && highlight.location + highlight.length <= nsText.length {
            let highlightBgColor = theme == .dark
                ? UIColor.yellow.withAlphaComponent(0.18)
                : UIColor.yellow.withAlphaComponent(0.28)
            attributedText.addAttribute(.backgroundColor, value: highlightBgColor, range: highlight)
            
            // Tự động cuộn màn hình (Auto-scroll) để đưa đoạn highlight vào khung hình
            DispatchQueue.main.async {
                if let scrollView = uiView.parentScrollView {
                    uiView.layoutManager.ensureLayout(for: uiView.textContainer)
                    let start = uiView.position(from: uiView.beginningOfDocument, offset: highlight.location) ?? uiView.beginningOfDocument
                    let end = uiView.position(from: start, offset: highlight.length) ?? start
                    if let textRange = uiView.textRange(from: start, to: end) {
                        let rect = uiView.firstRect(for: textRange)
                        let rectInScrollView = uiView.convert(rect, to: scrollView)
                        
                        let visibleHeight = scrollView.bounds.height
                        // Chỉ cuộn nếu nằm ngoài vùng nhìn thấy hiện tại
                        if rectInScrollView.minY < scrollView.contentOffset.y || rectInScrollView.maxY > scrollView.contentOffset.y + visibleHeight {
                            let targetY = max(0, rectInScrollView.minY - 100) // Lùi lên 100px
                            scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
                        }
                    }
                }
            }
        }
        
        uiView.attributedText = attributedText
        
        // Xử lý trigger lấy index ký tự hiển thị đầu tiên
        if context.coordinator.lastTriggeredId != triggerGetVisibleIndex {
            context.coordinator.lastTriggeredId = triggerGetVisibleIndex
            if triggerGetVisibleIndex != nil {
                DispatchQueue.main.async {
                    if let scrollView = uiView.parentScrollView {
                        let point = CGPoint(x: 0, y: scrollView.contentOffset.y)
                        let pointInTextView = scrollView.convert(point, to: uiView)
                        let charIndex = uiView.layoutManager.characterIndex(for: pointInTextView, in: uiView.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
                        onGetVisibleIndex(charIndex)
                    } else {
                        onGetVisibleIndex(0)
                    }
                }
            }
        }
        
        uiView.invalidateIntrinsicContentSize()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ReaderTextView
        weak var parentTextView: UITextView?
        var lastTriggeredId: UUID?
        
        init(_ parent: ReaderTextView) {
            self.parent = parent
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            // Không làm gì để tránh sheet dịch tự mở lập tức khi bôi đen
        }
        
        // Cấu hình Edit Menu cho iOS 16+
        @available(iOS 16.0, *)
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            let customAction = UIAction(
                title: "Dịch",
                image: UIImage(systemName: "character.book.closed")
            ) { [weak self] _ in
                if let selectedText = textView.text(in: textView.selectedTextRange!) {
                    self?.triggerCustomDefine(text: selectedText)
                }
            }
            
            let ttsAction = UIAction(
                title: "Đọc từ đây",
                image: UIImage(systemName: "play.circle")
            ) { [weak self] _ in
                self?.parent.onSpeakFromHere(range.location)
            }
            
            var actions = suggestedActions
            actions.insert(customAction, at: 0)
            actions.insert(ttsAction, at: 1)
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
            
            parent.onSelectionChange(text, surroundingSentence, offsetInSentence, nsRange.location)
        }
    }
}

// MARK: - Subclass UITextView to support custom action selector

class ReaderUITextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(customDefineAction) || action == #selector(customSpeakAction) {
            return true
        }
        // Chặn tính năng Tra cứu của Apple trên iOS 15 trở xuống
        let actionString = action.description
        if actionString == "_define:" || actionString == "_lookup:" {
            return false
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
    
    @objc func customSpeakAction() {
        if let range = self.selectedTextRange,
           let delegate = self.delegate as? ReaderTextView.Coordinator {
            let nsRange = self.selectedRange
            delegate.parent.onSpeakFromHere(nsRange.location)
        }
    }
}

class AutoSizingTextView: ReaderUITextView {

    override var contentSize: CGSize {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: contentSize.height
        )
    }
}

// MARK: - Helpers

extension UIView {
    var parentScrollView: UIScrollView? {
        var current = self.superview
        while current != nil {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            current = current?.superview
        }
        return nil
    }
}