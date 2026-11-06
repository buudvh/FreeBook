import SwiftUI
import UniformTypeIdentifiers

struct RepositoryManagerView: View {
    /// Nguồn sự thật (`@Observable`): đọc trong `body` là tự vẽ lại khi kho/tiện ích đổi. Ghi qua
    /// `ExtensionTransactionCoordinator`.
    internal var library: ExtensionLibraryRepository { ExtensionLibraryRepository.shared }
    /// Kiểm tra cập nhật + thêm kho (`@Observable`): tự chạy khi vào "Tất cả tiện ích", trang Danh sách kho đọc chung.
    internal var updateChecker: ExtensionUpdateCheckCoordinator { ExtensionUpdateCheckCoordinator.shared }
    /// Đã cài ∪ mục registry chưa cài (`folder` rỗng ⇒ `localPath` rỗng). **Không** gồm nguồn Legado (tab riêng).
    internal var allExtensions: [Extension] { LegadoSourcePolicy.excludingLegado(library.catalog) }

    // Quản lý Tab chính của view. Tag 1 (Danh sách kho) bỏ từ 1.3.673 — giờ là trang con `ExtensionRepositoryListView`
    // mở từ ngăn kéo …; giữ tag 2 cho Legado để các chỗ so `== 2` không phải đổi.
    @State internal var selectedTab = 0 // 0: Tất cả tiện ích, 2: Nguồn Legado
    @State internal var renderedTab = 0
    @State internal var legadoState = LegadoSourceTabState()
    @State internal var showingRepositoryList = false
    /// Trang con "Báo cáo kiểm tra" (1.3.759), mở từ ngăn kéo … của tab JS / Legado với loại tương ứng.
    @State internal var checkReportsKind: CheckReportKind?
    /// Đặt khi đẩy trang Danh sách kho: back về thì gốc nhận lại `onAppear` ⇒ bỏ qua đúng một lần (không dọn, không
    /// kiểm tra lại).
    @State internal var isReturningFromRepositoryList = false

    // Trạng thái của tab Tất cả tiện ích
    @State internal var isUpdatingAll = false
    @State internal var statusMessage = ""
    @State internal var storeSearchQuery: String = ""
    @ObservedObject internal var extensionManager = ExtensionManager.shared
    @State internal var errorMessage = ""
    @State internal var selectedExtensionForConfig: Extension? = nil
    @State internal var selectedExtensionForScriptEditor: Extension? = nil
    @State internal var sourceCheckRoute: ExtensionCheckView.Route? // `+SourceCheck`

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
                Text("Tiện ích Tàng Công Các").tag(0)
                Text("Tiện ích Legado").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(.systemGroupedBackground))
            
            TabView(selection: $selectedTab) {
                allExtensionsTab.tag(0)
                legadoSourcesTab.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: selectedTab) { _, newVal in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    renderedTab = newVal
                }
                // Từ Nguồn Legado sang ⇒ cũng là "vào Tất cả tiện ích" (coordinator tự giãn cách 5 phút).
                if newVal == 0 { updateChecker.checkOnEntry() }
            }
        }
        .pageTitle("Kho tiện ích") // tab gốc
        .mainTabBar(hidesWithKeyboard: true) // thanh tab tự vẽ (1.3.668); có ô tìm ⇒ ẩn theo bàn phím
        .toolbar { toolbarContent }
    }

    @ViewBuilder
    internal func applySheetsAndAlerts<V: View>(_ content: V) -> some View {
        content
            .sideDrawerMenu(isPresented: $showingExtensionsMenu, title: "Tiện ích Tàng Công Các") { extensionsMenuItems }
            .sideDrawerMenu(isPresented: $showingLegadoMenu, title: "Tiện ích Legado") { legadoMenuItems }
            .alert("Xóa tất cả tiện ích?", isPresented: $showingUninstallAllAlert) {
                Button("Hủy", role: .cancel) { }
                Button("Xóa sạch", role: .destructive) {
                    uninstallAllExtensions()
                }
            } message: {
                Text("Hành động này sẽ gỡ cài đặt toàn bộ các tiện ích đã cài trong ứng dụng. Bạn có chắc chắn không?")
            }
            .sheet(isPresented: $showingFilterSheet) {
                makeFilterSheet()
            }
            .navigationDestination(isPresented: $showingRepositoryList) {
                ExtensionRepositoryListView()
            }
            .navigationDestination(item: $checkReportsKind) { kind in
                CheckReportListView(initialKind: kind)
            }
            .sheet(item: $selectedExtensionForConfig, onDismiss: { MinimizedSourceCheckCoordinator.shared.screenDidClose(.script, screenId: nil) }) { ext in
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
                if isReturningFromRepositoryList {
                    isReturningFromRepositoryList = false
                    return
                }
                // Dọn trước khi kiểm tra cập nhật: hàng đã mất file mà không có nguồn tải lại chỉ gây lỗi.
                auditInstalledExtensions()
                // Không tự thêm kho nào khi danh sách kho trống (1.3.749) — người dùng tự dán link ở Danh sách kho.
                if selectedTab == 0 {
                    updateChecker.checkOnEntry()
                }
            }
    }

    @ToolbarContentBuilder
    internal var toolbarContent: some ToolbarContent {
        if selectedTab == 2 {
            legadoToolbarContent
        } else {
            allExtensionsToolbarContent // `+SourceCheck`
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
                if ExtensionUpdateCheckStatusLine.hasContent {
                    ExtensionUpdateCheckStatusLine()
                        .padding(.horizontal)
                }
                searchAndFilterBar
                Divider()
                updateAllBanner

                // Kết quả "Cập nhật tất cả", Import zip — trước 1.3.673 chỉ hiện ở tab Danh sách kho.
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

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
                        // App không gieo sẵn kho (1.3.749) ⇒ chỉ đường cho người mới cài.
                        Text(library.repositories.isEmpty
                             ? "Chưa có kho tiện ích. Mở … › Danh sách kho để nhập link kho."
                             : "Không tìm thấy tiện ích nào")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
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

    /// Ô tìm viên thuốc kiểu mục lục (`ChapterTOCSearchField`, tìm theo tên/URL như trước) + icon lọc phễu (`FilterGlyph`,
    /// chấm trắng khi đang lọc) — cùng kiểu nút lọc tiện ích ở Khám phá / màn Tìm.
    @ViewBuilder
    internal var searchAndFilterBar: some View {
        HStack(spacing: 2) {
            ChapterTOCSearchField(
                text: $storeSearchQuery,
                placeholder: "Tìm kiếm \(allExtensions.count) tiện ích",
                palette: .system
            )
            Button(action: { showingFilterSheet = true }) {
                FilterGlyph(style: .inline, isActive: isFiltering)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFiltering ? "Bộ lọc (đang lọc)" : "Bộ lọc")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
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
}
