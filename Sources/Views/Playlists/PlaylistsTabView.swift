import SwiftUI

/// Tab **Playlist** của Kệ sách (1.3.802): chip Tất cả / Nhạc / Video (nhớ chip đang chọn; "Tất cả" thêm ở 1.3.810, là
/// mặc định), lưới thẻ playlist của chip đó (bìa ghép từ bìa các mục đầu; ở "Tất cả" dòng số mục của thẻ có icon loại),
/// nút "+" nổi tạo playlist mới (ở "Tất cả" sheet tạo chọn sẵn Nhạc). Trống ⇒ màn mời tạo.
///
/// Chỉ đọc `PlaylistRepository`; mọi lượt ghi đi qua `PlaylistCoordinator` (sheet tạo, hộp đổi tên / xoá). Công tắc NSFW
/// tắt ⇒ bìa và số mục bỏ mục của nguồn NSFW, như thẻ Bộ sưu tập.
///
/// Lưới `LazyVGrid` trong `ScrollView` (không lồng trong hàng `List` — xem `CollectionsTabView`).
struct PlaylistsTabView: View {
    /// Khoá `@AppStorage` của chip đang chọn (giá trị = `PlaylistKindFilter.rawValue`: `"all"` / `"audio"` / `"video"` —
    /// hai giá trị sau trùng `PlaylistKind.rawValue` đã lưu trước 1.3.810).
    static let kindDefaultsKey = "shelfPlaylistKind"

    @AppStorage(PlaylistsTabView.kindDefaultsKey) private var kindRaw = PlaylistKindFilter.all.rawValue
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    @State private var showingCreateSheet = false
    @State private var renameTarget: Playlist? = nil
    @State private var renameText = ""
    @State private var deleteTarget: Playlist? = nil

    private let horizontalPadding: CGFloat = 16
    private let columnSpacing: CGFloat = 16

    private var repository: PlaylistRepository { .shared }

    private var filter: PlaylistKindFilter { PlaylistKindFilter(rawValue: kindRaw) ?? .all }

    private var filterBinding: Binding<PlaylistKindFilter> {
        Binding(get: { filter }, set: { kindRaw = $0.rawValue })
    }

    var body: some View {
        let all = repository.playlists
        let current = filter
        let playlists = all.filter { current.matches($0) }
        VStack(spacing: 0) {
            PlaylistKindChipBar(selection: filterBinding, counts: Self.chipCounts(all))
            if playlists.isEmpty {
                emptyState
            } else {
                grid(playlists, showsKindIcon: current == .all)
            }
        }
        .floatingAddButton("Tạo playlist") { showingCreateSheet = true }
        .sheet(isPresented: $showingCreateSheet) {
            // "Tất cả" ⇒ chọn sẵn Nhạc, đổi được trong sheet.
            PlaylistCreateSheet(initialKind: current.kind ?? .audio) { created in
                // Đang ở "Tất cả" thì thẻ mới đã hiện ⇒ giữ chip; chip loại khác ⇒ sang chip của loại vừa tạo.
                guard filter != .all else { return }
                kindRaw = PlaylistKindFilter(kind: created.kind).rawValue
            }
        }
        .playlistManageAlerts(renameTarget: $renameTarget, renameText: $renameText, deleteTarget: $deleteTarget)
    }

    /// Số playlist của từng chip: "Tất cả" = mọi playlist, Nhạc / Video theo loại.
    private static func chipCounts(_ all: [Playlist]) -> [PlaylistKindFilter: Int] {
        var counts: [PlaylistKindFilter: Int] = [.all: all.count]
        for playlist in all {
            counts[PlaylistKindFilter(kind: playlist.kind), default: 0] += 1
        }
        return counts
    }

    // MARK: - Lưới

    private func grid(_ playlists: [Playlist], showsKindIcon: Bool) -> some View {
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
                            showsKindIcon: showsKindIcon,
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
            Text(emptyTitle)
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

    private var emptyTitle: String {
        guard let kind = filter.kind else { return "Chưa có playlist nào" }
        return "Chưa có playlist \(kind.title.lowercased()) nào"
    }

    private var emptyHint: String {
        switch filter.kind {
        case nil:
            return "Gom bài hát hoặc tập phim yêu thích từ nhiều album, nhiều phim vào một danh sách. Thêm từ màn nghe, màn xem, nút ⋮ ở Khám phá / Tìm kiếm hoặc nhấn giữ album, phim trên kệ."
        case .audio?:
            return "Gom các bài hát yêu thích từ nhiều album vào một danh sách. Thêm bài từ màn nghe (ngăn kéo …, nhấn giữ một bài) hoặc nhấn giữ album trên kệ."
        case .video?:
            return "Gom các tập phim từ nhiều phim vào một danh sách. Thêm tập từ màn xem (ngăn kéo …, nhấn giữ một tập) hoặc nhấn giữ phim trên kệ."
        }
    }

    private func beginRename(_ playlist: Playlist) {
        renameText = playlist.name
        renameTarget = playlist
    }
}
