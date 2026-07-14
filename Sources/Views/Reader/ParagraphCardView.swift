import SwiftUI

struct ParagraphCardView: View {
    let item: ParagraphItem
    let isTranslationEnabled: Bool
    let fontSize: Double
    let lineSpacing: Double
    let theme: ReaderTheme
    let highlightRange: NSRange?
    @Binding var triggerGetVisibleIndex: UUID?
    let onGetVisibleIndex: (Int) -> Void
    let onSelectionChange: (String, String, Int, Int) -> Void
    let onSpeakFromHere: (Int) -> Void
    
    var body: some View {
        ReaderTextView(
            text: isTranslationEnabled ? item.translated : item.original,
            fontSize: item.isTitle ? fontSize * 1.25 : fontSize,
            lineSpacing: lineSpacing,
            theme: theme,
            highlightRange: highlightRange,
            isBold: item.isTitle,
            triggerGetVisibleIndex: $triggerGetVisibleIndex,
            onGetVisibleIndex: onGetVisibleIndex,
            onSelectionChange: onSelectionChange,
            onSpeakFromHere: onSpeakFromHere
        )
        .frame(minHeight: 20)
    }
}

extension ParagraphCardView: Equatable {
    static func == (lhs: ParagraphCardView, rhs: ParagraphCardView) -> Bool {
        return lhs.item == rhs.item &&
               lhs.isTranslationEnabled == rhs.isTranslationEnabled &&
               lhs.fontSize == rhs.fontSize &&
               lhs.lineSpacing == rhs.lineSpacing &&
               lhs.theme == rhs.theme &&
               lhs.highlightRange == rhs.highlightRange &&
               lhs.triggerGetVisibleIndex == rhs.triggerGetVisibleIndex
    }
}

// Cấu trúc dữ liệu dòng text song hành
public struct ParagraphItem: Identifiable, Codable, Equatable {
    public let id: Int
    public let original: String
    public let translated: String
    public let isTitle: Bool
    
    public init(id: Int, original: String, translated: String, isTitle: Bool = false) {
        self.id = id
        self.original = original
        self.translated = translated
        self.isTitle = isTitle
    }
}
