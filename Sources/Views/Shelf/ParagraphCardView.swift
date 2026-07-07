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
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            theme: theme,
            highlightRange: highlightRange,
            triggerGetVisibleIndex: $triggerGetVisibleIndex,
            onGetVisibleIndex: onGetVisibleIndex,
            onSelectionChange: onSelectionChange,
            onSpeakFromHere: onSpeakFromHere
        )
        .frame(minHeight: 20)
    }
}
