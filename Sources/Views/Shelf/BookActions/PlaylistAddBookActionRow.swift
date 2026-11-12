import SwiftUI

/// Hàng "Thêm cả album / phim vào playlist" của sheet nhấn giữ (`BookActionSheet`) — chỉ cho album âm thanh và phim.
///
/// Tự lo trọn: bấm ⇒ lấy mọi bài / tập của mục lục (`PlaylistAlbumItemsLoader.addRequest`: mục lục trên máy, chưa có thì
/// tải từ tiện ích — cùng đường với ⋮ của item danh sách; có vòng chờ trên hàng, lỗi thì toast `PlaylistAddFeedback`) ⇒
/// mở `PlaylistAddSheet` chồng lên sheet nhấn giữ. Sheet nhấn giữ không cần thêm case `BookSheetAction` (cùng kiểu
/// `VideoDownloadsActionRow`).
struct PlaylistAddBookActionRow: View {
    let book: Book
    let kind: PlaylistKind

    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var request: PlaylistAddRequest? = nil

    var body: some View {
        Button {
            load()
        } label: {
            HStack {
                Label(kind == .audio ? "Thêm cả album vào playlist" : "Thêm cả phim vào playlist", systemImage: "text.badge.plus")
                Spacer(minLength: 8)
                if isLoading {
                    ProgressView()
                }
            }
        }
        .disabled(isLoading)
        .sheet(item: $request) { request in
            Group {
                PlaylistAddSheet(request: request)
            }
            .appGlassSheet()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func load() {
        guard !isLoading else { return }
        let album = PlaylistItemMapper.album(of: book)
        let playlistKind = self.kind
        isLoading = true
        loadTask = Task { @MainActor in
            do {
                let built = try await PlaylistAlbumItemsLoader.addRequest(for: album, kind: playlistKind)
                isLoading = false
                loadTask = nil
                request = built
            } catch {
                isLoading = false
                loadTask = nil
                PlaylistAddFeedback.reportLoadFailure(error, album: album, kind: playlistKind)
            }
        }
    }
}
