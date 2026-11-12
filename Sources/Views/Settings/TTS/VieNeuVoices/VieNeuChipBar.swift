import SwiftUI

/// Hàng chip chọn **một** mục (1.3.900): "Nano | Turbo" ở sheet chọn giọng, "Nano | Turbo | Cả hai" ở sheet nhân bản. Kiểu
/// chip như `ExtensionKindFilterBar`: đang chọn = chữ màu nhấn, nền nhấn ~18 %, viền ~60 %.
struct VieNeuChipBar<Option: Hashable>: View {
    let options: [(value: Option, title: String)]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                chip(option.title, isSelected: option.value == selection) {
                    selection = option.value
                }
            }
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundColor(isSelected ? .accentColor : .primary)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
