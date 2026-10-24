import SwiftUI

struct CategoryNovelsListView: View {
    let category: CategoryResult
    let extensionPackageId: String
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let sourceName: String
    @StateObject private var loader: PaginatedNovelLoader
    /// Referer dự phòng cho bìa khi item không có `host`. Tra lười khi xuất hiện, không trong `init` — `init` chạy lại
    /// mỗi lần view cha dựng lại body.
    @State private var sourceHost: String? = nil
    @State private var selectedNovel: ExtensionItemResult? = nil
    @State private var showingLayoutSheet = false

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
        sourceName: String
    ) {
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
                    Button("Thử lại") {
                        Task {
                            await loader.loadInitial()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxHeight: .infinity)
            } else {
                DiscoveryNovelsLayoutView(
                    loader: loader,
                    layout: layout,
                    aspectRatio: scope.coverAspectRatio,
                    sourceHost: sourceHost,
                    isTranslationEnabled: isTranslationEnabled,
                    rowVerticalPadding: 4,
                    onSelectNovel: { selectedNovel = $0 }
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
        .navigationTitle(translateIfNeeded(category.title))
        .navigationBarTitleDisplayMode(.inline)
        .closesWhenNsfwHidden(packageId: extensionPackageId) // tắt NSFW ⇒ đóng danh sách của nguồn NSFW
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingLayoutSheet = true
                } label: {
                    Image(systemName: layout.mode.symbolName)
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("Kiểu hiển thị")
            }
        }
        .sheet(isPresented: $showingLayoutSheet) {
            BookListLayoutSheet(scope: layoutScope)
        }
        .onAppear {
            if sourceHost == nil {
                sourceHost = ExtensionHostResolver.sourceUrl(localPath: localPath)
            }
        }
        .task {
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
