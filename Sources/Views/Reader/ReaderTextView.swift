import SwiftUI
import UIKit

struct ReaderTextView: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let lineSpacing: Double
    let fontFamily: ReaderFontFamily
    let theme: ReaderTheme
    let highlightRange: NSRange?
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

        let isHighlightChanged = context.coordinator.lastHighlightRange != highlightRange
        let oldHighlight = context.coordinator.lastHighlightRange

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
                attributedText.addAttribute(.backgroundColor, value: theme.highlightUIColor, range: highlight)
                if let textFgColor = theme.highlightTextUIColor {
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
            let storageLength = uiView.textStorage.length
            uiView.textStorage.beginEditing()

            if let old = oldHighlight, old.location != NSNotFound, old.location >= 0, old.location + old.length <= storageLength {
                uiView.textStorage.removeAttribute(.backgroundColor, range: old)
                uiView.textStorage.addAttribute(.foregroundColor, value: UIColor(theme.textColor), range: old)
            }

            if let highlight = highlightRange, highlight.location != NSNotFound, highlight.location >= 0, highlight.location + highlight.length <= storageLength {
                uiView.textStorage.addAttribute(.backgroundColor, value: theme.highlightUIColor, range: highlight)
                if let textFgColor = theme.highlightTextUIColor {
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
        var lastClearTriggerId: UUID?
        var lastText: String? = nil
        var lastFontSize: Double? = nil
        var lastLineSpacing: Double? = nil
        var lastFontFamilyName: String? = nil
        var lastIsBold: Bool? = nil
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
                let (minY, maxY) = selectionGlobalMinMaxY(textView: textView, textRange: textRange)
                parent.onSelectionChange(nsRange, minY, maxY)
            }
        }
        
        /// Tính toán minY và maxY của toàn bộ vùng selection trong tọa độ màn hình.
        /// Dùng firstRect (đầu selection) và lastRect (cuối selection) để union,
        /// tránh menu đè lên vùng bôi đen khi selection nhiều dòng.
        func selectionGlobalMinMaxY(textView: UITextView, textRange: UITextRange) -> (CGFloat?, CGFloat?) {
            guard let start = textView.selectedTextRange?.start,
                  let end = textView.selectedTextRange?.end,
                  let startRange = textView.textRange(from: start, to: start),
                  let endRange = textView.textRange(from: end, to: end) else {
                let rect = textView.firstRect(for: textRange)
                let globalRect = textView.convert(rect, to: nil)
                return (globalRect.minY, globalRect.maxY)
            }
            let firstRect = textView.convert(textView.firstRect(for: textRange), to: nil)
            let lastRect = textView.convert(textView.caretRect(for: end), to: nil)
            let _ = startRange // suppress unused warning
            let _ = endRange   // suppress unused warning
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
                parent.onSelectionChange(NSRange(location: NSNotFound, length: 0), nil, nil)
                return
            }
            
            guard nsRange != lastSelectionRange else { return }
            lastSelectionRange = nsRange
            
            let textLength = ((textView.text ?? "") as NSString).length
            if nsRange.length > 0 && NSMaxRange(nsRange) <= textLength,
               let textRange = textView.selectedTextRange {
                let (minY, maxY) = selectionGlobalMinMaxY(textView: textView, textRange: textRange)
                parent.onSelectionChange(nsRange, minY, maxY)
            } else {
                parent.onSelectionChange(NSRange(location: NSNotFound, length: 0), nil, nil)
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
            let (minY, maxY) = selectionGlobalMinMaxY(textView: textView, textRange: textRange)
            parent.onSelectionChange(nsRange, minY, maxY)
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

@MainActor
final class ReaderEnergyDiagnostics {
    static let shared = ReaderEnergyDiagnostics()

    private struct Window {
        let startedAt: TimeInterval
        var updateUIViewCount = 0
        var uniqueViews: Set<ObjectIdentifier> = []
        var highlightMutations = 0
        var geometryRebuilds = 0
        var themeRebuilds = 0
        var explicitSizeInvalidations = 0
        var contentSizeInvalidations = 0
        var ttsScrollTargets = 0
    }

    private static let summaryInterval: TimeInterval = 60
    private var window: Window?

    private init() {}

    func beginReaderSession() {
        window = Window(startedAt: ProcessInfo.processInfo.systemUptime)
    }

    func recordUIViewUpdate(for coordinator: AnyObject) {
        updateWindow { snapshot in
            snapshot.updateUIViewCount += 1
            snapshot.uniqueViews.insert(ObjectIdentifier(coordinator))
        }
    }

    func recordHighlightMutation() {
        updateWindow { $0.highlightMutations += 1 }
    }

    func recordGeometryRebuild() {
        updateWindow { $0.geometryRebuilds += 1 }
    }

    func recordThemeRebuild() {
        updateWindow { $0.themeRebuilds += 1 }
    }

    func recordExplicitSizeInvalidation() {
        updateWindow { $0.explicitSizeInvalidations += 1 }
    }

    func recordContentSizeInvalidation() {
        updateWindow { $0.contentSizeInvalidations += 1 }
    }

    func recordTTSScrollTarget() {
        updateWindow { $0.ttsScrollTargets += 1 }
    }

    func flush(reason: String) {
        emitSummary(reason: reason, resetWindow: false)
        window = nil
    }

    private func updateWindow(_ mutation: (inout Window) -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        var snapshot = window ?? Window(startedAt: now)
        mutation(&snapshot)
        window = snapshot

        if now - snapshot.startedAt >= Self.summaryInterval {
            emitSummary(reason: "interval", resetWindow: true)
        }
    }

    private func emitSummary(reason: String, resetWindow: Bool) {
        guard let snapshot = window else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let elapsedSeconds = max(0.1, now - snapshot.startedAt)
        let totalEvents = snapshot.updateUIViewCount + snapshot.ttsScrollTargets
        guard totalEvents > 0 else {
            if resetWindow {
                window = Window(startedAt: now)
            }
            return
        }

        let updateRPM = Double(snapshot.updateUIViewCount) * 60 / elapsedSeconds
        let repeatedUpdates = max(0, snapshot.updateUIViewCount - snapshot.uniqueViews.count)
        let repeatedUpdateRPM = Double(repeatedUpdates) * 60 / elapsedSeconds
        let highlightRPM = Double(snapshot.highlightMutations) * 60 / elapsedSeconds
        let sizeInvalidations = snapshot.explicitSizeInvalidations + snapshot.contentSizeInvalidations
        let sizeInvalidationRPM = Double(sizeInvalidations) * 60 / elapsedSeconds
        let scrollRPM = Double(snapshot.ttsScrollTargets) * 60 / elapsedSeconds
        let repeatedGeometryRebuilds = max(0, snapshot.geometryRebuilds - snapshot.uniqueViews.count)
        let expectedInitialSizeInvalidations = snapshot.uniqueViews.count * 2
        let excessSizeInvalidations = max(0, sizeInvalidations - expectedInitialSizeInvalidations)
        let thermal = ProcessInfo.processInfo.thermalState
        let prediction = Self.prediction(
            elapsedSeconds: elapsedSeconds,
            thermalState: thermal,
            repeatedUpdateRPM: repeatedUpdateRPM,
            highlightRPM: highlightRPM,
            repeatedGeometryRebuilds: repeatedGeometryRebuilds,
            excessSizeInvalidations: excessSizeInvalidations,
            scrollRPM: scrollRPM
        )

        let message = String(
            format: "[ReaderEnergy] Summary reason=%@ state=%@ elapsedSec=%.1f updateUIView=%d updateRPM=%.1f repeatUpdateRPM=%.1f uniqueViews=%d highlight=%d highlightRPM=%.1f geometry=%d repeatGeometry=%d theme=%d explicitSizeInvalidation=%d contentSizeInvalidation=%d excessSizeInvalidation=%d sizeInvalidationRPM=%.1f ttsScrollTarget=%d scrollRPM=%.1f thermal=%@ prediction=%@",
            reason,
            Self.applicationStateName(),
            elapsedSeconds,
            snapshot.updateUIViewCount,
            updateRPM,
            repeatedUpdateRPM,
            snapshot.uniqueViews.count,
            snapshot.highlightMutations,
            highlightRPM,
            snapshot.geometryRebuilds,
            repeatedGeometryRebuilds,
            snapshot.themeRebuilds,
            snapshot.explicitSizeInvalidations,
            snapshot.contentSizeInvalidations,
            excessSizeInvalidations,
            sizeInvalidationRPM,
            snapshot.ttsScrollTargets,
            scrollRPM,
            Self.thermalStateName(thermal),
            prediction
        )
        AppLogger.shared.log(message)

        if resetWindow {
            window = Window(startedAt: now)
        }
    }

    private static func prediction(
        elapsedSeconds: TimeInterval,
        thermalState: ProcessInfo.ThermalState,
        repeatedUpdateRPM: Double,
        highlightRPM: Double,
        repeatedGeometryRebuilds: Int,
        excessSizeInvalidations: Int,
        scrollRPM: Double
    ) -> String {
        if elapsedSeconds < 20 {
            return "insufficient_sample"
        }

        let hasThermalPressure = thermalState == .serious || thermalState == .critical
        let hasLayoutChurn = repeatedGeometryRebuilds >= 5 || excessSizeInvalidations >= 10
        let hasElevatedHighlightActivity = highlightRPM >= 30 || scrollRPM >= 18

        if hasThermalPressure && hasLayoutChurn {
            return "reader_layout_thermal_pressure_likely"
        }
        if hasThermalPressure && hasElevatedHighlightActivity {
            return "reader_activity_with_thermal_pressure"
        }
        if hasThermalPressure {
            return "thermal_pressure_not_explained_by_reader_updates"
        }
        if hasLayoutChurn {
            return "reader_layout_churn_likely"
        }
        if hasElevatedHighlightActivity || repeatedUpdateRPM >= 60 {
            return "reader_update_rate_elevated"
        }
        return "reader_render_load_low"
    }

    private static func applicationStateName() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "foreground"
        case .background: return "background"
        case .inactive: return "inactive"
        @unknown default: return "unknown"
        }
    }

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
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
