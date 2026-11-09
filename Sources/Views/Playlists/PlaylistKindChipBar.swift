import SwiftUI

/// Hàng chip chọn loại playlist ở tab Playlist của Kệ sách: **Tất cả · Nhạc · Video** (1.3.810 thêm "Tất cả", đứng đầu,
/// mặc định). Cùng kiểu chip đang chọn của `ExtensionKindFilterBar`: chữ màu nhấn, nền nhấn mờ 18%, viền nhấn 60%.
struct PlaylistKindChipBar: View {
    @Binding var selection: PlaylistKindFilter
    /// Số playlist mỗi chip — hiện cạnh nhãn khi > 0.
    let counts: [PlaylistKindFilter: Int]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PlaylistKindFilter.allCases) { filter in
                chip(filter)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func chip(_ filter: PlaylistKindFilter) -> some View {
        let isSelected = selection == filter
        let count = counts[filter] ?? 0
        let foreground: Color = isSelected ? .accentColor : .primary
        let fill: Color = isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground)
        let stroke: Color = isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12)
        return Button {
            guard selection != filter else { return }
            withAnimation(.easeInOut(duration: 0.18)) { selection = filter }
        } label: {
            HStack(spacing: 4) {
                if let symbol = filter.symbolName {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(count > 0 ? "\(filter.title) · \(count)" : filter.title)
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
        .accessibilityLabel(count > 0 ? "\(filter.title), \(count) playlist" : filter.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
