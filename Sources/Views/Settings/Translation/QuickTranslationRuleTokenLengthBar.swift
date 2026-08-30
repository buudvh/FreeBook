import SwiftUI

/// Thanh điều chỉnh khoảng độ dài của **token đang chọn** trong mẫu: `[−] tối thiểu [+]` và
/// `[−] tối đa [+]`, bước 1, kèm công tắc `?` (token vắng mặt vẫn khớp).
///
/// Mọi biên đều lấy từ parser chứ không tự đặt: `min ≥ 1` là điều kiện cứng (sai thì
/// `UNKNOWN_TOKEN_NAME`, lỗi hard), `max ≥ min`, và token không khai `:min-max` nghĩa là `1...12` —
/// nên khi hai đầu về đúng mặc định, `TokenSpec.syntax` tự xuất lại token trần thay vì viết thừa
/// `:1-12`. Nhờ vậy không có đường bấm nào tạo ra được token sai cú pháp.
struct QuickTranslationRuleTokenLengthBar: View {
    typealias TokenSpec = QuickTranslationRuleDraftAnalyzer.TokenSpec

    let spec: TokenSpec
    let onChange: (TokenSpec) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(spec.syntax)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.16))
                    .cornerRadius(6)

                Spacer(minLength: 0)

                optionalToggle
            }

            if spec.supportsLengthRange {
                HStack(spacing: 12) {
                    stepper(
                        title: "Tối thiểu",
                        value: spec.minLength,
                        canDecrease: spec.minLength > 1,
                        canIncrease: spec.minLength < TokenSpec.adjustableUpperBound
                    ) { delta in
                        adjust { $0.minLength += delta }
                    }

                    Divider().frame(height: 26)

                    stepper(
                        title: "Tối đa",
                        value: spec.maxLength,
                        canDecrease: spec.maxLength > spec.minLength,
                        canIncrease: spec.maxLength < TokenSpec.adjustableUpperBound
                    ) { delta in
                        adjust { $0.maxLength += delta }
                    }
                }

                if spec.isDefaultRange {
                    Text("Đang là mặc định \(TokenSpec.defaultMinLength)–\(TokenSpec.defaultMaxLength) ký tự, nên mẫu ghi token trần.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Token này luôn nuốt **đúng 1 ký tự**, không nhận khoảng độ dài.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var optionalToggle: some View {
        Button {
            adjust { $0.isOptional.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: spec.isOptional ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                Text("? vắng mặt được")
                    .font(.caption2)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spec.isOptional ? "Bỏ dấu ? của token" : "Cho token vắng mặt vẫn khớp")
    }

    private func stepper(
        title: String,
        value: Int,
        canDecrease: Bool,
        canIncrease: Bool,
        onStep: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                stepButton("minus", isEnabled: canDecrease) { onStep(-1) }

                Text("\(value)")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 22)

                stepButton("plus", isEnabled: canIncrease) { onStep(1) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(value)")
    }

    private func stepButton(_ icon: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(isEnabled ? 0.14 : 0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func adjust(_ transform: (inout TokenSpec) -> Void) {
        var updated = spec
        transform(&updated)
        updated.clamp()
        guard updated != spec else { return }
        onChange(updated)
    }
}
