import SwiftUI
import SwiftData

/// Struct định danh cho item-based fullScreenCover mở trình duyệt bypass
struct ExtensionBrowserTarget: Identifiable {
    let id = UUID()
    let urlString: String
}

struct DiscoveryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allExtensions: [Extension]
    
    // Nhớ Extension và Home tab cuối cùng đã xem
    @AppStorage("lastSelectedExtensionId") private var lastSelectedExtensionId: String = ""
    @AppStorage("lastSelectedCategoryId") private var lastSelectedCategoryId: String = ""
    
    private var activeExtensions: [Extension] {
        allExtensions
            .filter { !$0.localPath.isEmpty && $0.isEnabled && ($0.type == "novel" || $0.type == "chinese_novel") }
            .sorted { ext1, ext2 in
                // Nguồn được ghim lên đầu, sau đó sắp xếp theo A-Z
                if ext1.isPinned != ext2.isPinned {
                    return ext1.isPinned && !ext2.isPinned
                }
                return ext1.name.localizedCaseInsensitiveCompare(ext2.name) == .orderedAscending
            }
    }
    
    @State private var selectedExtensionId: String = ""
    @State private var isLoading = true
    
    // Nguồn dữ liệu danh mục của tiện ích
    @State private var homeItems: [CategoryResult] = []
    @State private var genreItems: [CategoryResult] = []
    
    // ID danh mục / Tab đang được chọn hiển thị
    @State private var selectedCategoryId: String = ""
    @State private var discoveryError: String = ""
    
    // Thể loại được chọn để điều hướng đẩy view chuyên biệt
    @State private var selectedGenre: CategoryResult? = nil
    @State private var navigateToGenre = false
    
    // Hiển thị danh mục thể loại dạng sheet trượt
    @State private var showingGenresSheet = false
    
    // Sheet chọn nguồn "Phần mở rộng" nâng cao
    @State private var showingExtensionSelector = false
    @State private var extensionSearchQuery = ""
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    
    // Import từ trình duyệt
    @State private var importedBookId: String = ""
    @State private var importedExtensionPackageId: String = ""
    @State private var importedDetailUrl: String = ""
    @State private var importedSourceName: String = ""
    @State private var importedHost: String = ""
    @State private var navigateToImportedBook = false
    
    // Trình duyệt trang chủ extension (item-based để khởi tạo đúng lúc, tránh URL rỗng)
    @State private var headerBrowserTarget: ExtensionBrowserTarget? = nil
    
    private var selectedExtension: Extension? {
        activeExtensions.first(where: { $0.packageId == selectedExtensionId })
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if activeExtensions.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "safari")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.secondary)
                        Text("Chưa có nguồn đọc truyện nào hoạt động")
                            .font(.headline)
                        Text("Hãy cài đặt và kích hoạt ít nhất một tiện ích trong kho để khám phá danh mục truyện.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Spacer()
                    }
                } else {
                    // 1. Custom Header Bar (Nguồn bên trái có icon & tên, Tìm kiếm bên phải)
                    HStack {
                        // Nút chọn nguồn tiện ích
                        Button(action: { showingExtensionSelector = true }) {
                            HStack(spacing: 6) {
                                if let ext = selectedExtension {
                                    ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: 24)
                                    Text(ext.name)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                } else {
                                    Image(systemName: "puzzlepiece.extension")
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                    Text("Chọn Nguồn")
                                }
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(18)
                        }
                        .layoutPriority(1) // Đảm bảo nút chọn nguồn được hiển thị trọn vẹn nhất có thể
                        
                        Spacer()
                        
                        // Mở nhanh trang chủ tiện ích
                        if let ext = selectedExtension, !ext.sourceUrl.isEmpty {
                            Button(action: {
                                headerBrowserTarget = ExtensionBrowserTarget(urlString: ext.sourceUrl)
                            }) {
                                Image(systemName: "safari")
                                    .font(.title3)
                                    .foregroundColor(.primary)
                                    .padding(10)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(Circle())
                            }
                        }
                        
                        // Toggle dịch
                        Button(action: {
                            isTranslationEnabled.toggle()
                        }) {
                            Image(systemName: isTranslationEnabled ? "character.bubble.fill" : "character.bubble")
                                .font(.title3)
                                .foregroundColor(.primary)
                                .padding(10)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                        
                        // Nút Tìm Kiếm chuyển sang SearchView
                        NavigationLink(destination: SearchView(
                            activeExtensions: activeExtensions,
                            selectedExtension: selectedExtension
                        )) {
                            Image(systemName: "magnifyingglass")
                                .font(.title3)
                                .foregroundColor(.primary)
                                .padding(10)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    .onChange(of: selectedExtensionId) { _, newValue in
                        lastSelectedExtensionId = newValue
                        // Xóa sạch dữ liệu cũ khi đổi extension để tránh rác hiển thị
                        homeItems.removeAll()
                        genreItems.removeAll()
                        selectedCategoryId = ""
                        discoveryError = ""
                        if !newValue.isEmpty {
                            loadDiscoveryData()
                        } else {
                            isLoading = false
                        }
                    }
                    
                    if isLoading && homeItems.isEmpty && genreItems.isEmpty && discoveryError.isEmpty {
                        // Hiển thị Skeleton UI toàn trang khám phá khi tải lần đầu
                        DiscoveryMainSkeletonView()
                    } else {
                        // 3. Menu danh mục & Home tabs hiển thị khi có dữ liệu
                        if !homeItems.isEmpty {
                            HStack(spacing: 0) {
                                Button(action: { showingGenresSheet = true }) {
                                    Image(systemName: "circle.grid.2x2.fill")
                                        .font(.title3)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(Color.accentColor.opacity(0.1))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(8)
                                }
                                .padding(.leading)
                                
                                ScrollViewReader { proxy in
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(homeItems) { item in
                                                let isSelected = selectedCategoryId == item.id
                                                Button(action: {
                                                    selectedCategoryId = item.id
                                                }) {
                                                    Text(translateIfNeeded(item.title))
                                                        .font(.subheadline)
                                                        .fontWeight(isSelected ? .bold : .regular)
                                                        .padding(.horizontal, 14)
                                                        .padding(.vertical, 8)
                                                        .background(isSelected ? Color.accentColor : Color.gray.opacity(0.1))
                                                        .foregroundColor(isSelected ? .white : .primary)
                                                        .cornerRadius(20)
                                                }
                                                .id(item.id)
                                            }
                                        }
                                        .padding(.horizontal, 8)
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
                            }
                            .padding(.vertical, 10)
                            .background(Color(.systemBackground))
                            
                            Divider()
                        }
                        
                        VStack(spacing: 0) {
                            if !discoveryError.isEmpty {
                                // Hiển thị thông báo thiếu home và genres ở khám phá
                                VStack(spacing: 16) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(.orange)
                                    Text(discoveryError)
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.vertical, 80)
                            } else if homeItems.isEmpty && !genreItems.isEmpty {
                                // Chỉ có genres, gợi ý người dùng bấm nút thể loại
                                VStack(spacing: 16) {
                                    Image(systemName: "circle.grid.2x2")
                                        .font(.system(size: 48))
                                        .foregroundColor(.accentColor)
                                    Text("Nguồn truyện này chỉ hỗ trợ xem theo Thể loại.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Button(action: { showingGenresSheet = true }) {
                                        Text("Mở danh sách Thể loại")
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .background(Color.accentColor)
                                            .foregroundColor(.white)
                                            .cornerRadius(20)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.vertical, 80)
                            } else {
                                // TabView vuốt ngang trang gốc
                                TabView(selection: $selectedCategoryId) {
                                    ForEach(homeItems) { item in
                                        if let ext = selectedExtension {
                                            DiscoveryCategoryTabView(
                                                category: item,
                                                extensionPackageId: ext.packageId,
                                                localPath: ext.localPath,
                                                downloadUrl: ext.downloadUrl,
                                                configJson: ext.configJson,
                                                sourceName: ext.name,
                                                isTranslationEnabled: isTranslationEnabled,
                                                selectedCategoryId: $selectedCategoryId
                                            )
                                            .tag(item.id)
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
            .onAppear {
                // Tự động khôi phục nguồn cuối cùng đã xem
                if selectedExtensionId.isEmpty {
                    if !lastSelectedExtensionId.isEmpty && activeExtensions.contains(where: { $0.packageId == lastSelectedExtensionId }) {
                        selectedExtensionId = lastSelectedExtensionId
                    } else if let first = activeExtensions.first {
                        selectedExtensionId = first.packageId
                    } else {
                        // Không có extension hoạt động, tắt loading
                        isLoading = false
                    }
                }
                
                if !selectedExtensionId.isEmpty && homeItems.isEmpty && genreItems.isEmpty && discoveryError.isEmpty {
                    loadDiscoveryData()
                } else if selectedExtensionId.isEmpty {
                    isLoading = false
                }
            }
            // Sheet hiển thị danh sách thể loại đầy đủ (Genres)
            .sheet(isPresented: $showingGenresSheet) {
                NavigationStack {
                    ScrollView {
                        if genreItems.isEmpty {
                            Text("Nguồn truyện này không có danh sách thể loại cụ thể.")
                                .foregroundColor(.gray)
                                .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(genreItems) { item in
                                    Button(action: {
                                        showingGenresSheet = false
                                        if homeItems.contains(where: { $0.id == item.id }) {
                                            selectedCategoryId = item.id
                                        } else {
                                            selectedGenre = item
                                            navigateToGenre = true
                                        }
                                    }) {
                                        Text(translateIfNeeded(item.title))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .padding(.horizontal, 4)
                                            .frame(height: 50) // Chiều cao cố định đảm bảo bằng nhau tuyệt đối
                                            .background(Color.accentColor.opacity(0.1))
                                            .foregroundColor(.accentColor)
                                            .cornerRadius(10)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                    .navigationTitle("Thể loại")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Đóng") {
                                showingGenresSheet = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingExtensionSelector) {
                ExtensionSelectorView(
                    activeExtensions: activeExtensions,
                    selectedExtensionId: $selectedExtensionId,
                    extensionSearchQuery: $extensionSearchQuery,
                    modelContext: modelContext,
                    onImport: { detailUrl, packageId, sourceName in
                        importedBookId = "\(sourceName.lowercased())_\(detailUrl)"
                        importedExtensionPackageId = packageId
                        importedDetailUrl = detailUrl
                        importedSourceName = sourceName
                        if let url = URL(string: detailUrl), let scheme = url.scheme, let host = url.host {
                            importedHost = "\(scheme)://\(host)"
                        } else {
                            importedHost = ""
                        }
                        navigateToImportedBook = true
                    }
                )
            }
            .fullScreenCover(item: $headerBrowserTarget) { target in
                BypassWebView(
                    urlString: target.urlString,
                    onImport: { detailUrl, packageId, sourceName in
                        importedBookId = "\(sourceName.lowercased())_\(detailUrl)"
                        importedExtensionPackageId = packageId
                        importedDetailUrl = detailUrl
                        importedSourceName = sourceName
                        if let url = URL(string: detailUrl), let scheme = url.scheme, let host = url.host {
                            importedHost = "\(scheme)://\(host)"
                        } else {
                            importedHost = ""
                        }
                        navigateToImportedBook = true
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
            .onChange(of: isTranslationEnabled) { _, _ in
                loadDiscoveryData()
            }
        }
    }
    
    private func loadDiscoveryData() {
        guard let ext = selectedExtension else { return }
        isLoading = true
        discoveryError = ""
        
        Task {
            var loadedHome: [CategoryResult] = []
            var loadedGenre: [CategoryResult] = []
            
            // Tải Home song song độc lập
            do {
                loadedHome = try await ExtensionManager.shared.home(localPath: ext.localPath, downloadUrl: ext.downloadUrl, configJson: ext.configJson)
            } catch {
                #if DEBUG
                AppLogger.shared.log("⚠️ [DiscoveryView] Không có hoặc lỗi chạy script home: \(error.localizedDescription)")
                #endif
            }
            
            // Tải Genre song song độc lập
            do {
                loadedGenre = try await ExtensionManager.shared.genre(localPath: ext.localPath, downloadUrl: ext.downloadUrl, configJson: ext.configJson)
            } catch {
                #if DEBUG
                AppLogger.shared.log("⚠️ [DiscoveryView] Không có hoặc lỗi chạy script genre: \(error.localizedDescription)")
                #endif
            }
            
            await MainActor.run {
                self.homeItems = loadedHome
                self.genreItems = loadedGenre
                self.isLoading = false
                
                let hasHome = !loadedHome.isEmpty
                let hasGenre = !loadedGenre.isEmpty
                
                if !hasHome && !hasGenre {
                    // Nếu không có cả hai: Báo lỗi thiếu home và genres
                    self.discoveryError = "Extension thiếu home và genres"
                } else {
                    self.discoveryError = ""
                }
                
                if hasHome {
                    // Khôi phục hoặc chọn Home tab đầu tiên nếu có
                    if !lastSelectedCategoryId.isEmpty,
                       let savedCat = loadedHome.first(where: { $0.id == lastSelectedCategoryId }) {
                        selectedCategoryId = savedCat.id
                    } else if let firstHome = loadedHome.first {
                        selectedCategoryId = firstHome.id
                    }
                } else {
                    // Không có home thì không tự chọn mục home
                    selectedCategoryId = ""
                }
            }
        }
    }
    
    private func translateIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text)
    }
}

// MARK: - Subviews

struct DiscoveryCategoryTabView: View {
    let category: CategoryResult
    let extensionPackageId: String
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let sourceName: String
    let isTranslationEnabled: Bool
    @Binding var selectedCategoryId: String
    
    @State private var novels: [SearchNovelResult] = []
    @State private var isLoadingNovels = false
    @State private var novelsError = ""
    @State private var currentPage = 1
    @State private var canLoadMore = false
    @State private var isLoadingMore = false
    @State private var nextNovelPageUrl: String? = nil
    @State private var retryCount = 0
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoadingNovels && novels.isEmpty {
                DiscoverySkeletonListView()
                    .frame(maxHeight: .infinity)
            } else if !novelsError.isEmpty && novels.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Text(novelsError)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Thử lại") {
                        loadNovels(page: 1)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else if novels.isEmpty {
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
                List {
                    ForEach(novels) { novel in
                        NavigationLink(destination: BookDetailView(
                            bookId: "\(sourceName.lowercased())_\(novel.link)",
                            extensionPackageId: extensionPackageId,
                            initialDetailUrl: novel.link,
                            sourceName: sourceName,
                            initialHost: novel.host
                        )) {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: novel.cover)) { image in
                                    image.resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                        .overlay(Image(systemName: "book"))
                                }
                                .frame(width: 50, height: 70)
                                .cornerRadius(6)
                                .clipped()
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(translateIfNeeded(novel.name))
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .lineLimit(2)
                                    
                                    let descText = !novel.description.isEmpty ? novel.description : novel.author
                                    Text(translateIfNeeded(descText))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    
                    if canLoadMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .onAppear {
                                    if !isLoadingMore && !isLoadingNovels {
                                        currentPage += 1
                                        loadNovels(page: currentPage)
                                    }
                                }
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await reloadCurrentCategory()
                }
            }
        }
        .onAppear {
            checkAndLoadData()
        }
        .onChange(of: selectedCategoryId) { _, _ in
            checkAndLoadData()
        }
        .onChange(of: isTranslationEnabled) { _, _ in
            // Xóa data cũ và reload để tên truyện được dịch / bỏ dịch đúng
            guard selectedCategoryId == category.id else { return }
            novels = []
            novelsError = ""
            currentPage = 1
            nextNovelPageUrl = nil
            canLoadMore = false
            loadNovels(page: 1)
        }
    }
    
    private func checkAndLoadData() {
        // Chỉ nạp dữ liệu khi tab này thực sự là tab được chọn VÀ chưa có dữ liệu
        guard selectedCategoryId == category.id else { return }
        guard novels.isEmpty && !isLoadingNovels && novelsError.isEmpty else { return }
        loadNovels(page: 1)
    }
    
    private func translateIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text)
    }
    
    private func loadNovels(page: Int) {
        if page == 1 {
            isLoadingNovels = true
            novelsError = ""
            retryCount = 0
        } else {
            isLoadingMore = true
        }
        
        Task {
            do {
                let (results, nextPage) = try await ExtensionManager.shared.executeCustomScript(
                    localPath: localPath,
                    downloadUrl: downloadUrl,
                    scriptFileName: category.script,
                    input: category.input,
                    page: page,
                    pageUrl: page == 1 ? nil : self.nextNovelPageUrl,
                    configJson: configJson
                )
                
                await MainActor.run {
                    self.nextNovelPageUrl = nextPage
                    
                    // Lọc novel rỗng (name hoặc link trống) và trùng link (chuẩn hóa link)
                    let filtered = results.filter { !$0.name.isEmpty && !$0.link.isEmpty }
                    let unique = filtered.reduce(into: [SearchNovelResult]()) { acc, item in
                        if !acc.contains(where: { normalizeLink($0.link) == normalizeLink(item.link) }) {
                            acc.append(item)
                        }
                    }
                    
                    if page == 1 {
                        self.novels = unique
                        self.isLoadingNovels = false
                    } else {
                        // Load more: chỉ append cái chưa có trong danh sách hiện tại
                        let newUnique = unique.filter { item in
                            !self.novels.contains(where: { normalizeLink($0.link) == normalizeLink(item.link) })
                        }
                        self.novels.append(contentsOf: newUnique)
                        self.isLoadingMore = false
                    }
                    self.canLoadMore = results.count >= 10 && (nextPage != nil || category.input.contains("{0}"))
                    self.retryCount = 0
                }
            } catch {
                AppLogger.shared.log("❌ [DiscoveryCategoryTabView] loadNovels error page \(page): \(error.localizedDescription)")
                await MainActor.run {
                    if page == 1 {
                        self.novelsError = error.localizedDescription
                        self.isLoadingNovels = false
                        self.canLoadMore = false
                    } else {
                        self.isLoadingMore = false
                        if self.retryCount < 3 {
                            self.retryCount += 1
                            AppLogger.shared.log("🔄 Tự động tải lại trang \(page) (Lần thử \(self.retryCount))...")
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                self.loadNovels(page: page)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func reloadCurrentCategory() async {
        do {
            let (results, nextPage) = try await ExtensionManager.shared.executeCustomScript(
                localPath: localPath,
                downloadUrl: downloadUrl,
                scriptFileName: category.script,
                input: category.input,
                page: 1,
                pageUrl: nil,
                configJson: configJson
            )
            await MainActor.run {
                self.nextNovelPageUrl = nextPage
                self.novels = results
                self.canLoadMore = results.count >= 10 && (nextPage != nil || category.input.contains("{0}"))
            }
        } catch {
            await MainActor.run {
                self.novelsError = error.localizedDescription
            }
        }
    }
}

struct ExtensionSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    
    let activeExtensions: [Extension]
    @Binding var selectedExtensionId: String
    @Binding var extensionSearchQuery: String
    let modelContext: ModelContext
    var onImport: ((_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void)? = nil
    
    @State private var configExtension: Extension? = nil
    @State private var listBrowserTarget: ExtensionBrowserTarget? = nil
    
    private var filteredExtensions: [Extension] {
        let baseList: [Extension]
        if extensionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseList = activeExtensions
        } else {
            baseList = activeExtensions.filter {
                $0.name.localizedCaseInsensitiveContains(extensionSearchQuery) ||
                $0.sourceUrl.localizedCaseInsensitiveContains(extensionSearchQuery)
            }
        }
        
        // Đưa phần mở rộng đang chọn lên đầu danh sách
        return baseList.sorted { ext1, ext2 in
            let isSel1 = ext1.packageId == selectedExtensionId
            let isSel2 = ext2.packageId == selectedExtensionId
            if isSel1 != isSel2 {
                return isSel1
            }
            if ext1.isPinned != ext2.isPinned {
                return ext1.isPinned && !ext2.isPinned
            }
            return ext1.name.localizedCaseInsensitiveCompare(ext2.name) == .orderedAscending
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Ô tìm kiếm tích hợp di chuyển lên trên cùng của danh sách để dễ sử dụng
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Tìm kiếm phần mở rộng", text: $extensionSearchQuery)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.none)
                    
                    if !extensionSearchQuery.isEmpty {
                        Button(action: { extensionSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding()
                
                Divider()
                
                // Danh sách phần mở rộng
                List(filteredExtensions) { ext in
                    let isSelected = ext.packageId == selectedExtensionId
                    HStack(spacing: 12) {
                        // Icon đại diện nguồn
                        ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: 36)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ext.name)
                                .font(.body)
                                .fontWeight(isSelected ? .bold : .semibold)
                                .lineLimit(1) // Tránh tên tiện ích rớt dòng, tự động thu gọn bằng dấu ba chấm (...)
                            Text(ext.sourceUrl)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                                .padding(.trailing, 4)
                        }
                        
                        // Nút Trình duyệt trang chủ
                        if !ext.sourceUrl.isEmpty {
                            Button(action: {
                                listBrowserTarget = ExtensionBrowserTarget(urlString: ext.sourceUrl)
                            }) {
                                Image(systemName: "safari")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Nút cấu hình (Bánh răng)
                        Button(action: {
                            configExtension = ext
                        }) {
                            Image(systemName: "gearshape")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                        
                        // Nút Ghim (Pin)
                        Button(action: {
                            togglePin(ext)
                        }) {
                            Image(systemName: ext.isPinned ? "pin.fill" : "pin")
                                .font(.body)
                                .foregroundColor(ext.isPinned ? .accentColor : .secondary)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedExtensionId = ext.packageId
                        dismiss()
                    }
                    .listRowBackground(isSelected ? Color.accentColor.opacity(0.08) : Color(.systemBackground))
                }
                .listStyle(.plain)
            }
            .navigationTitle("Phần mở rộng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(item: $configExtension) { ext in
                ExtensionConfigView(ext: ext)
            }
            .fullScreenCover(item: $listBrowserTarget) { target in
                BypassWebView(
                    urlString: target.urlString,
                    onImport: { detailUrl, packageId, sourceName in
                        listBrowserTarget = nil
                        dismiss()
                        onImport?(detailUrl, packageId, sourceName)
                    }
                )
            }
        }
    }
    
    private func togglePin(_ ext: Extension) {
        ext.isPinned.toggle()
        try? modelContext.save()
    }
}

// MARK: - Skeleton UI Components

struct DiscoverySkeletonListView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(0..<8) { _ in
                    HStack(spacing: 12) {
                        SkeletonView(width: 50, height: 70)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonView(width: 160, height: 16)
                            SkeletonView(width: nil, height: 12)
                            SkeletonView(width: 100, height: 12)
                        }
                    }
                    .padding(.horizontal)
                    Divider()
                        .padding(.leading, 74)
                }
            }
            .padding(.top, 10)
        }
    }
}

struct DiscoveryMainSkeletonView: View {
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
            DiscoverySkeletonListView()
        }
    }
}

fileprivate func normalizeLink(_ link: String) -> String {
    var clean = link.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.hasPrefix("http://") || clean.hasPrefix("https://") {
        if let range = clean.range(of: "://") {
            let afterScheme = clean[range.upperBound...]
            if let slashIndex = afterScheme.firstIndex(of: "/") {
                clean = String(afterScheme[slashIndex...])
            } else {
                clean = "/"
            }
        }
    }
    if !clean.hasPrefix("/") {
        clean = "/" + clean
    }
    return clean
}
