import SwiftUI
import UIKit

struct ReaderTextView: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let lineSpacing: Double
    let fontFamily: ReaderFontFamily
    let theme: ReaderTheme
    let highlightRange: NSRange?
    let highlightIsPreparing: Bool
    let isBold: Bool
    let isCentered: Bool
    @Binding var triggerGetVisibleIndex: UUID?
    @Binding var clearSelectionTrigger: UUID?
    let onGetVisibleIndex: (Int) -> Void
    // Trả về (selectionRange, selectionMinY, selectionMaxY) trong tọa độ màn hình
    let onSelectionChange: (NSRange, CGFloat?, CGFloat?) -> Void
    let onSpeakFromHere: (Int) -> Void
    
    init(
        text: String,
        fontSize: Double,
        lineSpacing: Double,
        fontFamily: ReaderFontFamily = .georgia,
        theme: ReaderTheme,
        highlightRange: NSRange?,
        highlightIsPreparing: Bool = false,
        isBold: Bool = false,
        isCentered: Bool = false,
        triggerGetVisibleIndex: Binding<UUID?>,
        clearSelectionTrigger: Binding<UUID?>,
        onGetVisibleIndex: @escaping (Int) -> Void,
        onSelectionChange: @escaping (NSRange, CGFloat?, CGFloat?) -> Void,
        onSpeakFromHere: @escaping (Int) -> Void
    ) {
        self.text = text
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.fontFamily = fontFamily
        self.theme = theme
        self.highlightRange = highlightRange
        self.highlightIsPreparing = highlightIsPreparing
        self.isBold = isBold
        self.isCentered = isCentered
        self._triggerGetVisibleIndex = triggerGetVisibleIndex
        self._clearSelectionTrigger = clearSelectionTrigger
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
        let textView: AutoSizingTextView
        if #available(iOS 16.0, *) {
            textView = AutoSizingTextView(usingTextLayoutManager: false)
        } else {
            textView = AutoSizingTextView()
        }
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
        
        // Tắt kiểm tra chính tả và tự sửa — ngăn popup Spell-check phủ lên custom menu
        textView.spellCheckingType = .no
        textView.autocorrectionType = .no
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        ReaderEnergyDiagnostics.shared.recordUIViewUpdate(for: context.coordinator)
        
        let font: UIFont
        if let customFontName = fontFamily.fontName, let customFont = UIFont(name: customFontName, size: CGFloat(fontSize)) {
            font = customFont
        } else {
            font = isBold 
                ? UIFont.boldSystemFont(ofSize: CGFloat(fontSize))
                : UIFont.systemFont(ofSize: CGFloat(fontSize))
        }
            
        let isTextOrLayoutConfigChanged = context.coordinator.lastText != text ||
                                          context.coordinator.lastFontSize != fontSize ||
                                          context.coordinator.lastLineSpacing != lineSpacing ||
                                          context.coordinator.lastFontFamilyName != fontFamily.rawValue ||
                                          context.coordinator.lastIsBold != isBold ||
                                          context.coordinator.lastIsCentered != isCentered
        let isThemeChanged = context.coordinator.lastThemeName != theme.rawValue
        let shouldRebuildAttributedText = isTextOrLayoutConfigChanged || isThemeChanged

        let isHighlightChanged = context.coordinator.lastHighlightRange != highlightRange ||
                                 context.coordinator.lastHighlightIsPreparing != highlightIsPreparing
        let oldHighlight = context.coordinator.lastHighlightRange
        let highlightBackgroundColor = highlightIsPreparing ? theme.highlightUIColor.withAlphaComponent(0.28) : theme.highlightUIColor

        if shouldRebuildAttributedText {
            if isTextOrLayoutConfigChanged {
                ReaderEnergyDiagnostics.shared.recordGeometryRebuild()
                context.coordinator.cachedWidth = nil
                context.coordinator.cachedHeight = nil
            } else {
                ReaderEnergyDiagnostics.shared.recordThemeRebuild()
            }
            context.coordinator.lastText = text
            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastLineSpacing = lineSpacing
            context.coordinator.lastFontFamilyName = fontFamily.rawValue
            context.coordinator.lastIsBold = isBold
            context.coordinator.lastThemeName = theme.rawValue
            context.coordinator.lastHighlightRange = highlightRange
            context.coordinator.lastHighlightIsPreparing = highlightIsPreparing
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
                paragraphStyle.alignment = .justified
                paragraphStyle.firstLineHeadIndent = CGFloat(fontSize * 1.5)
            }
            attributedText.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

            if let highlight = highlightRange, highlight.location != NSNotFound, highlight.location >= 0, highlight.location + highlight.length <= nsText.length {
                attributedText.addAttribute(.backgroundColor, value: highlightBackgroundColor, range: highlight)
                if !highlightIsPreparing, let textFgColor = theme.highlightTextUIColor {
                    attributedText.addAttribute(.foregroundColor, value: textFgColor, range: highlight)
                }
            }

            uiView.attributedText = attributedText
            uiView.selectedRange = NSRange(location: 0, length: 0)
            if isTextOrLayoutConfigChanged {
                ReaderEnergyDiagnostics.shared.recordExplicitSizeInvalidation()
                uiView.invalidateIntrinsicContentSize()
            }
        } else if isHighlightChanged {
            ReaderEnergyDiagnostics.shared.recordHighlightMutation()
            context.coordinator.lastHighlightRange = highlightRange
            context.coordinator.lastHighlightIsPreparing = highlightIsPreparing
            let storageLength = uiView.textStorage.length
            uiView.textStorage.beginEditing()

            if let old = oldHighlight, old.location != NSNotFound, old.location >= 0, old.location + old.length <= storageLength {
                uiView.textStorage.removeAttribute(.backgroundColor, range: old)
                uiView.textStorage.addAttribute(.foregroundColor, value: UIColor(theme.textColor), range: old)
            }

            if let highlight = highlightRange, highlight.location != NSNotFound, highlight.location >= 0, highlight.location + highlight.length <= storageLength {
                uiView.textStorage.addAttribute(.backgroundColor, value: highlightBackgroundColor, range: highlight)
                if !highlightIsPreparing, let textFgColor = theme.highlightTextUIColor {
                    uiView.textStorage.addAttribute(.foregroundColor, value: textFgColor, range: highlight)
                }
            }

            uiView.textStorage.endEditing()
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
        
        // Xử lý trigger xóa selection từ SwiftUI (sau khi bấm nút menu)
        if context.coordinator.lastClearTriggerId != clearSelectionTrigger {
            context.coordinator.lastClearTriggerId = clearSelectionTrigger
            if clearSelectionTrigger != nil {
                DispatchQueue.main.async {
                    self.clearSelectionTrigger = nil
                    uiView.selectedRange = NSRange(location: 0, length: 0)
                }
            }
        }
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
        var lastClearTriggerId: UUID?
        var lastText: String? = nil
        var lastFontSize: Double? = nil
        var lastLineSpacing: Double? = nil
        var lastFontFamilyName: String? = nil
        var lastIsBold: Bool? = nil
        var lastThemeName: String? = nil
        var lastHighlightRange: NSRange? = nil
        var lastHighlightIsPreparing = false
        var lastIsCentered: Bool? = nil
        var cachedWidth: CGFloat? = nil
        var cachedHeight: CGFloat? = nil
        
        var lastSelectionRange: NSRange? = nil
        var offsetObservation: NSKeyValueObservation? = nil
        /// Lần publish gần nhất — dùng để chặn onSelectionChange trùng lặp khi cuộn.
        private var lastPublishedSelection: (range: NSRange, minY: CGFloat?, maxY: CGFloat?)? = nil

        init(_ parent: ReaderTextView) {
            self.parent = parent
        }
        
        deinit {
            offsetObservation?.invalidate()
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        /// Chỉ quan sát contentOffset khi text view này đang có selection thật.
        /// Trạng thái thường ngày (không bôi đen) là 0 observer, thay vì một observer
        /// cho mỗi paragraph đang realized — mỗi frame cuộn trước đây gọi lại toàn bộ.
        func setupScrollObservation(for textView: UITextView) {
            guard offsetObservation == nil else { return }
            if let scrollView = textView.parentScrollView {
                offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    self?.handleSelectionOrScrollUpdate()
                }
            }
        }

        func teardownScrollObservation() {
            offsetObservation?.invalidate()
            offsetObservation = nil
        }

        func handleSelectionOrScrollUpdate() {
            guard let textView = parentTextView else { return }
            let nsRange = textView.selectedRange
            guard nsRange.length > 0 else { return }
            guard NSMaxRange(nsRange) <= textView.textStorage.length,
                  let textRange = textView.selectedTextRange else { return }
            let (minY, maxY) = selectionGlobalMinMaxY(textView: textView, textRange: textRange)
            publishSelection(nsRange, minY, maxY)
        }

        /// Bỏ qua publish khi range không đổi và vị trí lệch dưới 0.5 pt — chặn
        /// onSelectionChangeInParagraph ghi @State của ReaderView mỗi frame cuộn.
        private func publishSelection(_ range: NSRange, _ minY: CGFloat?, _ maxY: CGFloat?, force: Bool = false) {
            if !force, let last = lastPublishedSelection,
               last.range == range,
               Self.isSamePosition(last.minY, minY),
               Self.isSamePosition(last.maxY, maxY) {
                return
            }
            lastPublishedSelection = (range, minY, maxY)
            parent.onSelectionChange(range, minY, maxY)
        }

        private static func isSamePosition(_ lhs: CGFloat?, _ rhs: CGFloat?) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil): return true
            case let (left?, right?): return abs(left - right) < 0.5
            default: return false
            }
        }
        
        /// Tính toán minY và maxY của toàn bộ vùng selection trong tọa độ màn hình.
        /// Dùng firstRect (đầu selection) và lastRect (cuối selection) để union,
        /// tránh menu đè lên vùng bôi đen khi selection nhiều dòng.
        func selectionGlobalMinMaxY(textView: UITextView, textRange: UITextRange) -> (CGFloat?, CGFloat?) {
            guard let end = textView.selectedTextRange?.end else {
                let rect = textView.firstRect(for: textRange)
                let globalRect = textView.convert(rect, to: nil)
                return (globalRect.minY, globalRect.maxY)
            }
            let firstRect = textView.convert(textView.firstRect(for: textRange), to: nil)
            let lastRect = textView.convert(textView.caretRect(for: end), to: nil)
            let unionMinY = min(firstRect.minY, lastRect.minY)
            let unionMaxY = max(firstRect.maxY, lastRect.maxY)
            return (unionMinY, unionMaxY)
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            let nsRange = textView.selectedRange
            
            // Ẩn menu hệ thống (UIMenuController) ngay khi selection thay đổi
            // để nó không phủ lên FloatingSelectionMenu của chúng ta.
            DispatchQueue.main.async {
                UIMenuController.shared.hideMenu()
            }
            
            // Khi length == 0 (deselect / tap ra ngoài), bỏ qua guard lastSelectionRange
            // để sự kiện deselect luôn được gửi lên và tắt Floating Menu.
            if nsRange.length == 0 {
                lastSelectionRange = nsRange
                teardownScrollObservation()
                publishSelection(NSRange(location: NSNotFound, length: 0), nil, nil, force: true)
                return
            }

            guard nsRange != lastSelectionRange else { return }
            lastSelectionRange = nsRange

            if NSMaxRange(nsRange) <= textView.textStorage.length,
               let textRange = textView.selectedTextRange {
                // Có selection thật ⇒ giờ mới cần theo dõi contentOffset để menu bám theo chữ.
                setupScrollObservation(for: textView)
                let (minY, maxY) = selectionGlobalMinMaxY(textView: textView, textRange: textRange)
                publishSelection(nsRange, minY, maxY, force: true)
            } else {
                teardownScrollObservation()
                publishSelection(NSRange(location: NSNotFound, length: 0), nil, nil, force: true)
            }
        }
        
        @available(iOS 16.0, *)
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            return nil
        }
        
        func triggerCustomDefine() {
            guard let textView = parentTextView else { return }
            let nsRange = textView.selectedRange
            guard nsRange.location != NSNotFound,
                  nsRange.length > 0,
                  NSMaxRange(nsRange) <= textView.textStorage.length,
                  let textRange = textView.selectedTextRange else { return }
            let (minY, maxY) = selectionGlobalMinMaxY(textView: textView, textRange: textRange)
            publishSelection(nsRange, minY, maxY, force: true)
        }
    }
}

