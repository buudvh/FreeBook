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
    let isFlipped: Bool
    let fontSize: Double
    let lineSpacing: Double
    let theme: ReaderTheme
    let onTap: () -> Void
    let onSelectionChange: (String, String, Int, Int) -> Void
    let onSpeakFromHere: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ReaderTextView hiển thị nội dung tùy theo mặt thẻ đang lật
            ReaderTextView(
                text: isFlipped ? item.original : item.translated,
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                theme: theme,
                highlightRange: nil,
                triggerGetVisibleIndex: .constant(nil),
                onGetVisibleIndex: { _ in },
                onSelectionChange: onSelectionChange,
                onSpeakFromHere: onSpeakFromHere
            )
            .frame(minHeight: 30)
            
            // Thanh trạng thái dưới cùng của thẻ
            HStack {
                Text(isFlipped ? "Chữ gốc" : "Bản dịch")
                    .font(.caption2)
                    .foregroundColor(theme.textColor.opacity(0.4))
                Spacer()
                Button(action: onTap) {
                    Label(isFlipped ? "Xem dịch" : "Xem gốc", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(theme.textColor.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.textColor.opacity(0.12), lineWidth: 1)
        )
    }
}
