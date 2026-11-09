import SwiftUI

/// Trang chi tiết một playlist (trang đẩy vào từ thẻ ở tab Playlist): đầu trang (`PlaylistDetailHeader`) rồi danh sách mục
/// theo thứ tự người dùng xếp.
///
/// - Vuốt trái một hàng / nhấn giữ ⇒ bỏ mục khỏi playlist. "Sắp xếp lại" (ngăn kéo `…`) bật chế độ sửa của `List` ⇒ kéo
///   tay nắm đổi thứ tự, "Xong" ở header để thoát. Header chỉ có quay lại + `…` (chuẩn màn danh sách).
/// - Ngăn kéo `…`: Sắp xếp lại, Đổi tên, Xoá playlist (hỏi trước — `PlaylistManageAlertsModifier`).
/// - Công tắc NSFW tắt ⇒ ẩn mục của nguồn NSFW; xoá / đổi thứ tự theo **id** nên mục đang ẩn giữ nguyên chỗ.
/// - Chạm một mục chưa làm gì (phát playlist là phần sau).
struct PlaylistDetailView: View {
    let playlistId: UUID

    @Environment(\.dismiss) private var dismiss
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false
    @State private var editMode: EditMode = .inactive
    @State private var showingMenu = false
    @State private var renameTarget: Playlist? = nil
    @State private var renameText = ""
    @State private var deleteTarget: Playlist? = nil

    private var playlist: Playlist? { PlaylistRepository.shared.playlist(id: playlistId) }

    var body: some View {
        let current = playlist
        Group {
            if let current {
                content(current)
            } else {
                missingState
            }
        }
        .backPageTitle(current?.name ?? "Playlist")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if editMode.isEditing {
                    Button("Xong") {
                        withAnimation { editMode = .inactive }
                    }
                    .headerTextButton()
                } else if current != nil {
                    Button {
                        showingMenu = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 38)
                    }
                    .accessibilityLabel("Tuỳ chọn playlist")
                }
            }
        }
        .sideDrawerMenu(isPresented: $showingMenu, title: "Tuỳ chọn playlist") {
            menuItems
        }
        .playlistManageAlerts(
            renameTarget: $renameTarget,
            renameText: $renameText,
            deleteTarget: $deleteTarget,
            onDeleted: { dismiss() }
        )
    }

    // MARK: - Danh sách

    private func content(_ playlist: Playlist) -> some View {
        let items = PlaylistRepository.visibleItems(of: playlist, includeNsfw: includeNsfw)
        return List {
            PlaylistDetailHeader(playlist: playlist, visibleItems: items)
                .bookListPanelRowChrome()
            // Hàng nút phát playlist (Phát tất cả / Phát ngẫu nhiên) đặt ngay dưới đầu trang này.
            if items.isEmpty {
                emptyRow(playlist.kind)
                    .bookListPanelRowChrome()
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                    PlaylistItemRow(item: item, kind: playlist.kind, position: offset + 1)
                        .bookListPanelRow()
                        .contextMenu {
                            Button(role: .destructive) {
                                remove([item.id])
                            } label: {
                                Label("Xoá khỏi playlist", systemImage: "trash")
                            }
                        }
                }
                .onDelete { offsets in
                    remove(Set(offsets.map { items[$0].id }))
                }
                .onMove { source, destination in
                    move(items, from: source, to: destination)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
    }

    private func emptyRow(_ kind: PlaylistKind) -> some View {
        let hint: String
        switch kind {
        case .audio:
            hint = "Thêm bài từ màn nghe (ngăn kéo …, nút thêm vào playlist, nhấn giữ một bài ở trang Danh sách) hoặc nhấn giữ album trên kệ để thêm cả album."
        case .video:
            hint = "Thêm tập từ màn xem phim (ngăn kéo …, nhấn giữ một tập) hoặc nhấn giữ phim trên kệ để thêm cả phim."
        }
        return VStack(spacing: 8) {
            Text("Playlist chưa có \(kind.itemNoun) nào")
                .font(.headline)
            Text(hint)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var missingState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            Text("Playlist không còn nữa")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ngăn kéo

    @ViewBuilder
    private var menuItems: some View {
        if let current = playlist {
            if current.items.count > 1 {
                SideDrawerActionRow("Sắp xếp lại", systemImage: "arrow.up.arrow.down") {
                    withAnimation { editMode = .active }
                }
            }
            SideDrawerActionRow("Đổi tên", systemImage: "pencil") {
                renameText = current.name
                renameTarget = current
            }
            SideDrawerDivider()
            SideDrawerActionRow("Xoá playlist", systemImage: "trash", role: .destructive) {
                deleteTarget = current
            }
        }
    }

    // MARK: - Thao tác

    private func remove(_ ids: Set<UUID>) {
        if case .failure(let error) = PlaylistCoordinator.shared.removeItems(ids: ids, from: playlistId) {
            ToastManager.shared.show(message: error.localizedDescription, type: .error)
        }
    }

    /// `IndexSet` là vị trí trong danh sách **đang hiện** ⇒ đổi thành thứ tự id rồi giao coordinator.
    private func move(_ items: [PlaylistItem], from source: IndexSet, to destination: Int) {
        var orderedIds = items.map(\.id)
        orderedIds.move(fromOffsets: source, toOffset: destination)
        if case .failure(let error) = PlaylistCoordinator.shared.reorderItems(in: playlistId, orderedIds: orderedIds) {
            ToastManager.shared.show(message: error.localizedDescription, type: .error)
        }
    }
}
