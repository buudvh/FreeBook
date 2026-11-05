import SwiftUI

struct CategoryNovelsListView: View {
    let category: CategoryResult
    let extensionPackageId: String
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let sourceName: String
    /// Mở từ trang toàn màn của màn xem phim (`VideoWatchPagePresenter`): bấm phim của nguồn video ⇒ gọi closure này (đóng
    /// trang, đổi phim tại chỗ) thay cho mở màn xem mới. `nil` (mặc định, mọi chỗ khác) ⇒ hành vi cũ. Nguồn khác ⇒ vẫn
    /// đẩy Chi tiết trong trang.
    let onSelectVideo: ((ExtensionItemResult) -> Void)?
    /// Container cho màn xem phim (`ContentDetailRouter`): item của nguồn video mở màn xem thay cho Chi tiết.
    @Environment(\.modelContext) private var modelContext
    @StateObject private var loader: PaginatedNovelLoader
    /// Referer dự phòng cho bìa khi item không có `host`. Tra lười khi xuất hiện, không trong `init` — `init` chạy lại
    /// mỗi lần view cha dựng lại body.
    @State private var sourceHost: String? = nil
    @State private var selectedNovel: ExtensionItemResult? = nil
    @State private var showingLayoutSheet = false
    /// Sheet "Bộ lọc" của tiện ích (`ExtensionFilterSheet`); áp dụng ⇒ tải lại từ trang 1 bằng config mới.
    @State private var showingFilterSheet = false
    @State private var openingErrorLink: SourceErrorLink? = nil
    /// Màn bị trình duyệt "Mở link lỗi" che (biến mất khi nó mở): lần xuất hiện lại kế tiếp không để `.task` tải chồng
    /// trước khi chép cookie — lượt thử lại do `.errorLinkBrowser` gọi sau khi chép.
    @State private var skipsReappearLoad = false

    /// Kiểu hiển thị theo loại của nguồn (màn này mở cả từ Khám phá lẫn Chi tiết truyện, chỉ có `packageId`).
    private var layoutScope: BookListLayoutScope {
        BookListLayoutScope(kind: ExtensionContentKind.resolve(packageId: extensionPackageId))
    }

    /// Cờ dịch **theo nguồn** (giống `DiscoveryView`), không phải công tắc dịch toàn app: tắt dịch cho nguồn thì danh
    /// sách và tiêu đề phải hiện nguyên văn.
    private var isTranslationEnabled: Bool {
        TranslationConfigStore.shared.isTranslationEnabled(
            bookId: "",
            packageId: extensionPackageId,
            isChineseSourceHint: ExtensionLibraryRepository.snapshot(packageId: extensionPackageId)?.isChineseSource
        )
    }

    init(
        category: CategoryResult,
        extensionPackageId: String,
        localPath: String,
        downloadUrl: String,
        configJson: String,
        sourceName: String,
        onSelectVideo: ((ExtensionItemResult) -> Void)? = nil
    ) {
        self.onSelectVideo = onSelectVideo
        self.category = category
        self.extensionPackageId = extensionPackageId
        self.localPath = localPath
        self.downloadUrl = downloadUrl
        self.configJson = configJson
        self.sourceName = sourceName
        _loader = StateObject(wrappedValue: PaginatedNovelLoader(
            localPath: localPath,
            downloadUrl: downloadUrl,
            scriptFileName: category.script,
            input: category.input,
            configJson: configJson
        ))
    }

