import SwiftUI

/// Thanh thao tác của chế độ chọn nhiều ở Kệ Sách / Lịch Sử (anh Bửu duyệt mockup
/// https://claude.ai/artifact/Es6YfEe94Zyi2uigCzMTPX): đè đúng chỗ thanh tab — cùng khuôn `MainTabBar` (vạch + hàng 49pt,
/// icon 21 / chữ 10) — `ShelfView` gắn bằng `overlay(alignment: .bottom)` ngay sau `.mainTabBar()`, không sửa thanh tab
/// dùng chung. Nền `.bar` chồng lên nền đặc `systemBackground` để thanh tab bên dưới không lộ qua lớp kính; `contentShape`
/// nuốt mọi chạm của vùng thanh.
///
/// Ba ô: **Thêm vào playlist** · **Thêm vào bộ sưu tập** · **Xoá** (đỏ). Chưa chọn truyện nào ⇒ cả ba mờ và tắt.
/// - Playlist và bộ sưu tập do thanh tự lo trọn (sheet trình bày từ đây, như `PlaylistAddBookActionRow`); thêm xong ⇒
///   `onFinished` (thoát chế độ chọn) trong `onDismiss` của sheet. Vuốt đóng sheet mà chưa thêm ⇒ giữ lựa chọn.
/// - Xoá chỉ hỏi (hộp xác nhận) rồi trả lựa chọn cho `ShelfView` — màn đó giữ `modelContext` và lớp chờ "Đang dọn dẹp
///   sách...".
///
/// Playlist chỉ nhận album âm thanh / phim, mỗi playlist một loại (`PlaylistKind`, phân loại như `PlaylistAddBookActionRow`):
/// không có cuốn nào hợp ⇒ ô mờ, bấm ⇒ toast; có cả hai loại ⇒ hỏi Nhạc / Video; mục lục lấy **lần lượt** từng album / phim
/// (`PlaylistAlbumItemsLoader.items`: trên máy trước, chưa có thì tải từ tiện ích — tuần tự như tải truyện), ô hiện
/// "Đang lấy i/N · Huỷ", bấm lần nữa ⇒ huỷ. Truyện khác loại và album lỗi mục lục bị bỏ qua, báo gộp một toast.
struct ShelfSelectionActionBar: View {
    enum DeleteChoice {
        /// Kệ Sách: rời kệ, về Lịch sử.
        case removeFromShelf
        /// Kệ Sách: xoá hẳn khỏi máy.
        case deleteFromDevice
        /// Lịch Sử: trên kệ ⇒ chỉ rời Lịch sử; không ở kệ ⇒ xoá khỏi máy (như "Xoá lịch sử" từng truyện).
        case removeFromHistory
    }

    /// Lựa chọn có cả album âm thanh lẫn phim ⇒ hỏi loại playlist.
    private struct PlaylistKindChoice {
        let audio: [Book]
        let video: [Book]
        let skipped: Int
    }

    let page: ShelfTab
    /// Truyện đã chọn **đang hiện** của trang (đã giao với danh sách đã lọc), theo thứ tự của trang.
    let books: [Book]
    let onDelete: (DeleteChoice, [Book]) -> Void
    let onFinished: () -> Void

