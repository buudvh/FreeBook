import SwiftUI

/// Ô tìm chương dạng viên thuốc của panel Mục lục (`ChapterTOCPanelHeader`), chữ gợi ý "Tìm kiếm N chương".
struct ChapterTOCSearchField: View {
    @Binding var text: String
    let placeholder: String
    let palette: ChapterTOCPalette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(palette.secondaryText)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(palette.secondaryText))
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .foregroundColor(palette.text)
                .submitLabel(.search)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(palette.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xoá từ khoá")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(palette.fieldFill, in: Capsule())
        .padding(.trailing, 6) // lề phải panel hẹp hơn (chừa vùng chạm nút sắp xếp) ⇒ bù cho ô tìm cân hai bên
    }
}