    var body: some View {
        let scope = layoutScope
        // Đọc trong `body` ⇒ sheet "Kiểu hiển thị" hay màn Cài đặt ghi là danh sách vẽ lại theo kiểu mới.
        let layout = BookListLayoutPreferences.shared.layout(for: scope)
        VStack {
            if loader.isLoading && loader.novels.isEmpty {
                if layout.mode.isGrid {
                    DiscoverySkeletonGridView(
                        columns: layout.columns,
                        aspectRatio: scope.coverAspectRatio,
                        showsText: layout.mode == .grid
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ProgressView("Đang tải danh sách truyện...")
                        .frame(maxHeight: .infinity)
                }
            } else if !loader.errorMessage.isEmpty && loader.novels.isEmpty {
                VStack(spacing: 12) {
                    Text(loader.errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    ErrorLinkCaption(link: loader.errorLink)
                        .padding(.horizontal)
                    HStack(spacing: 10) {
                        Button("Thử lại") {
                            Task {
                                await loader.loadInitial()
                            }
                        }
                        .buttonStyle(.bordered)
                        ErrorLinkButton(link: loader.errorLink, presenting: $openingErrorLink, style: .bordered)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                DiscoveryNovelsLayoutView(
                    loader: loader,
                    layout: layout,
                    aspectRatio: scope.coverAspectRatio,
                    sourceHost: sourceHost,
                    isTranslationEnabled: isTranslationEnabled,
                    itemNoun: scope.itemNoun,
                    onSelectNovel: { novel in
                        if let onSelectVideo, ContentDetailRouter.isVideo(packageId: extensionPackageId) {
                            onSelectVideo(novel)
                            return
                        }
                        // Nguồn video ⇒ màn xem phim (phát dọc ngay), không đẩy Chi tiết.
                        if ContentDetailRouter.openIfVideo(
                            novel, packageId: extensionPackageId, sourceName: sourceName,
                            modelContainer: modelContext.container
                        ) { return }
                        selectedNovel = novel
                    }
                )
            }
        }
        // Gắn ở `VStack` ngoài (luôn tồn tại), không trong một nhánh danh sách/lưới: đổi kiểu không làm mất đích.
        .navigationDestination(item: $selectedNovel) { novel in
            BookDetailView(
                bookId: novel.link,
                extensionPackageId: extensionPackageId,
                initialDetailUrl: novel.link,
                sourceName: sourceName,
                initialHost: novel.host
            )
        }
        .backPageTitle(translateIfNeeded(category.title))
        .closesWhenNsfwHidden(packageId: extensionPackageId) // tắt NSFW ⇒ đóng danh sách của nguồn NSFW
        .toolbar {
            // Cụm nút sát nhau trong MỘT `ToolbarItem` (`HeaderButtonMetrics`): Lọc (chỉ khi tiện ích có bộ lọc) · Kiểu hiển thị.
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: HeaderButtonMetrics.pairSpacing) {
                    ExtensionFilterButton(
                        ext: ExtensionLibraryRepository.shared.installedExtension(packageId: extensionPackageId),
                        style: .toolbar
                    ) { showingFilterSheet = true }
                    Button {
                        showingLayoutSheet = true
                    } label: {
                        Image(systemName: layout.mode.symbolName)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: HeaderButtonMetrics.pairIconWidth, height: 36)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Kiểu hiển thị")
                }
            }
        }
        .sheet(isPresented: $showingLayoutSheet) {
            BookListLayoutSheet(scope: layoutScope)
        }
        .sheet(isPresented: $showingFilterSheet) {
            ExtensionFilterSheet(packageId: extensionPackageId) { configJson in
                Task { await loader.reset(configJson: configJson) }
            }
        }
        .errorLinkBrowser(link: $openingErrorLink, packageId: extensionPackageId) {
            Task { await loader.loadInitial() }
        }
        .onAppear {
            if sourceHost == nil {
                sourceHost = ExtensionHostResolver.sourceUrl(localPath: localPath)
            }
        }
        .onDisappear {
            if openingErrorLink != nil { skipsReappearLoad = true }
        }
        .task {
            if skipsReappearLoad {
                skipsReappearLoad = false
                return
            }
            // Back từ Chi tiết truyện: danh sách đã có (kể cả các trang cuộn thêm) ⇒ giữ nguyên, không về trang 1.
            // Rỗng = chưa tải, bị huỷ hoặc lỗi trang 1 ⇒ tải (lỗi thì tự thử lại).
            guard loader.novels.isEmpty else { return }
            await loader.loadInitial()
        }
    }

    private func translateIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text)
    }
}
