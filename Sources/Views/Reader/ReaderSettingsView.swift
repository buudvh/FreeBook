import SwiftUI

struct ReaderSettingsView: View {
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var selectedTheme: ReaderTheme
    @Binding var isTranslationEnabled: Bool

    var body: some View {
        VStack(spacing: 20) {
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

            Picker("Theme", selection: $selectedTheme) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }

            Toggle("Bật dịch Quick Translate", isOn: $isTranslationEnabled)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
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
