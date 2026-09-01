import SwiftUI

struct ReaderSettingsView: View {
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var fontFamily: ReaderFontFamily
    @Binding var selectedTheme: ReaderTheme
    @Binding var isTranslationEnabled: Bool
    @Binding var isPronounsEnabled: Bool
    @Binding var isLuatNhanEnabled: Bool
    @Binding var shouldConvertTraditionalToSimplified: Bool
    @Binding var showChapterTitle: Bool
    @Binding var removeDuplicatedTitle: Bool

    /// Hai công tắc tiêu đề chương không tự đủ: `ReaderViewModel` đọc cờ từ UserDefaults theo từng
    /// truyện lúc dựng `[ParagraphItem]`, nên đổi binding thôi thì màn hình không đổi gì. `ReaderView`
    /// sở hữu việc lưu theo `bookId` + dựng lại đoạn và nhận giá trị mới qua hai closure này.
    let onShowChapterTitleChanged: (Bool) -> Void
    let onRemoveDuplicatedTitleChanged: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Cài đặt trình đọc")
                    .font(.headline)
                    .padding(.top)

                HStack(spacing: 40) {
                    valueStepper(
                        title: "Cỡ chữ",
                        value: $fontSize,
                        range: 12...36
                    )
                    valueStepper(
                        title: "Giãn dòng",
                        value: $lineSpacing,
                        range: 2...20
                    )
                }

                fontFamilyRow

                Picker("Theme", selection: $selectedTheme) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }

                Toggle("Bật dịch Quick Translate", isOn: $isTranslationEnabled)
                    .padding(.horizontal)

                if isTranslationEnabled {
                    translationOptions
                }

                chapterTitleOptions
            }
            .padding()
        }
        .presentationDragIndicator(.visible)
    }

    /// Nhãn của `Picker` kiểu `.menu` do hệ thống dựng nên không chắc nhận `lineLimit`; tên phông
    /// dài nhất ("Tống Thể - 宋体 (Hán Tự Cổ Điển)") vì thế hay xuống hai dòng và đẩy hàng cao lên.
    /// Dùng `Menu` với nhãn tự dựng để giữ đúng một dòng, phần tràn cắt ở cuối.
    private var fontFamilyRow: some View {
        HStack {
            Text("Kiểu chữ:")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize()

            Spacer(minLength: 8)

            Menu {
                Picker("Kiểu chữ", selection: $fontFamily) {
                    ForEach(ReaderFontFamily.allCases) { family in
                        Text(family.rawValue).tag(family)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(fontFamily.rawValue)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
            }
            .accessibilityLabel("Kiểu chữ, \(fontFamily.rawValue)")
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var translationOptions: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Văn bản trước khi dịch:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("Văn bản trước khi dịch", selection: $shouldConvertTraditionalToSimplified) {
                    Text("Giữ nguyên").tag(false)
                    Text("Phồn thể → giản thể").tag(true)
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            .padding(.leading, 12)

            Toggle("Bật dịch Đại từ (Pronouns)", isOn: $isPronounsEnabled)
                .font(.subheadline)
                .padding(.horizontal)
                .padding(.leading, 12)

            Toggle("Bật dịch Luật nhân hóa", isOn: $isLuatNhanEnabled)
                .font(.subheadline)
                .padding(.horizontal)
                .padding(.leading, 12)
        }
    }

    @ViewBuilder
    private var chapterTitleOptions: some View {
        VStack(spacing: 16) {
            Toggle("Hiển thị tên chương trong nội dung", isOn: Binding(
                get: { showChapterTitle },
                set: { newValue in
                    showChapterTitle = newValue
                    onShowChapterTitleChanged(newValue)
                }
            ))
            .padding(.horizontal)

            Toggle("Loại bỏ tiêu đề chương trùng trong nội dung", isOn: Binding(
                get: { removeDuplicatedTitle },
                set: { newValue in
                    removeDuplicatedTitle = newValue
                    onRemoveDuplicatedTitleChanged(newValue)
                }
            ))
            .padding(.horizontal)
        }
    }

    private func valueStepper(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                } label: {
                    Image(systemName: "minus.circle")
                        .padding(6)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Text("\(Int(value.wrappedValue))")
                    .font(.body)
                    .frame(width: 30)

                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                } label: {
                    Image(systemName: "plus.circle")
                        .padding(6)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}
