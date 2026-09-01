import SwiftUI

/// Thanh điều chỉnh khoảng độ dài của **token đang chọn** trong mẫu: mỗi đầu một hàng
/// `[−] thanh-kéo giá trị [+]`, bước 1, kèm công tắc `?` (token vắng mặt vẫn khớp).
///
/// Thanh kéo và hai nút `+/−` là **hai lối vào cùng một cửa** (`adjust`): nút cho một bước chính xác,
/// thanh kéo cho lượt nhảy xa. Không lối nào tự kẹp biên — `TokenSpec.clamp()` làm việc đó.
///
/// Mọi biên đều lấy từ parser chứ không tự đặt: `min ≥ 1` là điều kiện cứng (sai thì
/// `UNKNOWN_TOKEN_NAME`, lỗi hard), `max ≥ min`, và token không khai `:min-max` nghĩa là `1...12` —
/// nên khi hai đầu về đúng mặc định, `TokenSpec.syntax` tự xuất lại token trần thay vì viết thừa
/// `:1-12`. Nhờ vậy không có đường bấm hay kéo nào tạo ra được token sai cú pháp.
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
                VStack(spacing: 6) {
                    lengthRow(
                        title: "Tối thiểu",
                        value: spec.minLength,
                        canDecrease: spec.minLength > 1,
                        canIncrease: spec.minLength < TokenSpec.adjustableUpperBound,
                        onStep: { delta in adjust { $0.minLength += delta } },
                        onSlide: { newValue in adjust { $0.minLength = newValue } }
                    )

                    lengthRow(
                        title: "Tối đa",
                        value: spec.maxLength,
                        canDecrease: spec.maxLength > spec.minLength,
                        canIncrease: spec.maxLength < TokenSpec.adjustableUpperBound,
                        onStep: { delta in adjust { $0.maxLength += delta } },
                        onSlide: { newValue in adjust { $0.maxLength = newValue } }
                    )
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

    /// `[−] ──o── giá trị [+]`. Thanh kéo và hai nút đi qua **cùng một** `adjust`, nên `clamp()` là chỗ
    /// duy nhất quyết định vùng hợp lệ: kéo `Tối đa` xuống dưới `Tối thiểu` thì nó dừng ở `Tối thiểu`
    /// thay vì tạo ra một khoảng ngược.
    private func lengthRow(
        title: String,
        value: Int,
        canDecrease: Bool,
        canIncrease: Bool,
        onStep: @escaping (Int) -> Void,
        onSlide: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(width: 52, alignment: .leading)

            stepButton("minus", isEnabled: canDecrease) { onStep(-1) }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onSlide(Int($0.rounded())) }
                ),
                in: 1...Double(TokenSpec.adjustableUpperBound),
                step: 1
            )

            Text("\(value)")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .frame(minWidth: 22, alignment: .trailing)

            stepButton("plus", isEnabled: canIncrease) { onStep(1) }
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
