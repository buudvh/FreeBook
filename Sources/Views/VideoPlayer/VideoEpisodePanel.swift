import SwiftUI

/// Bảng danh sách tập trượt từ phải khi xem toàn màn. Hai kiểu như sheet "Tất cả tập" của màn xem, chọn bằng nút đổi
/// kiểu cạnh nút đóng và nhớ chung theo tiện ích (`VideoEpisodeLayoutMode`): **Lưới** (nhóm theo section như màn dọc)
/// hoặc **Danh sách** (`VideoEpisodeListView` không có đầu panel Mục lục — panel hẹp, phủ lên phim nên không có ô tìm,
/// ↓↑). Chạm vùng trống bên trái hoặc nút đóng để ẩn; chọn tập thì phát và ẩn bảng.
@MainActor
struct VideoEpisodePanel: View {
    let session: VideoPlaybackSession
    let onClose: () -> Void

    @State private var layout: VideoEpisodeLayoutMode

    init(session: VideoPlaybackSession, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
        _layout = State(initialValue: VideoEpisodeLayoutMode.load(packageId: session.launch?.extensionPackageId))
    }

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

    private var downloadActions: VideoEpisodeDownloadActions? {
        session.isLocalMedia ? nil : VideoEpisodeDownloadActions(session: session)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Danh sách tập")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                VideoPlayerIconButton(
                    systemName: layout.toggleSymbolName,
                    label: layout.toggleAccessibilityLabel,
                    action: toggleLayout
                )
                VideoPlayerIconButton(systemName: "xmark", label: "Đóng danh sách tập", action: onClose)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(height: 44)

            switch layout {
            case .grid:
                gridContent
            case .list:
                VideoEpisodeListView(
                    episodes: session.episodes,
                    currentIndex: session.currentEpisodeIndex,
                    downloadActions: downloadActions,
                    showsTOCHeader: false,
                    onSelect: select
                )
            }
        }
        .onAppear { VideoEpisodeDownloadActions(session: session).refresh() }
        .background(Color.black.opacity(0.88).ignoresSafeArea())
    }

    private var gridContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VideoEpisodeGridView(
                    episodes: session.episodes,
                    currentIndex: session.currentEpisodeIndex,
                    downloadActions: downloadActions,
                    onSelect: select
                )
                .padding(.vertical, 12)
            }
            .onAppear {
                proxy.scrollTo(session.currentEpisodeIndex, anchor: .center)
            }
        }
    }

    private func select(_ episode: VideoPlaybackSession.Episode) {
        session.selectEpisode(episode)
        onClose()
    }

    /// Đổi Lưới ⇄ Danh sách và nhớ cho tiện ích của phim đang phát (cùng khoá với sheet "Tất cả tập").
    private func toggleLayout() {
        layout = layout.toggled
        VideoEpisodeLayoutMode.save(layout, packageId: session.launch?.extensionPackageId)
    }
}
