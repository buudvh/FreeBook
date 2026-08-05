import SwiftUI

struct ParagraphCardView: View {
    let item: ParagraphItem
    let isTranslationEnabled: Bool
    let bookId: String
    let translationRefreshToken: UUID
    let fontSize: Double
    let lineSpacing: Double
    let fontFamily: ReaderFontFamily
    let theme: ReaderTheme
    let highlightRange: NSRange?
    @Binding var triggerGetVisibleIndex: UUID?
    @Binding var clearSelectionTrigger: UUID?
    let onGetVisibleIndex: (Int) -> Void
    let onSelectionChange: (Int, NSRange, CGFloat?, CGFloat?) -> Void
    let onSpeakFromHere: (Int) -> Void
    
    var body: some View {
        let displayText: String = {
            guard isTranslationEnabled && TranslateUtils.containsChinese(item.original) else {
                return item.original
            }
            if item.isTitle {
                return TranslateUtils.translateChapterTitle(item.original, bookId: bookId)
            } else {
                return TranslateUtils.translateContent(item.original, bookId: bookId)
            }
        }()

        // `highlightRange` đến từ TTS theo hệ tọa độ text GỐC. Ánh xạ tại đây vì đây là nơi duy nhất
        // biết chắc chuỗi đang thực sự hiển thị (item.translated có thể cũ khi người dùng bật/tắt
        // dịch mà chương chưa được build lại).
        let mappedHighlightRange = highlightRange.flatMap {
            ReaderSelectionMapper.mapHighlight($0, in: item, displayText: displayText)
        }

        ReaderTextView(
            text: displayText,
            fontSize: item.isTitle ? fontSize * 1.5 : fontSize,
            lineSpacing: lineSpacing,
            fontFamily: fontFamily,
            theme: theme,
            highlightRange: mappedHighlightRange,
            isBold: item.isTitle,
            isCentered: item.isTitle,
            triggerGetVisibleIndex: $triggerGetVisibleIndex,
            clearSelectionTrigger: $clearSelectionTrigger,
            onGetVisibleIndex: onGetVisibleIndex,
            onSelectionChange: { selectionRange, minY, maxY in
                onSelectionChange(item.id, selectionRange, minY, maxY)
            },
            onSpeakFromHere: onSpeakFromHere
        )
        .frame(minHeight: 20)
        .padding(.top, item.isTitle ? 10 : 0)
    }
}

extension ParagraphCardView: Equatable {
    static func == (lhs: ParagraphCardView, rhs: ParagraphCardView) -> Bool {
        return lhs.item == rhs.item &&
               lhs.isTranslationEnabled == rhs.isTranslationEnabled &&
               lhs.bookId == rhs.bookId &&
               lhs.translationRefreshToken == rhs.translationRefreshToken &&
               lhs.fontSize == rhs.fontSize &&
               lhs.lineSpacing == rhs.lineSpacing &&
               lhs.fontFamily == rhs.fontFamily &&
               lhs.theme == rhs.theme &&
               lhs.highlightRange == rhs.highlightRange &&
               lhs.triggerGetVisibleIndex == rhs.triggerGetVisibleIndex &&
               lhs.clearSelectionTrigger == rhs.clearSelectionTrigger
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
