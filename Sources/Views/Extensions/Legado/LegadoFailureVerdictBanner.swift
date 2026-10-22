import SwiftUI

/// Dải "Kết luận: …" ở đầu màn Gỡ lỗi từng bước khi có bước rỗng/lỗi: icon + nhãn theo màu kết luận, một câu lý do.
/// Nền là màu kết luận **mờ** (không dùng màu nhấn làm nền đặc).
struct LegadoFailureVerdictBanner: View {
    let verdict: LegadoFailureVerdict
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: verdict.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(verdict.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("Kết luận: \(verdict.label)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(verdict.tint)
                if !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(verdict.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(verdict.tint.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
