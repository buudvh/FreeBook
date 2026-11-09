import SwiftUI

/// Sheet "Tất cả tập" của màn xem (nửa màn / toàn màn, vuốt xuống để đóng), hai kiểu hiển thị chọn bằng nút đổi kiểu
/// (`VideoEpisodeLayoutMode`, nhớ theo tiện ích `packageId`, dùng chung với panel tập khi xem toàn màn):
/// - **Lưới** (mặc định): tiêu đề "Danh sách tập (N)" + nút đổi kiểu, chip nhóm + lưới **6 cột** (`VideoEpisodeGridView`).
/// - **Danh sách**: panel Mục lục như mục lục truyện (`VideoEpisodeListView`) — nút đổi kiểu đứng trước ↓↑.
///
/// Tập đã tải có dấu ⬇ (`VideoOfflineLibrary` theo phim của màn xem — cờ `isCached` của `ChapterStore` không đúng cho
/// video). Chạm tập ⇒ đóng sheet (nơi gọi), phát tập đó; khung phim vẫn phát phía trên suốt lúc mở.
struct VideoWatchEpisodeSheet: View {
    let episodes: [VideoPlaybackSession.Episode]
    let currentIndex: Int
    let bookId: String
    /// Tiện ích của phim — kiểu Lưới / Danh sách nhớ theo id này.
    let packageId: String
    let onSelect: (VideoPlaybackSession.Episode) -> Void

    @State private var layout: VideoEpisodeLayoutMode

    init(
        episodes: [VideoPlaybackSession.Episode],
        currentIndex: Int,
        bookId: String,
        packageId: String,
        onSelect: @escaping (VideoPlaybackSession.Episode) -> Void
    ) {
        self.episodes = episodes
        self.currentIndex = currentIndex
        self.bookId = bookId
        self.packageId = packageId
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
                accessory: { layoutButton }
            )
            .padding(.top, 16)
        }
    }

    private var gridContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Text("Danh sách tập (\(playableCount))")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        layoutButton
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
                    VideoEpisodeGridView(
                        episodes: episodes,
                        currentIndex: currentIndex,
                        columnCount: 6,
                        downloadedIndexes: downloadedIndexes,
                        onSelect: onSelect
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

    /// Đổi Lưới ⇄ Danh sách và nhớ cho tiện ích của phim. Icon = kiểu sẽ chuyển sang.
    private var layoutButton: some View {
        VideoPlayerIconButton(systemName: layout.toggleSymbolName, label: layout.toggleAccessibilityLabel) {
            layout = layout.toggled
            VideoEpisodeLayoutMode.save(layout, packageId: packageId)
        }
    }
}
