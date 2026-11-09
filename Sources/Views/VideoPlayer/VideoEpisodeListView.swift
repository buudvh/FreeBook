import SwiftUI

/// Kiểu **Danh sách** của danh sách tập phim (`VideoEpisodeLayoutMode.list`) — hàng giống mục lục truyện (mục lục Reader /
/// comic): cột số thứ tự (`ChapterOrdinalLabel`, theo công tắc "Hiện số thứ tự chương"), tên tập tối đa 2 dòng, tập đang
/// phát chữ đậm + nền mờ, tập đã xem mờ, tập đã tải có ⬇ xanh trong ô 30 × 30 cố định.
///
/// - `showsTOCHeader == true` (sheet "Tất cả tập"): bọc trong panel Mục lục dùng chung (`ChapterTOCPanelHeader` +
///   `.chapterTOCPanel(_:)`): "Mục lục (N tập)", `accessory` (nút đổi kiểu), ↓↑ và ô tìm. `false` (panel toàn màn hẹp,
///   phủ lên phim): chỉ chip nhóm + hàng, nút đổi kiểu nằm ở đầu panel của nơi gọi.
/// - Nhóm theo dòng `section` bằng chip như kiểu Lưới (`VideoEpisodeGroupTabs`); mỗi nhóm đánh số lại từ 1 (khớp ô số của
///   Lưới). Tìm và ↓↑ chỉ áp lên nhóm đang chọn, giữ số của từng tập; hai trạng thái này không lưu.
/// - "N" của tiêu đề = mọi tập phát được (như tiêu đề kiểu Lưới), kể cả khi có nhiều nhóm.
/// - Chỉ báo chọn qua `onSelect` — **không** tự `dismiss` (trong panel toàn màn `dismiss` sẽ đóng cả trình phát); nơi
///   gọi tự đóng sheet / panel. Nhấn giữ hàng (khi có `downloadActions`) ⇒ "Tải tập này" / "Xoá bản tải" như ô Lưới;
///   có `onAddToPlaylist` ⇒ thêm "Thêm vào playlist", kèm icon "Thêm vào playlist" ở cuối hàng sau ô ⬇ (1.3.810, chỉ
///   sheet "Tất cả tập" truyền; panel toàn màn không có).
/// - Hàng dựng bằng `ScrollView` + `LazyVStack` (không `List`) và giữ `.id(episode.index)` để cuộn tới tập đang phát.
struct VideoEpisodeListView<Accessory: View>: View {
    typealias Episode = VideoPlaybackSession.Episode
    typealias SectionTab = VideoEpisodeGrouping.Group<Episode>

    let episodes: [Episode]
    let currentIndex: Int
    /// Chỉ số mục lục của các tập đã tải trọn (`VideoOfflineLibrary`) — sheet của màn xem truyền vào.
    let downloadedIndexes: Set<Int>
    let downloadActions: VideoEpisodeDownloadActions?
    let showsTOCHeader: Bool
    let onSelect: (Episode) -> Void
    /// Có ⇒ nhấn giữ hàng thêm mục "Thêm vào playlist" (sheet "Tất cả tập" của màn xem).
    let onAddToPlaylist: ((Episode) -> Void)?
    let accessory: Accessory

    @State private var selectedGroup: Int
    @State private var searchQuery = ""
    @State private var isAscending = true
    /// Công tắc "Hiện số thứ tự chương" — đọc một lần ở danh sách, hàng chỉ nhận số + bề rộng cột.
    @AppStorage(ChapterOrdinalNumbering.showsOrdinalKey)
    private var showsOrdinal = ChapterOrdinalNumbering.showsOrdinalDefault

    /// Trình phát luôn tối ⇒ cùng bảng màu nền Tối với mục lục comic.
    private static var palette: ChapterTOCPalette { .reader(.dark) }