// MARK: - Subclass UITextView to support custom action selector

class ReaderUITextView: UITextView {

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return false
    }

    /// Chặn UIKit thêm UITextInteraction (nonEditable) và UIEditMenuInteraction.
    /// Đây là nguồn gốc của menu hệ thống "Speak / Look Up / Spell" xuất hiện
    /// khi bôi đen text, che phủ FloatingSelectionMenu tùy chỉnh.
    /// Override addInteraction thay vì didMoveToWindow để tránh timing issue
    /// (UIKit có thể thêm lại interaction sau khi view vào window).
    override func addInteraction(_ interaction: UIInteraction) {
        // Chặn UITextInteraction nonEditable — nguồn gốc menu Speak/Look Up
        if let textInteraction = interaction as? UITextInteraction,
           textInteraction.textInteractionMode == .nonEditable {
            return
        }
        // Chặn UIEditMenuInteraction (iOS 16+) — nguồn gốc menu Spell/Share
        if #available(iOS 16.0, *), interaction is UIEditMenuInteraction {
            return
        }
        super.addInteraction(interaction)
    }
}


class AutoSizingTextView: ReaderUITextView {

    override var contentSize: CGSize {
        didSet {
            let widthChanged = abs(contentSize.width - oldValue.width) > 0.5
            let heightChanged = abs(contentSize.height - oldValue.height) > 0.5
            if widthChanged || heightChanged {
                ReaderEnergyDiagnostics.shared.recordContentSizeInvalidation()
                invalidateIntrinsicContentSize()
            }
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
