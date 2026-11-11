import SwiftUI

/// Route snapshot bất biến cho màn chi tiết truyện từ Discovery
private struct DiscoveryDetailRoute: Identifiable, Hashable {
    var id: String { bookId }
    let bookId: String
    let extensionPackageId: String
    let initialDetailUrl: String
    let sourceName: String
    let initialHost: String
}

struct DiscoveryView: View {
    /// Container cho màn xem phim (`ContentDetailRouter`): item của nguồn video mở màn xem thay cho Chi tiết.
    @Environment(\.modelContext) private var modelContext
    // Nhớ Extension và Home tab cuối cùng đã xem
    @AppStorage("lastSelectedExtensionId") private var lastSelectedExtensionId: String = ""
    @AppStorage("lastSelectedCategoryId") private var lastSelectedCategoryId: String = ""

    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    /// Tiện ích nội dung đã cài (chữ/tranh/video), thứ tự ghim → vừa dùng → A-Z (`ExtensionSortPolicy`); công tắc NSFW
    /// tắt thì bỏ nguồn NSFW — nguồn đang xem bị ẩn sẽ được `onChange` bên dưới đổi sang nguồn đầu tiên còn lại.
    /// Nguồn Legado hiện khi đang bật, loại đã hỗ trợ và có Khám phá hoặc tìm được (danh mục tìm nhanh — `isDiscoverable`).
    private var activeExtensions: [Extension] {
        // Bật/tắt nguồn Legado nằm ở bảng chụp không quan sát được: đọc `summaries` để Observation vẽ lại khi đổi.
        _ = LegadoSourceRepository.shared.summaries
        return ExtensionSortPolicy.sorted(RepositoryFilterPolicy.applyNsfwFilter(
            ExtensionLibraryRepository.shared.installed.filter { SearchExtensionScopePolicy.isDiscoverable($0) },
            includeNsfw: includeNsfw
        ))
    }

    /// Nguồn đã nhớ là Legado mà danh sách Legado chưa nạp xong (mọi nguồn Legado tạm coi như tắt): chờ, đừng chọn
    /// nguồn đầu tiên — `onChange(selectedExtensionId)` sẽ ghi đè mất nguồn đã nhớ.
    private var isAwaitingLegadoList: Bool {
        lastSelectedExtensionId.hasPrefix(LegadoSourceIdentity.packageIdPrefix) && !LegadoSourceRepository.shared.hasLoaded
    }
    
    @State private var selectedExtensionId: String = ""
    @State private var isLoading = true
    @State private var needsReloadActiveExtension = false
    /// `packageId` của nguồn đang xem có config vừa đổi, chờ tải lại khi sheet chọn nguồn đóng / màn hiện lại — không
    /// tải lại sau mỗi lượt tự lưu (ô chữ lưu sau mỗi 0,4 s dừng gõ ⇒ gọi nguồn dồn dập, tên miền gõ dở). Đổi nguồn ⇒ `nil`.
    @State private var configReloadPendingId: String? = nil
    /// Tăng khi tải lại vì config ⇒ tab danh mục / `explore` dựng lại bộ nạp (`.id`).
    @State private var catalogConfigStamp = 0
    /// Lượt tải danh mục đang chạy; lượt mới huỷ lượt cũ (đổi nguồn nhanh / `extensionDidUpdate`).
    @State private var discoveryLoadTask: Task<Void, Never>? = nil
    
    // Nguồn dữ liệu danh mục của tiện ích
    @State private var homeItems: [CategoryResult] = []
    @State private var genreItems: [CategoryResult] = []
    
    // ID danh mục / Tab đang được chọn hiển thị
    @State private var selectedCategoryId: String = ""
    /// Vị trí cuộn của từng tab. `@State` giữ một `class` (không `@StateObject`) nên ghi vào đây lúc
    /// cuộn không invalidate body — xem `DiscoveryScrollAnchorStore`.
    @State private var scrollAnchors = DiscoveryScrollAnchorStore()
    @State private var discoveryError: String = ""
    /// Link "Mở link lỗi" của `discoveryError` — gán/xoá cùng chỗ với chữ lỗi; `nil` khi nguồn chỉ thiếu script.
    @State private var discoveryErrorLink: SourceErrorLink? = nil
    @State private var openingErrorLink: SourceErrorLink? = nil

