import SwiftUI

/// Icon "Thêm vào playlist" (`text.badge.plus`) cho cả một album / phim chưa mở — chỉ một việc nên chạm là làm ngay, không
/// có menu (1.3.810; dùng ở dòng gợi ý của trang Danh sách màn nghe). Chạm ⇒ tải mọi bài / tập
/// (`PlaylistAlbumItemsLoader.addRequest`; bài lẻ ⇒ đúng bài đó) ⇒ mở `PlaylistAddSheet`; đang tải thì vòng xoay thay
/// icon, lỗi ⇒ toast (`PlaylistAddFeedback`).
///
/// `makeAlbum` chạy lúc chạm (tra `Book` trên máy ở đó, không trong `body`); trả `nil` ⇒ không làm gì. Đặt **cạnh** nút mở
/// item, không trong `label` của nó.
struct PlaylistAlbumAddButton: View {
    let kind: PlaylistKind
    /// Màu icon — màn nghe / màn xem nền tối truyền trắng mờ.
    var tint: Color = .secondary
    let makeAlbum: () -> PlaylistAlbumInfo?

    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var request: PlaylistAddRequest? = nil

    var body: some View {
        Button {
            load()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(tint)
                } else {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 32, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(kind == .audio ? "Thêm album vào playlist" : "Thêm phim vào playlist")
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
        guard !isLoading, let album = makeAlbum() else { return }
        let playlistKind = kind
        isLoading = true
        loadTask = Task { @MainActor in
            do {
                let built = try await PlaylistAlbumItemsLoader.addRequest(for: album, kind: playlistKind)
                isLoading = false
                loadTask = nil
                guard !Task.isCancelled else { return }
                request = built
            } catch {
                isLoading = false
                loadTask = nil
                PlaylistAddFeedback.reportLoadFailure(error, album: album, kind: playlistKind)
            }
        }
    }
}
