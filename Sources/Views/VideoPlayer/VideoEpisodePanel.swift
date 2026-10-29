import SwiftUI

/// Bảng danh sách tập trượt từ phải khi xem toàn màn (lưới nhóm theo section như màn dọc). Chạm vùng trống bên trái
/// hoặc nút đóng để ẩn; chọn tập thì phát và ẩn bảng.
struct VideoEpisodePanel: View {
    let session: VideoPlaybackSession
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                panel
                    .frame(width: min(360, geometry.size.width * 0.85))
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Danh sách tập")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                VideoPlayerIconButton(systemName: "xmark", label: "Đóng danh sách tập", action: onClose)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(height: 44)

            ScrollViewReader { proxy in
                ScrollView {
                    VideoEpisodeGridView(
                        episodes: session.episodes,
                        currentIndex: session.currentEpisodeIndex,
                        downloadActions: session.isLocalMedia ? nil : VideoEpisodeDownloadActions(session: session),
                        onSelect: { episode in
                            session.selectEpisode(episode)
                            onClose()
                        }
                    )
                    .padding(.vertical, 12)
                }
                .onAppear {
                    proxy.scrollTo(session.currentEpisodeIndex, anchor: .center)
                    VideoEpisodeDownloadActions(session: session).refresh()
                }
            }
        }
        .background(Color.black.opacity(0.88).ignoresSafeArea())
    }
}
