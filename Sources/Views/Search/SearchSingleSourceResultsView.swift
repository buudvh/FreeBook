import SwiftUI

/// Kết quả "tìm trong một nguồn" của `SearchView`, dựng theo `BookListLayout` của loại nguồn đang tìm (chữ / comic /
/// video) — cùng phạm vi kiểu hiển thị với Khám phá của nguồn đó.
///
/// Two branches that never mix (same rule as `DiscoveryNovelsLayoutView`):
/// - `.list` → `List` of the search row as rounded panels (`bookListPanel`, no separators), sized by `layout.rowSize`
///   (cover 50×70 at the default size, description → content → author, source-name chip).
/// - `.grid` / `.coverOnly` → `ScrollView` + `LazyVGrid` of `DiscoveryNovelGridCardView`. A `LazyVGrid` must never be
///   nested inside a `List` row.
///
/// Chạm item: đang đổi nguồn ⇒ `onChangeSource` (hộp xác nhận nằm ở `SearchView`); ngược lại mở Chi tiết truyện.
///
/// Tải thêm trang (`footer == .loading`): `LoadMoreFooter` cuối danh sách / footer của lưới (hàng chân id cố định, vòng
/// xoay + kích hoạt lại theo `token` = số mục — 1.3.819, như `DiscoveryNovelsLayoutView`), và gọi sớm khi một trong
/// `preloadDistance` mục cuối hiện ra — tải trước khi chạm đáy.
struct SearchSingleSourceResultsView: View {
    let items: [ExtensionItemResultWithExt]
    let layout: BookListLayout
    /// Tỉ lệ rộng : cao của bìa ở kiểu lưới (`BookListLayoutScope.coverAspectRatio`).
    let aspectRatio: CGFloat
    /// Phồn → giản + dịch theo **nguồn đang tìm** (Nguồn ⇒ Tất cả — `SearchView.textOptions(for:)`), không theo công
    /// tắc dịch Tất cả.
    let textOptions: ChineseTextPipeline.Options
    /// `true` khi đang đổi nguồn: chạm item gọi `onChangeSource` thay vì mở Chi tiết.
    let isChangingSource: Bool
    let onChangeSource: (ExtensionItemResultWithExt) -> Void
    /// Chân danh sách (`SearchView.singleSourceFooterPhase`); `.loading` ⇒ gọi `onLoadMore` (`SearchView` tự chặn gọi
    /// trùng lúc đang tải), `.failed` ⇒ nút "Thử lại" gọi `onRetry`.
    let footer: LoadMoreFooter.Phase?
    let onLoadMore: () -> Void
    let onRetry: () -> Void
    /// Nguồn âm thanh / phim (không đổi nguồn) ⇒ mỗi hàng / thẻ có ⋮ "Thêm vào playlist / Thêm vào kệ" (1.3.810).
    var playlistContext: PlaylistListAddContext? = nil

    private static let preloadDistance = 5
    private static let footerId = "loadMoreFooter"

    var body: some View {
        if layout.mode.isGrid {
            gridBody
        } else {
            listBody
        }
    }

    // MARK: - Danh sách

    /// `ScrollView` + `LazyVStack`, không `List` (1.3.822): hàng cao thấp khác nhau ⇒ `List` chỉnh vị trí cuộn mỗi lần nối
    /// trang, nội dung nhảy lên. Ngoài `List` nên `NavigationLink` (trong `tappable`) không vẽ mũi tên `>` — không cần mẹo
    /// link ẩn dưới panel như trước.
    private var listBody: some View {
        let preloadIds = preloadTriggerIds
        return ScrollView {
            LazyVStack(spacing: BookListPanelModifier.stackSpacing) {
                ForEach(items) { item in
                    // ⋮ đè lên nút (không nằm trong `label`), chữ chừa lề phải.
                    tappable(item) {
                        listRow(item)
                            .padding(.trailing, playlistContext == nil ? 0 : 24)
                            .bookListPanel(layout.rowSize)
                    }
                    .playlistListItemMenuOverlay(item: item.result, context: playlistContext, style: .row)
                    .onAppear { preloadIfNeeded(item, triggerIds: preloadIds) }
                }

                // Hàng chân id cố định (1.3.819); vòng xoay mới + kích hoạt lại theo `token`.
                if let footer {
                    footerView(footer)
                        .id(Self.footerId)
                }
            }
            .bookListPanelStackPadding()
        }
        // Link không nhuộm màu nhấn (như lưới).
        .buttonStyle(.plain)
    }

