import Foundation

/// Đầu vào của sheet "Thêm vào playlist" (`PlaylistAddSheet`): các mục sắp thêm + loại playlist nhận chúng. Dùng cho
/// `.sheet(item:)` nên `Identifiable` — mỗi lần mở là một id mới.
///
/// Các lối tạo: bài/tập đang phát (màn nghe, màn xem phim), nhấn giữ hoặc icon cuối hàng của một bài/tập, nhấn giữ
/// album/phim trên Kệ (cả mục lục), ⋮ / icon của item danh sách chưa mở — Khám phá, Thể loại, Tìm, gợi ý nhạc, đề xuất phim
/// (cả mục lục, 1.3.810; dựng bằng `PlaylistAlbumItemsLoader.addRequest`).
struct PlaylistAddRequest: Identifiable, Sendable {
    let id = UUID()
    let kind: PlaylistKind
    let items: [PlaylistItem]
    /// Dòng mô tả ở đầu sheet: tên bài / tập, hoặc tên album / phim khi thêm cả mục lục.
    let summary: String

    init(kind: PlaylistKind, items: [PlaylistItem], summary: String) {
        self.kind = kind
        self.items = items
        self.summary = summary
    }

    /// Một mục: mô tả là tên mục.
    init(kind: PlaylistKind, item: PlaylistItem) {
        self.init(kind: kind, items: [item], summary: item.displayTitle(kind: kind))
    }
}
