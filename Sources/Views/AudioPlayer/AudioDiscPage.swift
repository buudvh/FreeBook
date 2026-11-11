import SwiftUI

/// Trang giữa của màn nghe: đĩa bìa xoay (`AudioRotatingCover`, cùng góc với đĩa của đĩa góc dưới), tên bài + nghệ sĩ + ♡
/// (kệ), một dòng lời đang hát (hoặc khối lỗi), thanh tua, cụm nút và hàng phụ (tốc độ, sang trang Danh sách / Lời).
///
/// Vuốt xuống trên đĩa / dòng tên bài ⇒ thu nhỏ màn (`audioMinimizeDrag`); thanh tua không gắn cử chỉ đó.
struct AudioDiscPage: View {
    let referer: String?
    /// Trang đang hiện và app đang mở — đĩa chỉ xoay khi `true` **và** nhạc đang phát.
    let isOnScreen: Bool
    let drag: AudioMinimizeDragState
    let onMinimize: () -> Void
    let isOnShelf: Bool
    let canToggleShelf: Bool
    let onToggleShelf: () -> Void
    let onShowPage: (AudioPlayerPage) -> Void
    @Binding var openingErrorLink: SourceErrorLink?

    private var session: AudioPlaybackSession { .shared }

    var body: some View {
        GeometryReader { proxy in
            let side = max(120, min(proxy.size.width * 0.7, proxy.size.height * 0.44))
            VStack(spacing: 0) {
                Spacer(minLength: 8)
                AudioRotatingCover(
                    coverUrl: session.coverUrl,
                    referer: referer,
                    size: side,
                    isRotating: isOnScreen && session.isPlaying
                )
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                .contentShape(Circle())
                .audioMinimizeDrag(drag, onCommit: onMinimize)
                Spacer(minLength: 16)
                titleRow
                    .audioMinimizeDrag(drag, onCommit: onMinimize)
                statusSlot
                    .padding(.top, 6)
                AudioPlayerSeekRow()
                    .padding(.top, 10)
                AudioTransportControls(style: .full)
                    .padding(.top, 4)
                AudioSecondaryControls(onShowPage: onShowPage)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var trackTitle: String {
        if let track = session.currentTrack { return track.displayTitle }
        if !session.albumTitle.isEmpty { return session.displayAlbumTitle }
        return "Đang tải…"
    }

    private var titleRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trackTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(session.currentArtist.isEmpty ? " " : session.currentArtist)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            Button(action: onToggleShelf) {
                Image(systemName: isOnShelf ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isOnShelf ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.85)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canToggleShelf)
            .opacity(canToggleShelf ? 1 : 0.4)
            .accessibilityLabel(isOnShelf ? "Bỏ khỏi kệ" : "Thêm vào kệ")
        }
    }

    @ViewBuilder
    private var statusSlot: some View {
        if case .failed(let message, let link) = session.phase {
            AudioPlaybackErrorView(message: message, link: link, openingErrorLink: $openingErrorLink)
        } else {
            AudioCurrentLyricLine()
        }
    }
}
