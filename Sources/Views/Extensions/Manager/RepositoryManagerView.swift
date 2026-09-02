import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RepositoryManagerView: View {
    @Environment(\.modelContext) internal var modelContext
    @Query(sort: \Repository.name) internal var repositories: [Repository]
    @Query internal var allExtensions: [Extension]
    
    // Quản lý Tab chính của view
    @State internal var selectedTab = 0 // 0: Tất cả tiện ích, 1: Danh sách kho
    @State internal var renderedTab = 0
    
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
    @State internal var repositoryToDelete: Repository?
    @State internal var showingDeleteRepositoryAlert = false
    
    internal var updatableExtensions: [Extension] {
        allExtensions.filter { $0.hasUpdate }
    }
    
    // Bộ lọc và Trạng thái Sheet/Alert mới
    @State internal var showingFilterSheet = false
    @State internal var showingUninstallAllAlert = false
    @State internal var showingZipImporter = false
    @AppStorage("extFilterType") internal var filterType: String = "all"
    @AppStorage("extFilterLocale") internal var filterLocale: String = "all"
    @AppStorage("extFilterAuthor") internal var filterAuthor: String = "all"
    
    // Trạng thái bộ lọc
    internal var isFiltering: Bool {
        filterType != "all" || filterLocale != "all" || filterAuthor != "all"
    }

    internal var isUninstallAllDisabled: Bool {
        allExtensions.filter { !$0.localPath.isEmpty }.isEmpty
    }
    
    // Lọc danh sách tác giả động từ database
    internal var allAuthors: [String] {
        let authors = allExtensions.map { $0.author }
        return Array(Set(authors)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    // Lọc danh sách ngôn ngữ động từ database
    internal var allLocales: [String] {
        let locales = allExtensions.map { $0.locale }
        return Array(Set(locales)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    // Lọc danh sách loại tiện ích động từ database (loại trừ comic)
    internal var allTypes: [String] {
        let types = allExtensions.map { $0.type }.filter { $0 != ExtensionType.comic }
        return Array(Set(types)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    // Danh sách tiện ích sau khi lọc theo các tiêu chí và tìm kiếm
    internal var filteredExtensions: [Extension] {
        RepositoryFilterPolicy.shared.filterExtensions(
            allExtensions,
            query: storeSearchQuery,
            author: filterAuthor,
            type: filterType,
            locale: filterLocale
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
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(.systemGroupedBackground))
            
            TabView(selection: $selectedTab) {
                allExtensionsTab.tag(0)
                repositoryListTab.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: selectedTab) { _, newVal in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    renderedTab = newVal
                }
            }
        }
        .navigationTitle("Kho Tiện Ích")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    @ViewBuilder
    internal func applySheetsAndAlerts<V: View>(_ content: V) -> some View {
        content
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
                FilterSheet(
                    allAuthors: allAuthors,
                    allLocales: allLocales,
                    allTypes: allTypes,
                    filterType: $filterType,
                    filterLocale: $filterLocale,
                    filterAuthor: $filterAuthor
                )
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
        if selectedTab == 0 {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingZipImporter = true }) {
                        Label("Import tiện ích (.zip)", systemImage: "doc.badge.plus")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: { showingUninstallAllAlert = true }) {
                        Label("Xóa tất cả tiện ích", systemImage: "trash")
                    }
                    .disabled(isUninstallAllDisabled)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddRepo = true }) {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: refreshAllRepositories) {
                    if isRefreshingAll {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshingAll || repositories.isEmpty)
            }
        }
    }

    @ViewBuilder
    internal var allExtensionsTab: some View {
        VStack(spacing: 8) {
            if renderedTab == 0 {
                filterStatusBar
                searchAndFilterBar
                Divider()
                updateAllBanner
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                if filteredExtensions.isEmpty {
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
                    List(filteredExtensions) { ext in
                        extensionRow(ext)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .background(Color(.systemGroupedBackground).opacity(0.3))
    }

    @ViewBuilder
    internal var filterStatusBar: some View {
        HStack {
            Text("Đang hiển thị \(filteredExtensions.count) tiện ích")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if isFiltering {
                Button(action: {
                    filterType = "all"
                    filterLocale = "all"
                    filterAuthor = "all"
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
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.none)
                
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
                    .foregroundColor(isFiltering ? .orange : .accentColor)
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
            if let iconUrl = ext.iconUrl, let url = URL(string: iconUrl) {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundColor(.accentColor)
                }
                .frame(width: 44, height: 44)
                .cornerRadius(8)
            } else {
                Image(systemName: ext.type == ExtensionType.tts ? "waveform" : "book.closed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .padding(6)
                    .background(Color.secondary.opacity(0.2))
                    .foregroundColor(.accentColor)
                    .cornerRadius(8)
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
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
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
                            .foregroundColor(.accentColor)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)
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
                        
                        Button(action: {
                            selectedExtensionForConfig = ext
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.blue)
                                .frame(width: 34, height: 34)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cấu hình \(ext.name)")
                        
                        Button(action: {
                            uninstallExtension(ext)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.red)
                                .frame(width: 34, height: 34)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Gỡ cài đặt \(ext.name)")
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
                            .foregroundColor(.blue)
                    }
                }
                
                Section(header: Text("Danh sách kho tiện ích")) {
                    if repositories.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Chưa nhập kho tiện ích nào.")
                                .font(.headline)
                                .foregroundColor(.gray)
                            Text("Bạn có thể nhập link kho truyện VBook (định dạng plugin.json) để bắt đầu tải các nguồn bóc tách truyện.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Button(action: {
                                addSampleRepository()
                            }) {
                                Text("Nhập kho tiện ích mặc định (buudvh)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
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

    internal func importExtensionFromZip(_ url: URL) {
        statusMessage = "Đang giải nén & import tiện ích từ file zip..."
        errorMessage = ""
        
        Task {
            do {
                let result = try await ExtensionManager.shared.installFromLocalZip(fileUrl: url)
                
                await MainActor.run {
                    let cmd = UpsertExtensionCommand(packageId: result.packageId, name: result.name, author: result.author, version: result.version, remoteVersion: result.version, sourceUrl: result.sourceUrl, iconUrl: result.iconUrl, desc: result.desc, type: result.type, locale: result.locale, localPath: result.mainFolderPath, downloadUrl: "", configJson: nil, repositoryUrl: nil)
                    let res = ExtensionTransactionCoordinator.shared.upsertExtension(command: cmd, in: modelContext)
                    switch res {
                    case .success:
                        statusMessage = "Đã import thành công tiện ích '\(result.name)' v\(result.version)!"
                    case .failure(let err):
                        errorMessage = "Lỗi lưu tiện ích import: \(err.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Lỗi import tệp zip: \(error.localizedDescription)"
                }
            }
        }
    }
    
    internal func addSampleRepository() {
        addNewRepository(name: "Kho mặc định (buudvh)", url: "https://raw.githubusercontent.com/buudvh/leech_story_ext/main/plugin.json")
    }
    
    internal func addNewRepository(name: String, url: String) {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else { return }
        
        if repositories.contains(where: { $0.url == trimmedUrl }) {
            statusMessage = "Kho tiện ích này đã được nhập trước đó!"
            return
        }
        
        isRefreshingAll = true
        statusMessage = "Đang tải dữ liệu kho..."
        
        Task {
            do {
                let items = try await ExtensionManager.shared.fetchRegistry(from: trimmedUrl)
                
                let repoName = name.isEmpty ? "Kho Tiện Ích Mới" : name
                let result = ExtensionTransactionCoordinator.shared.addRepository(url: trimmedUrl, name: repoName, in: modelContext)
                switch result {
                case .success:
                    let syncRes = await syncExtensions(for: trimmedUrl, with: items)
                    await MainActor.run {
                        switch syncRes {
                        case .success:
                            statusMessage = "Đã nhập thành công kho '\(repoName)' với \(items.count) nguồn truyện."
                        case .failure(let error):
                            errorMessage = "Lỗi đồng bộ tiện ích kho '\(repoName)': \(error.localizedDescription)"
                        }
                        isRefreshingAll = false
                    }
                case .failure(let error):
                    await MainActor.run {
                        statusMessage = "Lỗi khi lưu kho truyện: \(error.localizedDescription)"
                        isRefreshingAll = false
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Lỗi khi tải kho truyện: \(error.localizedDescription)"
                    isRefreshingAll = false
                }
            }
        }
    }
    
    internal func refreshAllRepositories() {
        guard !repositories.isEmpty else { return }
        isRefreshingAll = true
        statusMessage = "Đang cập nhật lại các kho..."
        
        Task {
            var updatedCount = 0
            for repo in repositories {
                do {
                    let items = try await ExtensionManager.shared.fetchRegistry(from: repo.url)
                    let syncRes = await syncExtensions(for: repo.url, with: items)
                    if case .failure(let err) = syncRes {
                        AppLogger.shared.log("⚠️ [RepoRefresh] Sync failed for repo \(repo.name): \(err.localizedDescription)")
                        continue
                    }
                    let touchRes = ExtensionTransactionCoordinator.shared.touchRepositoryLastUpdated(url: repo.url, in: modelContext)
                    switch touchRes {
                    case .success: updatedCount += 1
                    case .failure(let err): AppLogger.shared.log("⚠️ [RepoRefresh] Touch lastUpdated failed for repo \(repo.name): \(err.localizedDescription)")
                    }
                } catch {
                    AppLogger.shared.log("⚠️ [RepoRefresh] Fetch registry failed for repo \(repo.name): \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                statusMessage = "Đã cập nhật \(updatedCount) kho tiện ích."
                isRefreshingAll = false
            }
        }
    }
    
    /// Đồng bộ cả kho: chụp `localPath` hiện có trên MainActor, tải/parse `plugin.json` **song song
    /// ngoài main** qua `ExtensionSyncCommandBuilder`, rồi ghi **một transaction duy nhất**.
    ///
    /// Sau khi ghi xong mới dọn các tiện ích kho đã gỡ khỏi registry (`pruneRepositoryExtensions`) —
    /// đúng thứ tự này, vì tập giữ lại được suy ra từ chính danh sách command vừa ghi. Registry rỗng
    /// thoát sớm ở `guard` đầu hàm nên một lần fetch lỗi không bao giờ quét sạch kho.
    @MainActor
    @discardableResult
    internal func syncExtensions(for repoUrl: String, with items: [ExtensionRegistryItem]) async -> Result<Void, ExtensionTransactionError> {
        guard !items.isEmpty else { return .success(()) }
        let startedAt = Date()

        var localPaths: [String: String] = [:]
        for ext in allExtensions where !ext.localPath.isEmpty {
            localPaths[ext.packageId] = ext.localPath
        }
        let inputs = items.map { item in
            ExtensionSyncCommandBuilder.Input(
                item: item,
                existingLocalPath: localPaths[ExtensionSyncCommandBuilder.packageId(forName: item.name)] ?? ""
            )
        }

        let commands = await ExtensionSyncCommandBuilder.build(inputs: inputs, repositoryUrl: repoUrl)
        let result = ExtensionTransactionCoordinator.shared.upsertExtensions(commands: commands, in: modelContext)
        if case .success = result {
            let keep = Set(commands.map { $0.packageId })
            let pruneCmd = PruneRepositoryExtensionsCommand(repositoryUrl: repoUrl, keepPackageIds: keep)
            let pruneRes = ExtensionTransactionCoordinator.shared.pruneRepositoryExtensions(command: pruneCmd, in: modelContext)
            switch pruneRes {
            case .success(let removed) where removed > 0:
                AppLogger.shared.log("ℹ️ [ExtSync] Đã xoá \(removed) tiện ích kho \(repoUrl) đã gỡ khỏi registry (giữ tiện ích đã cài)")
            case .success:
                break
            case .failure(let err):
                AppLogger.shared.log("⚠️ [ExtSync] Dọn tiện ích đã gỡ của kho \(repoUrl) thất bại: \(err.localizedDescription)")
            }
        }
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(startedAt))
        AppLogger.shared.log("ℹ️ [ExtSync] Đồng bộ \(commands.count)/\(items.count) ext của kho \(repoUrl) trong \(elapsed)s")
        return result
    }
    


}
