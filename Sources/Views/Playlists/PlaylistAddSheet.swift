import SwiftUI

/// Sheet "Thêm vào playlist" dùng chung cho cả ba lối (bài / tập đang phát, nhấn giữ một bài / tập, nhấn giữ album / phim
/// trên Kệ): mô tả mục sắp thêm, hàng "Tạo playlist mới" (tạo xong thêm luôn) và các playlist **cùng loại** (mới sửa
/// trước). Chạm một playlist ⇒ thêm (bỏ mục trùng), đóng sheet, toast "Đã thêm N mục vào <tên>" / "Đã có sẵn trong <tên>".
///
/// Không có nút chỉ để đóng: vuốt xuống. Mở được từ màn trình bày bằng UIKit (màn nghe, màn xem phim) — các màn đó đã gắn
/// `.appAccentTint()` ở gốc nên sheet thừa hưởng; toast ở cửa sổ riêng nên vẫn hiện trên chúng.
struct PlaylistAddSheet: View {
    let request: PlaylistAddRequest

    @Environment(\.dismiss) private var dismiss
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false
    @State private var showingCreateAlert = false
    @State private var newName = ""

    private var targets: [Playlist] {
        PlaylistRepository.shared.playlists(of: request.kind).sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryRow
                }
                Section {
                    Button {
                        newName = ""
                        showingCreateAlert = true
                    } label: {
                        Label("Tạo playlist mới", systemImage: "plus.circle.fill")
                    }
                    ForEach(targets) { playlist in
                        playlistRow(playlist)
                    }
                } header: {
                    Text("Playlist \(request.kind.title.lowercased())")
                }
            }
            .listStyle(.insetGrouped)
            .pageTitle("Thêm vào playlist")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Playlist mới", isPresented: $showingCreateAlert) {
            TextField("Tên playlist", text: $newName)
                .textInputAutocapitalization(.sentences)
            Button("Tạo") { createAndAdd() }
            Button("Hủy", role: .cancel) { newName = "" }
        } message: {
            Text("\(request.kind.countLabel(request.items.count)) sẽ được thêm vào playlist vừa tạo.")
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            PlaylistCoverMosaicView(items: request.items, kind: request.kind, size: 48, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.summary)
                    .font(.headline)
                    .lineLimit(2)
                Text(request.kind.countLabel(request.items.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        // Bìa thu nhỏ bỏ mục của nguồn NSFW khi công tắc tắt, như thẻ ở tab Playlist.
        let coverItems = PlaylistRepository.visibleItems(of: playlist, includeNsfw: includeNsfw)
        return Button {
            add(to: playlist.id)
        } label: {
            HStack(spacing: 12) {
                PlaylistCoverMosaicView(items: coverItems, kind: playlist.kind, size: 44, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(playlist.kind.countLabel(playlist.items.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thao tác

    private func createAndAdd() {
        let name = newName
        newName = ""
        switch PlaylistCoordinator.shared.create(name: name, kind: request.kind) {
        case .success(let playlist):
            add(to: playlist.id)
        case .failure(let error):
            ToastManager.shared.show(message: error.localizedDescription, type: .error)
        }
    }

    private func add(to playlistId: UUID) {
        switch PlaylistCoordinator.shared.add(request.items, to: playlistId) {
        case .success(let outcome):
            dismiss()
            if outcome.added > 0 {
                ToastManager.shared.show(message: "Đã thêm \(outcome.added) mục vào \(outcome.playlist.name)", type: .success)
            } else {
                ToastManager.shared.show(message: "Đã có sẵn trong \(outcome.playlist.name)", type: .info)
            }
        case .failure(let error):
            ToastManager.shared.show(message: error.localizedDescription, type: .error)
        }
    }
}
