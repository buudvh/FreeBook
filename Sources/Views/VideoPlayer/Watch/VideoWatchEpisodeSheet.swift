import SwiftUI

/// Sheet "Tất cả tập" của màn xem (nửa màn / toàn màn, vuốt xuống để đóng): chip nhóm + lưới **6 cột**
/// (`VideoEpisodeGridView`), ô tập đã tải có dấu ⬇ (`VideoOfflineLibrary` theo phim của màn xem — cờ `isCached` của
/// `ChapterStore` không đúng cho video). Chạm ô ⇒ đóng sheet, phát tập đó; khung phim vẫn phát phía trên suốt lúc mở.
struct VideoWatchEpisodeSheet: View {
    let episodes: [VideoPlaybackSession.Episode]
    let currentIndex: Int
    let bookId: String
    let onSelect: (VideoPlaybackSession.Episode) -> Void

    private var playableCount: Int { episodes.filter { !$0.isSection }.count }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Danh sách tập (\(playableCount))")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                    VideoEpisodeGridView(
                        episodes: episodes,
                        currentIndex: currentIndex,
                        columnCount: 6,
                        downloadedIndexes: VideoOfflineLibrary.shared.summary(bookId: bookId).completedEpisodes,
                        onSelect: onSelect
                    )
                }
                .padding(.vertical, 20)
            }
            .onAppear {
                VideoOfflineLibrary.shared.refresh(bookId: bookId)
                if episodes.contains(where: { $0.index == currentIndex && !$0.isSection }) {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