    /// Cỡ theo `layout.rowSize`; nấc mặc định giữ đúng dòng cũ. Nấc gọn (1–2) bỏ chip tên nguồn, mô tả 1 dòng.
    private func listRow(_ item: ExtensionItemResultWithExt) -> some View {
        let size = layout.rowSize
        return HStack(spacing: 12) {
            SearchView.searchResultCover(item.result, ext: item.ext, width: size.coverWidth, height: size.coverHeight)

            VStack(alignment: .leading, spacing: 4) {
                Text(DisplayTextFormatter.titleCase(ChineseTextPipeline.meta(item.result.name, textOptions)))
                    .font(size.font(.subheadline, base: 15))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(size.titleLineLimit)
                    .multilineTextAlignment(.leading)

                let descText = !item.result.description.isEmpty ? item.result.description : (!item.result.content.isEmpty ? item.result.content : item.result.author)
                Text(ChineseTextPipeline.meta(descText, textOptions))
                    .font(size.font(.caption, base: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(size.isCompact ? 1 : 2)
                    .multilineTextAlignment(.leading)

                if !size.isCompact {
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
        }
    }

    // MARK: - Lưới

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: DiscoveryNovelsLayoutView.columnSpacing, alignment: .top),
            count: max(layout.columns, 1)
        )
    }

    private var gridBody: some View {
        let preloadIds = preloadTriggerIds
        return ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: DiscoveryNovelsLayoutView.rowSpacing) {
                Section {
                    ForEach(items) { item in
                        tappable(item) {
                            DiscoveryNovelGridCardView(
                                item: item.result,
                                sourceHost: ExtensionHostResolver.nonEmpty(item.ext.sourceUrl),
                                textOptions: textOptions,
                                mode: layout.mode,
                                aspectRatio: aspectRatio,
                                reservesMenuSpace: playlistContext != nil && layout.mode != .coverOnly
                            )
                        }
                        .playlistListItemMenuOverlay(
                            item: item.result,
                            context: playlistContext,
                            style: layout.mode == .coverOnly ? .onCover : .card
                        )
                        .onAppear { preloadIfNeeded(item, triggerIds: preloadIds) }
                    }
                } footer: {
                    // Footer của section được dựng lười (chỉ hiện khi cuộn tới cuối). Lưới chưa đầy màn sau một trang thì
                    // `LoadMoreFooter` tự kích hoạt lại theo `token` (số mục) ⇒ tải tiếp tới khi đầy màn.
                    if let footer {
                        footerView(footer)
                            .id(Self.footerId)
                    }
                }
            }
            // Link trong lưới không được nhuộm màu nhấn; dòng Danh sách giữ kiểu row mặc định của `List` như cũ.
            .buttonStyle(.plain)
            .padding(DiscoveryNovelsLayoutView.gridPadding)
        }
    }

    // MARK: - Dùng chung

    /// `id` của vài mục cuối: một trong số đó hiện ra ⇒ tải trang kế. Rỗng khi hết trang.
    private var preloadTriggerIds: Set<UUID> {
        guard footer == .loading else { return [] }
        return Set(items.suffix(Self.preloadDistance).map(\.id))
    }

    private func preloadIfNeeded(_ item: ExtensionItemResultWithExt, triggerIds: Set<UUID>) {
        if triggerIds.contains(item.id) { onLoadMore() }
    }

    private func footerView(_ phase: LoadMoreFooter.Phase) -> some View {
        LoadMoreFooter(phase: phase, token: items.count, onAppear: onLoadMore, onRetry: onRetry)
    }

    /// Bọc nội dung một item thành nút đổi nguồn, hoặc `ContentDetailLink`: phim / âm thanh ⇒ nút mở màn phát, loại khác ⇒ link
    /// mở Chi tiết truyện (`bookId` giữ đúng dạng cũ của màn này).
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
            // `label` không thoát được khỏi hàm ⇒ dựng nội dung trước rồi mới giao cho link.
            let content = label()
            ContentDetailLink(
                item: item.result,
                packageId: item.ext.packageId,
                sourceName: item.ext.name,
                detailBookId: "\(item.ext.name.lowercased())_\(item.result.link)"
            ) {
                content
            }
        }
    }
}
