import SwiftUI

/// Nút dấu hỏi cạnh tiêu đề section: bấm mở popover chứa đoạn giải thích — thay cho footer luôn hiện của section.
/// Dùng chung cho mọi màn; header chỉ có tiêu đề + nút thì dùng `SectionHelpHeader`.
///
/// - `paragraphs: [LocalizedStringKey]` giữ `**đậm**` và `` `token` `` như footer cũ. Chuỗi động (biến `String`) phải
///   đi qua `texts:` với `Text(chuỗi)` để vẫn vẽ nguyên văn — bọc vào `LocalizedStringKey` là bắt đầu đọc markdown.
/// - Nằm trong `header:` của `Section` thuộc `Form`, nên dùng `.buttonStyle(.borderless)` để bấm được riêng nút.
/// - Popover thừa hưởng environment của header (chữ hoa, font footnote, màu phụ) ⇒ nội dung đặt lại tường minh
///   `.textCase(nil)`, font và màu.
/// - `.presentationCompactAdaptation(.popover)`: iPhone vẫn hiện bong bóng nổi thay vì tự đổi thành sheet; chạm ra
///   ngoài là đóng.
/// - Cao theo nội dung, tối đa `maxHeight`; dài hơn thì `ViewThatFits` chọn bản cuộn.
struct SectionHelpButton: View {
    let accessibilityLabel: String
    let texts: [Text]

    @State private var isPresented = false

    private static let width: CGFloat = 300
    private static let maxHeight: CGFloat = 320

    init(accessibilityLabel: String, paragraphs: [LocalizedStringKey]) {
        self.accessibilityLabel = accessibilityLabel
        self.texts = paragraphs.map { Text($0) }
    }

    init(accessibilityLabel: String, texts: [Text]) {
        self.accessibilityLabel = accessibilityLabel
        self.texts = texts
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
                // Glyph theo cỡ chữ header, vùng chạm rộng hơn để dễ bấm.
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ViewThatFits(in: .vertical) {
                helpContent
                ScrollView {
                    helpContent
                }
            }
            .frame(width: Self.width)
            .frame(maxHeight: Self.maxHeight)
            .textCase(nil)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                text
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }
}
