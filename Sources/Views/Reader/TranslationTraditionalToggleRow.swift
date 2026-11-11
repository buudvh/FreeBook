import SwiftUI

/// Hàng công tắc "Phồn → giản" của popup dịch (1.3.845) — bản nháp + lưu ở `TranslationTraditionalDraft`. Phồn → giản là
/// bước riêng chạy **cả khi tắt dịch** (1.3.846) nên hàng này không bao giờ ẩn / khoá theo công tắc "Dịch văn bản".
struct TranslationTraditionalToggleRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 17)

            VStack(alignment: .leading, spacing: 1) {
                Text("Phồn → giản")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Chuyển chữ phồn thể sang giản thể, có dịch hay không")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.white)
        }
        .accessibilityElement(children: .combine)
    }
}
