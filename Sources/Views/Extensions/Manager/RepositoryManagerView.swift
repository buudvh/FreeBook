import SwiftUI
import UniformTypeIdentifiers

struct RepositoryManagerView: View {
    /// Nguồn sự thật (`@Observable`): đọc trong `body` là tự vẽ lại khi kho/tiện ích đổi. Ghi qua
    /// `ExtensionTransactionCoordinator`.
    internal var library: ExtensionLibraryRepository { ExtensionLibraryRepository.shared }
    internal var repositories: [ExtensionRepositoryRecord] {
        library.repositories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    /// Đã cài ∪ mục registry chưa cài (`folder` rỗng ⇒ `localPath` rỗng). **Không** gồm nguồn Legado (tab riêng).
    internal var allExtensions: [Extension] { LegadoSourcePolicy.excludingLegado(library.catalog) }

    // Quản lý Tab chính của view
    @State internal var selectedTab = 0 // 0: Tất cả tiện ích, 1: Danh sách kho, 2: Nguồn Legado
    @State internal var renderedTab = 0
    @State internal var legadoState = LegadoSourceTabState()
    
    // Trạng thái cho Tab 1: Cửa hàng tiện ích gộp
    @State internal var showingAddRepo = false
    @State internal var isRefreshingAll = false
    @State internal var isUpdatingAll = false
    @State internal var statusMessage = ""
    @State internal var storeSearchQuery: String = ""
    @ObservedObject internal var extensionManager = ExtensionManager.shared
    @State internal var errorMessage = ""
    @State internal var selectedExtensionForConfig: Extension? = nil
    @State internal var selectedExtensionForScriptEditor: Extension? = nil
    @State internal var sourceCheckRoute: ExtensionCheckView.Route? // `+SourceCheck`
    @State internal var repositoryToDelete: ExtensionRepositoryRecord?
    @State internal var showingDeleteRepositoryAlert = false
    
    internal var updatableExtensions: [Extension] {
        allExtensions.filter { $0.hasUpdate }
    }
    
    // Bộ lọc và Trạng thái Sheet/Alert mới
    @State internal var showingFilterSheet = false
    @State internal var showingUninstallAllAlert = false
    @State internal var showingZipImporter = false
    /// Ngăn kéo "…" của tab Tất cả tiện ích / tab Nguồn Legado (`RepositoryManagerView+LegadoMenu`).
    @State internal var showingExtensionsMenu = false
    @State internal var showingLegadoMenu = false
    // Bộ lọc chọn nhiều: JSON `[String]`, rỗng = chưa ghi (đọc khoá cũ) — xem `ExtensionFilterSelection`.
    @AppStorage(ExtensionFilterSelection.typesKey) internal var filterTypesJSON: String = ""
    @AppStorage(ExtensionFilterSelection.localesKey) internal var filterLocalesJSON: String = ""
    @AppStorage(ExtensionFilterSelection.authorsKey) internal var filterAuthorsJSON: String = ""
    /// Công tắc NSFW (mặc định tắt = ẩn tiện ích NSFW). Tìm mọi nguồn đọc cùng khoá; Khám phá không đọc.
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) internal var filterIncludeNsfw: Bool = false

    internal var filterTypes: Binding<Set<String>> {
        ExtensionFilterSelection.binding($filterTypesJSON, legacyKey: ExtensionFilterSelection.legacyTypeKey, normalize: ExtensionFilterGroups.typeGroup(for:))
    }
    internal var filterLocales: Binding<Set<String>> {
        ExtensionFilterSelection.binding($filterLocalesJSON, legacyKey: ExtensionFilterSelection.legacyLocaleKey, normalize: ExtensionFilterGroups.localeGroup(for:))
    }
    internal var filterAuthors: Binding<Set<String>> {
        ExtensionFilterSelection.binding($filterAuthorsJSON, legacyKey: ExtensionFilterSelection.legacyAuthorKey)
    }