    // Thể loại được chọn để điều hướng đẩy view chuyên biệt
    @State private var selectedGenre: CategoryResult? = nil
    @State private var navigateToGenre = false
    
    // Route điều hướng chi tiết truyện từ Discovery
    @State private var selectedDetailRoute: DiscoveryDetailRoute? = nil

    // Định danh tab Thể loại
    private let genresTabId = "__genres__"
    
    // Ngăn kéo chọn nguồn (trượt từ trái — `discoverySourcePicker`)
    @State private var showingExtensionSelector = false
    /// Sheet "Bộ lọc" của nguồn đang xem (`ExtensionFilterSheet`); đóng ⇒ tải lại nếu config vừa đổi.
    @State private var showingFilterSheet = false
    /// Tab lúc bấm nút lọc — sheet giữ đúng tab đó dù người dùng vuốt sang tab khác phía sau.
    @State private var filterSheetScope: ExtensionFilterScope = .file("")
    /// Phồn → giản + dịch của nguồn đang xem (Nguồn ⇒ Tất cả) — `refreshTextOptions`, không tra từng hàng.
    @State private var textOptions: ChineseTextPipeline.Options = .passthrough

    // Import từ trình duyệt
    @State private var importedBookId: String = ""
    @State private var importedExtensionPackageId: String = ""
    @State private var importedDetailUrl: String = ""
    @State private var importedSourceName: String = ""
    @State private var importedHost: String = ""
    @State private var navigateToImportedBook = false

    /// Sheet "Kiểu hiển thị" của loại nguồn đang chọn (dòng trong menu header).
    @State private var showingLayoutSheet = false
    /// Trình duyệt trang nguồn đang chọn (dòng "Mở trình duyệt" trong menu header); Import ⇒ Chi tiết trong stack này.
    @State private var showingSourceBrowser = false

    private var selectedExtension: Extension? {
        activeExtensions.first(where: { $0.packageId == selectedExtensionId })
    }

    /// Phạm vi kiểu hiển thị theo loại của nguồn; chưa chọn nguồn ⇒ truyện chữ.
    private static func layoutScope(for ext: Extension?) -> BookListLayoutScope {
        BookListLayoutScope(kind: ext.map(SearchExtensionScopePolicy.kind(of:)) ?? .text)
    }

    /// Script của tab đang chọn cho nút lọc: Trang chủ ⇒ `explore`, Thể loại ⇒ `genre`, tab home ⇒ script của mục.
    /// Chưa có tab ⇒ không có mục lọc.
    private var filterScope: ExtensionFilterScope {
        if selectedCategoryId == genresTabId { return .pluginScript("genre") }
        guard let item = homeItems.first(where: { $0.id == selectedCategoryId }) else { return .file("") }
        return ExploreSectionsView.isTab(item) ? .pluginScript("explore") : .file(item.script)
    }

    private func shouldRenderCategoryTab(id: String) -> Bool {
        if id == genresTabId { return true }
        guard let selectedIndex = homeItems.firstIndex(where: { $0.id == selectedCategoryId }),
              let itemIndex = homeItems.firstIndex(where: { $0.id == id }) else {
            return true
        }
        // Giữ 7 tab (3 trước, current, 3 sau) để cache nhiều hơn mà không quá tốn bộ nhớ
        return abs(itemIndex - selectedIndex) <= 3
    }
    
