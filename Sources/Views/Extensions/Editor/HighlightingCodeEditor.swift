import SwiftUI
import UIKit

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
                // Ghi chú + chuỗi nằm trong **một** regex: NSRegularExpression quét từ trái sang phải
                // và không cho match chồng nhau, nên match bắt đầu trước sẽ thắng. Nhờ vậy
                // `"https://x"` được nhận là chuỗi (không biến phần sau `//` thành ghi chú), còn
                // `// đừng "mở chuỗi"` được nhận là ghi chú (dấu nháy trong đó không mở chuỗi).
                ("protected", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"
                    + "|\"([^\"\\\\\\n]|\\\\.)*\"|'([^'\\\\\\n]|\\\\.)*'|`([^`\\\\]|\\\\.)*`"),
                ("keyword", "\\b(function|var|let|const|return|if|else|for|while|do|switch|case|break|continue|try|catch|finally|throw|async|await|import|export|from|default|class|extends|new|typeof|instanceof|in|of|void|delete)\\b"),
                ("builtin", "\\b(Response|JSON|Math|String|Array|Object|Number|Boolean|Date|RegExp|console|fetch|encodeURIComponent|decodeURIComponent|parseInt|parseFloat|localStorage|cacheStorage|localConfig|localCookie|UserAgent|Qt|Crypto|Script|Engine|Http|Html|toast|sleep|print|Log|atob|btoa)\\b"),
                ("functionCall", "\\b([a-zA-Z_$][a-zA-Z0-9_$]*)\\s*(?=\\()"),
                ("number", "\\b(true|false|null|undefined|\\d+(\\.\\d+)?)\\b")
            ]

            for (key, pattern) in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    regexCache[key] = regex
                }
            }
        }

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            scrollView.setNeedsDisplay()
        }

        public func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            // Tô màu **tại chỗ** trên textStorage thay vì gán lại `attributedText`: giữ nguyên con trỏ,
            // vùng chọn và marked text của bàn phím, nên màu không còn chớp/nhảy khi gõ nhanh.
            applyHighlight(to: textView, fontSize: parent.fontSize)

            if let codeEditor = textView as? CodeEditorTextView {
                codeEditor.updateGutterInset()
            }
        }

        /// Cập nhật màu ngay trên `textStorage` của text view đang gõ.
        public func applyHighlight(to textView: UITextView, fontSize: CGFloat) {
            let storage = textView.textStorage
            let code = storage.string
            let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let fullRange = NSRange(location: 0, length: (code as NSString).length)

            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: colorDefault], range: fullRange)
            for (range, color) in tokenColors(in: code) {
                storage.addAttribute(.foregroundColor, value: color, range: range)
            }
            storage.endEditing()

            // Không có dòng này thì ký tự vừa gõ tiếp sau một token sẽ thừa hưởng màu của token đó
            // cho tới lượt tô kế tiếp — đúng hiện tượng "màu thỉnh thoảng trục trặc".
            textView.typingAttributes = [.font: font, .foregroundColor: colorDefault]
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
            for (range, color) in tokenColors(in: code) {
                attributedString.addAttribute(.foregroundColor, value: color, range: range)
            }
            return attributedString
        }

        /// Danh sách (range, màu) cho toàn bộ tài liệu, theo hai lượt:
        /// 1. Chuỗi & ghi chú — quét trước để biết vùng nào là "văn bản thuần".
        /// 2. Số / từ khoá / built-in / tên hàm — chỉ tô khi **không** giao với vùng ở lượt 1.
        ///
        /// Cách này bỏ được lỗi của bản cũ: các lượt chồng nhau theo thứ tự ưu tiên, nên `//` trong
        /// một URL làm cả phần còn lại của dòng thành màu ghi chú.
        internal func tokenColors(in code: String) -> [(NSRange, UIColor)] {
            let nsString = code as NSString
            let fullRange = NSRange(location: 0, length: nsString.length)
            guard fullRange.length > 0 else { return [] }

            var result: [(NSRange, UIColor)] = []
            var protectedRanges: [NSRange] = []

            if let regex = regexCache["protected"] {
                for match in regex.matches(in: code, options: [], range: fullRange) {
                    protectedRanges.append(match.range)
                    let isComment = nsString.substring(with: NSRange(location: match.range.location, length: 1)) == "/"
                    result.append((match.range, isComment ? colorComment : colorString))
                }
            }

            let simplePasses: [(String, UIColor)] = [
                ("number", colorNumber),
                ("keyword", colorKeyword),
                ("builtin", colorBuiltin)
            ]
            for (key, color) in simplePasses {
                guard let regex = regexCache[key] else { continue }
                for match in regex.matches(in: code, options: [], range: fullRange)
                where !intersectsProtected(match.range, protectedRanges) {
                    result.append((match.range, color))
                }
            }

            if let regex = regexCache["functionCall"] {
                for match in regex.matches(in: code, options: [], range: fullRange) {
                    let nameRange = match.range(at: 1)
                    guard nameRange.location != NSNotFound,
                          !intersectsProtected(nameRange, protectedRanges) else { continue }
                    result.append((nameRange, colorFunction))
                }
            }

            return result
        }

        /// `ranges` do NSRegularExpression sinh ra nên đã rời nhau và tăng dần theo `location`,
        /// đủ điều kiện tìm nhị phân.
        private func intersectsProtected(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
            var low = 0
            var high = ranges.count - 1
            while low <= high {
                let mid = (low + high) / 2
                let candidate = ranges[mid]
                if NSIntersectionRange(candidate, range).length > 0 { return true }
                if candidate.location > range.location {
                    high = mid - 1
                } else {
                    low = mid + 1
                }
            }
            return false
        }
    }
}
