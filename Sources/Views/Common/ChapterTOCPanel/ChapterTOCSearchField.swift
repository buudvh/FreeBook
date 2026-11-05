import SwiftUI

/// Ô tìm chương dạng viên thuốc của panel Mục lục (`ChapterTOCPanelHeader`), chữ gợi ý "Tìm kiếm N chương". Dùng lại
/// cho ô tìm của tab nhãn Khám phá, ngăn kéo chọn nguồn, màn Tìm kiếm và danh sách chương của sheet Hẹn giờ TTS
/// (`onSubmit` = phím Tìm trên bàn phím, `onClear` = sau khi bấm ⓧ xoá chữ, `focus` = nơi dùng tự bật bàn phím).
struct ChapterTOCSearchField: View {
    @Binding var text: String
    let placeholder: String
    let palette: ChapterTOCPalette
    var onSubmit: (() -> Void)? = nil
    var onClear: (() -> Void)? = nil
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(palette.secondaryText)
            focusedField
            if !text.isEmpty {
                Button(action: {
                    text = ""
                    onClear?()
                }) {
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

    @ViewBuilder
    private var focusedField: some View {
        if let focus {
            field.focused(focus)
        } else {
            field
        }
    }

    private var field: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(palette.secondaryText))
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled() // từ khoá tên chương / tiện ích / nguồn, không phải câu văn
            .foregroundColor(palette.text)
            .submitLabel(.search)
            .onSubmit { onSubmit?() }
    }
}
