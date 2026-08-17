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

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
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

/// Component UIViewRepresentable cung cấp bộ biên tập code với Syntax Highlighting chuẩn VS Code Dark+ và Gutter số dòng thông minh
public struct HighlightingCodeEditor: UIViewRepresentable {
    @Binding public var text: String
    public var fontSize: CGFloat
    
    public init(text: Binding<String>, fontSize: CGFloat = 14.0) {
        self._text = text
        self.fontSize = fontSize
    }

    public func makeUIView(context: Context) -> CodeEditorTextView {
        let textView = CodeEditorTextView()
        textView.delegate = context.coordinator
        
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = font
        textView.lineNumberFont = UIFont.monospacedSystemFont(ofSize: max(9.0, fontSize - 2.0), weight: .regular)

        let highlighted = context.coordinator.highlight(text, fontSize: fontSize)
        textView.attributedText = highlighted
        textView.updateGutterInset()

        return textView
    }

    public func updateUIView(_ uiView: CodeEditorTextView, context: Context) {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        uiView.font = font
        uiView.lineNumberFont = UIFont.monospacedSystemFont(ofSize: max(9.0, fontSize - 2.0), weight: .regular)
        
        // Chỉ cập nhật nếu văn bản thực tế khác với uiView để tránh mất con trỏ chuột
        if uiView.text != text {
            let selectedRange = uiView.selectedRange
            uiView.attributedText = context.coordinator.highlight(text, fontSize: fontSize)
            if selectedRange.location <= (uiView.text as NSString).length {
                uiView.selectedRange = selectedRange
            }
            uiView.updateGutterInset()
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, UITextViewDelegate {
        var parent: HighlightingCodeEditor

        // Màu sắc chuẩn VS Code Dark+ Theme
        internal let colorDefault = UIColor(red: 205/255, green: 214/255, blue: 244/255, alpha: 1.0) // #CDD6F4
        internal let colorKeyword = UIColor(red: 86/255, green: 156/255, blue: 214/255, alpha: 1.0) // #569CD6
        internal let colorFunction = UIColor(red: 220/255, green: 220/255, blue: 170/255, alpha: 1.0) // #DCDCAA
        internal let colorString = UIColor(red: 206/255, green: 145/255, blue: 120/255, alpha: 1.0) // #CE9178
        internal let colorNumber = UIColor(red: 181/255, green: 206/255, blue: 168/255, alpha: 1.0) // #B5CEA8
        internal let colorBuiltin = UIColor(red: 78/255, green: 201/255, blue: 176/255, alpha: 1.0) // #4EC9B0
        internal let colorComment = UIColor(red: 106/255, green: 153/255, blue: 85/255, alpha: 1.0) // #6A9955

        internal var regexCache: [String: NSRegularExpression] = [:]

        init(_ parent: HighlightingCodeEditor) {
            self.parent = parent
            super.init()
            precompileRegexes()
        }

        internal func precompileRegexes() {
            let patterns: [(String, String)] = [
                ("comment", "//.*$|/\\*[\\s\\S]*?\\*/"),
                ("string", "\"([^\"\\\\]|\\\\.)*\"|'([^'\\\\]|\\\\.)*'|`([^`\\\\]|\\\\.)*`"),
                ("keyword", "\\b(function|var|let|const|return|if|else|for|while|do|switch|case|break|continue|try|catch|finally|throw|async|await|import|export|from|default|class|extends|new|typeof|instanceof|in|of|void|delete)\\b"),
                ("builtin", "\\b(Response|JSON|Math|String|Array|Object|Number|Boolean|Date|RegExp|console|fetch|encodeURIComponent|decodeURIComponent|parseInt|parseFloat|localStorage|cacheStorage|localConfig|localCookie|UserAgent|Qt|Crypto|Script|Engine|Http|Html|toast|sleep|print|Log|atob|btoa)\\b"),
                ("functionCall", "\\b([a-zA-Z_$][a-zA-Z0-9_$]*)\\s*(?=\\()"),
                ("number", "\\b(true|false|null|undefined|\\d+(\\.\\d+)?)\\b")
            ]

            for (key, pattern) in patterns {
                let options: NSRegularExpression.Options = key == "comment" ? [.anchorsMatchLines] : []
                if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                    regexCache[key] = regex
                }
            }
        }

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            scrollView.setNeedsDisplay()
        }

        public func textViewDidChange(_ textView: UITextView) {
            let selectedRange = textView.selectedRange
            let newText = textView.text ?? ""
            
            parent.text = newText
            textView.attributedText = highlight(newText, fontSize: parent.fontSize)
            
            if selectedRange.location <= (textView.text as NSString).length {
                textView.selectedRange = selectedRange
            }

            if let codeEditor = textView as? CodeEditorTextView {
                codeEditor.updateGutterInset()
            }
        }

        public func highlight(_ code: String, fontSize: CGFloat) -> NSAttributedString {
            let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let attributedString = NSMutableAttributedString(
                string: code,
                attributes: [
                    .font: font,
                    .foregroundColor: colorDefault
                ]
            )

            let nsString = code as NSString
            let fullRange = NSRange(location: 0, length: nsString.length)
            guard fullRange.length > 0 else { return attributedString }

            // 1. Phân tích Số & Values
            if let numberRegex = regexCache["number"] {
                for match in numberRegex.matches(in: code, options: [], range: fullRange) {
                    attributedString.addAttribute(.foregroundColor, value: colorNumber, range: match.range)
                }
            }

            // 2. Phân tích Từ khóa (Keywords)
            if let keywordRegex = regexCache["keyword"] {
                for match in keywordRegex.matches(in: code, options: [], range: fullRange) {
                    attributedString.addAttribute(.foregroundColor, value: colorKeyword, range: match.range)
                }
            }

            // 3. Phân tích Đối tượng tích hợp (Built-in Objects)
            if let builtinRegex = regexCache["builtin"] {
                for match in builtinRegex.matches(in: code, options: [], range: fullRange) {
                    attributedString.addAttribute(.foregroundColor, value: colorBuiltin, range: match.range)
                }
            }

            // 4. Phân tích Tên hàm (Function Calls)
            if let funcRegex = regexCache["functionCall"] {
                for match in funcRegex.matches(in: code, options: [], range: fullRange) {
                    let nameRange = match.range(at: 1)
                    if nameRange.location != NSNotFound {
                        attributedString.addAttribute(.foregroundColor, value: colorFunction, range: nameRange)
                    }
                }
            }

            // 5. Phân tích Chuỗi (Strings - Ghi đè màu từ khóa nếu nằm trong chuỗi)
            if let stringRegex = regexCache["string"] {
                for match in stringRegex.matches(in: code, options: [], range: fullRange) {
                    attributedString.addAttribute(.foregroundColor, value: colorString, range: match.range)
                }
            }

            // 6. Phân tích Ghi chú (Comments - Ghi đè cao nhất)
            if let commentRegex = regexCache["comment"] {
                for match in commentRegex.matches(in: code, options: [], range: fullRange) {
                    attributedString.addAttribute(.foregroundColor, value: colorComment, range: match.range)
                }
            }

            return attributedString
        }
    }
}
