import SwiftUI

/// Ảnh bìa của một kết quả tìm kiếm — tách khỏi `SearchView.swift` để file gốc không vượt baseline dòng.
///
/// Bìa tải qua `RemoteCoverImage` kèm `Referer` (host item → `source` của tiện ích), cộng nhãn `tag` góc dưới.
/// `result.cover` đã được resolve lúc parse (`ExtensionURLFormatter.resolveAssetURL`), nên chỉ cần phòng hờ dạng
/// tương đối / `//` bằng `CoverRequestResolver.displayURL`. `static` để `SearchSingleSourceResultsView` dùng chung.
extension SearchView {
    static func searchResultCover(_ result: ExtensionItemResult, ext: Extension, width: CGFloat, height: CGFloat) -> some View {
        RemoteCoverImage(
            url: CoverRequestResolver.displayURL(result.cover, itemHost: result.host, packageId: ext.packageId),
            referer: CoverRequestResolver.referer(itemHost: result.host, packageId: ext.packageId)
        )
        .frame(width: width, height: height)
        .overlay(alignment: .bottomLeading) {
            CoverTagBadge(tag: result.tag)
        }
        .cornerRadius(6)
        .clipped()
    }
}
