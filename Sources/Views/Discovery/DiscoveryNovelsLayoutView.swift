import SwiftUI

/// Khung danh sách truyện có phân trang dùng chung cho tab danh mục Khám phá (`DiscoveryCategoryTabView`) và màn
/// Thể loại / Xem thêm (`CategoryNovelsListView`), dựng theo `BookListLayout` của loại nguồn.
///
/// Two branches that never mix:
/// - `.list` → `ScrollView` + `LazyVStack` of `DiscoveryNovelRowView` as rounded panels (`bookListPanel`, no
///   separators), sized by `layout.rowSize`. Not a `List` (1.3.822): rows differ in height, `List` only estimates the
///   rows scrolled past and re-adjusts the offset on every appended page ⇒ content jumped up ~1 row.
/// - `.grid` / `.coverOnly` → `ScrollView` + `LazyVGrid` of `DiscoveryNovelGridCardView`. A `LazyVGrid` must never be
///   nested inside a `List` row (crashed with `EXC_BREAKPOINT` in 1.3.269, see `CollectionsTabView`).
///
/// Both branches keep the same contract the parents rely on:
/// - every row/cell carries `.id(novel.link)` so the parent's `ScrollViewReader` can `scrollTo` a saved anchor
///   (`link`, not `ExtensionItemResult.id` — that is a fresh `UUID()` on every parse);
/// - `onAppear`/`onDisappear` feed `scrollAnchors` when the parent passes one (only the discovery tab does);
/// - `.refreshable { await loader.reload() }` and a full-width `LoadMoreFooter` after the last item (spinner while
///   loading the next page, "Thử lại" after the loader gave up, "Đã hết · N truyện" when there are no more pages).
///
/// The `ScrollViewReader` itself stays in the parent (restore logic and its state live there); the proxy finds
/// whichever scroll container this view currently renders.
struct DiscoveryNovelsLayoutView: View {
    /// Khoảng cách cột / hàng / lề của lưới — `DiscoverySkeletonGridView` dùng lại để khung chờ khớp bố cục thật.
    static let columnSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 14
    static let gridPadding: CGFloat = 16
    /// Số mục cuối: hiện ra là tải trước trang kế.
    private static let preloadDistance = 5
    private static let footerId = "loadMoreFooter"

    @ObservedObject var loader: PaginatedNovelLoader
    let layout: BookListLayout
    /// Tỉ lệ rộng : cao của bìa ở kiểu lưới (`BookListLayoutScope.coverAspectRatio`).
    let aspectRatio: CGFloat
    let sourceHost: String?
    /// Phồn → giản + dịch của nguồn (`ChineseTextPipeline.sourceOptions`), màn cha tính một lần.
    let textOptions: ChineseTextPipeline.Options
    /// Neo cuộn của Khám phá; `nil` ở màn không nhớ vị trí cuộn.
    let scrollAnchors: DiscoveryScrollAnchorStore?
    /// Khoá tab trong `scrollAnchors` (`CategoryResult.id`).
    let anchorCategoryId: String
    /// Từ gọi mục ở dòng "Đã hết · N …" (`BookListLayoutScope.itemNoun`).
    let itemNoun: String
    /// Nguồn âm thanh / phim ⇒ mỗi hàng / thẻ có ⋮ "Thêm vào playlist / Thêm vào kệ" (1.3.810); `nil` ⇒ không có.
    let playlistContext: PlaylistListAddContext?
    let onSelectNovel: (ExtensionItemResult) -> Void

    init(
        loader: PaginatedNovelLoader,
        layout: BookListLayout,
        aspectRatio: CGFloat,
        sourceHost: String?,
        textOptions: ChineseTextPipeline.Options,
        scrollAnchors: DiscoveryScrollAnchorStore? = nil,
        anchorCategoryId: String = "",
        itemNoun: String = "truyện",
        playlistContext: PlaylistListAddContext? = nil,
        onSelectNovel: @escaping (ExtensionItemResult) -> Void
    ) {
        _loader = ObservedObject(wrappedValue: loader)
        self.layout = layout
        self.aspectRatio = aspectRatio
        self.sourceHost = sourceHost
        self.textOptions = textOptions
        self.scrollAnchors = scrollAnchors
        self.anchorCategoryId = anchorCategoryId
        self.itemNoun = itemNoun
        self.playlistContext = playlistContext
        self.onSelectNovel = onSelectNovel
    }

    var body: some View {
        if layout.mode.isGrid {
            gridBody
        } else {
            listBody
        }
    }

    // MARK: - Danh sách

    private var listBody: some View {
        ScrollView {
            LazyVStack(spacing: BookListPanelModifier.stackSpacing) {
                listRows
            }
            .bookListPanelStackPadding()
        }
        .refreshable {
            await loader.reload()
        }
    }

