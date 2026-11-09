import SwiftUI

/// Tab **Playlist** của Kệ sách (1.3.802): chip Nhạc / Video (nhớ chip đang chọn), lưới thẻ playlist của loại đó (bìa ghép
/// từ bìa các mục đầu), nút "+" nổi tạo playlist mới. Trống ⇒ màn mời tạo.
///
/// Chỉ đọc `PlaylistRepository`; mọi lượt ghi đi qua `PlaylistCoordinator` (sheet tạo, hộp đổi tên / xoá). Công tắc NSFW
/// tắt ⇒ bìa và số mục bỏ mục của nguồn NSFW, như thẻ Bộ sưu tập.
///
/// Lưới `LazyVGrid` trong `ScrollView` (không lồng trong hàng `List` — xem `CollectionsTabView`).
struct PlaylistsTabView: View {
    /// Khoá `@AppStorage` của chip loại đang chọn (giá trị = `PlaylistKind.rawValue`).
    static let kindDefaultsKey = "shelfPlaylistKind"

    @AppStorage(PlaylistsTabView.kindDefaultsKey) private var kindRaw = PlaylistKind.audio.rawValue
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    @State private var showingCreateSheet = false
    @State private var renameTarget: Playlist? = nil
    @State private var renameText = ""
    @State private var deleteTarget: Playlist? = nil

    private let horizontalPadding: CGFloat = 16
    private let columnSpacing: CGFloat = 16

    private var repository: PlaylistRepository { .shared }

    private var kind: PlaylistKind { PlaylistKind(rawValue: kindRaw) ?? .audio }

    private var kindBinding: Binding<PlaylistKind> {
        Binding(get: { kind }, set: { kindRaw = $0.rawValue })
    }

    var body: some View {
        let all = repository.playlists
        let playlists = all.filter { $0.kind == kind }
        let counts = Dictionary(grouping: all, by: \.kind).mapValues(\.count)
        VStack(spacing: 0) {
            PlaylistKindChipBar(selection: kindBinding, counts: counts)
            if playlists.isEmpty {
                emptyState
            } else {
                grid(playlists)
            }
        }
        .floatingAddButton("Tạo playlist") { showingCreateSheet = true }
        .sheet(isPresented: $showingCreateSheet) {
            PlaylistCreateSheet(initialKind: kind) { created in
                kindRaw = created.kind.rawValue
            }
        }
        .playlistManageAlerts(renameTarget: $renameTarget, renameText: $renameText, deleteTarget: $deleteTarget)
    }

    // MARK: - Lưới

    private func grid(_ playlists: [Playlist]) -> some View {
        GeometryReader { geometry in
            // Cột `.fixed` theo bề rộng đã tính (như `CollectionsTabView`): thẻ và bìa ghép rộng đúng bằng nhau.
            let cardSize = max(80, ((geometry.size.width - horizontalPadding * 2 - columnSpacing) / 2).rounded(.down))
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.fixed(cardSize), spacing: columnSpacing),
                        GridItem(.fixed(cardSize), spacing: columnSpacing)
                    ],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(playlists) { playlist in
                        PlaylistGridCardView(
                            playlist: playlist,
                            visibleItems: PlaylistRepository.visibleItems(of: playlist, includeNsfw: includeNsfw),
                            size: cardSize,
                            onRename: { beginRename(playlist) },
                            onDelete: { deleteTarget = playlist }
                        )
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Trống

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.secondary)
            Text("Chưa có playlist \(kind.title.lowercased()) nào")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(emptyHint)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showingCreateSheet = true
            } label: {
                Label("Tạo playlist", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.appFilled(.accentColor, fullWidth: false))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyHint: String {
        switch kind {
        case .audio:
            return "Gom các bài hát yêu thích từ nhiều album vào một danh sách. Thêm bài từ màn nghe (ngăn kéo …, nhấn giữ một bài) hoặc nhấn giữ album trên kệ."
        case .video:
            return "Gom các tập phim từ nhiều phim vào một danh sách. Thêm tập từ màn xem (ngăn kéo …, nhấn giữ một tập) hoặc nhấn giữ phim trên kệ."
        }
    }

    private func beginRename(_ playlist: Playlist) {
        renameText = playlist.name
        renameTarget = playlist
    }
}
