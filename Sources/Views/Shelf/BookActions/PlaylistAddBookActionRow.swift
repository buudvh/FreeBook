import SwiftUI

/// Hàng "Thêm cả album / phim vào playlist" của sheet nhấn giữ (`BookActionSheet`) — chỉ cho album âm thanh và phim.
///
/// Tự lo trọn: bấm ⇒ lấy mọi bài / tập của mục lục (`PlaylistAlbumItemsLoader`: mục lục trên máy, chưa có thì tải từ tiện
/// ích; có vòng chờ trên hàng, lỗi thì toast) ⇒ mở `PlaylistAddSheet` chồng lên sheet nhấn giữ. Sheet nhấn giữ không cần
/// thêm case `BookSheetAction` (cùng kiểu `VideoDownloadsActionRow`).
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
            PlaylistAddSheet(request: request)
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
                let items = try await PlaylistAlbumItemsLoader.items(for: album, kind: playlistKind)
                isLoading = false
                loadTask = nil
                let summary = album.title.isEmpty ? (playlistKind == .audio ? "Cả album" : "Cả phim") : album.title
                request = PlaylistAddRequest(kind: playlistKind, items: items, summary: summary)
            } catch {
                isLoading = false
                loadTask = nil
                // Lỗi của tiện ích được bọc trong `ExtensionLoadError` ⇒ bóc ra trước khi so huỷ.
                guard !(ExtensionLoadError.unwrapped(error) is CancellationError) else { return }
                AppLogger.shared.log("❌ [Playlist] Không lấy được danh sách để thêm vào playlist (bookId=\(album.bookId)): \(error.localizedDescription)")
                let noun = playlistKind.itemNoun
                ToastManager.shared.show(message: "Không lấy được danh sách \(noun): \(error.localizedDescription)", type: .error)
            }
        }
    }
}
