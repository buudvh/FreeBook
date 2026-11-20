import SwiftUI

/// Sheet "Tất cả tập" của màn xem (nửa màn / toàn màn, vuốt xuống để đóng), hai kiểu hiển thị chọn bằng nút đổi kiểu
/// (`VideoEpisodeLayoutMode`, nhớ theo tiện ích `packageId`, dùng chung với panel tập khi xem toàn màn):
/// - **Lưới** (mặc định): tiêu đề "Danh sách tập (N)" + nút đổi kiểu, chip nhóm + lưới **6 cột** (`VideoEpisodeGridView`).
/// - **Danh sách**: panel Mục lục như mục lục truyện (`VideoEpisodeListView`) — nút đổi kiểu đứng trước ↓↑.
///
/// Tập đã tải có dấu ⬇ (`VideoOfflineLibrary` theo phim của màn xem — cờ `isCached` của `ChapterStore` không đúng cho
/// video). Chạm tập ⇒ đóng sheet (nơi gọi), phát tập đó; khung phim vẫn phát phía trên suốt lúc mở. Nhấn giữ tập (khi có
/// `playlistAlbum`) ⇒ "Thêm vào playlist" — sheet `PlaylistAddSheet` mở chồng lên sheet này.
struct VideoWatchEpisodeSheet: View {
    let episodes: [VideoPlaybackSession.Episode]
    let currentIndex: Int
    let bookId: String
    /// Tiện ích của phim — kiểu Lưới / Danh sách nhớ theo id này.
    let packageId: String
    /// Phim của màn xem — có ⇒ nhấn giữ tập thêm được vào playlist.
    let playlistAlbum: PlaylistAlbumInfo?
    let onSelect: (VideoPlaybackSession.Episode) -> Void

    @State private var layout: VideoEpisodeLayoutMode
    @State private var playlistRequest: PlaylistAddRequest? = nil

    init(
        episodes: [VideoPlaybackSession.Episode],
        currentIndex: Int,
        bookId: String,
        packageId: String,
        playlistAlbum: PlaylistAlbumInfo? = nil,
        onSelect: @escaping (VideoPlaybackSession.Episode) -> Void
    ) {
        self.episodes = episodes
        self.currentIndex = currentIndex
        self.bookId = bookId
        self.packageId = packageId
        self.playlistAlbum = playlistAlbum
        self.onSelect = onSelect
        _layout = State(initialValue: VideoEpisodeLayoutMode.load(packageId: packageId))
    }

    private var playableCount: Int { episodes.filter { !$0.isSection }.count }

    private var downloadedIndexes: Set<Int> {
        VideoOfflineLibrary.shared.summary(bookId: bookId).completedEpisodes
    }

    var body: some View {
        content
            .onAppear { VideoOfflineLibrary.shared.refresh(bookId: bookId) }
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .sheet(item: $playlistRequest) { presentedItem in PlaylistAddSheet(request: presentedItem).appGlassSheet() }
    }

    /// `nil` khi không có phim để dựng mục (lưới / danh sách không hiện mục "Thêm vào playlist").
    private var addToPlaylist: ((VideoPlaybackSession.Episode) -> Void)? {
        guard let album = playlistAlbum else { return nil }
        return { episode in
            playlistRequest = PlaylistItemMapper.addRequest(episode: episode, album: album)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .grid:
            gridContent
        case .list:
            VideoEpisodeListView(
                episodes: episodes,
                currentIndex: currentIndex,
                downloadedIndexes: downloadedIndexes,
                showsTOCHeader: true,
                onSelect: onSelect,
                onAddToPlaylist: addToPlaylist,
                // Đứng trước ↓↑ (không phải nút ngoài cùng) ⇒ icon giữa khung.
                accessory: { layoutButton(alignment: .center) }
            )
            .padding(.top, 16)
        }
    }

    private var gridContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Lưới header chung: tiêu đề 22pt đậm không co chữ, nút ngoài cùng canh icon vào lề.
                    HStack(spacing: 6) {
                        Text("Danh sách tập (\(playableCount))")
                            .font(.system(size: HeaderMetrics.rowTitleFontSize, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        layoutButton(alignment: .trailing)
                    }
                    .padding(.horizontal, HeaderMetrics.horizontalMargin)
                    VideoEpisodeGridView(
                        episodes: episodes,
                        currentIndex: currentIndex,
                        columnCount: 6,
                        downloadedIndexes: downloadedIndexes,
                        onSelect: onSelect,
                        onAddToPlaylist: addToPlaylist
                    )
                }
                .padding(.vertical, 20)
            }
            .onAppear {
                if episodes.contains(where: { $0.index == currentIndex && !$0.isSection }) {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
    }

    /// Đổi Lưới ⇄ Danh sách và nhớ cho tiện ích của phim. Icon = kiểu sẽ chuyển sang. `alignment` = canh icon trong khung:
    /// `.trailing` khi là nút ngoài cùng của hàng tiêu đề (kiểu Lưới).
    private func layoutButton(alignment: Alignment) -> some View {
        VideoPlayerIconButton(
            systemName: layout.toggleSymbolName,
            label: layout.toggleAccessibilityLabel,
            alignment: alignment
        ) {
            layout = layout.toggled
            VideoEpisodeLayoutMode.save(layout, packageId: packageId)
        }
    }
}
