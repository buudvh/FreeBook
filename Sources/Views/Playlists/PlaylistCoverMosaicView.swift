import SwiftUI

/// Bìa ghép của một playlist: **4 bìa khác nhau đầu tiên** xếp lưới 2 × 2; ít hơn 4 bìa khác nhau ⇒ một bìa phủ cả ô; chưa
/// có bìa nào ⇒ ô trống có icon loại. Các bài cùng album dùng chung một bìa nên phải lọc bìa trùng, không thì lưới bốn ô
/// giống hệt nhau.
///
/// Ảnh tải qua `RemoteCoverImage` (cache của `CoverImageLoader`) — **không** dùng `BookCoverView`, vốn ghi bìa xuống
/// `covers/` theo `bookId` (mục playlist không có `Book`).
struct PlaylistCoverMosaicView: View {
    let items: [PlaylistItem]
    let kind: PlaylistKind
    let size: CGFloat
    var cornerRadius: CGFloat = 12

    private let gap: CGFloat = 2

    /// Mục đại diện cho từng bìa khác nhau, theo thứ tự trong playlist (tối đa `limit`).
    static func distinctCoverItems(_ items: [PlaylistItem], limit: Int = 4) -> [PlaylistItem] {
        var seen = Set<String>()
        var picked: [PlaylistItem] = []
        for item in items {
            let url = item.coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, seen.insert(url).inserted else { continue }
            picked.append(item)
            if picked.count == limit { break }
        }
        return picked
    }

    var body: some View {
        let covers = Self.distinctCoverItems(items)
        content(covers)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func content(_ covers: [PlaylistItem]) -> some View {
        if covers.count >= 4 {
            let cell = max(0, (size - gap) / 2)
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    cover(covers[0], side: cell)
                    cover(covers[1], side: cell)
                }
                HStack(spacing: gap) {
                    cover(covers[2], side: cell)
                    cover(covers[3], side: cell)
                }
            }
        } else if let first = covers.first {
            cover(first, side: size)
        } else {
            placeholder
        }
    }

    private func cover(_ item: PlaylistItem, side: CGFloat) -> some View {
        RemoteCoverImage(url: item.coverUrl, referer: item.coverReferer, placeholderSymbol: kind.symbolName)
            .frame(width: side, height: side)
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "music.note.list")
                .font(.system(size: size * 0.28, weight: .light))
                .foregroundColor(.secondary.opacity(0.45))
        }
    }
}
