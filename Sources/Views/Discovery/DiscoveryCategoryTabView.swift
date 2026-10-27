import SwiftUI

/// Một tab danh mục `home` kiểu cũ của Khám phá: danh sách truyện có phân trang của một `CategoryResult`, dựng
/// theo kiểu hiển thị của loại nguồn (`layoutScope`) qua `DiscoveryNovelsLayoutView`. Tab dạng section dùng
/// `ExploreSectionsView`, không đi qua đây.
struct DiscoveryCategoryTabView: View {
    let category: CategoryResult
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let isTranslationEnabled: Bool
    /// Loại của nguồn đang xem — chọn kiểu hiển thị (`BookListLayoutPreferences`) và tỉ lệ bìa.
    let layoutScope: BookListLayoutScope
    @Binding var selectedCategoryId: String
    /// Neo cuộn dùng chung của cả Khám Phá — giữ ở `DiscoveryView` nên sống qua một lượt tab bị dựng lại.
    let scrollAnchors: DiscoveryScrollAnchorStore
    /// Tiện ích/nguồn của tab — nguồn Legado thì cookie của trình duyệt "Mở link lỗi" được gộp vào kho của nguồn.
    let packageId: String?
    let onSelectNovel: (ExtensionItemResult) -> Void
    /// Referer dự phòng cho bìa khi item không có `host`. Tra lười khi tab xuất hiện, không trong `init` — `init`
    /// chạy lại mỗi lần `DiscoveryView` dựng lại body.
    @State private var sourceHost: String? = nil

    @StateObject private var loader: PaginatedNovelLoader
    @State private var initialLoadTask: Task<Void, Never>? = nil
    /// Neo đang chờ áp. Có giá trị từ lúc tab xuất hiện/được chọn tới lúc `scrollTo` chạy được —
    /// dữ liệu có thể chưa nạp xong ở thời điểm xuất hiện.
    @State private var pendingRestoreAnchor: String? = nil
    @State private var openingErrorLink: SourceErrorLink? = nil

    init(
        category: CategoryResult,
        localPath: String,
        downloadUrl: String,
        configJson: String,
        isTranslationEnabled: Bool,
        layoutScope: BookListLayoutScope,
        selectedCategoryId: Binding<String>,
        scrollAnchors: DiscoveryScrollAnchorStore,
        packageId: String? = nil,
        onSelectNovel: @escaping (ExtensionItemResult) -> Void
    ) {
        self.category = category
        self.localPath = localPath
        self.downloadUrl = downloadUrl
        self.configJson = configJson
        self.isTranslationEnabled = isTranslationEnabled
        self.layoutScope = layoutScope
        self._selectedCategoryId = selectedCategoryId
        self.scrollAnchors = scrollAnchors
        self.packageId = packageId
        self.onSelectNovel = onSelectNovel
        _loader = StateObject(wrappedValue: PaginatedNovelLoader(
            localPath: localPath,
            downloadUrl: downloadUrl,
            scriptFileName: category.script,
            input: category.input,
            configJson: configJson
        ))
    }

