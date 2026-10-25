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

                    if !session.servers.isEmpty || session.hasOfflineCopy {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Server")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                            VideoServerChipBar(
                                servers: session.servers,
                                selectedIndex: session.isPlayingOffline ? nil : session.selectedServerIndex,
                                offline: offlineChips,
                                onSelect: { session.selectServer(at: $0) }
                            )
                        }
                    }

                    if !session.episodes.isEmpty {
                        VideoEpisodeGridView(
                            episodes: session.episodes,
                            currentIndex: session.currentEpisodeIndex,
                            downloadActions: downloadActions,
                            onSelect: { session.selectEpisode($0) }
                        )
                    }
                }
                .padding(.vertical, 16)
            }
            .onAppear {
                scrollToEpisode(session.currentEpisodeIndex, proxy: proxy, animated: false)
                downloadActions.refresh()
            }
            .onChange(of: session.currentEpisodeIndex) { _, newIndex in
                scrollToEpisode(newIndex, proxy: proxy, animated: true)
            }
            .onChange(of: session.episodes.count) { _, _ in
                scrollToEpisode(session.currentEpisodeIndex, proxy: proxy, animated: true)
            }
        }
    }

    private var downloadActions: VideoEpisodeDownloadActions {
        VideoEpisodeDownloadActions(session: session)
    }

    /// Chip "Bản tải" / "Trực tuyến" khi tập đang xem đã tải về máy.
    private var offlineChips: VideoServerChipBar.OfflineChips? {
        guard session.hasOfflineCopy else { return nil }
        return VideoServerChipBar.OfflineChips(
            isSelected: session.isPlayingOffline,
            onSelectOffline: { session.playOffline() },
            onSelectOnline: { session.playOnline() }
        )
    }

    /// Tên phim và tên tập hiện đầy đủ, không cắt dòng — phần này nằm trong `ScrollView` nên tên dài chỉ đẩy lưới tập
    /// xuống.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.bookTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if !session.currentEpisodeLabel.isEmpty {
                Text(session.currentEpisodeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
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
