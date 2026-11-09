import SwiftUI

/// Hàng chip chọn loại playlist ở tab Playlist của Kệ sách: **Nhạc · Video** (không có "Tất cả" — hai loại tách hẳn).
/// Cùng kiểu chip đang chọn của `ExtensionKindFilterBar`: chữ màu nhấn, nền nhấn mờ 18%, viền nhấn 60%.
struct PlaylistKindChipBar: View {
    @Binding var selection: PlaylistKind
    /// Số playlist mỗi loại — hiện cạnh nhãn khi > 0.
    let counts: [PlaylistKind: Int]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PlaylistKind.allCases) { kind in
                chip(kind)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func chip(_ kind: PlaylistKind) -> some View {
        let isSelected = selection == kind
        let count = counts[kind] ?? 0
        let foreground: Color = isSelected ? .accentColor : .primary
        let fill: Color = isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground)
        let stroke: Color = isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12)
        return Button {
            guard selection != kind else { return }
            withAnimation(.easeInOut(duration: 0.18)) { selection = kind }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                Text(count > 0 ? "\(kind.title) · \(count)" : kind.title)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundColor(foreground)
            .background(fill)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(kind.title), \(count) playlist" : kind.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
