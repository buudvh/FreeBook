import SwiftUI
import UIKit

/// Component UIViewRepresentable cung cấp bộ biên tập code với Syntax Highlighting chuẩn VS Code Dark+
public struct HighlightingCodeEditor: UIViewRepresentable {
    @Binding public var text: String
    public var fontSize: CGFloat
    
    public init(text: Binding<String>, fontSize: CGFloat = 14.0) {
        self._text = text
        self.fontSize = fontSize
    }

    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = UIColor(red: 24/255, green: 24/255, blue: 37/255, alpha: 1.0) // #181825
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.isScrollEnabled = true
        textView.delegate = context.coordinator
        
        // Thiết lập lề đệm bên trong
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = font

        let highlighted = context.coordinator.highlight(text, fontSize: fontSize)
        textView.attributedText = highlighted

        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        uiView.font = font
        
        // Chỉ cập nhật nếu văn bản thực tế khác với uiView để tránh mất con trỏ chuột
        if uiView.text != text {
            let selectedRange = uiView.selectedRange
            uiView.attributedText = context.coordinator.highlight(text, fontSize: fontSize)
            if selectedRange.location <= (uiView.text as NSString).length {
                uiView.selectedRange = selectedRange
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, UITextViewDelegate {
        var parent: HighlightingCodeEditor

        // Màu sắc chuẩn VS Code Dark+ Theme
        private let colorDefault = UIColor(red: 205/255, green: 214/255, blue: 244/255, alpha: 1.0) // #CDD6F4
        private let colorKeyword = UIColor(red: 86/255, green: 156/255, blue: 214/255, alpha: 1.0) // #569CD6
        private let colorFunction = UIColor(red: 220/255, green: 220/255, blue: 170/255, alpha: 1.0) // #DCDCAA
        private let colorString = UIColor(red: 206/255, green: 145/255, blue: 120/255, alpha: 1.0) // #CE9178
        private let colorNumber = UIColor(red: 181/255, green: 206/255, blue: 168/255, alpha: 1.0) // #B5CEA8
        private let colorBuiltin = UIColor(red: 78/255, green: 201/255, blue: 176/255, alpha: 1.0) // #4EC9B0
        private let colorComment = UIColor(red: 106/255, green: 153/255, blue: 85/255, alpha: 1.0) // #6A9955

        private var regexCache: [String: NSRegularExpression] = [:]

        init(_ parent: HighlightingCodeEditor) {
            self.parent = parent
            super.init()
            precompileRegexes()
        }

        private func precompileRegexes() {
            let patterns: [(String, String)] = [
                ("comment", "//.*$|/\\*[\\s\\S]*?\\*/"),
                ("string", "\"([^\"\\\\]|\\\\.)*\"|'([^'\\\\]|\\\\.)*'|`([^`\\\\]|\\\\.)*`"),
                ("keyword", "\\b(function|var|let|const|return|if|else|for|while|do|switch|case|break|continue|try|catch|finally|throw|async|await|import|export|from|default|class|extends|new|typeof|instanceof|in|of|void|delete)\\b"),
                ("builtin", "\\b(Response|JSON|Math|String|Array|Object|Number|Boolean|Date|RegExp|console|fetch|encodeURIComponent|decodeURIComponent|parseInt|parseFloat)\\b"),
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

        public func textViewDidChange(_ textView: UITextView) {
            let selectedRange = textView.selectedRange
            let newText = textView.text ?? ""
            
            parent.text = newText
            textView.attributedText = highlight(newText, fontSize: parent.fontSize)
            
            if selectedRange.location <= (textView.text as NSString).length {
                textView.selectedRange = selectedRange
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
