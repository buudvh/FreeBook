import SwiftUI

/// Thẻ truyện của các danh sách Khám phá kiểu cũ (tab `home`, màn Thể loại / Xem thêm) ở hai kiểu lưới của
/// `BookListLayoutMode`. Kiểu Danh sách vẫn dùng `DiscoveryNovelRowView`.
///
/// - Bìa: khung màu tỉ lệ cố định (2:3, video 16:9) với ảnh `RemoteCoverImage(.fill)` trong `overlay` — giống
///   `ExploreCoverView`, ảnh không làm phình bố cục. **Không** dùng `BookCoverView`: nó ghi bìa xuống `covers/`, còn
///   item Khám phá chỉ là danh sách tạm (xem comment đầu `DiscoveryNovelRowView`). Referer = host item → `source`.
/// - `.grid`: tên 2 dòng + mô tả 1 dòng dưới bìa (như `ExploreItemCard`).
/// - `.coverOnly`: tên đè lên dải mờ ở đáy bìa.
/// - Dịch theo cùng luật với `DiscoveryNovelRowView`: chỉ dịch khi cờ dịch **theo nguồn** bật và chuỗi có chữ Hán.
///
/// Bề rộng do cột lưới quyết định; chiều cao bìa suy ra từ `aspectRatio`. Nơi dùng bọc thẻ trong `Button`.
struct DiscoveryNovelGridCardView: View {
    let item: ExtensionItemResult
    /// `source` của tiện ích — Referer dự phòng khi item không có `host`.
    let sourceHost: String?
    /// Cờ dịch theo nguồn (`TranslationConfigStore`, do màn cha tính).
    let isTranslationEnabled: Bool
    /// `.grid` hoặc `.coverOnly`; `.list` được vẽ như `.grid` (nơi dùng không truyền giá trị này).
    let mode: BookListLayoutMode
    /// Tỉ lệ rộng : cao của bìa (`BookListLayoutScope.coverAspectRatio`).
    let aspectRatio: CGFloat

    private static let coverCornerRadius: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            cover

            if mode != .coverOnly {
                Text(displayedTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !item.description.isEmpty {
                    Text(translateIfNeeded(item.description.cleanHTML()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var cover: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                RemoteCoverImage(
                    url: item.cover,
                    referer: ExtensionHostResolver.nonEmpty(item.host) ?? sourceHost,
                    contentMode: .fill
                )
            }
            .overlay(alignment: .bottom) {
                if mode == .coverOnly {
                    coverTitleStrip
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.coverCornerRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                CoverTagBadge(tag: translateIfNeeded(item.tag), fontSize: 10, inset: 4)
            }
    }

    /// Tên truyện trên dải tối mờ dần lên trên — đọc được trên mọi bìa. Nằm trong khung đã `clipShape` nên góc
    /// dưới bo theo bìa.
    private var coverTitleStrip: some View {
        Text(displayedTitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var displayedTitle: String {
        DisplayTextFormatter.titleCase(translateIfNeeded(item.name, bookId: item.link))
    }

    private func translateIfNeeded(_ text: String, bookId: String? = nil) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }
}
