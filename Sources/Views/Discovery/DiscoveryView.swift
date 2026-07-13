import SwiftUI
import SwiftData

struct DiscoveryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allExtensions: [Extension]
    
    // Nhớ Extension và Home tab cuối cùng đã xem
    @AppStorage("lastSelectedExtensionId") private var lastSelectedExtensionId: String = ""
    @AppStorage("lastSelectedCategoryId") private var lastSelectedCategoryId: String = ""
    
    private var activeExtensions: [Extension] {
        allExtensions
            .filter { !$0.localPath.isEmpty && $0.isEnabled }
            .sorted { ext1, ext2 in
                // Nguồn được ghim lên đầu, sau đó sắp xếp theo A-Z
                if ext1.isPinned != ext2.isPinned {
                    return ext1.isPinned && !ext2.isPinned
                }
                return ext1.name.localizedCaseInsensitiveCompare(ext2.name) == .orderedAscending
            }
    }
    
    @State private var selectedExtensionId: String = ""
    @State private var isLoading = false
    
    // Nguồn dữ liệu danh mục của tiện ích
    @State private var homeItems: [CategoryResult] = []
    @State private var genreItems: [CategoryResult] = []
    
    // Danh mục / Tab đang được chọn hiển thị
    @State private var selectedCategory: CategoryResult? = nil
    
    // Trạng thái truyện hiển thị
    @State private var novels: [SearchNovelResult] = []
    @State private var isLoadingNovels = false
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var canLoadMore = true
    @State private var nextNovelPageUrl: String? = nil
    
    // Hiển thị danh mục thể loại dạng sheet trượt
    @State private var showingGenresSheet = false
    @State private var novelsError = ""
    @State private var retryCount = 0
    
    // Sheet chọn nguồn "Phần mở rộng" nâng cao
    @State private var showingExtensionSelector = false
    @State private var extensionSearchQuery = ""
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    
    // Trình duyệt trang chủ extension
    @State private var showingHeaderWeb = false
    
    // Import từ trình duyệt
    @State private var importedBookId: String = ""
    @State private var importedExtensionPackageId: String = ""
    @State private var importedDetailUrl: String = ""
    @State private var importedSourceName: String = ""
    @State private var navigateToImportedBook = false
    
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
                        
                        Spacer()
                        
                        // Mở nhanh trang chủ tiện ích
                        if let ext = selectedExtension, !ext.sourceUrl.isEmpty {
                            Button(action: {
                                showingHeaderWeb = true
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
                        if !newValue.isEmpty {
                            loadDiscoveryData()
                        } else {
                            homeItems.removeAll()
                            genreItems.removeAll()
                            selectedCategory = nil
                            novels.removeAll()
                        }
                    }
                    
                    Divider()
                    
                    // 3. Menu danh mục & Home tabs luôn hiển thị
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
                                        let isSelected = selectedCategory?.id == item.id
                                        Button(action: { selectCategory(item) }) {
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
                            .onChange(of: selectedCategory?.id) { _, newValue in
                                if let id = newValue {
                                    withAnimation {
                                        proxy.scrollTo(id, anchor: .center)
                                    }
                                }
                            }
                            .onAppear {
                                if let id = selectedCategory?.id {
                                    DispatchQueue.main.async {
                                        withAnimation {
                                            proxy.scrollTo(id, anchor: .center)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    
                    Divider()
                    
                    VStack(spacing: 0) {
                        if isLoading && homeItems.isEmpty && genreItems.isEmpty {
                            // Chỉ hiển thị loading nhỏ của cấu trúc nếu lần đầu mở mà chưa có gì cả
                            ProgressView("Đang tải danh mục...")
                                .padding(.vertical, 40)
                        } else {
                            if let cat = selectedCategory {
                                HStack {
                                    Text(translateIfNeeded(cat.title))
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.accentColor)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemBackground).opacity(0.5))
                            }
                            
                            // Danh sách truyện của danh mục
                            if isLoadingNovels {
                                ProgressView("Đang tải danh sách truyện...")
                                    .frame(maxHeight: .infinity)
                            } else if !novelsError.isEmpty {
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
                                    if let ext = selectedExtension {
                                        NavigationLink(destination: BookDetailView(
                                            bookId: "\(ext.name.lowercased())_\(novel.link)",
                                            extensionPackageId: ext.packageId,
                                            initialDetailUrl: novel.link,
                                            sourceName: ext.name
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
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 80)
                                .onEnded { value in
                                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                    switchCategory(forward: value.translation.width < 0)
                                }
                        )
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
                    }
                }
                
                if !selectedExtensionId.isEmpty && homeItems.isEmpty {
                    loadDiscoveryData()
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
                                        selectCategory(item)
                                    }) {
                                        Text(translateIfNeeded(item.title))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
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
                        navigateToImportedBook = true
                    }
                )
            }
            .fullScreenCover(isPresented: $showingHeaderWeb) {
                if let ext = selectedExtension {
                    BypassWebView(
                        urlString: ext.sourceUrl,
                        localPath: ext.localPath,
                        onImport: { detailUrl, packageId, sourceName in
                            importedBookId = "\(sourceName.lowercased())_\(detailUrl)"
                            importedExtensionPackageId = packageId
                            importedDetailUrl = detailUrl
                            importedSourceName = sourceName
                            navigateToImportedBook = true
                        }
                    )
                }
            }
            .navigationDestination(isPresented: $navigateToImportedBook) {
                BookDetailView(
                    bookId: importedBookId,
                    extensionPackageId: importedExtensionPackageId,
                    initialDetailUrl: importedDetailUrl,
                    sourceName: importedSourceName
                )
            }
            .onChange(of: isTranslationEnabled) { _, _ in
                loadDiscoveryData()
            }
        }
    }
    
    private func loadDiscoveryData() {
        guard let ext = selectedExtension else { return }
        isLoading = true
        novelsError = ""
        
        Task {
            do {
                let homeRes = try await ExtensionManager.shared.home(localPath: ext.localPath, downloadUrl: ext.downloadUrl, configJson: ext.configJson)
                let genreRes = try await ExtensionManager.shared.genre(localPath: ext.localPath, downloadUrl: ext.downloadUrl, configJson: ext.configJson)
                
                await MainActor.run {
                    self.homeItems = homeRes
                    self.genreItems = genreRes
                    self.isLoading = false
                    
                    // Khôi phục Home tab cuối cùng
                    if !lastSelectedCategoryId.isEmpty,
                       let savedCat = homeRes.first(where: { $0.id == lastSelectedCategoryId }) {
                        selectCategory(savedCat)
                    } else if let firstHome = homeRes.first {
                        selectCategory(firstHome)
                    }
                }
            } catch {
                await MainActor.run {
                    self.novelsError = "Không thể tải cấu trúc khám phá: \(error.localizedDescription)"
                    self.isLoading = false
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

    private func selectCategory(_ category: CategoryResult) {
        selectedCategory = category
        currentPage = 1
        nextNovelPageUrl = nil
        novels.removeAll()
        canLoadMore = true
        
        // Khi chọn một danh mục, nếu nó thuộc homeItems (Home tab) thì lưu trạng thái
        if homeItems.contains(where: { $0.id == category.id }) {
            lastSelectedCategoryId = category.id
        }
        
        loadNovels(page: 1)
    }
    
    private var currentCategoryIndex: Int {
        guard let cat = selectedCategory else { return -1 }
        return homeItems.firstIndex(where: { $0.id == cat.id }) ?? -1
    }
    
    private func switchCategory(forward: Bool) {
        let idx = currentCategoryIndex
        guard idx >= 0 else { return }
        let newIdx = forward ? idx + 1 : idx - 1
        guard newIdx >= 0 && newIdx < homeItems.count else { return }
        withAnimation { selectCategory(homeItems[newIdx]) }
    }
    
    private func loadNovels(page: Int) {
        guard let ext = selectedExtension, let cat = selectedCategory else { return }
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
                    localPath: ext.localPath,
                    downloadUrl: ext.downloadUrl,
                    scriptFileName: cat.script,
                    input: cat.input,
                    page: page,
                    pageUrl: page == 1 ? nil : self.nextNovelPageUrl,
                    configJson: ext.configJson
                )
                
                await MainActor.run {
                    self.nextNovelPageUrl = nextPage
                    if page == 1 {
                        self.novels = results
                        self.isLoadingNovels = false
                    } else {
                        self.novels.append(contentsOf: results)
                        self.isLoadingMore = false
                    }
                    self.canLoadMore = results.count >= 10 && (nextPage != nil || cat.input.contains("{0}"))
                    self.retryCount = 0 // Reset khi thành công
                }
            } catch {
                AppLogger.shared.log("❌ [DiscoveryView] loadNovels error page \(page): \(error.localizedDescription)")
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
                                try? await Task.sleep(nanoseconds: 2_000_000_000) // Đợi 2 giây
                                self.loadNovels(page: page)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func reloadCurrentCategory() async {
        guard let ext = selectedExtension, let cat = selectedCategory else { return }
        currentPage = 1
        do {
            let (results, nextPage) = try await ExtensionManager.shared.executeCustomScript(
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                scriptFileName: cat.script,
                input: cat.input,
                page: 1,
                pageUrl: nil,
                configJson: ext.configJson
            )
            await MainActor.run {
                self.nextNovelPageUrl = nextPage
                self.novels = results
                self.canLoadMore = results.count >= 10 && (nextPage != nil || cat.input.contains("{0}"))
            }
        } catch {
            await MainActor.run {
                self.novelsError = error.localizedDescription
            }
        }
    }
}
// MARK: - Subviews

struct ExtensionSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    
    let activeExtensions: [Extension]
    @Binding var selectedExtensionId: String
    @Binding var extensionSearchQuery: String
    let modelContext: ModelContext
    var onImport: ((_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void)? = nil
    
    @State private var configExtension: Extension? = nil
    @State private var showingListWeb = false
    @State private var listWebUrl = ""
    @State private var listWebLocalPath = ""
    
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
                                listWebUrl = ext.sourceUrl
                                listWebLocalPath = ext.localPath
                                showingListWeb = true
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
                
                // Ô tìm kiếm tích hợp ở dưới cùng
                VStack(spacing: 0) {
                    Divider()
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
                }
                .background(Color(.systemBackground))
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
            .fullScreenCover(isPresented: $showingListWeb) {
                BypassWebView(
                    urlString: listWebUrl,
                    localPath: listWebLocalPath,
                    onImport: { detailUrl, packageId, sourceName in
                        showingListWeb = false
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

// MARK: - ExtensionIconView
struct ExtensionIconView: View {
    let localPath: String
    let iconUrl: String?
    let size: CGFloat
    
    var body: some View {
        if !localPath.isEmpty,
           let uiImage = UIImage(contentsOfFile: URL(fileURLWithPath: localPath).appendingPathComponent("icon.png").path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .cornerRadius(size * 0.18)
        } else if let iconUrl = iconUrl, let url = URL(string: iconUrl) {
            AsyncImage(url: url) { image in
                image.resizable()
            } placeholder: {
                fallbackIcon
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .cornerRadius(size * 0.18)
        } else {
            fallbackIcon
        }
    }
    
    private var fallbackIcon: some View {
        Image(systemName: "puzzlepiece.extension")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.7, height: size * 0.7)
            .padding(size * 0.15)
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
            .cornerRadius(size * 0.18)
    }
}