    var body: some View {
        // Đọc trong `body` ⇒ sheet "Kiểu hiển thị" hay màn Cài đặt ghi là tab vẽ lại theo kiểu mới.
        let layout = BookListLayoutPreferences.shared.layout(for: layoutScope)
        VStack(spacing: 0) {
            if loader.isLoading && loader.novels.isEmpty {
                Group {
                    if layout.mode.isGrid {
                        DiscoverySkeletonGridView(
                            columns: layout.columns,
                            aspectRatio: layoutScope.coverAspectRatio,
                            showsText: layout.mode == .grid
                        )
                    } else {
                        DiscoverySkeletonListView()
                    }
                }
                .frame(maxHeight: .infinity)
            } else if !loader.errorMessage.isEmpty && loader.novels.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
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
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else if loader.novels.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Không tìm thấy truyện nào")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    DiscoveryNovelsLayoutView(
                        loader: loader,
                        layout: layout,
                        aspectRatio: layoutScope.coverAspectRatio,
                        sourceHost: sourceHost,
                        isTranslationEnabled: isTranslationEnabled,
                        scrollAnchors: scrollAnchors,
                        anchorCategoryId: category.id,
                        onSelectNovel: onSelectNovel
                    )
                    // Neo có thể được đặt lúc dữ liệu chưa nạp xong, nên phải thử lại khi danh sách
                    // vừa có hàng đầu tiên. `pendingRestoreAnchor` bị xoá ngay sau lượt áp nên các
                    // lượt `loadMore` sau đó không kéo người dùng về chỗ cũ.
                    .onChange(of: loader.novels.count) { oldValue, _ in
                        guard oldValue == 0 else { return }
                        applyPendingRestore(proxy: proxy)
                    }
                    .onAppear {
                        pendingRestoreAnchor = scrollAnchors.anchor(for: category.id)
                        applyPendingRestore(proxy: proxy, delay: 0.2)
                    }
                }
            }
        }
        // Đóng trình duyệt "Mở link lỗi" ⇒ chép cookie rồi tải lại trang đầu. Lần xuất hiện lại không tự tải chồng:
        // `checkAndLoadData` bỏ qua khi đang có lỗi.
        .errorLinkBrowser(link: $openingErrorLink, packageId: packageId) {
            Task { await loader.loadInitial() }
        }
        .onAppear {
            checkAndLoadData()
        }
        .onDisappear {
            initialLoadTask?.cancel()
            initialLoadTask = nil
            // Chốt neo đúng lúc rời tab: một phép quét cho mỗi lượt đổi tab, thay vì mỗi hàng cuộn.
            captureAnchor()
        }
        .onChange(of: selectedCategoryId) { _, newValue in
            checkAndLoadData()
            if newValue == category.id {
                // Tab này vừa thành tab đang xem: nạp neo để lượt `applyPendingRestore` kế tiếp có việc.
                pendingRestoreAnchor = scrollAnchors.anchor(for: category.id)
            } else {
                // Đường thứ hai để chốt neo, cho ca `onDisappear` không nổ (trang chưa bị dỡ hẳn).
                captureAnchor()
            }
        }
    }

    private func captureAnchor() {
        guard scrollAnchors.hasVisibleRows(categoryId: category.id) else { return }
        scrollAnchors.captureAnchor(categoryId: category.id, orderedIds: loader.novels.map(\.link))
    }

    private func applyPendingRestore(proxy: ScrollViewProxy, delay: TimeInterval = 0.05) {
        guard let anchor = pendingRestoreAnchor else { return }
        // Neo trỏ hàng đầu tiên thì không có gì phải khôi phục — tránh một cú nhảy vô nghĩa.
        guard loader.novels.first?.link != anchor else {
            pendingRestoreAnchor = nil
            return
        }
        guard loader.novels.contains(where: { $0.link == anchor }) else { return }
        pendingRestoreAnchor = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func checkAndLoadData() {
        // Tab có thể nạp từ `onChange(selectedCategoryId)` trước khi `onAppear` chạy: tra Referer ở cả hai đường.
        if sourceHost == nil {
            sourceHost = ExtensionHostResolver.sourceUrl(localPath: localPath)
        }
        // Chỉ nạp dữ liệu khi tab này thực sự là tab được chọn VÀ chưa có dữ liệu
        guard selectedCategoryId == category.id else { return }
        guard loader.novels.isEmpty && !loader.isLoading && loader.errorMessage.isEmpty else { return }
        scheduleInitialLoad()
    }

    private func scheduleInitialLoad() {
        initialLoadTask?.cancel()
        initialLoadTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard selectedCategoryId == category.id,
                      loader.novels.isEmpty,
                      !loader.isLoading,
                      loader.errorMessage.isEmpty else { return }
                Task {
                    await loader.loadInitial()
                }
            }
        }
    }
}