    // Trạng thái bộ lọc: có ít nhất một nhóm không rỗng, hoặc đã bật hiện NSFW (mặc định tắt không tính là lọc)
    internal var isFiltering: Bool {
        !filterTypes.wrappedValue.isEmpty || !filterLocales.wrappedValue.isEmpty || !filterAuthors.wrappedValue.isEmpty
            || filterIncludeNsfw
    }

    internal var isUninstallAllDisabled: Bool {
        !library.installed.contains { !LegadoSourcePolicy.isLegado($0) }
    }
    
    /// Sheet bộ lọc. Tác giả / nhóm ngôn ngữ / nhóm thể loại và số trên chip tính trên catalog (đã cài ∪ cache
    /// registry) **sau** công tắc NSFW — lọc NSFW **một lần** cho cả sheet: bấm chip là dựng lại nội dung sheet.
    internal func makeFilterSheet() -> FilterSheet {
        let pool = RepositoryFilterPolicy.applyNsfwFilter(allExtensions, includeNsfw: filterIncludeNsfw)
        let typeCounts = ExtensionFilterGroups.typeGroupCounts(pool)
        let localeCounts = ExtensionFilterGroups.localeGroupCounts(pool)
        let authors = Array(Set(pool.map { $0.author }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterSheet(
            allAuthors: authors,
            allLocales: ExtensionFilterGroups.presentGroups(ExtensionFilterGroups.localeGroupOrder, counts: localeCounts),
            allTypes: ExtensionFilterGroups.presentGroups(ExtensionFilterGroups.typeGroupOrder, counts: typeCounts),
            typeCounts: typeCounts,
            localeCounts: localeCounts,
            filterTypes: filterTypes,
            filterLocales: filterLocales,
            filterAuthors: filterAuthors,
            includeNsfw: $filterIncludeNsfw,
            hiddenNsfwCount: allExtensions.count - pool.count
        )
    }

    // Danh sách tiện ích sau khi lọc theo các tiêu chí, công tắc NSFW và tìm kiếm
    internal var filteredExtensions: [Extension] {
        RepositoryFilterPolicy.shared.filterExtensions(
            allExtensions,
            query: storeSearchQuery,
            authors: filterAuthors.wrappedValue,
            types: filterTypes.wrappedValue,
            locales: filterLocales.wrappedValue,
            includeNsfw: filterIncludeNsfw
        )
    }
    
    var body: some View {
        NavigationStack {
            applySheetsAndAlerts(mainContentView)
        }
    }

    @ViewBuilder
    internal var mainContentView: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Tất cả tiện ích").tag(0)
                Text("Danh sách kho").tag(1)
                Text("Nguồn Legado").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(.systemGroupedBackground))
            
            TabView(selection: $selectedTab) {
                allExtensionsTab.tag(0)
                repositoryListTab.tag(1)
                legadoSourcesTab.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: selectedTab) { _, newVal in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    renderedTab = newVal
                }
            }
        }
        .pageTitle("Kho tiện ích") // tab gốc
        .toolbar { toolbarContent }
    }

    @ViewBuilder
    internal func applySheetsAndAlerts<V: View>(_ content: V) -> some View {
        content
            .sideDrawerMenu(isPresented: $showingExtensionsMenu, title: "Tất cả tiện ích") { extensionsMenuItems }
            .sideDrawerMenu(isPresented: $showingLegadoMenu, title: "Nguồn Legado") { legadoMenuItems }
            .alert("Xóa tất cả tiện ích?", isPresented: $showingUninstallAllAlert) {
                Button("Hủy", role: .cancel) { }
                Button("Xóa sạch", role: .destructive) {
                    uninstallAllExtensions()
                }
            } message: {
                Text("Hành động này sẽ gỡ cài đặt toàn bộ các tiện ích đã cài trong ứng dụng. Bạn có chắc chắn không?")
            }
            .alert(
                "Xóa kho tiện ích?",
                isPresented: $showingDeleteRepositoryAlert,
                presenting: repositoryToDelete
            ) { repo in
                Button("Hủy", role: .cancel) {
                    repositoryToDelete = nil
                }
                Button("Xóa kho", role: .destructive) {
                    deleteRepository(repo)
                    repositoryToDelete = nil
                }
            } message: { repo in
                Text("Kho \(repo.name) và các tiện ích đã cài từ kho này sẽ bị xóa khỏi ứng dụng.")
            }
            .sheet(isPresented: $showingFilterSheet) {
                makeFilterSheet()
            }
            .sheet(isPresented: $showingAddRepo) {
                AddRepositoryView { name, url in
                    addNewRepository(name: name, url: url)
                }
            }
            .sheet(item: $selectedExtensionForConfig) { ext in
                ExtensionConfigView(ext: ext)
            }
            .sheet(item: $selectedExtensionForScriptEditor) { ext in
                ExtensionScriptEditorView(ext: ext)
            }
            .sheet(item: $sourceCheckRoute, onDismiss: stopSourceCheck) { route in sourceCheckSheet(route) }
            .background {
                DocumentPickerPresenter(
                    isPresented: $showingZipImporter,
                    allowedContentTypes: [.zip],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        guard let url = urls.first else { return }
                        importExtensionFromZip(url)
                    },
                    onCancel: nil
                )
            }
            .background { legadoFilePicker }
            .onAppear {
                renderedTab = selectedTab
                // Dọn trước khi làm mới kho: hàng đã mất file mà không có nguồn tải lại chỉ gây lỗi.
                auditInstalledExtensions()
                if repositories.isEmpty {
                    addSampleRepository()
                } else {
                    refreshAllRepositories()
                }
            }
    }

    @ToolbarContentBuilder
    internal var toolbarContent: some ToolbarContent {
        if selectedTab == 2 {
            legadoToolbarContent
        } else if selectedTab == 0 {
            allExtensionsToolbarContent // `+SourceCheck`
        } else {
            // Bên trái là tiêu đề trang ⇒ ↻ dồn sang phải, đứng trước +.
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: { refreshAllRepositories(force: true) }) {
                    if isRefreshingAll {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .disabled(isRefreshingAll || repositories.isEmpty)
                .accessibilityLabel("Làm mới tất cả kho")
                Button(action: { showingAddRepo = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("Thêm kho")
            }
        }
    }

    @ViewBuilder
    internal var allExtensionsTab: some View {
        VStack(spacing: 8) {
            if renderedTab == 0 {
                // Tính **một lần** cho cả lượt vẽ: trước 1.3.330 `filteredExtensions` chạy 3 lần
                // (thanh đếm, `isEmpty`, `List`), mỗi lần là 4 vòng `filter` + một `sorted` dùng
                // `localizedCompare` — nhân với mỗi ký tự người dùng gõ vào ô tìm kiếm.
                let extensions = filteredExtensions

                filterStatusBar(count: extensions.count)
                searchAndFilterBar
                Divider()
                updateAllBanner

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                if extensions.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "puzzlepiece.extension")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Không tìm thấy tiện ích nào")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List(extensions) { ext in
                        extensionRow(ext)
                            .contextMenu { nsfwContextMenu(ext) }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .background(Color(.systemGroupedBackground).opacity(0.3))
    }

    @ViewBuilder
    internal func filterStatusBar(count: Int) -> some View {
        HStack {
            Text("Đang hiển thị \(count) tiện ích")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if isFiltering {
                Button(action: {
                    filterTypes.wrappedValue = []
                    filterLocales.wrappedValue = []
                    filterAuthors.wrappedValue = []
                    filterIncludeNsfw = false
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.circle")
                        Text("Đặt lại bộ lọc")
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    internal var searchAndFilterBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Tìm tên tiện ích hoặc URL...", text: $storeSearchQuery)
                    .textInputAutocapitalization(.none)
                    .submitLabel(.search)
                if !storeSearchQuery.isEmpty {
                    Button(action: { storeSearchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            
            Button(action: { showingFilterSheet = true }) {
                Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundColor(isFiltering ? .orange : .white)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    internal var updateAllBanner: some View {
        if !updatableExtensions.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Có \(updatableExtensions.count) tiện ích có bản cập nhật mới")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Cập nhật ngay để nhận các sửa lỗi & tính năng mới nhất.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: updateAllExtensions) {
                    if isUpdatingAll {
                        ProgressView()
                            .padding(.horizontal, 8)
                    } else {
                        Text("Cập nhật tất cả")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange)
                            .cornerRadius(8)
                    }
                }
                .disabled(isUpdatingAll)
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(10)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    internal func extensionRow(_ ext: Extension) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Dùng `ExtensionIconView`: nó ưu tiên `icon.png` **cục bộ** (qua cache) rồi mới ra mạng,
            // nên tiện ích đã cài không tải icon lần nào và vẫn hiện đúng khi offline.
            if !ext.localPath.isEmpty || !(ext.iconUrl ?? "").isEmpty {
                ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: 44, packageId: ext.packageId)
            } else {
                Image(systemName: typeIcon(ext.type))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .padding(6)
                    .background(Color.secondary.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .overlay(alignment: .topTrailing) {
                        if ExtensionNsfwCache.shared.isNsfw(ext) { ExtensionNsfwBadge(iconSize: 44) }
                    }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(ext.name)
                        .font(.headline)
                    if ext.hasUpdate, let remote = ext.remoteVersion {
                        Text("v\(ext.version) ➔ v\(remote)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    } else {
                        Text("v\(ext.version)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    
                    Text(getFlagEmoji(ext.locale))
                        .font(.subheadline)
                }
                
                HStack(spacing: 6) {
                    Text(translateType(ext.type))
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ext.type == ExtensionType.tts ? Color.orange.opacity(0.12) : Color.purple.opacity(0.12))
                        .foregroundColor(ext.type == ExtensionType.tts ? .orange : .purple)
                        .cornerRadius(4)
                    
                    Text(ext.author)
                        .font(.system(size: 9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(4)

                    if ext.showsDebugBadge {
                        Text("debug")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                }
                
                Text(ext.sourceUrl)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if extensionManager.loadingStates[ext.packageId] == true {
                ProgressView()
                    .frame(width: 60)
            } else {
                if ext.localPath.isEmpty {
                    Button(action: {
                        installExtension(ext)
                    }) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cài đặt \(ext.name)")
                } else {
                    HStack(spacing: 8) {
                        if ext.hasUpdate {
                            Button(action: {
                                installExtension(ext)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 34)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cập nhật \(ext.name)")
                        }
                        
                        Button(action: { selectedExtensionForConfig = ext }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cấu hình \(ext.name)")

                        ExtensionRowTrashButton(accessibilityLabel: "Gỡ cài đặt \(ext.name)") {
                            uninstallExtension(ext)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    internal var repositoryListTab: some View {
        List {
            if renderedTab == 1 {
                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
                Section(header: Text("Danh sách kho tiện ích")) {
                    if repositories.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("Bạn có thể nhập link kho tiện ích (định dạng plugin.json) để bắt đầu tải các nguồn bóc tách truyện.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Button(action: { addSampleRepository() }) {
                                Text("Nhập kho tiện ích mặc định (buudvh)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.18))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 5)
                        }
                        .padding(.vertical)
                    } else {
                        ForEach(repositories) { repo in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(repo.name)
                                        .font(.headline)
                                    Text(repo.url)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                                Spacer()
                                
                                Button {
                                    guard !isRefreshingAll else { return }
                                    repositoryToDelete = repo
                                    showingDeleteRepositoryAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                        .padding(8)
                                        .background(Color.red.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.borderless)
                                .disabled(isRefreshingAll)
                                .accessibilityLabel("Xóa kho \(repo.name)")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
