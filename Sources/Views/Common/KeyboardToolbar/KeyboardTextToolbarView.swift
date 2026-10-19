import SwiftUI

/// Thanh công cụ trên bàn phím (mockup đã duyệt 2026-10-19), trái → phải:
/// **đóng bàn phím** · nhóm **`aa · Aa¹ · Aa² · Aa · AA`** (ẩn ở ô tìm kiếm / URL) · khoảng trống · **Xoá · Sao chép ·
/// Dán**. Ô trống ⇒ nhóm định dạng, Xoá, Sao chép mờ; Dán và đóng bàn phím luôn bấm được.
///
/// Nút đóng bàn phím là `Menu(primaryAction:)`: **chạm** = đóng bàn phím, **giữ** = menu chọn cách tắt khi chạm ra
/// ngoài ô nhập (cùng tuỳ chọn với Cài đặt → Bàn phím & ô nhập).
struct KeyboardTextToolbarView: View {
    @ObservedObject var model: KeyboardTextToolbarModel

    var body: some View {
        HStack(spacing: 8) {
            dismissButton

            if model.showsCaseGroup {
                caseGroup
            }

            Spacer(minLength: 4)

            circleButton(accessibility: "Xoá hết chữ trong ô", isDisabled: model.isEmpty, action: { model.clear() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
            }
            circleButton(accessibility: "Sao chép cả ô", isDisabled: model.isEmpty, action: { model.copy() }) {
                AppGlyph.copy.image(size: 15)
            }
            circleButton(accessibility: "Dán tại con trỏ", isDisabled: false, action: { model.paste() }) {
                AppGlyph.paste.image(size: 15)
            }
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
        // Nền riêng của thanh: bàn phím nổi kiểu mới (iOS 26) để nền `.keyboard` của `UIInputView` trong suốt ⇒ không
        // có nền này thì chữ của màn bên dưới lộ qua giữa các nút. Trên bàn phím kiểu cũ, viên kính nằm gọn trên dải
        // màu bàn phím nên vẫn khớp.
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
    }

    // MARK: - Nút đóng bàn phím

    private var dismissButton: some View {
        Menu {
            Section("Khi chạm ra ngoài ô nhập") {
                Button {
                    model.setTapOutsideDismisses(true)
                } label: {
                    optionLabel("Tự tắt bàn phím", isSelected: model.tapOutsideDismisses)
                }
                Button {
                    model.setTapOutsideDismisses(false)
                } label: {
                    optionLabel("Không tắt bàn phím", isSelected: !model.tapOutsideDismisses)
                }
            }
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        } primaryAction: {
            model.dismissKeyboard()
        }
        .accessibilityLabel("Đóng bàn phím")
        .accessibilityHint("Giữ để chọn có tự tắt bàn phím khi chạm ra ngoài ô nhập hay không")
    }

    @ViewBuilder
    private func optionLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    // MARK: - aa · Aa¹ · Aa² · Aa · AA

    private var caseGroup: some View {
        HStack(spacing: 0) {
            ForEach(Array(TextCaseFormatter.styles.enumerated()), id: \.offset) { index, style in
                if index > 0 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 0.5, height: 16)
                }
                Button {
                    model.applyCase(style)
                } label: {
                    Text(style)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 7)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Định dạng chữ \(style)")
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemFill)))
        .disabled(model.isEmpty)
        .opacity(model.isEmpty ? 0.35 : 1)
    }

    // MARK: - Nút tròn

    private func circleButton<Content: View>(
        accessibility: String,
        isDisabled: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .accessibilityLabel(accessibility)
    }
}
