import SwiftUI
import UIKit

struct ReaderTextView: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let theme: ReaderTheme
    let onSelectionChange: (String, String, Int) -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
        uiView.font = UIFont.systemFont(ofSize: CGFloat(fontSize))
        uiView.textColor = UIColor(theme.textColor)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ReaderTextView
        
        init(_ parent: ReaderTextView) {
            self.parent = parent
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let range = textView.selectedTextRange,
                  let selectedText = textView.text(in: range),
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            
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
            
            parent.onSelectionChange(selectedText, surroundingSentence, offsetInSentence)
        }
    }
}
