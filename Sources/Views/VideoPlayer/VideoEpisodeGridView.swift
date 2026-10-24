import SwiftUI

/// Lưới tập phim **chia tab theo section**: mỗi dòng `type: "section"` của `toc` (extension nhiều server) là một tab
/// ("Vietsub", "Thuyết minh"…). Chọn tab nào thì lưới hiện đúng bộ tập của nhóm đó, số tập đánh lại từ 1.
///
/// Dùng chung cho panel toàn màn (`VideoEpisodePanel`) và màn dọc (`VideoPlayerDetailsView`); trước đây hai chỗ này
/// vẽ tiêu đề nhóm chen giữa lưới nên phải cuộn qua cả bộ tập của nhóm khác. Ô giữ `.id(episode.index)` để màn cha
/// vẫn `scrollTo` tới tập đang phát được.
///
/// Hợp đồng: chỉ đọc `episodes` + `currentIndex`, mọi thao tác đi qua `onSelect` — đổi tab **không** đổi tập đang phát.
/// Nhấn giữ ô tập (khi có `downloadActions`) ⇒ "Tải tập này" / "Xoá bản tải".
struct VideoEpisodeGridView: View {
    let episodes: [VideoPlaybackSession.Episode]
    let currentIndex: Int
    let onSelect: (VideoPlaybackSession.Episode) -> Void
    let downloadActions: VideoEpisodeDownloadActions?

    @State private var selectedGroup: Int

    private struct SectionTab: Identifiable {
        let id: Int
        let title: String
        let episodes: [VideoPlaybackSession.Episode]

        /// Nhóm đứng trước section đầu tiên không có tên.
        var label: String { title.isEmpty ? "Tập" : title }
    }

    /// Tối đa chừng này tab thì chia đều bề ngang; nhiều hơn thì cho cuộn ngang để tên không bị cắt.
    private static let maxEvenTabs = 3
    private static let cellHeight: CGFloat = 46

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 4)

    init(
        episodes: [VideoPlaybackSession.Episode],
        currentIndex: Int,
        downloadActions: VideoEpisodeDownloadActions? = nil,
        onSelect: @escaping (VideoPlaybackSession.Episode) -> Void
    ) {
        self.episodes = episodes
        self.currentIndex = currentIndex
        self.onSelect = onSelect
        self.downloadActions = downloadActions
        // Mở đúng tab chứa tập đang phát ngay từ lần vẽ đầu, để `scrollTo` của màn cha tìm thấy ô.
        let initial = Self.makeGroups(episodes).firstIndex { group in
            group.episodes.contains { $0.index == currentIndex }
        } ?? 0
        _selectedGroup = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if groups.count > 1 {
                tabs
            }

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(Array(activeEpisodes.enumerated()), id: \.element.id) { offset, episode in
                    cellWithMenu(episode, number: offset + 1)
                        .id(episode.index)
                }
            }
        }
        .padding(.horizontal, 16)
        .onAppear(perform: syncGroupToCurrent)
        .onChange(of: currentIndex) { _, _ in syncGroupToCurrent() }
        .onChange(of: episodes) { _, _ in syncGroupToCurrent() }
    }

    // MARK: - Tab

    @ViewBuilder
    private var tabs: some View {
        if groups.count <= Self.maxEvenTabs {
            HStack(spacing: 4) {
                ForEach(groups) { group in
                    tab(group, fillsWidth: true)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(groups) { group in
                        tab(group, fillsWidth: false)
                    }
                }
            }
        }
    }

    private func tab(_ group: SectionTab, fillsWidth: Bool) -> some View {
        let isSelected = group.id == selectedGroup
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedGroup = group.id }
        } label: {
            HStack(spacing: 6) {
                Text(group.label)
                    .lineLimit(1)
                Text("\(group.episodes.count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .opacity(0.55)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.72))
            .padding(.horizontal, 12)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.label), \(group.episodes.count) tập")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Ô tập

    @ViewBuilder
    private func cellWithMenu(_ episode: VideoPlaybackSession.Episode, number: Int) -> some View {
        if let actions = downloadActions {
            cell(episode, number: number)
                .contextMenu {
                    if actions.isDownloaded(episode) {
                        Button(role: .destructive) {
                            actions.deleteDownload(episode)
                        } label: {
                            Label("Xoá bản tải", systemImage: "trash")
                        }
                    } else {
                        Button {
                            actions.download(episode)
                        } label: {
                            Label("Tải tập này", systemImage: "arrow.down.circle")
                        }
                    }
                }
        } else {
            cell(episode, number: number)
        }
    }

    private func cell(_ episode: VideoPlaybackSession.Episode, number: Int) -> some View {
        let isCurrent = episode.index == currentIndex
        let isWatched = currentIndex >= 0 && episode.index < currentIndex

        return Button {
            onSelect(episode)
        } label: {
            Text("\(number)")
                .font(.system(size: 14, weight: isCurrent ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Color.black : Color.white.opacity(isWatched ? 0.36 : 1))
                .frame(maxWidth: .infinity)
                .frame(height: Self.cellHeight)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isCurrent ? Color.white : Color.white.opacity(isWatched ? 0.04 : 0.07))
                )
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tập \(number): \(episode.displayTitle)")
        .accessibilityValue(isCurrent ? "Đang phát" : "")
    }

    // MARK: - Dữ liệu dẫn xuất

    private var groups: [SectionTab] {
        Self.makeGroups(episodes)
    }

    private var activeEpisodes: [VideoPlaybackSession.Episode] {
        guard !groups.isEmpty else { return [] }
        return groups[min(max(selectedGroup, 0), groups.count - 1)].episodes
    }

    /// Mỗi dòng `section` là một tab. Dòng trước section đầu tiên (mục lục không có nhóm) thành tab không tên;
    /// nếu chỉ có một tab thì hàng tab bị ẩn.
    private static func makeGroups(_ episodes: [VideoPlaybackSession.Episode]) -> [SectionTab] {
        var buckets: [(title: String, episodes: [VideoPlaybackSession.Episode])] = []
        var pendingTitle: String?
        var bucket: [VideoPlaybackSession.Episode] = []

        for episode in episodes {
            if episode.isSection {
                if pendingTitle != nil || !bucket.isEmpty {
                    buckets.append((pendingTitle ?? "", bucket))
                }
                pendingTitle = episode.title
                bucket = []
            } else {
                bucket.append(episode)
            }
        }
        if pendingTitle != nil || !bucket.isEmpty {
            buckets.append((pendingTitle ?? "", bucket))
        }

        return buckets.enumerated().compactMap { offset, bucket in
            bucket.episodes.isEmpty
                ? nil
                : SectionTab(id: offset, title: bucket.title, episodes: bucket.episodes)
        }
    }

    /// Chỉ đồng bộ tab khi tập đang phát đổi — người dùng đổi tab để xem thì không bị kéo lại.
    private func syncGroupToCurrent() {
        guard !groups.isEmpty else {
            selectedGroup = 0
            return
        }
        if let index = groups.firstIndex(where: { group in
            group.episodes.contains { $0.index == currentIndex }
        }) {
            selectedGroup = index
        } else if selectedGroup >= groups.count {
            selectedGroup = 0
        }
    }
}