    @State private var showingDeleteDialog = false
    @State private var showingCollectionSheet = false
    @State private var playlistKindChoice: PlaylistKindChoice? = nil
    @State private var playlistTask: Task<Void, Never>? = nil
    @State private var playlistLoaded = 0
    @State private var playlistTotal = 0
    @State private var playlistRequest: PlaylistAddRequest? = nil
    /// Sheet báo đã thêm ⇒ thoát chế độ chọn khi sheet đóng hẳn (`finishIfAdded`).
    @State private var didAdd = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                playlistButton
                barButton("Thêm vào bộ sưu tập", systemImage: "folder.badge.plus") {
                    showingCollectionSheet = true
                }
                barButton("Xoá", systemImage: "trash", isDestructive: true) {
                    showingDeleteDialog = true
                }
            }
            .frame(height: MainTabBar.barHeight)
        }
        .background(.bar, ignoresSafeAreaEdges: .bottom)
        .background(Color(.systemBackground), ignoresSafeAreaEdges: .bottom)
        .contentShape(Rectangle())
        .disabled(books.isEmpty)
        .confirmationDialog(deleteTitle, isPresented: $showingDeleteDialog, titleVisibility: .visible) {
            deleteButtons
        } message: {
            Text(deleteMessage)
        }
        .confirmationDialog(
            "Thêm vào playlist loại nào?",
            isPresented: kindChoiceBinding,
            titleVisibility: .visible,
            presenting: playlistKindChoice
        ) { choice in
            Button("Nhạc · \(choice.audio.count) album") {
                loadPlaylist(choice.audio, kind: .audio, skipped: choice.skipped + choice.video.count)
            }
            Button("Video · \(choice.video.count) phim") {
                loadPlaylist(choice.video, kind: .video, skipped: choice.skipped + choice.audio.count)
            }
            Button("Hủy", role: .cancel) {}
        }
        .sheet(isPresented: $showingCollectionSheet, onDismiss: finishIfAdded) {
            Group {
                CollectionBatchAddSheet(books: books) { didAdd = true }
            }
            .appGlassSheet()
        }
        .sheet(item: $playlistRequest, onDismiss: finishIfAdded) { request in
            Group {
                PlaylistAddSheet(request: request) { didAdd = true }
            }
            .appGlassSheet()
        }
        .onDisappear {
            playlistTask?.cancel()
            playlistTask = nil
        }
    }

    // MARK: - Ô của thanh

    private var playlistButton: some View {
        let isLoading = playlistTask != nil
        let hasPlayable = books.contains { ExtensionContentKind.resolve(packageId: $0.extensionPackageId).isPlayable }
        return Button {
            if isLoading {
                cancelPlaylist()
            } else {
                startPlaylist()
            }
        } label: {
            barLabel(
                isLoading ? "Đang lấy \(playlistLoaded)/\(playlistTotal) · Huỷ" : "Thêm vào playlist",
                systemImage: "text.badge.plus",
                color: .accentColor,
                isLoading: isLoading
            )
        }
        .buttonStyle(.plain)
        // Không có album / phim nào ⇒ mờ nhưng vẫn bấm được để toast lý do.
        .opacity(books.isEmpty || !hasPlayable ? 0.35 : 1)
        .accessibilityLabel(isLoading ? "Huỷ lấy mục lục cho playlist" : "Thêm vào playlist")
    }

    private func barButton(
        _ title: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            barLabel(title, systemImage: systemImage, color: isDestructive ? .red : .accentColor, isLoading: false)
        }
        .buttonStyle(.plain)
        .opacity(books.isEmpty ? 0.35 : 1)
    }

    /// Khuôn ô của `MainTabBar`: icon 21pt trong khung cao 26, chữ 10pt vừa, cách 3.
    private func barLabel(_ title: String, systemImage: String, color: Color, isLoading: Bool) -> some View {
        VStack(spacing: 3) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 21))
                }
            }
            .frame(height: 26)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Xoá

    private var deleteTitle: String {
        page == .history ? "Xoá \(books.count) truyện khỏi lịch sử" : "Xoá \(books.count) truyện đã chọn"
    }

    private var deleteMessage: String {
        if page == .history {
            return "Truyện trên kệ chỉ rời Lịch sử. Truyện không ở trên kệ bị xoá khỏi máy, không hoàn tác. Truyện đang nghe được giữ."
        }
        return "Xoá hẳn: mất chương đã tải và tiến độ, không hoàn tác. Truyện đang nghe được giữ."
    }

    @ViewBuilder
    private var deleteButtons: some View {
        if page == .history {
            Button("Xoá khỏi lịch sử", role: .destructive) { onDelete(.removeFromHistory, books) }
        } else {
            Button("Bỏ khỏi kệ (về Lịch sử)") { onDelete(.removeFromShelf, books) }
            Button("Xoá hẳn khỏi máy", role: .destructive) { onDelete(.deleteFromDevice, books) }
        }
        Button("Hủy", role: .cancel) {}
    }

    // MARK: - Playlist

    private var kindChoiceBinding: Binding<Bool> {
        Binding(
            get: { playlistKindChoice != nil },
            set: { if !$0 { playlistKindChoice = nil } }
        )
    }

    private func startPlaylist() {
        var audio: [Book] = []
        var video: [Book] = []
        for book in books {
            switch PlaylistKind(contentKind: BookContentKindResolver.kind(bookId: book.bookId, packageId: book.extensionPackageId)) {
            case .audio?: audio.append(book)
            case .video?: video.append(book)
            case nil: break
            }
        }
        let skipped = books.count - audio.count - video.count
        if audio.isEmpty && video.isEmpty {
            ToastManager.shared.show(message: "Playlist chỉ nhận album âm thanh và phim", type: .info)
        } else if !audio.isEmpty && !video.isEmpty {
            playlistKindChoice = PlaylistKindChoice(audio: audio, video: video, skipped: skipped)
        } else if audio.isEmpty {
            loadPlaylist(video, kind: .video, skipped: skipped)
        } else {
            loadPlaylist(audio, kind: .audio, skipped: skipped)
        }
    }

    /// Lấy mục lục **lần lượt** từng album / phim rồi mở `PlaylistAddSheet` với cả lô.
    private func loadPlaylist(_ albumBooks: [Book], kind: PlaylistKind, skipped: Int) {
        let albums = albumBooks.map { PlaylistItemMapper.album(of: $0) }
        let albumNoun = kind == .audio ? "album" : "phim"
        playlistLoaded = 0
        playlistTotal = albums.count
        playlistTask = Task { @MainActor in
            var items: [PlaylistItem] = []
            var failed = 0
            for album in albums {
                do {
                    items += try await PlaylistAlbumItemsLoader.items(for: album, kind: kind)
                } catch {
                    if Task.isCancelled { return }
                    failed += 1
                    AppLogger.shared.log("❌ [ShelfSelection] Không lấy được mục lục cho playlist (tiện ích=\(album.packageId)): \(error.localizedDescription)")
                }
                if Task.isCancelled { return }
                playlistLoaded += 1
            }
            playlistTask = nil

            var notes: [String] = []
            if skipped > 0 { notes.append("bỏ qua \(skipped) truyện không phải \(albumNoun)") }
            if failed > 0 { notes.append("\(failed) \(albumNoun) lỗi mục lục") }
            let noteText = notes.joined(separator: ", ")
            guard !items.isEmpty else {
                let reason = noteText.isEmpty ? "" : " — \(noteText)"
                ToastManager.shared.show(message: "Không lấy được \(kind.itemNoun) nào\(reason)", type: .error)
                return
            }
            if !noteText.isEmpty {
                ToastManager.shared.show(message: "Lấy được \(kind.countLabel(items.count)) — \(noteText)", type: .info)
            }
            let summary = albums.count == 1 && !albums[0].title.isEmpty ? albums[0].title : "\(albums.count) \(albumNoun)"
            playlistRequest = PlaylistAddRequest(kind: kind, items: items, summary: summary)
        }
    }

    private func cancelPlaylist() {
        playlistTask?.cancel()
        playlistTask = nil
    }

    private func finishIfAdded() {
        guard didAdd else { return }
        didAdd = false
        onFinished()
    }
}
