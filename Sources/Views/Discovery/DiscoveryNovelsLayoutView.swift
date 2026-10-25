import SwiftUI

/// Khung danh sách truyện có phân trang dùng chung cho tab danh mục Khám phá (`DiscoveryCategoryTabView`) và màn
/// Thể loại / Xem thêm (`CategoryNovelsListView`), dựng theo `BookListLayout` của loại nguồn.
///
/// Two branches that never mix:
/// - `.list` → `List` of `DiscoveryNovelRowView`, sized by `layout.rowSize` (the default size is exactly the row from
///   before the layout option existed).
/// - `.grid` / `.coverOnly` → `ScrollView` + `LazyVGrid` of `DiscoveryNovelGridCardView`. A `LazyVGrid` must never be
///   nested inside a `List` row (crashed with `EXC_BREAKPOINT` in 1.3.269, see `CollectionsTabView`).
///
/// Both branches keep the same contract the parents rely on:
/// - every row/cell carries `.id(novel.link)` so the parent's `ScrollViewReader` can `scrollTo` a saved anchor
///   (`link`, not `ExtensionItemResult.id` — that is a fresh `UUID()` on every parse);
/// - `onAppear`/`onDisappear` feed `scrollAnchors` when the parent passes one (only the discovery tab does);
/// - `.refreshable { await loader.reload() }` and a full-width `loadMore` sentinel after the last item.
///
/// The `ScrollViewReader` itself stays in the parent (restore logic and its state live there); the proxy finds
/// whichever scroll container this view currently renders.
struct DiscoveryNovelsLayoutView: View {
    /// Khoảng cách cột / hàng / lề của lưới — `DiscoverySkeletonGridView` dùng lại để khung chờ khớp bố cục thật.
    static let columnSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 14
    static let gridPadding: CGFloat = 16

    @ObservedObject var loader: PaginatedNovelLoader
    let layout: BookListLayout
    /// Tỉ lệ rộng : cao của bìa ở kiểu lưới (`BookListLayoutScope.coverAspectRatio`).
    let aspectRatio: CGFloat
    let sourceHost: String?
    let isTranslationEnabled: Bool
    /// Lề dọc thêm cho mỗi hàng ở kiểu Danh sách (màn Thể loại dùng 4, tab Khám phá dùng 0 — giữ như trước).
    let rowVerticalPadding: CGFloat
    /// Neo cuộn của Khám phá; `nil` ở màn không nhớ vị trí cuộn.
    let scrollAnchors: DiscoveryScrollAnchorStore?
    /// Khoá tab trong `scrollAnchors` (`CategoryResult.id`).
    let anchorCategoryId: String
    let onSelectNovel: (ExtensionItemResult) -> Void

    init(
        loader: PaginatedNovelLoader,
        layout: BookListLayout,
        aspectRatio: CGFloat,
        sourceHost: String?,
        isTranslationEnabled: Bool,
        rowVerticalPadding: CGFloat = 0,
        scrollAnchors: DiscoveryScrollAnchorStore? = nil,
        anchorCategoryId: String = "",
        onSelectNovel: @escaping (ExtensionItemResult) -> Void
    ) {
        _loader = ObservedObject(wrappedValue: loader)
        self.layout = layout
        self.aspectRatio = aspectRatio
        self.sourceHost = sourceHost
        self.isTranslationEnabled = isTranslationEnabled
        self.rowVerticalPadding = rowVerticalPadding
        self.scrollAnchors = scrollAnchors
        self.anchorCategoryId = anchorCategoryId
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
        List {
            ForEach(loader.novels) { novel in
                Button {
                    onSelectNovel(novel)
                } label: {
                    DiscoveryNovelRowView(
                        item: novel,
                        sourceHost: sourceHost,
                        isTranslationEnabled: isTranslationEnabled,
                        rowSize: layout.rowSize
                    )
                        .padding(.vertical, rowVerticalPadding)
                }
                .buttonStyle(.plain)
                .id(novel.link)
                .onAppear { setVisible(novel.link, true) }
                .onDisappear { setVisible(novel.link, false) }
            }

            if loader.canLoadMore {
                loadMoreSentinel
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await loader.reload()
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
                                isTranslationEnabled: isTranslationEnabled,
                                mode: layout.mode,
                                aspectRatio: aspectRatio
                            )
                        }
                        .buttonStyle(.plain)
                        .id(novel.link)
                        .onAppear { setVisible(novel.link, true) }
                        .onDisappear { setVisible(novel.link, false) }
                    }
                } footer: {
                    // Footer của section trải hết bề ngang lưới và cũng được dựng lười: `onAppear` chỉ nổ khi cuộn
                    // tới cuối — đặt ngoài vùng lazy (VStack thường) thì nó nổ ngay lượt vẽ đầu.
                    // `.id(count)`: lưới nhiều cột / chỉ bìa có thể chưa đầy màn sau một trang, footer vẫn trong
                    // màn nên `onAppear` không nổ lại và không cuộn được để kích hoạt. Mỗi lượt nối thêm đổi id ⇒
                    // sentinel mới ⇒ tải tiếp tới khi đầy màn. Trang toàn mục trùng thì `count` đứng yên, không lặp.
                    if loader.canLoadMore {
                        loadMoreSentinel
                            .id(loader.novels.count)
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

    private var loadMoreSentinel: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 8)
        .onAppear {
            Task {
                await loader.loadMore()
            }
        }
    }

    private func setVisible(_ link: String, _ isVisible: Bool) {
        scrollAnchors?.setVisible(link, isVisible: isVisible, categoryId: anchorCategoryId)
    }
}
