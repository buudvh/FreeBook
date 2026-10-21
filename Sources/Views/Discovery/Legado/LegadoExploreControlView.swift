import SwiftUI

/// Một **điều khiển** do nguồn Legado khai trong `exploreUrl` (spec §11.2): chọn (`select`, menu từ `chars`), bật/tắt
/// (`toggle`, bấm ⇒ phần tử kế), ô nhập + "Áp dụng" (`text`), nút (`button`). Giá trị gốc (`chars`, `value`) giữ nguyên
/// văn để ghi `infoMap`; chỉ nhãn hiển thị đi qua `display` (dịch khi bật dịch).
struct LegadoExploreControlView: View {
    let item: LegadoEngineExploreItem
    let isBusy: Bool
    /// Nội dung đang gõ của ô `text`.
    @Binding var draft: String
    let display: (String) -> String
    /// `select`/`toggle`: giá trị mới (nguyên văn).
    let onChange: (String) -> Void
    /// `text`: "Áp dụng".
    let onApply: () -> Void
    /// `button`: bấm.
    let onPress: () -> Void

    var body: some View {
        switch item.kind {
        case .select:
            selectControl
        case .toggle:
            toggleControl
        case .text:
            textControl
        case .button, .link:
            buttonControl
        }
    }

    private var selectControl: some View {
        Menu {
            ForEach(Array(item.chars.enumerated()), id: \.offset) { _, option in
                Button(action: {
                    guard option != item.value else { return }
                    onChange(option)
                }) {
                    if option == item.value {
                        Label(display(option), systemImage: "checkmark")
                    } else {
                        Text(display(option))
                    }
                }
            }
        } label: {
            capsule {
                HStack(spacing: 4) {
                    Text(display(item.label))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                    Text(display(item.value ?? ""))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(isBusy || item.chars.isEmpty)
    }

    private var toggleControl: some View {
        Button(action: { onChange(item.nextToggleValue) }) {
            capsule {
                HStack(spacing: 4) {
                    Text(display(item.label))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                    Text(display(item.value ?? ""))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
        }
        .disabled(isBusy)
    }

    private var textControl: some View {
        HStack(spacing: 6) {
            TextField(display(item.label), text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(onApply)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .frame(minHeight: 40)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            Button(action: onApply) {
                Text("Áp dụng")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(Color.accentColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isBusy)
        }
    }

    private var buttonControl: some View {
        Button(action: onPress) {
            capsule {
                HStack(spacing: 6) {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    }
                    Text(display(item.label))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .disabled(isBusy)
    }

    private func capsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.subheadline)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.45), lineWidth: 1))
    }
}
