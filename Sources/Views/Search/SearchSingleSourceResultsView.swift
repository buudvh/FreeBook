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
/// Tải thêm trang (`footer == .loading`): `LoadMoreFooter` cuối danh sách / footer của lưới (cùng mẹo `.id(count)`
/// với `DiscoveryNovelsLayoutView`), và gọi sớm khi một trong `preloadDistance` mục cuối hiện ra — tải trước khi chạm đáy.
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
    /// Chân danh sách (`SearchView.singleSourceFooterPhase`); `.loading` ⇒ gọi `onLoadMore` (`SearchView` tự chặn gọi
    /// trùng lúc đang tải), `.failed` ⇒ nút "Thử lại" gọi `onRetry`.
    let footer: LoadMoreFooter.Phase?
    let onLoadMore: () -> Void
    let onRetry: () -> Void

    private static let preloadDistance = 5

    var body: some View {
        if layout.mode.isGrid {
            gridBody
        } else {
            listBody
        }
    }

    // MARK: - Danh sách

    private var listBody: some View {
        let preloadIds = preloadTriggerIds
        return List {
            ForEach(items) { item in
                listTappable(item)
                    .bookListPanelRowChrome()
                    .onAppear { preloadIfNeeded(item, triggerIds: preloadIds) }
            }

            if let footer {
                footerView(footer)
                    .bookListPanelRowChrome()
                    .id(items.count)
            }
        }
        .listStyle(.plain)
    }

    /// Hàng panel: link mở Chi tiết nằm **ẩn** dưới panel (`opacity(0)`) — `NavigationLink` làm hàng của `List` thì
    /// hệ thống vẽ mũi tên `>` ở mép phải, nằm ngoài panel. Chạm hàng vẫn mở link như cũ.
    @ViewBuilder
    private func listTappable(_ item: ExtensionItemResultWithExt) -> some View {
        if isChangingSource || ContentDetailRouter.isVideo(packageId: item.ext.packageId) {
            // Đổi nguồn / phim (mở màn xem phim): nút thường, không có mũi tên `>` của `NavigationLink`.
            tappable(item) {
                listRow(item).bookListPanel(layout.rowSize)
            }
            .buttonStyle(.plain)
        } else {
            ZStack {
                NavigationLink(destination: detailView(item)) {
                    EmptyView()
                }
                .opacity(0)

                listRow(item).bookListPanel(layout.rowSize)
            }
        }
    }

    /// Cỡ theo `layout.rowSize`; nấc mặc định giữ đúng dòng cũ. Nấc gọn (1–2) bỏ chip tên nguồn, mô tả 1 dòng.
    private func listRow(_ item: ExtensionItemResultWithExt) -> some View {
        let size = layout.rowSize
        return HStack(spacing: 12) {
            SearchView.searchResultCover(item.result, ext: item.ext, width: size.coverWidth, height: size.coverHeight)

            VStack(alignment: .leading, spacing: 4) {
                Text(DisplayTextFormatter.titleCase(translateIfNeeded(item.result.name)))
                    .font(size.font(.subheadline, base: 15))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(size.titleLineLimit)
                    .multilineTextAlignment(.leading)

                let descText = !item.result.description.isEmpty ? item.result.description : (!item.result.content.isEmpty ? item.result.content : item.result.author)
                Text(translateIfNeeded(descText))
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
                                isTranslationEnabled: isTranslationEnabled,
                                mode: layout.mode,
                                aspectRatio: aspectRatio
                            )
                        }
                        .onAppear { preloadIfNeeded(item, triggerIds: preloadIds) }
                    }
                } footer: {
                    // Footer của section được dựng lười (chỉ hiện khi cuộn tới cuối). `.id(count)`: lưới chưa đầy màn
                    // sau một trang thì mỗi lượt nối thêm đổi id ⇒ sentinel mới ⇒ tải tiếp tới khi đầy màn.
                    if let footer {
                        footerView(footer)
                            .id(items.count)
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
        LoadMoreFooter(phase: phase, onAppear: onLoadMore, onRetry: onRetry)
    }

    /// Bọc nội dung một item thành nút đổi nguồn, hoặc `ContentDetailLink`: phim ⇒ nút mở màn xem phim, loại khác ⇒ link
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

    private func detailView(_ item: ExtensionItemResultWithExt) -> BookDetailView {
        BookDetailView(
            bookId: "\(item.ext.name.lowercased())_\(item.result.link)",
            extensionPackageId: item.ext.packageId,
            initialDetailUrl: item.result.link,
            sourceName: item.ext.name,
            initialHost: item.result.host
        )
    }

    private func translateIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text)
    }
}