    init(
        episodes: [Episode],
        currentIndex: Int,
        downloadedIndexes: Set<Int> = [],
        downloadActions: VideoEpisodeDownloadActions? = nil,
        showsTOCHeader: Bool,
        onSelect: @escaping (Episode) -> Void,
        onAddToPlaylist: ((Episode) -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.episodes = episodes
        self.currentIndex = currentIndex
        self.downloadedIndexes = downloadedIndexes
        self.downloadActions = downloadActions
        self.showsTOCHeader = showsTOCHeader
        self.onSelect = onSelect
        self.onAddToPlaylist = onAddToPlaylist
        self.accessory = accessory()
        // Mở đúng nhóm chứa tập đang phát ngay từ lần vẽ đầu, để lần cuộn đầu tìm thấy hàng.
        let initial = VideoEpisodeGrouping.groupPosition(of: currentIndex, in: VideoEpisodeGrouping.groups(episodes)) ?? 0
        _selectedGroup = State(initialValue: initial)
    }

    var body: some View {
        if showsTOCHeader {
            VStack(spacing: 0) {
                ChapterTOCPanelHeader(
                    chapterCount: playableCount,
                    noun: "tập",
                    searchText: $searchQuery,
                    isAscending: isAscending,
                    palette: Self.palette,
                    onToggleSort: { isAscending.toggle() },
                    accessory: { accessory }
                )
                content
            }
            .chapterTOCPanel(Self.palette)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if groups.count > 1 {
                VideoEpisodeGroupTabs(groups: groups, selection: $selectedGroup)
                    .padding(.horizontal, 16)
                    .padding(.top, showsTOCHeader ? 2 : 8)
                    .padding(.bottom, 6)
            }
            rows
        }
        .onAppear(perform: syncGroupToCurrent)
        .onChange(of: currentIndex) { _, _ in syncGroupToCurrent() }
        .onChange(of: episodes) { _, _ in syncGroupToCurrent() }
    }

    // MARK: - Hàng

    private var rows: some View {
        // Số dựng từ **cả nhóm đang chọn** theo thứ tự gốc (không phải danh sách đã lọc/đảo) ⇒ tìm / ↓↑ vẫn giữ số,
        // mỗi nhóm đánh từ 1. Dựng một lần cho cả danh sách.
        let numbering: ChapterOrdinalNumbering? = showsOrdinal
            ? ChapterOrdinalNumbering(activeEpisodes, index: { $0.index }, isSection: { _ in false })
            : nil
        let visible = visibleEpisodes
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { episode in
                        rowWithMenu(episode, numbering: numbering)
                            .id(episode.index)
                    }
                    if visible.isEmpty, !trimmedQuery.isEmpty {
                        Text("Không có tập nào khớp")
                            .font(.subheadline)
                            .foregroundColor(Self.palette.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                // Đợi danh sách dựng xong rồi mới cuộn tới tập đang phát.
                DispatchQueue.main.async { scrollToCurrent(proxy, animated: false) }
            }
            .onChange(of: currentIndex) { _, _ in scrollToCurrent(proxy, animated: true) }
            .onChange(of: selectedGroup) { _, _ in scrollToCurrent(proxy, animated: false) }
            .onChange(of: isAscending) { _, _ in scrollToCurrent(proxy, animated: false) }
        }
    }

    @ViewBuilder
    private func rowWithMenu(_ episode: Episode, numbering: ChapterOrdinalNumbering?) -> some View {
        if downloadActions != nil || onAddToPlaylist != nil {
            row(episode, numbering: numbering)
                .contextMenu {
                    if let actions = downloadActions {
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
                    if let onAddToPlaylist {
                        Button {
                            onAddToPlaylist(episode)
                        } label: {
                            Label("Thêm vào playlist", systemImage: "text.badge.plus")
                        }
                    }
                }
        } else {
            row(episode, numbering: numbering)
        }
    }

    private func row(_ episode: Episode, numbering: ChapterOrdinalNumbering?) -> some View {
        let palette = Self.palette
        let isCurrent = episode.index == currentIndex
        let isWatched = currentIndex >= 0 && episode.index < currentIndex
        let isDownloaded = isDownloaded(episode)
        let titleColor: Color = isCurrent ? palette.title : (isWatched ? palette.text.opacity(0.4) : palette.text)
        let rowFill: Color = isCurrent ? palette.currentRowFill : .clear
        let traits: AccessibilityTraits = isCurrent ? .isSelected : []
        // Nền tập đang phát + vạch ngăn gắn ở hàng ngoài để phủ cả icon "Thêm vào playlist" (nút anh em, 1.3.810).
        return HStack(spacing: 0) {
            Button {
                onSelect(episode)
            } label: {
                HStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let numbering {
                            ChapterOrdinalLabel(
                                ordinal: numbering.ordinal(forIndex: episode.index),
                                digits: numbering.digits,
                                palette: palette,
                                isCurrent: isCurrent,
                                isRead: isWatched
                            )
                        }
                        Text(episode.displayTitle)
                            .font(.body)
                            .fontWeight(isCurrent ? .semibold : .regular)
                            .foregroundColor(titleColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    downloadMark(isDownloaded)
                }
                .padding(.leading, 16)
                .padding(.trailing, onAddToPlaylist == nil ? 10 : 0)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(episode.displayTitle)
            .accessibilityValue(isCurrent ? "Đang phát" : (isDownloaded ? "Đã tải" : ""))
            .accessibilityAddTraits(traits)

            if let onAddToPlaylist {
                Button {
                    onAddToPlaylist(episode)
                } label: {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(palette.secondaryText)
                        .frame(width: 32, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .accessibilityLabel("Thêm \(episode.displayTitle) vào playlist")
            }
        }
        .background(rowFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.divider)
                .frame(height: 0.5)
                .padding(.leading, 16)
        }
    }

    /// Khung 30 × 30 cố định để hàng không đổi chiều cao khi tập vừa tải xong.
    private func downloadMark(_ isDownloaded: Bool) -> some View {
        Color.clear
            .frame(width: 30, height: 30)
            .overlay {
                if isDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .accessibilityHidden(true)
                }
            }
    }

    // MARK: - Dữ liệu dẫn xuất

    private var playableCount: Int {
        episodes.filter { !$0.isSection }.count
    }

    private var groups: [SectionTab] {
        VideoEpisodeGrouping.groups(episodes)
    }

    private var activeEpisodes: [Episode] {
        let all = groups
        guard !all.isEmpty else { return [] }
        return all[min(max(selectedGroup, 0), all.count - 1)].items
    }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nhóm đang chọn, lọc theo tên tập (`ChapterTitleSearchMatcher`: không phân biệt hoa thường và dấu) rồi xếp theo ↓↑.
    private var visibleEpisodes: [Episode] {
        let query = trimmedQuery
        let matched = query.isEmpty
            ? activeEpisodes
            : activeEpisodes.filter { ChapterTitleSearchMatcher.matches(query, anyOf: [$0.displayTitle, $0.title]) }
        return isAscending ? matched : Array(matched.reversed())
    }

    private func isDownloaded(_ episode: Episode) -> Bool {
        downloadedIndexes.contains(episode.index) || downloadActions?.isDownloaded(episode) == true
    }

    // MARK: - Đồng bộ

    /// Chỉ đồng bộ nhóm khi tập đang phát đổi — người dùng đổi chip để xem thì không bị kéo lại.
    private func syncGroupToCurrent() {
        let all = groups
        if let position = VideoEpisodeGrouping.groupPosition(of: currentIndex, in: all) {
            selectedGroup = position
        } else if selectedGroup >= all.count {
            selectedGroup = 0
        }
    }

    /// Cuộn tới tập đang phát nếu nó đang hiện; không thì về hàng đầu (đổi nhóm / đảo thứ tự).
    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        let visible = visibleEpisodes
        let showsCurrent = visible.contains { $0.index == currentIndex }
        let target: Int? = showsCurrent ? currentIndex : visible.first?.index
        guard let target else { return }
        let anchor: UnitPoint = showsCurrent ? .center : .top
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(target, anchor: anchor) }
        } else {
            proxy.scrollTo(target, anchor: anchor)
        }
    }
}

extension VideoEpisodeListView where Accessory == EmptyView {
    /// Panel toàn màn: không có đầu panel Mục lục nên không có `accessory`.
    init(
        episodes: [Episode],
        currentIndex: Int,
        downloadedIndexes: Set<Int> = [],
        downloadActions: VideoEpisodeDownloadActions? = nil,
        showsTOCHeader: Bool,
        onSelect: @escaping (Episode) -> Void,
        onAddToPlaylist: ((Episode) -> Void)? = nil
    ) {
        self.init(
            episodes: episodes,
            currentIndex: currentIndex,
            downloadedIndexes: downloadedIndexes,
            downloadActions: downloadActions,
            showsTOCHeader: showsTOCHeader,
            onSelect: onSelect,
            onAddToPlaylist: onAddToPlaylist,
            accessory: { EmptyView() }
        )
    }
}
