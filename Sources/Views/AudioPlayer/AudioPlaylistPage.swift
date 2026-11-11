import SwiftUI

/// Trang trái của màn nghe: "Danh sách phát · N bài". Thứ tự hiển thị **luôn** theo mục lục (`tracks`), không theo thứ
/// tự xáo; số thứ tự = vị trí trong danh sách (không phải `Track.index` thưa). Chạm hàng ⇒ `playTrack(at: track.index)`.
/// Trang hiện ra (và khi đổi bài lúc đang xem) ⇒ cuộn bài đang phát vào giữa. Dưới danh sách bài là phần gợi ý của nguồn
/// (`AudioSuggestionSection`), tải khi trang hiện. Icon cuối hàng (1.3.810) hoặc nhấn giữ một bài ⇒ "Thêm vào playlist"
/// (`PlaylistAddSheet`).
/// Đang phát playlist (`PlaylistPlaybackCoordinator.audioQueue`) ⇒ cả trang là các mục của playlist
/// (`AudioPlaylistQueueList`), không có danh sách bài của album lẫn phần gợi ý.
struct AudioPlaylistPage: View {
    let isVisible: Bool
    let drag: AudioMinimizeDragState
    let onMinimize: () -> Void

    @State private var playlistRequest: PlaylistAddRequest? = nil

    private var session: AudioPlaybackSession { .shared }

    var body: some View {
        Group {
            if let queue = PlaylistPlaybackCoordinator.shared.audioQueue, session.isActive {
                AudioPlaylistQueueList(queue: queue, isVisible: isVisible, drag: drag, onMinimize: onMinimize)
            } else {
                albumPage
            }
        }
        .sheet(item: $playlistRequest) { request in
            PlaylistAddSheet(request: request)
        }
    }

    private var albumPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Danh sách phát · \(session.tracks.count) bài")
                .font(.headline)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .audioMinimizeDrag(drag, onCommit: onMinimize)
            if session.tracks.isEmpty {
                placeholder
            } else {
                trackList
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 10) {
            if session.phase == .loading {
                ProgressView()
                    .tint(.white)
                Text("Đang tải danh sách bài…")
            } else {
                Text("Chưa có bài nào để phát.")
            }
        }
        .font(.subheadline)
        .foregroundStyle(Color.white.opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trackList: some View {
        let fallbackArtist = session.displayAlbumAuthor
        let names = session.displayNames
        let current = session.currentTrackIndex
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(session.tracks.enumerated()), id: \.element.id) { position, track in
                        AudioPlaylistRow(
                            position: position + 1,
                            title: track.displayTitle,
                            artist: track.artist.isEmpty ? fallbackArtist : names.author(track.artist),
                            isCurrent: track.index == current,
                            onSelect: {
                                AppLogger.shared.log("🎵 [AudioPlayerUI] Chọn bài \(track.index) ở danh sách phát")
                                session.playTrack(at: track.index)
                            },
                            onAddToPlaylist: {
                                playlistRequest = PlaylistItemMapper.addRequest(track: track, in: session)
                            }
                        )
                        .contextMenu {
                            Button {
                                playlistRequest = PlaylistItemMapper.addRequest(track: track, in: session)
                            } label: {
                                Label("Thêm vào playlist", systemImage: "text.badge.plus")
                            }
                        }
                        .id(track.index)
                    }
                    AudioSuggestionSection()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .onAppear {
                scrollToCurrent(proxy, animated: false)
                loadSuggestionsIfVisible()
            }
            .onChange(of: isVisible) { _, visible in
                if visible {
                    scrollToCurrent(proxy, animated: false)
                    loadSuggestionsIfVisible()
                }
            }
            .onChange(of: current) { _, _ in
                if isVisible { scrollToCurrent(proxy, animated: true) }
            }
            .onChange(of: session.bookId) { _, _ in
                loadSuggestionsIfVisible()
            }
        }
    }

    /// Trang đang hiện ⇒ tải gợi ý của album (nhóm đầu thường đã có sẵn từ lượt tải trước của tự phát; các nhóm sau tải
    /// lúc này). Cùng album gọi lại không gọi nguồn lần nữa.
    private func loadSuggestionsIfVisible() {
        guard isVisible, let album = AudioSuggestionStore.Album.snapshot(of: session) else { return }
        AudioSuggestionStore.shared.loadForDisplay(album)
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let current = session.currentTrackIndex else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(current, anchor: .center)
            }
        } else {
            proxy.scrollTo(current, anchor: .center)
        }
    }
}
