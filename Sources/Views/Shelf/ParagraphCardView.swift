import SwiftUI

public struct ParagraphItem: Identifiable {
    public let id: Int // Dùng chỉ số dòng làm ID
    public let original: String
    public let translated: String
    
    public init(id: Int, original: String, translated: String) {
        self.id = id
        self.original = original
        self.translated = translated
    }
}

struct ParagraphCardView: View {
    let item: ParagraphItem
    let isTranslationEnabled: Bool
    let fontSize: Double
    let lineSpacing: Double
    let theme: ReaderTheme
    let onSelectionChange: (String, String, Int, Int) -> Void
    let onSpeakFromHere: (Int) -> Void
    
    var body: some View {
        ReaderTextView(
            text: isTranslationEnabled ? item.translated : item.original,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            theme: theme,
            highlightRange: nil,
            triggerGetVisibleIndex: .constant(nil),
            onGetVisibleIndex: { _ in },
            onSelectionChange: onSelectionChange,
            onSpeakFromHere: onSpeakFromHere
        )
        .frame(minHeight: 20)
    }
}
