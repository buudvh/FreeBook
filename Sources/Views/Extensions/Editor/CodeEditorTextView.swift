import SwiftUI
import UIKit

/// Custom UITextView với Line Number Gutter vẽ trực tiếp qua layoutManager,
/// đảm bảo số dòng không bao giờ bị lệch khi văn bản dài tự động xuống hàng (word wrap).
public final class CodeEditorTextView: UITextView {
    public var gutterWidth: CGFloat = 38.0
    public var lineNumberFont: UIFont = .monospacedSystemFont(ofSize: 11.0, weight: .regular)
    public var lineNumberColor: UIColor = UIColor(red: 108/255, green: 112/255, blue: 134/255, alpha: 1.0)
    public var gutterBgColor: UIColor = UIColor(red: 30/255, green: 30/255, blue: 46/255, alpha: 1.0)
    public var dividerColor: UIColor = UIColor.white.withAlphaComponent(0.12)

    /// Khung bàn phím lần cuối (toạ độ màn hình); `nil` = bàn phím đang ẩn.
    private var keyboardScreenFrame: CGRect?
    private var keyboardObservers: [NSObjectProtocol] = []

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    deinit {
        keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func setupView() {
        backgroundColor = UIColor(red: 24/255, green: 24/255, blue: 37/255, alpha: 1.0)
        autocapitalizationType = .none
        autocorrectionType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        isScrollEnabled = true
        updateGutterInset()
        observeKeyboard()
    }

    // MARK: - Chừa chỗ cho bàn phím

    private func observeKeyboard() {
        let names: [Notification.Name] = [
            UIResponder.keyboardWillShowNotification,
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardWillHideNotification
        ]
        keyboardObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if name == UIResponder.keyboardWillHideNotification {
                    self.keyboardScreenFrame = nil
                } else if let value = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                    self.keyboardScreenFrame = value.cgRectValue
                }
                self.setNeedsLayout()
                self.applyKeyboardInset()
            }
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Tính lại **sau** khi layout xong: SwiftUI có thể đã tự thu nhỏ khung theo bàn phím, khi đó
        // phần che thực tế bằng 0 và không được cộng thêm inset.
        applyKeyboardInset()
    }

    /// Cộng đúng phần bàn phím phủ lên text view vào `contentInset.bottom`. Thiếu inset này thì tài
    /// liệu ngắn hơn khung hiển thị **không cuộn được**, nên mấy dòng cuối bị bàn phím che vĩnh viễn.
    private func applyKeyboardInset() {
        guard let window, let keyboardFrame = keyboardScreenFrame else {
            setKeyboardInset(0)
            return
        }
        let keyboardInWindow = window.convert(keyboardFrame, from: nil)
        let selfInWindow = convert(bounds, to: window)
        setKeyboardInset(max(0, selfInWindow.maxY - keyboardInWindow.minY))
    }

    private func setKeyboardInset(_ bottom: CGFloat) {
        guard abs(contentInset.bottom - bottom) > 0.5 else { return }
        contentInset.bottom = bottom
        verticalScrollIndicatorInsets.bottom = bottom
        if bottom > 0, isFirstResponder {
            scrollRangeToVisible(selectedRange)
        }
    }

    public func updateGutterInset() {
        let totalLines = text.components(separatedBy: .newlines).count
        let digits = max(2, String(totalLines).count)
        let calcWidth = CGFloat(digits * 8 + 20)
        self.gutterWidth = max(38.0, calcWidth)
        self.textContainerInset = UIEdgeInsets(top: 8, left: gutterWidth + 8, bottom: 8, right: 8)
        self.setNeedsDisplay()
    }

    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // 1. Vẽ nền Gutter
        let gutterRect = CGRect(x: contentOffset.x, y: contentOffset.y, width: gutterWidth, height: bounds.height)
        context.setFillColor(gutterBgColor.cgColor)
        context.fill(gutterRect)

        // 2. Vẽ đường phân cách
        context.setStrokeColor(dividerColor.cgColor)
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: contentOffset.x + gutterWidth, y: contentOffset.y))
        context.addLine(to: CGPoint(x: contentOffset.x + gutterWidth, y: contentOffset.y + bounds.height))
        context.strokePath()

        // 3. Quét và vẽ số dòng tương ứng với từng đoạn code
        let layoutManager = self.layoutManager
        let textStorage = self.textStorage

        let textString = textStorage.string as NSString
        guard textString.length > 0 else {
            let lineNumStr = "1" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: lineNumberFont,
                .foregroundColor: lineNumberColor
            ]
            let size = lineNumStr.size(withAttributes: attrs)
            let drawPoint = CGPoint(
                x: contentOffset.x + gutterWidth - size.width - 6,
                y: textContainerInset.top + 2
            )
            lineNumStr.draw(at: drawPoint, withAttributes: attrs)
            return
        }

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: bounds, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        var lineNumber = 1
        textString.enumerateSubstrings(in: NSRange(location: 0, length: min(visibleCharRange.location, textString.length)), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        textString.enumerateSubstrings(in: visibleCharRange, options: [.byLines, .substringNotRequired]) { [weak self] _, substringRange, _, _ in
            guard let self = self else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: substringRange, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound else { return }

            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            lineRect.origin.x += self.textContainerInset.left
            lineRect.origin.y += self.textContainerInset.top

            let lineNumStr = "\(lineNumber)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: self.lineNumberFont,
                .foregroundColor: self.lineNumberColor
            ]
            let textSize = lineNumStr.size(withAttributes: attrs)
            let drawPoint = CGPoint(
                x: self.contentOffset.x + self.gutterWidth - textSize.width - 6,
                y: lineRect.origin.y + max(0, (lineRect.height - textSize.height) / 2.0)
            )

            lineNumStr.draw(at: drawPoint, withAttributes: attrs)
            lineNumber += 1
        }
    }
}
