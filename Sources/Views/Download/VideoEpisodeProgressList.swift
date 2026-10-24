import SwiftUI

/// Mục "Chi tiết tập (N)" trong dòng tác vụ tải video ở tab Tải (`DownloadTrackerView`): bấm mở/thu danh sách từng tập
/// kèm trạng thái — "✓ Xong · 480 MB", "✓ Có sẵn", "↓ 45% · 210 MB", "Chờ", "✕ Lỗi: …", "Đã huỷ".
///
/// Danh sách dài (> `fullListLimit` tập) chỉ hiện phần đáng xem — mọi tập lỗi (tối đa 50), 10 tập xong gần nhất, tập đang
/// tải, 5 tập chờ kế tiếp — cộng dòng đếm, để dòng tác vụ không dựng lại hàng trăm hàng mỗi nhịp tiến độ.
/// Nút mở/thu dùng `.borderless`: dòng `List` còn nút huỷ / thử lại riêng.
struct VideoEpisodeProgressList: View {
    let episodes: [VideoEpisodeProgress]

    @State private var isExpanded = false

    private static let fullListLimit = 60
    private static let maxFailedShown = 50
    private static let recentFinishedShown = 10
    private static let nextWaitingShown = 5

    private enum Category {
        case waiting
        case active
        case finished
        case failed
        case cancelled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                    Text("Chi tiết tập (\(episodes.count))")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if isExpanded {
                let visible = visibleEpisodes
                if episodes.count > Self.fullListLimit {
                    Text(countsText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                ForEach(visible) { episode in
                    row(episode)
                }
                if visible.count < episodes.count {
                    Text("… và \(episodes.count - visible.count) tập khác")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Hàng

    private func row(_ episode: VideoEpisodeProgress) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(episode.displayTitle)
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(Self.statusText(episode.state))
                .foregroundColor(Self.statusColor(episode.state))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.caption2)
    }

    private static func statusText(_ state: VideoEpisodeProgress.State) -> String {
        switch state {
        case .waiting:
            return "Chờ"
        case .downloading(let fraction, let bytes):
            let percent = Int((min(1, max(0, fraction)) * 100).rounded())
            return "↓ \(percent)% · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        case .done(let bytes):
            return "✓ Xong · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        case .alreadyDownloaded:
            return "✓ Có sẵn"
        case .failed(let message):
            return "✕ Lỗi: \(message)"
        case .cancelled:
            return "Đã huỷ"
        }
    }

    private static func statusColor(_ state: VideoEpisodeProgress.State) -> Color {
        switch category(state) {
        case .finished: return .green
        case .active: return .primary
        case .failed: return .red
        case .waiting, .cancelled: return .secondary
        }
    }

    // MARK: - Lọc danh sách dài

    private static func category(_ state: VideoEpisodeProgress.State) -> Category {
        switch state {
        case .waiting: return .waiting
        case .downloading: return .active
        case .done, .alreadyDownloaded: return .finished
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }

    /// Đủ ngắn thì hiện hết; dài thì chỉ giữ phần đáng xem, vẫn theo thứ tự mục lục.
    private var visibleEpisodes: [VideoEpisodeProgress] {
        guard episodes.count > Self.fullListLimit else { return episodes }
        var keep = Set<Int>()
        let failed = episodes.filter { Self.category($0.state) == .failed }.prefix(Self.maxFailedShown)
        let finished = episodes.filter { Self.category($0.state) == .finished }.suffix(Self.recentFinishedShown)
        let active = episodes.filter { Self.category($0.state) == .active }
        let waiting = episodes.filter { Self.category($0.state) == .waiting }.prefix(Self.nextWaitingShown)
        for episode in failed { keep.insert(episode.index) }
        for episode in finished { keep.insert(episode.index) }
        for episode in active { keep.insert(episode.index) }
        for episode in waiting { keep.insert(episode.index) }
        return episodes.filter { keep.contains($0.index) }
    }

    /// "Xong 120 · Lỗi 2 · Chờ 38" (+ "Đang tải 1", "Đã huỷ N" khi có).
    private var countsText: String {
        var counts: [Category: Int] = [:]
        for episode in episodes {
            counts[Self.category(episode.state), default: 0] += 1
        }
        var parts = ["Xong \(counts[.finished] ?? 0)"]
        if let active = counts[.active], active > 0 { parts.append("Đang tải \(active)") }
        parts.append("Lỗi \(counts[.failed] ?? 0)")
        parts.append("Chờ \(counts[.waiting] ?? 0)")
        if let cancelled = counts[.cancelled], cancelled > 0 { parts.append("Đã huỷ \(cancelled)") }
        return parts.joined(separator: " · ")
    }
}
