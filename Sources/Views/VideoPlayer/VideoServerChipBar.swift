import SwiftUI

/// Hàng chip chọn server của tập đang xem (pill cao 38pt). Chọn server nào thì nhớ theo `title`
/// cho cả bộ phim (`VideoPlaybackSession.selectServer`).
struct VideoServerChipBar: View {
    let servers: [VideoServer]
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(servers.enumerated()), id: \.offset) { index, server in
                    chip(index: index, title: server.title)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(index: Int, title: String) -> some View {
        let isSelected = index == selectedIndex
        return Button {
            onSelect(index)
        } label: {
            Text(title.isEmpty ? "Server \(index + 1)" : title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
