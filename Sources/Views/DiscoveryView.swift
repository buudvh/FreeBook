import SwiftUI
import SwiftData

struct SearchNovelResultWithExt: Identifiable {
    let id = UUID()
    let result: SearchNovelResult
    let ext: Extension
}

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
    @State private var errorMessage = ""
    
    // Sheet chọn nguồn "Phần mở rộng" nâng cao
    @State private var showingExtensionSelector = false
    @State private var extensionSearchQuery = ""
    
    // Tìm kiếm truyện
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchAllSources = false
    @State private var searchResults: [SearchNovelResultWithExt] = []
    @State private var searchStatusMessage = ""
    
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
                    // 1. Giao diện Chọn Nguồn Truyện "Phần mở rộng"
                    HStack {
                        Text("Nguồn đọc:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button(action: { showingExtensionSelector = true }) {
                            HStack(spacing: 4) {
                                if let ext = selectedExtension {
                                    Text(ext.name)
                                        .fontWeight(.bold)
                                } else {
                                    Text("Chọn Nguồn")
                                }
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground).opacity(0.5))
                    .onChange(of: selectedExtensionId) { _, newValue in
                        lastSelectedExtensionId = newValue
                        if !newValue.isEmpty {
                            loadDiscoveryData()
                        } else {
                            homeItems.removeAll()
                            genreItems.removeAll()
                            selectedCategory = nil
                            novels.removeAll()
                            searchResults.removeAll()
                            searchQuery = ""
                        }
                    }
                    
                    // 2. Thanh Tìm Kiếm Truyện Tích Hợp
                    VStack(spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Tìm truyện hoặc tác giả...", text: $searchQuery, onCommit: performSearch)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.none)
                                
                                if !searchQuery.isEmpty {
                                    Button(action: {
                                        searchQuery = ""
                                        searchResults.removeAll()
                                        searchStatusMessage = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                            
                            Button(action: performSearch) {
                                Text("Tìm")
                                    .bold()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        Toggle(isOn: $searchAllSources) {
                            Text("Tìm trên tất cả nguồn đã cài")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    
                    Divider()
                    
                    if isSearching {
                        ProgressView(searchAllSources ? "Đang tìm trên các nguồn..." : "Đang tìm trên nguồn hiện tại...")
                            .frame(maxHeight: .infinity)
                    } else if !searchResults.isEmpty {
                        // Hiển thị Kết quả tìm kiếm
                        VStack(alignment: .leading, spacing: 0) {
                            if !searchStatusMessage.isEmpty {
                                Text(searchStatusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemBackground))
                            }
                            
                            List(searchResults) { item in
                                NavigationLink(destination: BookDetailView(
                                    bookId: "\(item.ext.name.lowercased())_\(item.result.link)",
                                    extensionPackageId: item.ext.packageId,
                                    initialDetailUrl: item.result.link,
                                    sourceName: item.ext.name
                                )) {
                                    HStack(spacing: 12) {
                                        AsyncImage(url: URL(string: item.result.cover)) { image in
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
                                            Text(item.result.name)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .lineLimit(2)
                                            
                                            let descText = !item.result.description.isEmpty ? item.result.description : item.result.author
                                            Text(descText)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                            
                                            Text(item.ext.name)
                                                .font(.system(size: 9))
                                                .fontWeight(.semibold)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor.opacity(0.1))
                                                .foregroundColor(.accentColor)
                                                .cornerRadius(4)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .listStyle(.plain)
                        }
                    } else if isLoading {
                        ProgressView("Đang tải cấu trúc danh mục...")
                            .frame(maxHeight: .infinity)
                    } else if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.subheadline)
                            .padding()
                            .frame(maxHeight: .infinity)
                    } else {
                        // 3. Menu danh mục & Home tabs (Chỉ hiện khi không ở chế độ tìm kiếm)
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
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(homeItems) { item in
                                        let isSelected = selectedCategory?.id == item.id
                                        Button(action: { selectCategory(item) }) {
                                            Text(item.title)
                                                .font(.subheadline)
                                                .fontWeight(isSelected ? .bold : .regular)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.1))
                                                .foregroundColor(isSelected ? .white : .primary)
                                                .cornerRadius(20)
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                        .padding(.vertical, 10)
                        .background(Color(.systemBackground))
                        
                        Divider()
                        
                        if let cat = selectedCategory {
                            HStack {
                                Text(cat.title)
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
                                                    Text(novel.name)
                                                        .font(.subheadline)
                                                        .fontWeight(.bold)
                                                        .lineLimit(2)
                                                    
                                                    let descText = !novel.description.isEmpty ? novel.description : novel.author
                                                    Text(descText)
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
                                        if isLoadingMore {
                                            ProgressView()
                                        } else {
                                            Button(action: {
                                                currentPage += 1
                                                loadNovels(page: currentPage)
                                            }) {
                                                Text("Tải thêm truyện")
                                                    .font(.subheadline)
                                                    .foregroundColor(.accentColor)
                                                    .padding(.vertical, 8)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Khám Phá")
            .navigationBarTitleDisplayMode(.inline)
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
                                        Text(item.title)
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
            // Sheet chọn nguồn "Phần mở rộng" nâng cao
            .sheet(isPresented: $showingExtensionSelector) {
                ExtensionSelectorView(
                    activeExtensions: activeExtensions,
                    selectedExtensionId: $selectedExtensionId,
                    extensionSearchQuery: $extensionSearchQuery,
                    modelContext: modelContext
                )
            }
        }
    }
    
    private func loadDiscoveryData() {
        guard let ext = selectedExtension else { return }
        isLoading = true
        errorMessage = ""
        homeItems.removeAll()
        genreItems.removeAll()
        selectedCategory = nil
        novels.removeAll()
        
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
                    self.errorMessage = "Không thể tải cấu trúc khám phá: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
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
        
        // Khi chuyển sang danh mục, tự động tắt chế độ tìm kiếm cũ
        searchQuery = ""
        searchResults.removeAll()
        searchStatusMessage = ""
        
        loadNovels(page: 1)
    }
    
    private func loadNovels(page: Int) {
        guard let ext = selectedExtension, let cat = selectedCategory else { return }
        if page == 1 {
            isLoadingNovels = true
            errorMessage = ""
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
                }
            } catch {
                AppLogger.shared.log("❌ [DiscoveryView] loadNovels error: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoadingNovels = false
                    self.isLoadingMore = false
                    self.canLoadMore = false
                }
            }
        }
    }
    
    private func performSearch() {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        
        isSearching = true
        searchResults.removeAll()
        
        if searchAllSources {
            let extensionsToSearch = activeExtensions
            guard !extensionsToSearch.isEmpty else {
                isSearching = false
                searchStatusMessage = "Không có nguồn nào hoạt động."
                return
            }
            
            searchStatusMessage = "Đang tìm kiếm trên \(extensionsToSearch.count) nguồn..."
            
            Task {
                await withTaskGroup(of: (String, [SearchNovelResult]?).self) { group in
                    for ext in extensionsToSearch {
                        let path = ext.localPath
                        let packageId = ext.packageId
                        let configJson = ext.configJson
                        let downloadUrl = ext.downloadUrl
                        
                        group.addTask {
                            do {
                                let extResults = try await ExtensionManager.shared.search(
                                    localPath: path,
                                    downloadUrl: downloadUrl,
                                    query: trimmedQuery,
                                    page: 1,
                                    configJson: configJson
                                )
                                return (packageId, extResults)
                            } catch {
                                return (packageId, nil)
                            }
                        }
                    }
                    
                    for await (packageId, searchResults) in group {
                        if let searchResults = searchResults,
                           let ext = extensionsToSearch.first(where: { $0.packageId == packageId }) {
                            let wrapped = searchResults.map { SearchNovelResultWithExt(result: $0, ext: ext) }
                            await MainActor.run {
                                self.searchResults.append(contentsOf: wrapped)
                            }
                        }
                    }
                }
                
                await MainActor.run {
                    self.isSearching = false
                    self.searchStatusMessage = "Tìm thấy \(searchResults.count) truyện trên các nguồn."
                }
            }
        } else {
            guard let ext = selectedExtension else {
                isSearching = false
                searchStatusMessage = "Vui lòng chọn một nguồn trước."
                return
            }
            
            searchStatusMessage = "Đang tìm trên nguồn \(ext.name)..."
            
            Task {
                do {
                    let results = try await ExtensionManager.shared.search(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        query: trimmedQuery,
                        page: 1,
                        configJson: ext.configJson
                    )
                    await MainActor.run {
                        self.searchResults = results.map { SearchNovelResultWithExt(result: $0, ext: ext) }
                        self.isSearching = false
                        self.searchStatusMessage = "Tìm thấy \(results.count) truyện trên nguồn \(ext.name)."
                    }
                } catch {
                    AppLogger.shared.log("❌ Lỗi tìm kiếm trên \(ext.name): \(error.localizedDescription)")
                    await MainActor.run {
                        self.isSearching = false
                        self.searchStatusMessage = "Lỗi khi tìm kiếm: \(error.localizedDescription)"
                    }
                }
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
    
    @State private var configExtension: Extension? = nil
    
    private var filteredExtensions: [Extension] {
        if extensionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return activeExtensions
        } else {
            return activeExtensions.filter {
                $0.name.localizedCaseInsensitiveContains(extensionSearchQuery) ||
                $0.sourceUrl.localizedCaseInsensitiveContains(extensionSearchQuery)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Danh sách phần mở rộng
                List(filteredExtensions) { ext in
                    HStack(spacing: 12) {
                        // Icon đại diện nguồn
                        Image(systemName: "puzzlepiece.extension")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ext.name)
                                .font(.body)
                                .fontWeight(.semibold)
                            Text(ext.sourceUrl)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
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
        }
    }
    
    private func togglePin(_ ext: Extension) {
        ext.isPinned.toggle()
        try? modelContext.save()
    }
}
