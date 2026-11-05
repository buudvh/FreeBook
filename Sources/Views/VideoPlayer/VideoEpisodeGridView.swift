import SwiftUI

/// Lưới tập phim **chia tab theo section**: mỗi dòng `type: "section"` của `toc` (extension nhiều server) là một tab
/// ("Vietsub", "Thuyết minh"…). Chọn tab nào thì lưới hiện đúng bộ tập của nhóm đó, số tập đánh lại từ 1.
///
/// Dùng chung cho panel toàn màn (`VideoEpisodePanel`) và màn dọc (`VideoPlayerDetailsView`); trước đây hai chỗ này
/// vẽ tiêu đề nhóm chen giữa lưới nên phải cuộn qua cả bộ tập của nhóm khác. Ô giữ `.id(episode.index)` để màn cha
/// vẫn `scrollTo` tới tập đang phát được.
///
/// Hợp đồng: chỉ đọc `episodes` + `currentIndex`, mọi thao tác đi qua `onSelect` — đổi tab **không** đổi tập đang phát.
/// Nhấn giữ ô tập (khi có `downloadActions`) ⇒ "Tải tập này" / "Xoá bản tải". `downloadedIndexes` (sheet "Tất cả tập"
/// của màn xem) ⇒ ô tập đã tải có dấu ⬇ ở góc. Chia nhóm bằng `VideoEpisodeGrouping`.
struct VideoEpisodeGridView: View {
    typealias SectionTab = VideoEpisodeGrouping.Group<VideoPlaybackSession.Episode>

    let episodes: [VideoPlaybackSession.Episode]
    let currentIndex: Int
    let onSelect: (VideoPlaybackSession.Episode) -> Void
    let downloadActions: VideoEpisodeDownloadActions?
    /// Chỉ số mục lục của các tập đã tải trọn (`VideoOfflineLibrary`) — rỗng thì không vẽ dấu.
    let downloadedIndexes: Set<Int>

    @State private var selectedGroup: Int

    /// Tối đa chừng này tab thì chia đều bề ngang; nhiều hơn thì cho cuộn ngang để tên không bị cắt.
    private static let maxEvenTabs = 3
    private static let cellHeight: CGFloat = 46

    private let columns: [GridItem]

    init(
        episodes: [VideoPlaybackSession.Episode],
        currentIndex: Int,
        columnCount: Int = 4,
        downloadedIndexes: Set<Int> = [],
        downloadActions: VideoEpisodeDownloadActions? = nil,
        onSelect: @escaping (VideoPlaybackSession.Episode) -> Void
    ) {
        self.episodes = episodes
        self.currentIndex = currentIndex
        self.onSelect = onSelect
        self.downloadActions = downloadActions
        self.downloadedIndexes = downloadedIndexes
        self.columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: max(1, columnCount))
        // Mở đúng tab chứa tập đang phát ngay từ lần vẽ đầu, để `scrollTo` của màn cha tìm thấy ô.
        let initial = VideoEpisodeGrouping.groupPosition(of: currentIndex, in: VideoEpisodeGrouping.groups(episodes)) ?? 0
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
        let label = Self.label(of: group)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedGroup = group.id }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .lineLimit(1)
                Text("\(group.items.count)")
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
        .accessibilityLabel("\(label), \(group.items.count) tập")
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
                .overlay(alignment: .topTrailing) {
                    if downloadedIndexes.contains(episode.index) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isCurrent ? Color.black.opacity(0.6) : Color.white.opacity(0.75))
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tập \(number): \(episode.displayTitle)")
        .accessibilityValue(isCurrent ? "Đang phát" : (downloadedIndexes.contains(episode.index) ? "Đã tải" : ""))
    }

    // MARK: - Dữ liệu dẫn xuất

    private var groups: [SectionTab] {
        VideoEpisodeGrouping.groups(episodes)
    }

    private var activeEpisodes: [VideoPlaybackSession.Episode] {
        guard !groups.isEmpty else { return [] }
        return groups[min(max(selectedGroup, 0), groups.count - 1)].items
    }

    /// Nhóm đứng trước section đầu tiên không có tên ⇒ "Tập".
    static func label(of group: SectionTab) -> String {
        group.title.isEmpty ? "Tập" : group.title
    }

    /// Chỉ đồng bộ tab khi tập đang phát đổi — người dùng đổi tab để xem thì không bị kéo lại.
    private func syncGroupToCurrent() {
        guard !groups.isEmpty else {
            selectedGroup = 0
            return
        }
        if let index = VideoEpisodeGrouping.groupPosition(of: currentIndex, in: groups) {
            selectedGroup = index
        } else if selectedGroup >= groups.count {
            selectedGroup = 0
        }
    }
}
