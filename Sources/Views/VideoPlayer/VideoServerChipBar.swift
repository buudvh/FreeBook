import SwiftUI

/// Hàng chip chọn server của tập đang xem (pill cao 38pt). Chọn server nào thì nhớ theo `title`
/// cho cả bộ phim (`VideoPlaybackSession.selectServer`).
///
/// Tập có bản tải (`offline`) ⇒ chip "Bản tải" đứng đầu; khi đang phát bản tải (chưa nạp server) có thêm chip
/// "Trực tuyến" — chạm mới nạp danh sách server (`VideoPlaybackSession+Offline`).
struct VideoServerChipBar: View {
    struct OfflineChips {
        let isSelected: Bool
        let onSelectOffline: () -> Void
        let onSelectOnline: () -> Void
    }

    let servers: [VideoServer]
    let selectedIndex: Int?
    var offline: OfflineChips? = nil
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let offline {
                    chip(title: "Bản tải", systemImage: "arrow.down.circle.fill", isSelected: offline.isSelected, action: offline.onSelectOffline)
                    if servers.isEmpty {
                        chip(title: "Trực tuyến", systemImage: nil, isSelected: false, action: offline.onSelectOnline)
                    }
                }
                ForEach(Array(servers.enumerated()), id: \.offset) { index, server in
                    chip(
                        title: server.title.isEmpty ? "Server \(index + 1)" : server.title,
                        systemImage: nil,
                        isSelected: index == selectedIndex
                    ) {
                        onSelect(index)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(title: String, systemImage: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
