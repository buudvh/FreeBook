import SwiftUI

/// Nút ⋮ (`ellipsis` xoay 90°, khuôn ⋮ của `VideoWatchSuggestCard`) trên item danh sách của nguồn **âm thanh / phim**
/// (1.3.810): menu hai mục "Thêm vào playlist" (mọi bài / tập của album / phim — bài lẻ thì đúng bài đó) và "Thêm vào kệ".
///
/// - "Thêm vào playlist": `PlaylistAlbumItemsLoader.addRequest` (mục lục trên máy, chưa có thì tải từ tiện ích) ⇒ mở
///   `PlaylistAddSheet`; trong lúc tải ⋮ thành vòng xoay, lỗi ⇒ toast (`PlaylistAddFeedback`).
/// - "Thêm vào kệ": `VideoWatchShelfAdder` (đã có `Book` ⇒ bật cờ kệ; chưa có ⇒ tải chi tiết + mục lục rồi tạo).
///
/// Tự giữ trạng thái + sheet (như `PlaylistAddBookActionRow`). Chỗ gắn **không** đặt nút này trong `label` của nút /
/// link mở item — gắn cạnh (anh em) hoặc `overlay` lên nút đó.
struct PlaylistListItemMenu: View {
    enum Style {
        /// Cuối hàng danh sách: 17pt nửa đậm, màu phụ.
        case row
        /// Cạnh tên dưới bìa của thẻ lưới / thẻ ngang: 15pt nửa đậm, màu phụ.
        case card
        /// Đè lên góc bìa (lưới chỉ bìa): chấm tròn nền tối, ⋮ trắng.
        case onCover

        /// Chỗ đặt khi đè lên nút mở item (`playlistListItemMenuOverlay`): hàng ⇒ giữa mép phải; thẻ ⇒ góc dưới phải
        /// (cạnh tên / mô tả); chỉ bìa ⇒ góc trên phải bìa (góc trên trái là nhãn `tag`).
        var overlayAlignment: Alignment {
            switch self {
            case .row: return .trailing
            case .card: return .bottomTrailing
            case .onCover: return .topTrailing
            }
        }
    }

    let item: ExtensionItemResult
    /// Link chi tiết khác `item.link` (mục Khám phá có action `detail`); `nil` ⇒ `item.link`.
    var detailUrl: String? = nil
    let context: PlaylistListAddContext
    var style: Style = .row

    @State private var isLoadingPlaylist = false
    @State private var isAddingToShelf = false
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var request: PlaylistAddRequest? = nil

    private var isBusy: Bool { isLoadingPlaylist || isAddingToShelf }

    var body: some View {
        Menu {
            Button {
                addToPlaylist()
            } label: {
                Label("Thêm vào playlist", systemImage: "text.badge.plus")
            }
            .disabled(isLoadingPlaylist)
            Button {
                addToShelf()
            } label: {
                Label("Thêm vào kệ", systemImage: "plus.circle")
            }
            .disabled(isAddingToShelf)
        } label: {
            glyph
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        // Như menu chuyển từ của `DictionaryEntryRow`: trong hàng `List`, Menu kiểu mặc định có thể nhận chạm của cả hàng
        // (chạm item lại mở ⋮) — kiểu không viền chỉ nhận chạm trong khung nút.
        .menuStyle(.borderlessButton)
        .accessibilityLabel(context.kind == .audio ? "Tuỳ chọn album" : "Tuỳ chọn phim")
        // Thẻ hẹp: vùng chạm vẫn 32 × 36 nhưng chỉ chiếm 20 × 16 trong bố cục (tràn sang khe giữa các thẻ) ⇒ tên dưới
        // bìa không bị ép hẹp, ⋮ ngang dòng tên đầu.
        .padding(style == .card ? EdgeInsets(top: -10, leading: -6, bottom: -10, trailing: -6) : EdgeInsets())
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

    @ViewBuilder
    private var glyph: some View {
        switch style {
        case .row, .card:
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: style == .row ? 17 : 15, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        case .onCover:
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 26, height: 26)
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                } else {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Thao tác

    private func addToPlaylist() {
        guard !isLoadingPlaylist else { return }
        let album = context.album(of: item, detailUrl: detailUrl)
        let kind = context.kind
        isLoadingPlaylist = true
        loadTask = Task { @MainActor in
            do {
                let built = try await PlaylistAlbumItemsLoader.addRequest(for: album, kind: kind)
                isLoadingPlaylist = false
                loadTask = nil
                guard !Task.isCancelled else { return }
                request = built
            } catch {
                isLoadingPlaylist = false
                loadTask = nil
                PlaylistAddFeedback.reportLoadFailure(error, album: album, kind: kind)
            }
        }
    }

    private func addToShelf() {
        guard !isAddingToShelf else { return }
        isAddingToShelf = true
        let shelfRequest = context.shelfRequest(for: item, detailUrl: detailUrl)
        let container = context.modelContainer
        let kind = context.kind
        Task { @MainActor in
            let outcome = await VideoWatchShelfAdder.add(shelfRequest, modelContainer: container)
            isAddingToShelf = false
            PlaylistAddFeedback.reportShelf(outcome, title: shelfRequest.title, kind: kind)
        }
    }
}

extension View {
    /// Đè ⋮ (`PlaylistListItemMenu`) lên nút / link mở item — **không** lồng trong `label` của nó. Hàng danh sách chừa lề
    /// phải cho ⋮ trước khi gắn panel; thẻ lưới chừa bằng `DiscoveryNovelGridCardView.reservesMenuSpace`. `context == nil`
    /// (truyện chữ / truyện tranh, đang đổi nguồn) ⇒ giữ nguyên view.
    @ViewBuilder
    func playlistListItemMenuOverlay(
        item: ExtensionItemResult,
        context: PlaylistListAddContext?,
        style: PlaylistListItemMenu.Style
    ) -> some View {
        if let context {
            overlay(alignment: style.overlayAlignment) {
                PlaylistListItemMenu(item: item, context: context, style: style)
            }
        } else {
            self
        }
    }
}