    @ViewBuilder
    private var listRows: some View {
        // Định danh theo `link` như lưới (1.3.819): `ExtensionItemResult.id` là `UUID()` mới mỗi lần bóc tách ⇒ kéo làm
        // mới dựng lại mọi hàng + bìa.
        ForEach(loader.novels, id: \.link) { novel in
            Button {
                onSelectNovel(novel)
            } label: {
                DiscoveryNovelRowView(
                    item: novel,
                    sourceHost: sourceHost,
                    textOptions: textOptions,
                    rowSize: layout.rowSize
                )
                .padding(.trailing, playlistContext == nil ? 0 : 24)
                .bookListPanel(layout.rowSize)
            }
            .buttonStyle(.plain)
            // ⋮ đè lên nút (không nằm trong `label`), chữ đã chừa lề phải.
            .playlistListItemMenuOverlay(item: novel, context: playlistContext, style: .row)
            .id(novel.link)
            .onAppear {
                setVisible(novel.link, true)
                preloadIfNeeded(novel)
            }
            .onDisappear { setVisible(novel.link, false) }
        }

        // Hàng chân **id cố định** (1.3.819); vòng xoay mới + kích hoạt lại do `LoadMoreFooter` lo theo `token`.
        if let phase = footerPhase {
            footer(phase)
                .id(Self.footerId)
        }
    }

    // MARK: - Lưới

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Self.columnSpacing, alignment: .top),
            count: max(layout.columns, 1)
        )
    }

    private var gridBody: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Self.rowSpacing) {
                Section {
                    // Định danh theo `link` (đã duy nhất nhờ `filterAndDeduplicate`): `scrollTo` trong lưới lazy tìm
                    // được ô chưa dựng, và nạp lại không dựng lại ô (bìa) của truyện vẫn còn trong danh sách.
                    ForEach(loader.novels, id: \.link) { novel in
                        Button {
                            onSelectNovel(novel)
                        } label: {
                            DiscoveryNovelGridCardView(
                                item: novel,
                                sourceHost: sourceHost,
                                textOptions: textOptions,
                                mode: layout.mode,
                                aspectRatio: aspectRatio,
                                reservesMenuSpace: playlistContext != nil && layout.mode != .coverOnly
                            )
                        }
                        .buttonStyle(.plain)
                        .playlistListItemMenuOverlay(
                            item: novel,
                            context: playlistContext,
                            style: layout.mode == .coverOnly ? .onCover : .card
                        )
                        .id(novel.link)
                        .onAppear {
                            setVisible(novel.link, true)
                            preloadIfNeeded(novel)
                        }
                        .onDisappear { setVisible(novel.link, false) }
                    }
                } footer: {
                    // Footer của section trải hết bề ngang lưới và cũng được dựng lười: chỉ hiện khi cuộn tới cuối —
                    // đặt ngoài vùng lazy (VStack thường) thì nó hiện ngay lượt vẽ đầu.
                    // Lưới nhiều cột / chỉ bìa có thể chưa đầy màn sau một trang, footer vẫn trong màn: `LoadMoreFooter`
                    // tự kích hoạt lại theo `token` (số mục) ⇒ tải tiếp tới khi đầy màn. Trang toàn mục trùng thì
                    // `token` đứng yên, không lặp.
                    if let phase = footerPhase {
                        footer(phase)
                            .id(Self.footerId)
                    }
                }
            }
            .padding(Self.gridPadding)
        }
        .refreshable {
            await loader.reload()
        }
    }

    // MARK: - Dùng chung

    /// Lỗi trang kế (hết lượt tự thử) ⇒ "Thử lại"; còn trang ⇒ vòng xoay; hết trang ⇒ "Đã hết · N …".
    private var footerPhase: LoadMoreFooter.Phase? {
        if let error = loader.loadMoreError { return .failed(error) }
        if loader.canLoadMore { return .loading }
        return loader.novels.isEmpty ? nil : .finished("\(loader.novels.count) \(itemNoun)")
    }

    private func footer(_ phase: LoadMoreFooter.Phase) -> some View {
        LoadMoreFooter(
            phase: phase,
            token: loader.novels.count,
            onAppear: { Task { await loader.loadMore() } },
            onRetry: { Task { await loader.retryLoadMore() } }
        )
    }

    /// Tải trang kế khi một trong `preloadDistance` mục cuối hiện ra (1.3.819) ⇒ mục mới nối vào lúc người dùng còn ở
    /// phía trên, không đợi chạm chân. `loadMore()` tự chặn gọi trùng / khi hết trang.
    private func preloadIfNeeded(_ novel: ExtensionItemResult) {
        guard loader.canLoadMore, !loader.isLoadingMore, loader.loadMoreError == nil else { return }
        guard loader.novels.suffix(Self.preloadDistance).contains(where: { $0.link == novel.link }) else { return }
        Task { await loader.loadMore() }
    }

    private func setVisible(_ link: String, _ isVisible: Bool) {
        scrollAnchors?.setVisible(link, isVisible: isVisible, categoryId: anchorCategoryId)
    }
}
