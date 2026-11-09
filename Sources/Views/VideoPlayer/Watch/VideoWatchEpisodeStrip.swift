import SwiftUI

/// Dải tập của màn xem: tiêu đề "Danh sách tập" + "Tất cả ›", hàng chip nhóm (`VideoEpisodeGrouping`; chỉ hiện khi có
/// từ 2 nhóm, chọn sẵn nhóm chứa tập đang xem), rồi một dải ngang các ô số tập của nhóm đang chọn. Chạm ô ⇒ phát tập đó
/// ngay tại chỗ. "Tất cả ›" ⇒ sheet `VideoWatchEpisodeSheet` (Lưới 6 cột hoặc Danh sách như mục lục truyện, nhớ theo
/// tiện ích) có dấu ⬇ cho tập đã tải.
///
/// Đổi chip **không** đổi tập đang phát; tập đang phát đổi (tự sang tập kế…) thì chip nhảy theo và dải cuộn tới ô đó.
struct VideoWatchEpisodeStrip: View {
    let episodes: [VideoPlaybackSession.Episode]
    let currentIndex: Int
    /// Phim của màn xem — dấu đã tải đọc theo id này, không theo phim đang chạy trong phiên.
    let bookId: String
    /// Tiện ích của phim của màn xem — sheet "Tất cả tập" nhớ kiểu Lưới / Danh sách theo id này.
    let packageId: String
    let onSelect: (VideoPlaybackSession.Episode) -> Void

    @State private var selectedGroup = 0
    @State private var showingAll = false

    private static let cellSize = CGSize(width: 58, height: 46)

    private var groups: [VideoEpisodeGrouping.Group<VideoPlaybackSession.Episode>] {
        VideoEpisodeGrouping.groups(episodes)
    }

    private var activeEpisodes: [VideoPlaybackSession.Episode] {
        let all = groups
        guard !all.isEmpty else { return [] }
        return all[min(max(selectedGroup, 0), all.count - 1)].items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if groups.count > 1 {
                groupChips
            }
            strip
        }
        .onAppear(perform: syncGroupToCurrent)
        .onChange(of: currentIndex) { _, _ in syncGroupToCurrent() }
        .onChange(of: episodes) { _, _ in syncGroupToCurrent() }
        .sheet(isPresented: $showingAll) {
            VideoWatchEpisodeSheet(
                episodes: episodes,
                currentIndex: currentIndex,
                bookId: bookId,
                packageId: packageId,
                onSelect: { episode in
                    showingAll = false
                    onSelect(episode)
                }
            )
        }
    }

    private var header: some View {
        HStack {
            Text("Danh sách tập")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Button {
                showingAll = true
            } label: {
                HStack(spacing: 4) {
                    Text("Tất cả")
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xem tất cả tập")
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Chip nhóm

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups) { group in
                    chip(group)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ group: VideoEpisodeGrouping.Group<VideoPlaybackSession.Episode>) -> some View {
        let isSelected = group.id == selectedGroup
        let label = VideoEpisodeGridView.label(of: group)
        let count = group.items.count
        let groupId = group.id
        // Tách màu / chữ ra hằng có kiểu rõ: gộp cả vào một biểu thức thì trình biên dịch không kiểm kiểu kịp.
        let foreground: Color = isSelected ? .accentColor : Color.white.opacity(0.75)
        let fill: Color = isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.07)
        let stroke: Color = isSelected ? Color.accentColor.opacity(0.6) : .clear
        let traits: AccessibilityTraits = isSelected ? .isSelected : []
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedGroup = groupId }
        } label: {
            chipLabel(title: "\(label) · \(count)", foreground: foreground, fill: fill, stroke: stroke)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count) tập")
        .accessibilityAddTraits(traits)
    }

    private func chipLabel(title: String, foreground: Color, fill: Color, stroke: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: 1))
            .contentShape(shape)
    }

    // MARK: - Dải ô tập

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 7) {
                    ForEach(Array(activeEpisodes.enumerated()), id: \.element.id) { offset, episode in
                        cell(episode, number: offset + 1)
                            .id(episode.index)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: Self.cellSize.height)
            .onAppear { scrollToCurrent(proxy, animated: false) }
            .onChange(of: currentIndex) { _, _ in scrollToCurrent(proxy, animated: true) }
            .onChange(of: selectedGroup) { _, _ in scrollToCurrent(proxy, animated: false) }
        }
    }

    private func cell(_ episode: VideoPlaybackSession.Episode, number: Int) -> some View {
        let isCurrent = episode.index == currentIndex
        let isDownloaded = VideoOfflineLibrary.shared.isDownloaded(bookId: bookId, episodeIndex: episode.index)
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return Button {
            onSelect(episode)
        } label: {
            Text("\(number)")
                .font(.system(size: 14, weight: isCurrent ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Color.black : Color.white)
                .frame(width: Self.cellSize.width, height: Self.cellSize.height)
                .background(shape.fill(isCurrent ? Color.white : Color.white.opacity(0.07)))
                .overlay(alignment: .topTrailing) {
                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isCurrent ? Color.black.opacity(0.6) : Color.white.opacity(0.75))
                            .padding(4)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tập \(number): \(episode.displayTitle)")
        .accessibilityValue(isCurrent ? "Đang xem" : (isDownloaded ? "Đã tải" : ""))
    }

    // MARK: - Đồng bộ

    private func syncGroupToCurrent() {
        let all = groups
        if let position = VideoEpisodeGrouping.groupPosition(of: currentIndex, in: all) {
            selectedGroup = position
        } else if selectedGroup >= all.count {
            selectedGroup = 0
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        guard activeEpisodes.contains(where: { $0.index == currentIndex }) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(currentIndex, anchor: .center) }
        } else {
            proxy.scrollTo(currentIndex, anchor: .center)
        }
    }
}
