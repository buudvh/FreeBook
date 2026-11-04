import SwiftUI

/// Phần "Giới hạn giá trị" dưới thanh độ dài của token số đang chọn (1.3.701): công tắc + hai hàng `[−] ô số [+]`
/// cho `#min-max` của `<n>` `<y>` `<h>` `<d>` `<hn>`. Tắt công tắc = bỏ hẳn `#…` khỏi mẫu.
///
/// Không dùng thanh kéo như độ dài: khoảng giá trị có thể là 1–9999, kéo không chính xác. Ô số giữ chữ đang gõ ở
/// `@State` và chỉ ghi ra ngoài **khi rời ô** (hoặc bấm −/+) — ghi theo từng phím thì `TokenSpec.clamp()` kẹp con số
/// gõ dở (đang gõ `15` khi Từ = 10 ⇒ chữ `1` bị kẹp lên 10) và ô nhảy số dưới tay. Ô Đến để trống = không chặn trên
/// (`#100-`). Biên hợp lệ lấy từ `QuickTranslationRuleValueRange.clamped()` — cùng chỗ kẹp với `TokenSpec.clamp()`.
struct QuickTranslationRuleTokenValueRangeEditor: View {
    let range: QuickTranslationRuleValueRange?
    let onChange: (QuickTranslationRuleValueRange?) -> Void

    /// Bật công tắc lần đầu ⇒ 1–100: thấy tác dụng ngay, sửa tiếp bằng ô số.
    static let defaultRange = QuickTranslationRuleValueRange(lowerBound: 1, upperBound: 100)

    private enum Field: Hashable {
        case lower
        case upper
    }

    @FocusState private var focusedField: Field?
    @State private var lowerText = ""
    @State private var upperText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { range != nil },
                set: { onChange($0 ? (range ?? Self.defaultRange) : nil) }
            )) {
                Text("Giới hạn giá trị")
                    .font(.caption.weight(.semibold))
            }

            if let range {
                valueRow(title: "Từ", field: .lower, text: $lowerText, placeholder: "0", canDecrease: range.lowerBound > 0)
                valueRow(title: "Đến", field: .upper, text: $upperText, placeholder: "∞", canDecrease: range.upperBound != nil)

                Text(caption(for: range))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { show(range) }
        // Khoảng chỉ đổi khi chính view này ghi ra (đang gõ thì chưa ghi) — chọn token khác là view mới (`.id`).
        .onChange(of: range) { _, newValue in show(newValue) }
        .onChange(of: focusedField) { oldValue, _ in
            if let oldValue { commit(oldValue) }
        }
    }

    // MARK: - Hàng `[−] ô số [+]`

    private func valueRow(
        title: String,
        field: Field,
        text: Binding<String>,
        placeholder: String,
        canDecrease: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(width: 52, alignment: .leading)

            stepButton("minus", isEnabled: canDecrease) { step(field, by: -1) }

            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .focused($focusedField, equals: field)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12))
                .cornerRadius(8)

            stepButton("plus", isEnabled: true) { step(field, by: 1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(text.wrappedValue.isEmpty ? "không giới hạn" : text.wrappedValue)")
    }

    private func stepButton(_ icon: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(isEnabled ? 0.18 : 0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    // MARK: - Ghi ra ngoài

    /// −/+ tính từ chữ **đang** nằm trong ô (có thể chưa ghi), để bấm khi còn đang gõ không quay về số cũ. Ô Đến
    /// đang trống mà bấm + thì bắt đầu từ số của ô Từ; bấm − ở số Đến bằng số Từ thì `clamp()` giữ nguyên.
    private func step(_ field: Field, by delta: Int) {
        guard let range else { return }
        switch field {
        case .lower:
            let current = Int(lowerText) ?? range.lowerBound
            lowerText = String(Self.bump(current, by: delta))
        case .upper:
            let current = Int(upperText) ?? range.upperBound ?? Int(lowerText) ?? range.lowerBound
            upperText = String(Self.bump(current, by: delta))
        }
        commit(field)
    }

    /// `+1`/`−1` không bao giờ tràn `Int` (ô số gõ được tới `Int.max`) và không xuống dưới 0.
    private static func bump(_ value: Int, by delta: Int) -> Int {
        let (next, overflow) = value.addingReportingOverflow(delta)
        return overflow ? value : max(0, next)
    }

    /// Ô Từ không đọc được số ⇒ giữ số cũ; ô Đến trống ⇒ không chặn trên, chữ lạ ⇒ giữ số cũ. Ô luôn được đưa về
    /// đúng khoảng sau khi kẹp — kể cả khi kẹp xong trùng khoảng cũ và bên ngoài không có gì để dựng lại.
    private func commit(_ field: Field) {
        guard var updated = range else { return }
        switch field {
        case .lower:
            if let value = Int(lowerText.trimmingCharacters(in: .whitespaces)) { updated.lowerBound = value }
        case .upper:
            let text = upperText.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                updated.upperBound = nil
            } else if let value = Int(text) {
                updated.upperBound = value
            }
        }
        let normalized = updated.clamped()
        show(normalized)
        if normalized != range { onChange(normalized) }
    }

    private func show(_ range: QuickTranslationRuleValueRange?) {
        lowerText = range.map { String($0.lowerBound) } ?? ""
        upperText = range?.upperBound.map(String.init) ?? ""
    }

    private func caption(for range: QuickTranslationRuleValueRange) -> String {
        guard let upper = range.upperBound else {
            return "Chỉ khớp số từ \(range.lowerBound) trở lên (để trống ô Đến)."
        }
        if upper == range.lowerBound {
            return "Chỉ khớp đúng số \(upper)."
        }
        return "Chỉ khớp số từ \(range.lowerBound) đến \(upper); số ngoài khoảng thì rule bỏ qua."
    }
}
