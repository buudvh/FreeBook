import SwiftUI

/// Kết quả "tìm trong một nguồn" của `SearchView`, dựng theo `BookListLayout` của loại nguồn đang tìm (chữ / comic /
/// video) — cùng phạm vi kiểu hiển thị với Khám phá của nguồn đó.
///
/// Two branches that never mix (same rule as `DiscoveryNovelsLayoutView`):
/// - `.list` → `List` of the search row, kept exactly as before the layout option existed (cover 50×70, description →
///   content → author, source-name chip).
/// - `.grid` / `.coverOnly` → `ScrollView` + `LazyVGrid` of `DiscoveryNovelGridCardView`. A `LazyVGrid` must never be
///   nested inside a `List` row.
///
/// Chạm item: đang đổi nguồn ⇒ `onChangeSource` (hộp xác nhận nằm ở `SearchView`); ngược lại mở Chi tiết truyện.
struct SearchSingleSourceResultsView: View {
    let items: [ExtensionItemResultWithExt]
    let layout: BookListLayout
    /// Tỉ lệ rộng : cao của bìa ở kiểu lưới (`BookListLayoutScope.coverAspectRatio`).
    let aspectRatio: CGFloat
    /// Công tắc dịch của màn Tìm kiếm (`@AppStorage("isTranslationEnabled")`), giữ như trước.
    let isTranslationEnabled: Bool
    /// `true` khi đang đổi nguồn: chạm item gọi `onChangeSource` thay vì mở Chi tiết.
    let isChangingSource: Bool
    let onChangeSource: (ExtensionItemResultWithExt) -> Void

    var body: some View {
        if layout.mode.isGrid {
            gridBody
        } else {
            listBody
        }
    }

    // MARK: - Danh sách

    private var listBody: some View {
        List(items) { item in
            tappable(item) {
                listRow(item)
            }
        }
        .listStyle(.plain)
    }

    private func listRow(_ item: ExtensionItemResultWithExt) -> some View {
        HStack(spacing: 12) {
            SearchView.searchResultCover(item.result, ext: item.ext, width: 50, height: 70)

            VStack(alignment: .leading, spacing: 4) {
                Text(DisplayTextFormatter.titleCase(translateIfNeeded(item.result.name)))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                let descText = !item.result.description.isEmpty ? item.result.description : (!item.result.content.isEmpty ? item.result.content : item.result.author)
                Text(translateIfNeeded(descText))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(item.ext.name)
                    .font(.system(size: 9))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Lưới

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: DiscoveryNovelsLayoutView.columnSpacing, alignment: .top),
            count: max(layout.columns, 1)
        )
    }

    private var gridBody: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: DiscoveryNovelsLayoutView.rowSpacing) {
                ForEach(items) { item in
                    tappable(item) {
                        DiscoveryNovelGridCardView(
                            item: item.result,
                            sourceHost: ExtensionHostResolver.nonEmpty(item.ext.sourceUrl),
                            isTranslationEnabled: isTranslationEnabled,
                            mode: layout.mode,
                            aspectRatio: aspectRatio
                        )
                    }
                }
            }
            // Link trong lưới không được nhuộm màu nhấn; dòng Danh sách giữ kiểu row mặc định của `List` như cũ.
            .buttonStyle(.plain)
            .padding(DiscoveryNovelsLayoutView.gridPadding)
        }
    }

    // MARK: - Dùng chung

    /// Bọc nội dung một item thành nút đổi nguồn hoặc link mở Chi tiết truyện (`bookId` giữ đúng dạng cũ của màn này).
    @ViewBuilder
    private func tappable<Label: View>(_ item: ExtensionItemResultWithExt, @ViewBuilder label: () -> Label) -> some View {
        if isChangingSource {
            Button {
                onChangeSource(item)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: BookDetailView(
                bookId: "\(item.ext.name.lowercased())_\(item.result.link)",
                extensionPackageId: item.ext.packageId,
                initialDetailUrl: item.result.link,
                sourceName: item.ext.name,
                initialHost: item.result.host
            )) {
                label()
            }
        }
    }

    private func translateIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text)
    }
}