    var body: some View {
        // Lọc + sort nguồn MỘT lần mỗi body; chỉ dùng trong biểu thức dựng view. Closure hành động/onChange
        // vẫn đọc `selectedExtension`/`activeExtensions` để lấy giá trị hiện tại, không bắt bản cũ.
        let active = activeExtensions
        let selected = active.first(where: { $0.packageId == selectedExtensionId })
        // Kiểu hiển thị theo loại nguồn đang xem; đọc trong `body` nên đổi nguồn hay ghi từ sheet là vẽ lại.
        let layoutScope = Self.layoutScope(for: selected)
        let layout = BookListLayoutPreferences.shared.layout(for: layoutScope)
        NavigationStack {
            VStack(spacing: 0) {
                if active.isEmpty {
                    // Có nguồn duyệt được nhưng đều bị công tắc NSFW ẩn ⇒ chỉ chỗ bật lại, không báo "chưa có nguồn".
                    let hidesNsfwOnly = !includeNsfw
                        && ExtensionLibraryRepository.shared.installed.contains { SearchExtensionScopePolicy.isDiscoverable($0) }
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "safari")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.secondary)
                        Text(hidesNsfwOnly ? "Đang ẩn nguồn nhạy cảm (NSFW)" : "Chưa có nguồn đọc truyện nào hoạt động")
                            .font(.headline)
                        Text(hidesNsfwOnly
                             ? "Bật trong Cài đặt › Thư Viện để xem."
                             : "Hãy cài đặt và kích hoạt ít nhất một tiện ích trong kho để khám phá danh mục truyện.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Spacer()
                    }
                } else {
                    // 1. Custom Header Bar (nguồn bên trái: icon tròn + tên/link hai dòng; Lọc · menu · Tìm kiếm bên phải)
                    HStack(spacing: 8) {
                        // Nút tròn icon + vùng chữ đều mở ngăn kéo chọn nguồn
                        DiscoverySourceHeaderButton(ext: selected) { showingExtensionSelector = true }

                        // Các nút tròn đứng sát nhau (`HeaderButtonMetrics.pairCircleSpacing`), giữ cỡ 38.
                        HStack(spacing: HeaderButtonMetrics.pairCircleSpacing) {
                            // Bộ lọc của tab đang xem (mục select/công tắc/list mà script của tab dùng) — không có thì không hiện.
                            let scope = filterScope
                            ExtensionFilterButton(ext: selected, scope: scope, style: .circle) {
                                filterSheetScope = scope
                                showingFilterSheet = true
                            }

                            // Menu gộp của nguồn: công tắc NSFW · Mở trình duyệt · Kiểu hiển thị · Dịch văn bản.
                            if let ext = selected {
                                DiscoverySourceMenuButton(
                                    packageId: ext.packageId,
                                    sourceName: ext.name,
                                    isChineseSourceHint: ext.isChineseSource,
                                    isTranslationEnabled: textOptions.translates,
                                    layoutSymbol: layout.mode.symbolName,
                                    canOpenBrowser: !ext.sourceUrl.isEmpty,
                                    onOpenBrowser: { showingSourceBrowser = true },
                                    onShowLayout: { showingLayoutSheet = true }
                                )
                            }

                            // Nút Tìm Kiếm chuyển sang SearchView
                            // Tìm kiếm tự lọc phạm vi nguồn (`SearchExtensionScopePolicy`): truyền cả kho để nguồn Legado
                            // có rule tìm kiếm mà không có Khám phá vẫn được "tìm mọi nguồn".
                            NavigationLink(destination: SearchView(
                                activeExtensions: ExtensionLibraryRepository.shared.installed,
                                selectedExtension: selected
                            )) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 38, height: 38)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))

                    if isLoading && homeItems.isEmpty && genreItems.isEmpty && discoveryError.isEmpty {
                        // Hiển thị Skeleton UI toàn trang khám phá khi tải lần đầu
                        DiscoveryMainSkeletonView(layout: layout, aspectRatio: layoutScope.coverAspectRatio)
                    } else {
                        // 3. Menu danh mục & Home tabs hiển thị khi có dữ liệu (chỉ có trang section thì không cần thanh chip)
                        if !genreItems.isEmpty || homeItems.contains(where: { !ExploreSectionsView.isTab($0) }) {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        if !genreItems.isEmpty {
                                            let isGenresSelected = selectedCategoryId == genresTabId
                                            Button(action: {
                                                selectedCategoryId = genresTabId
                                            }) {
                                                Image(systemName: "tag")
                                                    .font(.system(size: 17, weight: .semibold))
                                                    .foregroundColor(isGenresSelected ? .white : .secondary)
                                                    .frame(width: 36, height: 36)
                                                    .background(isGenresSelected ? Color.white.opacity(0.15) : Color(.secondarySystemBackground))
                                                    .clipShape(Circle())
                                                    .overlay(
                                                        Circle().strokeBorder(
                                                            isGenresSelected ? Color.white.opacity(0.32) : Color.secondary.opacity(0.25),
                                                            lineWidth: isGenresSelected ? 1.2 : 1
                                                        )
                                                    )
                                            }
                                            .id(genresTabId)
                                        }
                                        
                                        ForEach(homeItems) { item in
                                            let isSelected = selectedCategoryId == item.id
                                            Button(action: {
                                                selectedCategoryId = item.id
                                            }) {
                                                Text(ChineseTextPipeline.meta(item.title, textOptions))
                                                    .font(.subheadline)
                                                    .fontWeight(isSelected ? .bold : .regular)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 8)
                                                    .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                                                    .foregroundColor(isSelected ? .accentColor : .secondary)
                                                    .cornerRadius(20)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 20)
                                                            .stroke(
                                                                isSelected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25),
                                                                lineWidth: isSelected ? 1.2 : 1
                                                            )
                                                    )
                                            }
                                            .id(item.id)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                                .onChange(of: selectedCategoryId) { _, newValue in
                                    if !newValue.isEmpty {
                                        withAnimation {
                                            proxy.scrollTo(newValue, anchor: .center)
                                        }
                                        lastSelectedCategoryId = newValue
                                    }
                                }
                                .onAppear {
                                    if !selectedCategoryId.isEmpty {
                                        DispatchQueue.main.async {
                                            withAnimation {
                                                proxy.scrollTo(selectedCategoryId, anchor: .center)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                            .background(Color(.systemBackground))
                            
                            Divider()
                        }
                        
                        VStack(spacing: 0) {
                            if !discoveryError.isEmpty {
                                // Lỗi thật của script danh mục, hoặc câu báo nguồn thiếu home và genres.
                                DiscoveryCatalogErrorView(
                                    message: discoveryError,
                                    link: discoveryErrorLink,
                                    openingLink: $openingErrorLink,
                                    onRetry: { loadDiscoveryData() }
                                )
                            } else {
                                // TabView vuốt ngang trang gốc
                                TabView(selection: $selectedCategoryId) {
                                    if !genreItems.isEmpty {
                                        DiscoveryGenresTabView(
                                            genreItems: genreItems,
                                            homeItems: homeItems,
                                            textOptions: textOptions,
                                            selectedCategoryId: $selectedCategoryId,
                                            onSelectGenre: { item in
                                                selectedGenre = item
                                                navigateToGenre = true
                                            },
                                            legadoExtension: selected.flatMap { LegadoSourceIdentity.isLegado($0) ? $0 : nil }
                                        )
                                        .id(selectedExtensionId) // đổi nguồn ⇒ ô tìm thể loại về rỗng
                                        .tag(genresTabId)
                                    }

                                    ForEach(homeItems) { item in
                                        if let ext = selected {
                                            let extPackageId = ext.packageId
                                            let extSourceName = ext.name
                                            // Định danh trang = nguồn + lượt config: hai nguồn có tab trùng tên + input
                                            // (vd "Đồng nhân" của qidian và STV, tab section cố định) không được dùng lại
                                            // bộ nạp của nguồn trước — khi cả hai có `explore`, tab section được thêm lại
                                            // ngay nên khung tab không bị dựng lại lúc đổi nguồn.
                                            let pageIdentity = "\(extPackageId)#\(catalogConfigStamp)"
                                            let openNovel: (ExtensionItemResult) -> Void = { novel in
                                                // Nguồn video ⇒ màn xem phim (phát dọc ngay), không đẩy Chi tiết.
                                                if ContentDetailRouter.openIfVideo(
                                                    novel, packageId: extPackageId, sourceName: extSourceName,
                                                    modelContainer: modelContext.container
                                                ) { return }
                                                selectedDetailRoute = DiscoveryDetailRoute(
                                                    bookId: "\(extSourceName.lowercased())_\(novel.link)",
                                                    extensionPackageId: extPackageId,
                                                    initialDetailUrl: novel.link,
                                                    sourceName: extSourceName,
                                                    initialHost: novel.host
                                                )
                                            }
                                            if ExploreSectionsView.isTab(item) {
                                                ExploreSectionsView(ext: ext, textOptions: textOptions, onSelectNovel: openNovel,
                                                                    onSelectCategory: { selectedGenre = $0; navigateToGenre = true })
                                                    .id(pageIdentity) // đổi nguồn/config ⇒ dựng lại, tải lại theo giá trị mới
                                                    .tag(item.id)
                                            } else if shouldRenderCategoryTab(id: item.id) {
                                                DiscoveryCategoryTabView(
                                                    category: item,
                                                    localPath: ext.localPath,
                                                    downloadUrl: ext.downloadUrl,
                                                    configJson: ext.configJson,
                                                    textOptions: textOptions,
                                                    layoutScope: layoutScope,
                                                    selectedCategoryId: $selectedCategoryId,
                                                    scrollAnchors: scrollAnchors,
                                                    packageId: extPackageId,
                                                    onSelectNovel: openNovel
                                                )
                                                .id(pageIdentity) // bộ nạp là `@StateObject` tạo một lần với nguồn + `configJson` cũ
                                                .tag(item.id)
                                            } else {
                                                Color.clear
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                    .tag(item.id)
                                            }
                                        }
                                    }
                                }
                                .tabViewStyle(.page(indexDisplayMode: .never))
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            // Thanh tab tự vẽ: trong trang gốc, trang đẩy vào phủ lên (1.3.668); tab nhãn có ô tìm ⇒ ẩn theo bàn phím.
            .mainTabBar(hidesWithKeyboard: true)
            // Gắn ở view ngoài cùng (không nằm trong nhánh có nguồn) để vẫn chạy khi danh sách nguồn rỗng.
            .onChange(of: selectedExtensionId) { _, newValue in
                // Không ghi "" vào nguồn đã nhớ: hết nguồn (vd ẩn hết nguồn NSFW) rồi có lại thì còn khôi phục được.
                if !newValue.isEmpty { lastSelectedExtensionId = newValue }
                configReloadPendingId = nil // nguồn mới tải lại từ đầu bên dưới
                let isChinese = selectedExtension?.isChineseSource ?? false
                TranslationConfigStore.shared.registerSource(packageId: newValue, isChinese: isChinese)
                refreshTextOptions()
                // Xóa sạch dữ liệu cũ khi đổi extension để tránh rác hiển thị
                homeItems.removeAll()
                genreItems.removeAll()
                selectedCategoryId = ""
                discoveryError = ""
                discoveryErrorLink = nil
                if !newValue.isEmpty {
                    loadDiscoveryData()
                } else {
                    discoveryLoadTask?.cancel()
                    isLoading = false
                }
            }
            // Config của nguồn đang xem vừa đổi (màn Cấu hình tự lưu, vd "Nhóm nội dung" lọc `home`/`genre`) ⇒ đánh dấu
            // tải lại; chạy khi sheet chọn nguồn (nơi mở Cấu hình từ Khám phá) đóng, hoặc ở `onAppear` (sửa từ tab
            // Tiện ích). Đổi nguồn đã có `onChange(selectedExtensionId)` lo.
            .onChange(of: [selectedExtensionId, selectedExtension?.configJson ?? ""]) { old, new in
                guard old[0] == new[0], old[1] != new[1], !new[0].isEmpty else { return }
                configReloadPendingId = new[0]
            }
            .onChange(of: showingExtensionSelector) { _, isShowing in
                if !isShowing { _ = reloadAfterConfigChangeIfPending() }
            }
            // Áp dụng bộ lọc ⇒ config đổi (đánh dấu ở trên) ⇒ sheet đóng thì tải lại: tab đang xem về trang 1, lên đầu.
            .onChange(of: showingFilterSheet) { _, isShowing in
                if !isShowing { _ = reloadAfterConfigChangeIfPending() }
            }
            // Nguồn đang chọn vừa bị gỡ/ẩn ⇒ nguồn đầu tiên còn lại; hết nguồn thì xoá chọn. Đang không chọn gì mà có
            // nguồn trở lại (bật NSFW, cài tiện ích) ⇒ khôi phục nguồn cuối đã xem, không còn thì nguồn đầu tiên.
            .onChange(of: activeExtensions.map(\.packageId)) { _, ids in
                if selectedExtensionId.isEmpty {
                    selectedExtensionId = ids.contains(lastSelectedExtensionId) ? lastSelectedExtensionId : (ids.first ?? "")
                } else if !ids.contains(selectedExtensionId) {
                    selectedExtensionId = ids.first ?? ""
                }
            }
            // Danh sách Legado vừa nạp xong mà vẫn chưa chọn nguồn (đang chờ nguồn Legado đã nhớ — `isAwaitingLegadoList`)
            // ⇒ khôi phục nguồn đã nhớ nếu còn, không thì nguồn đầu tiên.
            .onChange(of: LegadoSourceRepository.shared.hasLoaded) { _, _ in
                guard selectedExtensionId.isEmpty else { return }
                let ids = activeExtensions.map(\.packageId)
                selectedExtensionId = ids.contains(lastSelectedExtensionId) ? lastSelectedExtensionId : (ids.first ?? "")
                if selectedExtensionId.isEmpty { isLoading = false }
            }
            .onAppear {
                // Khôi phục từ rỗng ⇒ `onChange(of: selectedExtensionId)` sẽ tự tải, nhánh tải bên dưới phải bỏ qua.
                let restoredSelection = selectedExtensionId.isEmpty
                // Tự động khôi phục nguồn cuối cùng đã xem
                if selectedExtensionId.isEmpty {
                    if !lastSelectedExtensionId.isEmpty && activeExtensions.contains(where: { $0.packageId == lastSelectedExtensionId }) {
                        selectedExtensionId = lastSelectedExtensionId
                    } else if isAwaitingLegadoList {
                        // Chờ `onChange(of: hasLoaded)` khôi phục nguồn Legado đã nhớ.
                    } else if let first = activeExtensions.first {
                        selectedExtensionId = first.packageId
                    } else {
                        // Không có extension hoạt động, tắt loading
                        isLoading = false
                    }
                }
                for ext in activeExtensions {
                    TranslationConfigStore.shared.registerSource(packageId: ext.packageId, isChinese: ext.isChineseSource)
                }
                refreshTextOptions()

                if !restoredSelection && reloadAfterConfigChangeIfPending() {
                    needsReloadActiveExtension = false
                } else if needsReloadActiveExtension {
                    needsReloadActiveExtension = false
                    if !selectedExtensionId.isEmpty {
                        loadDiscoveryData()
                    }
                } else if !restoredSelection && !selectedExtensionId.isEmpty && homeItems.isEmpty && genreItems.isEmpty && discoveryError.isEmpty && !isLoading {
                    // `!isLoading`: lượt tải đang bay (vd vừa tự chuyển nguồn) thì không tải chồng lần hai.
                    loadDiscoveryData()
                } else if selectedExtensionId.isEmpty {
                    isLoading = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("extensionDidUpdate"))) { notification in
                if let packageId = notification.userInfo?["packageId"] as? String {
                    if packageId == selectedExtensionId {
                        needsReloadActiveExtension = true
                    }
                }
            }
            // Cấu hình dịch / phồn → giản đổi ở bất kỳ cấp nào (popup dịch, công tắc Tất cả, từ điển / rule).
            .onChange(of: TranslationDisplayRevision.shared.value) { _, _ in refreshTextOptions() }
            .discoverySourcePicker(
                isPresented: $showingExtensionSelector,
                selectedExtensionId: $selectedExtensionId,
                extensions: active,
                onImport: { detailUrl, packageId, sourceName in
                    showImportedBook(detailUrl: detailUrl, packageId: packageId, sourceName: sourceName)
                },
                onConfigClosed: { _ = reloadAfterConfigChangeIfPending() }
            )
            .sheet(isPresented: $showingFilterSheet) {
                if let packageId = selectedExtension?.packageId {
                    ExtensionFilterSheet(packageId: packageId, scope: filterSheetScope)
                }
            }
            .sheet(isPresented: $showingLayoutSheet) {
                // Tính scope lúc mở từ nguồn hiện tại, không bắt `layoutScope` của lượt body cũ.
                BookListLayoutSheet(scope: Self.layoutScope(for: selectedExtension), showsExploreSizes: homeItems.contains(where: ExploreSectionsView.isTab))
            }
            // Đóng trình duyệt "Mở link lỗi" của khối lỗi danh mục ⇒ chép cookie rồi tải lại danh mục.
            .errorLinkBrowser(link: $openingErrorLink, packageId: selectedExtension?.packageId) { loadDiscoveryData() }
            .fullScreenCover(isPresented: $showingSourceBrowser) {
                // Đọc `sourceUrl` lúc trình bày từ nguồn hiện tại, không bắt bản của lượt body cũ.
                BypassWebView(
                    urlString: selectedExtension?.sourceUrl ?? "",
                    onImport: { detailUrl, packageId, sourceName in
                        showingSourceBrowser = false
                        AppLogger.shared.log("🌐 [Discovery] Import từ trình duyệt của \(sourceName): \(detailUrl)")
                        // Chờ `fullScreenCover` đóng xong rồi mới đẩy Chi tiết, kẻo stack đổi giữa lúc đóng.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showImportedBook(detailUrl: detailUrl, packageId: packageId, sourceName: sourceName)
                        }
                    }
                )
            }
            .navigationDestination(isPresented: $navigateToImportedBook) {
                BookDetailView(
                    bookId: importedBookId,
                    extensionPackageId: importedExtensionPackageId,
                    initialDetailUrl: importedDetailUrl,
                    sourceName: importedSourceName,
                    initialHost: importedHost
                )
            }
            .navigationDestination(isPresented: $navigateToGenre) {
                if let genre = selectedGenre {
                    CategoryNovelsListView(
                        category: genre,
                        extensionPackageId: selectedExtensionId,
                        localPath: selectedExtension?.localPath ?? "",
                        downloadUrl: selectedExtension?.downloadUrl ?? "",
                        configJson: selectedExtension?.configJson ?? "{}",
                        sourceName: selectedExtension?.name ?? ""
                    )
                }
            }
            .navigationDestination(item: $selectedDetailRoute) { route in
                BookDetailView(
                    bookId: route.bookId,
                    extensionPackageId: route.extensionPackageId,
                    initialDetailUrl: route.initialDetailUrl,
                    sourceName: route.sourceName,
                    initialHost: route.initialHost
                )
            }
        }
    }
    
    /// Dựng route Chi tiết của truyện vừa "Import truyện" (từ trình duyệt của nguồn, mở ở menu header hoặc ở màn
    /// Cấu hình tiện ích trong bảng chọn nguồn) rồi đẩy trong stack Khám phá.
    private func showImportedBook(detailUrl: String, packageId: String, sourceName: String) {
        importedBookId = BookIdUtils.make(extensionPackageId: packageId, detailUrl: detailUrl)
        importedExtensionPackageId = packageId
        importedDetailUrl = detailUrl
        importedSourceName = sourceName
        if let url = URL(string: detailUrl), let scheme = url.scheme, let host = url.host {
            importedHost = "\(scheme)://\(host)"
        } else {
            importedHost = ""
        }
        // Phim ⇒ màn xem (phát dọc ngay) thay cho Chi tiết.
        if ContentDetailRouter.openIfVideo(
            packageId: packageId, detailUrl: detailUrl, sourceName: sourceName,
            host: importedHost, modelContainer: modelContext.container
        ) { return }
        navigateToImportedBook = true
    }

    /// Tải lại danh mục + dựng lại bộ nạp của các tab nếu config của **nguồn đang xem** đã đổi. `true` khi đã tải.
    private func reloadAfterConfigChangeIfPending() -> Bool {
        guard let pendingId = configReloadPendingId else { return false }
        configReloadPendingId = nil
        guard pendingId == selectedExtensionId else { return false }
        catalogConfigStamp &+= 1
        loadDiscoveryData()
        return true
    }

    private func loadDiscoveryData() {
        guard let ext = selectedExtension else {
            isLoading = false
            return
        }
        let pid = ext.packageId
        discoveryLoadTask?.cancel()
        isLoading = true
        discoveryError = ""
        discoveryErrorLink = nil
        // Danh mục sắp được dựng lại từ đầu: neo cũ trỏ vào danh sách không còn tồn tại.
        scrollAnchors.removeAll()

        // Có `explore` ⇒ tab section đứng đầu, các tab `home` vẫn giữ (cố ý khác hợp đồng, xem `fetchCatalog`). Hiện ngay,
        // không chờ `home`/`genre`; giữ tạm tab `home` cũ để tải lại cùng nguồn không đẩy người dùng về "Trang chủ".
        let exploreTab: CategoryResult? = ExtensionManager.shared.hasScript(localPath: ext.localPath, scriptKey: "explore")
            ? ExploreSectionsView.makeTab() : nil
        if let exploreTab {
            homeItems = [exploreTab] + homeItems.filter { !ExploreSectionsView.isTab($0) }
            selectedCategoryId = Self.resolveCategoryId(current: selectedCategoryId, saved: lastSelectedCategoryId,
                                                        home: homeItems, hasGenre: !genreItems.isEmpty, genresTabId: genresTabId)
        }

        discoveryLoadTask = Task {
            let loaded = await Self.fetchCatalog(ext, exploreTab: exploreTab)
            await MainActor.run {
                // Đã đổi nguồn hoặc có lượt tải mới hơn ⇒ bỏ kết quả này, không ghi đè.
                guard !Task.isCancelled, selectedExtensionId == pid else { return }
                homeItems = loaded.home
                genreItems = loaded.genre
                isLoading = false
                let hasData = !loaded.home.isEmpty || !loaded.genre.isEmpty
                // Không có mục nào: lỗi thật của script đã khai, không thì nguồn thiếu cả hai script.
                discoveryError = hasData ? "" : (loaded.failure?.message ?? "Extension thiếu home và genres")
                discoveryErrorLink = hasData ? nil : loaded.failure?.link
                selectedCategoryId = Self.resolveCategoryId(current: selectedCategoryId, saved: lastSelectedCategoryId,
                                                            home: loaded.home, hasGenre: !loaded.genre.isEmpty, genresTabId: genresTabId)
            }
        }
    }
    
    /// Tính lại `textOptions` của nguồn đang xem (đổi nguồn, màn hiện lại, cấu hình đổi); giữ nguyên nếu không khác.
    private func refreshTextOptions() {
        let packageId = selectedExtensionId.isEmpty ? nil : selectedExtensionId
        let options = ChineseTextPipeline.sourceOptions(packageId: packageId, isChineseSourceHint: selectedExtension?.isChineseSource)
        if textOptions != options { textOptions = options }
    }
}

// MARK: - Skeleton UI Components

struct DiscoverySkeletonListView: View {
    var body: some View {
        // Dòng chờ cùng dáng panel của kiểu Danh sách (`bookListPanel`): lề 16, cách nhau 8, không vạch ngăn.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<8) { _ in
                    HStack(spacing: 12) {
                        SkeletonView(width: 50, height: 70)
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonView(width: 160, height: 16)
                            SkeletonView(width: nil, height: 12)
                            SkeletonView(width: 100, height: 12)
                        }
                    }
                    .bookListPanel()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

struct DiscoveryMainSkeletonView: View {
    /// Kiểu hiển thị của loại nguồn — khung chờ phần danh sách khớp kiểu mà tab danh mục sắp dựng.
    var layout: BookListLayout = .default
    var aspectRatio: CGFloat = BookListLayoutScope.text.coverAspectRatio

    var body: some View {
        VStack(spacing: 0) {
            // Category pills horizontal scroll skeleton
            HStack(spacing: 8) {
                SkeletonView(width: 44, height: 40)
                    .cornerRadius(8)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<5) { _ in
                            SkeletonView(width: CGFloat.random(in: 75...115), height: 32)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            Divider()
            
            // Novels list skeleton
            if layout.mode.isGrid {
                DiscoverySkeletonGridView(columns: layout.columns, aspectRatio: aspectRatio, showsText: layout.mode == .grid)
            } else {
                DiscoverySkeletonListView()
            }
        }
    }
}

