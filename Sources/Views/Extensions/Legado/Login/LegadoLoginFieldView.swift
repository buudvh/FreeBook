import SwiftUI

/// Một ô của form đăng nhập dựng từ `loginUi` (spec §10.3): ô nhập (`text`/`password`), chọn (`select`, menu từ
/// `chars`), bật/tắt (`toggle`, bấm ⇒ phần tử kế của `chars`), nút (`button`, chạy `action`), nhãn tĩnh (`title`).
///
/// Giá trị giữ ở màn cha (`value` binding, khoá = `field.name`); đổi `select`/`toggle` và bấm nút báo lên qua
/// `onCommit` để màn cha chạy `action` của nguồn. Nhãn là `viewName` đã được engine đánh giá.
struct LegadoLoginFieldView: View {
    let field: LegadoLoginField
    @Binding var value: String
    let isBusy: Bool
    /// Người dùng đổi `select`/`toggle` (giá trị mới đã ghi vào `value`) hoặc bấm `button`.
    let onCommit: () -> Void

    var body: some View {
        switch field.kind {
        case .title:
            Text(field.label)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        case .text, .password:
            inputField
        case .select:
            selectField
        case .toggle:
            toggleField
        case .button:
            actionButton
        }
    }

    // MARK: - Ô nhập

    private var inputField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Group {
                if field.kind == .password {
                    SecureField(placeholder, text: $value)
                } else {
                    TextField(placeholder, text: $value)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var placeholder: String {
        let hint = field.hint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return hint.isEmpty ? field.label : hint
    }

    // MARK: - Chọn / bật tắt

    private var selectField: some View {
        Menu {
            ForEach(Array(field.chars.enumerated()), id: \.offset) { _, option in
                Button(action: {
                    guard option != value else { return }
                    value = option
                    onCommit()
                }) {
                    if option == value {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            controlLabel(trailing: value, systemImage: "chevron.up.chevron.down")
        }
        .disabled(isBusy || field.chars.isEmpty)
    }

    private var toggleField: some View {
        Button(action: {
            value = field.toggledValue(after: value)
            onCommit()
        }) {
            controlLabel(trailing: value, systemImage: nil)
        }
        .disabled(isBusy)
    }

    private func controlLabel(trailing: String, systemImage: String?) -> some View {
        HStack(spacing: 6) {
            Text(field.label)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Text(trailing)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.accentColor)
                .lineLimit(1)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Nút của nguồn

    private var actionButton: some View {
        Button(action: onCommit) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else if field.actionURL != nil {
                    Image(systemName: "safari")
                        .font(.footnote.weight(.semibold))
                }
                Text(field.label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        .disabled(isBusy)
    }
}

private extension LegadoLoginField {
    /// Giá trị kế của `toggle` tính từ giá trị **đang hiện** trên form (có thể đã khác `value` lúc dựng form).
    func toggledValue(after current: String) -> String {
        guard !chars.isEmpty else { return current }
        guard let index = chars.firstIndex(of: current) else { return chars[0] }
        return chars[(index + 1) % chars.count]
    }
}
