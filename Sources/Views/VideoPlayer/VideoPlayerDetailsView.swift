import SwiftUI

/// Phần dưới khung phim ở màn dọc: tên phim + tập, chip server, lưới tập nhóm theo section. Tự cuộn tới tập đang xem.
struct VideoPlayerDetailsView: View {
    let session: VideoPlaybackSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                        .padding(.horizontal, 16)

                    if !session.servers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Server")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                            VideoServerChipBar(
                                servers: session.servers,
                                selectedIndex: session.selectedServerIndex,
                                onSelect: { session.selectServer(at: $0) }
                            )
                        }
                    }

                    if !session.episodes.isEmpty {
                        VideoEpisodeGridView(
                            episodes: session.episodes,
                            currentIndex: session.currentEpisodeIndex,
                            onSelect: { session.selectEpisode($0) }
                        )
                    }
                }
                .padding(.vertical, 16)
            }
            .onAppear {
                scrollToEpisode(session.currentEpisodeIndex, proxy: proxy, animated: false)
            }
            .onChange(of: session.currentEpisodeIndex) { _, newIndex in
                scrollToEpisode(newIndex, proxy: proxy, animated: true)
            }
            .onChange(of: session.episodes.count) { _, _ in
                scrollToEpisode(session.currentEpisodeIndex, proxy: proxy, animated: true)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.bookTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            if !session.currentEpisodeLabel.isEmpty {
                Text(session.currentEpisodeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            if session.phase == .embed {
                Text("Đang phát nhúng trang nguồn — bấm play trong khung phim.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func scrollToEpisode(_ index: Int, proxy: ScrollViewProxy, animated: Bool) {
        guard session.episodes.contains(where: { $0.index == index && !$0.isSection }) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(index, anchor: .center)
            }
        } else {
            proxy.scrollTo(index, anchor: .center)
        }
    }
}
