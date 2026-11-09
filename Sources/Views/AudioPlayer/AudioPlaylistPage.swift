import SwiftUI

/// Trang trái của màn nghe: "Danh sách phát · N bài". Thứ tự hiển thị **luôn** theo mục lục (`tracks`), không theo thứ
/// tự xáo; số thứ tự = vị trí trong danh sách (không phải `Track.index` thưa). Chạm hàng ⇒ `playTrack(at: track.index)`.
/// Trang hiện ra (và khi đổi bài lúc đang xem) ⇒ cuộn bài đang phát vào giữa.
struct AudioPlaylistPage: View {
    let isVisible: Bool
    let drag: AudioMinimizeDragState
    let onMinimize: () -> Void

    private var session: AudioPlaybackSession { .shared }

    var body: some View {
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
        let fallbackArtist = session.albumAuthor
        let current = session.currentTrackIndex
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(session.tracks.enumerated()), id: \.element.id) { position, track in
                        AudioPlaylistRow(
                            position: position + 1,
                            title: track.displayTitle,
                            artist: track.artist.isEmpty ? fallbackArtist : track.artist,
                            isCurrent: track.index == current
                        ) {
                            AppLogger.shared.log("🎵 [AudioPlayerUI] Chọn bài \(track.index) ở danh sách phát")
                            session.playTrack(at: track.index)
                        }
                        .id(track.index)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .onAppear {
                scrollToCurrent(proxy, animated: false)
            }
            .onChange(of: isVisible) { _, visible in
                if visible { scrollToCurrent(proxy, animated: false) }
            }
            .onChange(of: current) { _, _ in
                if isVisible { scrollToCurrent(proxy, animated: true) }
            }
        }
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
