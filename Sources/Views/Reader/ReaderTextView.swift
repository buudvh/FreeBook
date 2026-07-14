import SwiftUI
import UIKit

struct ReaderTextView: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let lineSpacing: Double
    let theme: ReaderTheme
    let highlightRange: NSRange?
    let isBold: Bool
    @Binding var triggerGetVisibleIndex: UUID?
    let onGetVisibleIndex: (Int) -> Void
    let onSelectionChange: (String, String, Int, Int) -> Void
    let onSpeakFromHere: (Int) -> Void
    
    init(
        text: String,
        fontSize: Double,
        lineSpacing: Double,
        theme: ReaderTheme,
        highlightRange: NSRange?,
        isBold: Bool = false,
        triggerGetVisibleIndex: Binding<UUID?>,
        onGetVisibleIndex: @escaping (Int) -> Void,
        onSelectionChange: @escaping (String, String, Int, Int) -> Void,
        onSpeakFromHere: @escaping (Int) -> Void
    ) {
        self.text = text
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.theme = theme
        self.highlightRange = highlightRange
        self.isBold = isBold
        self._triggerGetVisibleIndex = triggerGetVisibleIndex
        self.onGetVisibleIndex = onGetVisibleIndex
        self.onSelectionChange = onSelectionChange
        self.onSpeakFromHere = onSpeakFromHere
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {

        guard let width = proposal.width else {
            return nil
        }

        if let cachedW = context.coordinator.cachedWidth,
           let cachedH = context.coordinator.cachedHeight,
           abs(cachedW - width) < 0.1 {
            return CGSize(width: width, height: cachedH)
        }

        let size = uiView.sizeThatFits(
            CGSize(width: width,
                height: .greatestFiniteMagnitude)
        )

        let finalHeight = ceil(size.height)
        context.coordinator.cachedWidth = width
        context.coordinator.cachedHeight = finalHeight

        return CGSize(width: width, height: finalHeight)
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
        
        // Thêm cử chỉ chạm nhẹ (single tap) để toggle HUD
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = context.coordinator
        textView.addGestureRecognizer(tapGesture)
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        let font = isBold 
            ? UIFont.boldSystemFont(ofSize: CGFloat(fontSize))
            : UIFont.systemFont(ofSize: CGFloat(fontSize))
            
        let isHighlightedNow = highlightRange != nil
        let shouldScroll = isHighlightedNow && !context.coordinator.wasHighlighted
        context.coordinator.wasHighlighted = isHighlightedNow
        
        // Kiểm tra xem cấu hình có thực sự thay đổi không để tránh gán attributedText đắt đỏ
        let isConfigChanged = context.coordinator.lastText != text ||
                              context.coordinator.lastFontSize != fontSize ||
                              context.coordinator.lastLineSpacing != lineSpacing ||
                              context.coordinator.lastThemeName != theme.rawValue ||
                              context.coordinator.lastHighlightRange != highlightRange
                              
        if isConfigChanged {
            context.coordinator.cachedWidth = nil
            context.coordinator.cachedHeight = nil
            context.coordinator.lastText = text
            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastLineSpacing = lineSpacing
            context.coordinator.lastThemeName = theme.rawValue
            context.coordinator.lastHighlightRange = highlightRange
            
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let attributedText = NSMutableAttributedString(string: text)
            attributedText.addAttribute(.font, value: font, range: fullRange)
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
                
                // Tự động cuộn màn hình (Auto-scroll) để đưa đoạn highlight vào chính giữa màn hình
                if shouldScroll {
                    DispatchQueue.main.async {
                        if let scrollView = uiView.parentScrollView {
                            // Chỉ tự động cuộn nếu người dùng không tương tác vuốt chạm bằng tay
                            guard !scrollView.isDragging && !scrollView.isDecelerating && !scrollView.isTracking else {
                                return
                            }
                            
                            uiView.layoutManager.ensureLayout(for: uiView.textContainer)
                            let start = uiView.position(from: uiView.beginningOfDocument, offset: highlight.location) ?? uiView.beginningOfDocument
                            let end = uiView.position(from: start, offset: highlight.length) ?? start
                            if let textRange = uiView.textRange(from: start, to: end) {
                                let rect = uiView.firstRect(for: textRange)
                                guard !rect.isNull && !rect.isEmpty &&
                                      !rect.origin.x.isNaN && !rect.origin.y.isNaN &&
                                      !rect.origin.x.isInfinite && !rect.origin.y.isInfinite &&
                                      !rect.size.width.isNaN && !rect.size.height.isNaN else {
                                    return
                                }
                                
                                let rectInScrollView = uiView.convert(rect, to: scrollView)
                                guard !rectInScrollView.origin.x.isNaN && !rectInScrollView.origin.y.isNaN &&
                                      !rectInScrollView.origin.x.isInfinite && !rectInScrollView.origin.y.isInfinite &&
                                      !rectInScrollView.size.width.isNaN && !rectInScrollView.size.height.isNaN else {
                                    return
                                }
                                
                                let visibleHeight = scrollView.bounds.height
                                guard !visibleHeight.isNaN && !visibleHeight.isInfinite && visibleHeight > 0 else {
                                    return
                                }
                                
                                let targetY = rectInScrollView.midY - (visibleHeight / 2)
                                guard !targetY.isNaN && !targetY.isInfinite else {
                                    return
                                }
                                
                                let safeTargetY = max(0, targetY)
                                scrollView.setContentOffset(CGPoint(x: 0, y: safeTargetY), animated: true)
                            }
                        }
                    }
                }
            }
            
            uiView.attributedText = attributedText
        }
        
        // Xử lý trigger lấy index ký tự hiển thị đầu tiên
        if context.coordinator.lastTriggeredId != triggerGetVisibleIndex {
            context.coordinator.lastTriggeredId = triggerGetVisibleIndex
            if triggerGetVisibleIndex != nil {
                DispatchQueue.main.async {
                    self.triggerGetVisibleIndex = nil
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
    
    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: ReaderTextView
        weak var parentTextView: UITextView?
        var lastTriggeredId: UUID?
        var wasHighlighted: Bool = false
        var lastText: String? = nil
        var lastFontSize: Double? = nil
        var lastLineSpacing: Double? = nil
        var lastThemeName: String? = nil
        var lastHighlightRange: NSRange? = nil
        var cachedWidth: CGFloat? = nil
        var cachedHeight: CGFloat? = nil
        
        init(_ parent: ReaderTextView) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }
            // Nếu người dùng đang bôi đen chọn chữ, lần chạm đơn đầu tiên sẽ xóa vùng chọn chữ trước, tránh toggle HUD gây khó chịu
            if textView.selectedRange.length > 0 {
                return
            }
            NotificationCenter.default.post(name: NSNotification.Name("toggleReaderControls"), object: nil)
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            // Không làm gì để tránh sheet dịch tự mở lập tức khi bôi đen
        }
        
        // Cấu hình Edit Menu cho iOS 16+
        @available(iOS 16.0, *)
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            let customAction = UIAction(
                title: "📖 Dịch"
            ) { [weak self] _ in
                if let selectedText = textView.text(in: textView.selectedTextRange!) {
                    self?.triggerCustomDefine(text: selectedText)
                }
            }
            
            let ttsAction = UIAction(
                title: "🎧 Nghe đoạn này"
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
        if self.selectedTextRange != nil,
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