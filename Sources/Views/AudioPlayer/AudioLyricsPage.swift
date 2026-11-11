import SwiftUI

/// Trang phải của màn nghe: đầu trang bìa nhỏ + tên bài + nghệ sĩ (+ bộ chọn nguồn lời khi có ≥ 2 nguồn), lời bài hát
/// (`AudioLyricsScrollView`) hoặc câu báo theo `lyricsStatus`, cuối trang thanh tua + cụm nút thu gọn.
struct AudioLyricsPage: View {
    let referer: String?
    let isVisible: Bool
    let drag: AudioMinimizeDragState
    let onMinimize: () -> Void

    private var session: AudioPlaybackSession { .shared }

    var body: some View {
        VStack(spacing: 0) {
            header
                .audioMinimizeDrag(drag, onCommit: onMinimize)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 2) {
                AudioPlayerSeekRow()
                AudioTransportControls(style: .compact)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Đầu trang

    private var header: some View {
        HStack(spacing: 12) {
            // Đĩa tròn xoay khi đang phát, cùng góc với trang Đĩa / đĩa góc dưới (`AudioCoverRotation`); không có bìa ⇒ nốt nhạc.
            AudioRotatingCover(
                coverUrl: session.coverUrl,
                referer: referer,
                size: 48,
                isRotating: isVisible && session.isPlaying
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(session.currentTrack?.displayTitle ?? session.displayAlbumTitle)
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(session.currentArtist.isEmpty ? " " : session.currentArtist)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if session.lyricSources.count >= 2 {
                lyricSourceMenu
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var lyricSourceMenu: some View {
        Menu {
            ForEach(session.lyricSources) { source in
                Button {
                    session.selectLyricSource(source)
                } label: {
                    if source.id == session.selectedLyricSourceId {
                        Label(source.displayLabel, systemImage: "checkmark")
                    } else {
                        Text(source.displayLabel)
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Chọn nguồn lời")
    }

    // MARK: - Lời

    @ViewBuilder
    private var content: some View {
        switch session.lyricsStatus {
        case .unavailable:
            notice(systemImage: "text.quote", text: "Bài này không có lời")
        case .pending, .loading:
            VStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text("Đang tải lời bài hát…")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        case .failed(let message):
            VStack(spacing: 10) {
                notice(systemImage: "exclamationmark.bubble", text: "Không tải được lời bài hát")
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
                if let source = retrySource {
                    Button {
                        session.selectLyricSource(source)
                    } label: {
                        Label("Thử lại", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(Color.white.opacity(0.16), in: Capsule())
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .loaded:
            if let lyrics = session.lyrics, !lyrics.lines.isEmpty {
                AudioLyricsScrollView(lyrics: lyrics, isVisible: isVisible)
            } else {
                notice(systemImage: "text.quote", text: "Bài này không có lời")
            }
        }
    }

    /// Nguồn lời để "Thử lại": nguồn đang chọn, chưa chọn được thì nguồn đầu tiên.
    private var retrySource: AudioLyricSource? {
        let sources = session.lyricSources
        return sources.first { $0.id == session.selectedLyricSourceId } ?? sources.first
    }

    private func notice(systemImage: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(Color.white.opacity(0.6))
    }
}
