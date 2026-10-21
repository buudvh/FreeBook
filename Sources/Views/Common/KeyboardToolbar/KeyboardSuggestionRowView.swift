import SwiftUI

/// Hàng gợi ý nằm **trên** thanh công cụ bàn phím, chỉ có ở ô cài `KeyboardSuggestionSource` (mockup đã duyệt
/// 2026-10-21): một dòng chip cuộn ngang, mỗi chip chỉ một dòng chữ để hàng thấp nhất có thể.
///
/// Cuộn ngang ở đây là cố ý: hàng nằm ngoài `Form` nên không dính bẫy lazy container của bảng token, và mép phải mờ dần
/// để báo còn chip phía sau — bài học 1.3.339 (chip bị cắt mà không có dấu hiệu nào nên tưởng app thiếu token).
struct KeyboardSuggestionRowView: View {
    /// Chiều cao cả hàng (kể cả lề), để `KeyboardTextToolbarInstaller` cộng vào chiều cao accessory.
    static let height: CGFloat = 36

    let suggestions: [KeyboardSuggestion]
    let onSelect: (KeyboardSuggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions) { suggestion in
                    chip(suggestion)
                }
            }
            .padding(.horizontal, 8)
        }
        // Danh sách đổi (lọc theo phần gõ dở) thì dựng lại ScrollView để về đầu hàng — giữ vị trí cuộn cũ có thể để
        // 3 chip vừa lọc nằm khuất bên trái. Chỉ đổi khi tập chip đổi, không phải mỗi phím gõ.
        .id(suggestions.map(\.text).joined(separator: " "))
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.9),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        // Cùng kiểu nền kính với thanh bên dưới (xem `KeyboardTextToolbarView`): bàn phím nổi iOS 26 để nền trong suốt.
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
    }

    private func chip(_ suggestion: KeyboardSuggestion) -> some View {
        Button {
            onSelect(suggestion)
        } label: {
            HStack(spacing: 3) {
                Text(suggestion.text)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                if suggestion.style == .used {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundColor(suggestion.style == .missing ? Color.red : Color.primary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule(style: .continuous).fill(background(for: suggestion.style)))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(suggestion.style == .missing ? Color.red.opacity(0.6) : .clear, lineWidth: 1)
            )
            .opacity(suggestion.style == .dimmed ? 0.45 : 1)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(suggestion.accessibilityLabel)
    }

    private func background(for style: KeyboardSuggestion.Style) -> Color {
        style == .missing ? Color.red.opacity(0.1) : Color(.tertiarySystemFill)
    }
}
