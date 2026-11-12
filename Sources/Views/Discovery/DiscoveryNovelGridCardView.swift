import SwiftUI

/// Thẻ truyện của các danh sách Khám phá kiểu cũ (tab `home`, màn Thể loại / Xem thêm) ở hai kiểu lưới của
/// `BookListLayoutMode`. Kiểu Danh sách vẫn dùng `DiscoveryNovelRowView`.
///
/// - Bìa: khung màu tỉ lệ cố định (2:3, video 16:9) với ảnh `RemoteCoverImage(.fill)` trong `overlay` — giống
///   `ExploreCoverView`, ảnh không làm phình bố cục. **Không** dùng `BookCoverView`: nó ghi bìa xuống `covers/`, còn
///   item Khám phá chỉ là danh sách tạm (xem comment đầu `DiscoveryNovelRowView`). Referer = host item → `source`.
/// - `.grid`: tên 2 dòng + mô tả 1 dòng dưới bìa (như `ExploreItemCard`).
/// - `.coverOnly`: tên đè lên dải tối ở đáy bìa (`CoverCaptionStrip`).
/// - Chữ Trung theo cùng luật với `DiscoveryNovelRowView`: phồn → giản rồi dịch **theo nguồn** (`textOptions`); có
///   `textStore` (Khám phá / Thể loại) ⇒ bộ dịch tiện ích dịch tên / mô tả / nhãn (QT hiện trước).
///
/// Bề rộng do cột lưới quyết định; chiều cao bìa suy ra từ `aspectRatio`. Nơi dùng bọc thẻ trong `Button`.
struct DiscoveryNovelGridCardView: View {
    let item: ExtensionItemResult
    /// `source` của tiện ích — Referer dự phòng khi item không có `host`.
    let sourceHost: String?
    /// Phồn → giản + dịch theo nguồn (`ChineseTextPipeline.sourceOptions`, do màn cha tính một lần).
    let textOptions: ChineseTextPipeline.Options
    /// `.grid` hoặc `.coverOnly`; `.list` được vẽ như `.grid` (nơi dùng không truyền giá trị này).
    let mode: BookListLayoutMode
    /// Tỉ lệ rộng : cao của bìa (`BookListLayoutScope.coverAspectRatio`).
    let aspectRatio: CGFloat
    /// Nơi dùng đè ⋮ "Thêm vào playlist" ở góc dưới phải thẻ (`PlaylistListItemMenu`, 1.3.810) ⇒ chừa lề phải cho tên /
    /// mô tả để chữ không chạy dưới ⋮. Kiểu chỉ bìa đặt ⋮ trên góc bìa nên không cần.
    var reservesMenuSpace: Bool = false
    /// Khám phá / Thể loại / Xem thêm: store của màn cha (bộ dịch tiện ích). `nil` (Tìm kiếm) ⇒ chỉ QT theo `textOptions`.
    var textStore: ExtensionTextTranslationStore? = nil

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
                    .padding(.trailing, reservesMenuSpace ? 18 : 0)

                if !item.description.isEmpty {
                    Text(display(item.description.cleanHTML()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.trailing, reservesMenuSpace ? 18 : 0)
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
                CoverTagBadge(tag: display(item.tag), fontSize: 10, inset: 4)
            }
    }

    /// Tên truyện trên dải tối ở đáy bìa — cùng kiểu với kiểu chỉ bìa của Kệ. Nằm trong khung đã `clipShape` nên góc
    /// dưới bo theo bìa. Bìa ngang 16:9 thấp: một dòng tên và phần chuyển thấp.
    private var coverTitleStrip: some View {
        let isLandscape = aspectRatio > 1
        return CoverCaptionStrip(
            title: displayedTitle,
            titleLineLimit: isLandscape ? 1 : 2,
            fadeHeight: isLandscape ? CoverCaptionStrip.compactFadeHeight : CoverCaptionStrip.regularFadeHeight
        )
    }

    /// Tên: bộ dịch tiện ích ⇒ bản tiện ích (QT trước); QT ⇒ tra từ điển riêng theo `link` như trước.
    private var displayedTitle: String {
        if let textStore, textStore.request != nil {
            return DisplayTextFormatter.titleCase(textStore.text(item.name, kind: .meta))
        }
        var nameOptions = textOptions
        nameOptions.dictionaryBookId = item.link
        return DisplayTextFormatter.titleCase(ChineseTextPipeline.meta(item.name, nameOptions))
    }

    private func display(_ text: String) -> String {
        textStore?.text(text, kind: .meta) ?? ChineseTextPipeline.meta(text, textOptions)
    }
}
