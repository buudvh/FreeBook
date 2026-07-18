import SwiftUI
import UIKit

struct ReaderTextView: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let lineSpacing: Double
    let theme: ReaderTheme
    let highlightRange: NSRange?
    let isBold: Bool
    let isCentered: Bool
    @Binding var triggerGetVisibleIndex: UUID?
    let onGetVisibleIndex: (Int) -> Void
    let onSelectionChange: (NSRange, CGRect?) -> Void
    let onSpeakFromHere: (Int) -> Void
    
    init(
        text: String,
        fontSize: Double,
        lineSpacing: Double,
        theme: ReaderTheme,
        highlightRange: NSRange?,
        isBold: Bool = false,
        isCentered: Bool = false,
        triggerGetVisibleIndex: Binding<UUID?>,
        onGetVisibleIndex: @escaping (Int) -> Void,
        onSelectionChange: @escaping (NSRange, CGRect?) -> Void,
        onSpeakFromHere: @escaping (Int) -> Void
    ) {
        self.text = text
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.theme = theme
        self.highlightRange = highlightRange
        self.isBold = isBold
        self.isCentered = isCentered
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
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
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
                              context.coordinator.lastHighlightRange != highlightRange ||
                              context.coordinator.lastIsCentered != isCentered
                              
        if isConfigChanged {
            context.coordinator.cachedWidth = nil
            context.coordinator.cachedHeight = nil
            context.coordinator.lastText = text
            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastLineSpacing = lineSpacing
            context.coordinator.lastThemeName = theme.rawValue
            context.coordinator.lastHighlightRange = highlightRange
            context.coordinator.lastIsCentered = isCentered
            
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let attributedText = NSMutableAttributedString(string: text)
            attributedText.addAttribute(.font, value: font, range: fullRange)
            attributedText.addAttribute(.foregroundColor, value: UIColor(theme.textColor), range: fullRange)
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = CGFloat(lineSpacing)
            if isCentered {
                paragraphStyle.alignment = .center
            } else {
                paragraphStyle.firstLineHeadIndent = CGFloat(fontSize * 1.5)
            }
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
        context.coordinator.setupScrollObservation(for: uiView)
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        uiView.delegate = nil
        coordinator.offsetObservation?.invalidate()
        coordinator.offsetObservation = nil
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
        var lastIsCentered: Bool? = nil
        var cachedWidth: CGFloat? = nil
        var cachedHeight: CGFloat? = nil
        
        var lastSelectionRange: NSRange? = nil
        var offsetObservation: NSKeyValueObservation? = nil
        
        init(_ parent: ReaderTextView) {
            self.parent = parent
        }
        
        deinit {
            offsetObservation?.invalidate()
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        func setupScrollObservation(for textView: UITextView) {
            guard offsetObservation == nil else { return }
            if let scrollView = textView.parentScrollView {
                offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    self?.handleSelectionOrScrollUpdate()
                }
            }
        }
        
        func handleSelectionOrScrollUpdate() {
            guard let textView = parentTextView else { return }
            let nsRange = textView.selectedRange
            let textLength = ((textView.text ?? "") as NSString).length
            
            if nsRange.length > 0 && NSMaxRange(nsRange) <= textLength,
               let textRange = textView.selectedTextRange {
                let rect = textView.firstRect(for: textRange)
                let globalRect = textView.convert(rect, to: nil)
                parent.onSelectionChange(nsRange, globalRect)
            }
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            let nsRange = textView.selectedRange
            guard nsRange != lastSelectionRange else { return }
            lastSelectionRange = nsRange
            
            let textLength = ((textView.text ?? "") as NSString).length
            if nsRange.length > 0 && NSMaxRange(nsRange) <= textLength,
               let textRange = textView.selectedTextRange {
                let rect = textView.firstRect(for: textRange)
                let globalRect = textView.convert(rect, to: nil)
                parent.onSelectionChange(nsRange, globalRect)
            } else {
                parent.onSelectionChange(NSRange(location: NSNotFound, length: 0), nil)
            }
        }
        
        @available(iOS 16.0, *)
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            return nil
        }
        
        func triggerCustomDefine() {
            guard let textView = parentTextView else { return }
            let nsRange = textView.selectedRange
            let textLength = ((textView.text ?? "") as NSString).length
            guard nsRange.location != NSNotFound,
                  nsRange.length > 0,
                  NSMaxRange(nsRange) <= textLength,
                  let textRange = textView.selectedTextRange else { return }
            let rect = textView.firstRect(for: textRange)
            let globalRect = textView.convert(rect, to: nil)
            parent.onSelectionChange(nsRange, globalRect)
        }
    }
}

// MARK: - Subclass UITextView to support custom action selector

class ReaderUITextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return false
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
