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
    let onSelectionChange: (Int, NSRange, CGRect?) -> Void
    let onSpeakFromHere: (Int) -> Void
    
    var body: some View {
        ReaderTextView(
            text: isTranslationEnabled ? item.translated : item.original,
            fontSize: item.isTitle ? fontSize * 1.5 : fontSize,
            lineSpacing: lineSpacing,
            theme: theme,
            highlightRange: highlightRange,
            isBold: item.isTitle,
            isCentered: item.isTitle,
            triggerGetVisibleIndex: $triggerGetVisibleIndex,
            onGetVisibleIndex: onGetVisibleIndex,
            onSelectionChange: { selectionRange, rect in
                onSelectionChange(item.id, selectionRange, rect)
            },
            onSpeakFromHere: onSpeakFromHere
        )
        .frame(minHeight: 20)
        .padding(.top, item.isTitle ? 32 : 0)
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
public struct ParagraphItem: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let original: String
    public let translated: String
    public let isTitle: Bool
    public let translationSpans: [TranslationSpan]
    
    public init(
        id: Int,
        original: String,
        translated: String,
        isTitle: Bool = false,
        translationSpans: [TranslationSpan] = []
    ) {
        self.id = id
        self.original = original
        self.translated = translated
        self.isTitle = isTitle
        self.translationSpans = translationSpans
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case original
        case translated
        case isTitle
        case translationSpans
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        original = try container.decode(String.self, forKey: .original)
        translated = try container.decode(String.self, forKey: .translated)
        isTitle = try container.decodeIfPresent(Bool.self, forKey: .isTitle) ?? false
        translationSpans = try container.decodeIfPresent([TranslationSpan].self, forKey: .translationSpans) ?? []
    }
}
