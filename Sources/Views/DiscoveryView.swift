import SwiftUI
import SwiftData

struct DiscoveryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allExtensions: [Extension]
    
    private var activeExtensions: [Extension] {
        allExtensions
            .filter { !$0.localPath.isEmpty && $0.isEnabled }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    
    // Hiển thị danh mục thể loại dạng sheet trượt
    @State private var showingGenresSheet = false
    @State private var errorMessage = ""
    
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
                    // 1. Hàng chọn nguồn truyện
                    HStack {
                        Text("Nguồn đọc:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Picker("Chọn Nguồn", selection: $selectedExtensionId) {
                            Text("-- Chọn Nguồn --").tag("")
                            ForEach(activeExtensions) { ext in
                                Text(ext.name).tag(ext.packageId)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground).opacity(0.5))
                    .onChange(of: selectedExtensionId) { _, newValue in
                        if !newValue.isEmpty {
                            loadDiscoveryData()
                        } else {
                            homeItems.removeAll()
                            genreItems.removeAll()
                            selectedCategory = nil
                            novels.removeAll()
                        }
                    }
                    
                    if isLoading {
                        ProgressView("Đang tải cấu trúc danh mục...")
                            .frame(maxHeight: .infinity)
                    } else if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.subheadline)
                            .padding()
                            .frame(maxHeight: .infinity)
                    } else {
                        // 2. Thanh Menu: Nút danh mục bên trái + Các tab của Home
                        HStack(spacing: 0) {
                            // Nút mở thể loại bên trái
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
                            
                            // Thanh cuộn ngang các mục Home
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
                        
                        // Tiêu đề danh mục đang hiển thị
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
                        
                        // 3. Danh sách truyện của danh mục được chọn
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
                                            bookId: "\(ext.name.lowercased())_\(novel.detailUrl)",
                                            extensionPackageId: ext.packageId,
                                            initialDetailUrl: novel.detailUrl,
                                            sourceName: ext.name
                                        )) {
                                            HStack(spacing: 12) {
                                                AsyncImage(url: URL(string: novel.coverUrl)) { image in
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
                                                    Text(novel.title)
                                                        .font(.subheadline)
                                                        .fontWeight(.bold)
                                                        .lineLimit(2)
                                                    
                                                    Text(novel.author)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                // Tải thêm truyện
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
            .onAppear {
                // Tự động chọn nguồn đầu tiên nếu có và chưa chọn
                if selectedExtensionId.isEmpty, let first = activeExtensions.first {
                    selectedExtensionId = first.packageId
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
                // 1. Tải danh mục Home
                let homeRes = try await ExtensionManager.shared.home(localPath: ext.localPath, downloadUrl: ext.downloadUrl, configJson: ext.configJson)
                
                // 2. Tải danh mục Thể loại
                let genreRes = try await ExtensionManager.shared.genre(localPath: ext.localPath, downloadUrl: ext.downloadUrl, configJson: ext.configJson)
                
                await MainActor.run {
                    self.homeItems = homeRes
                    self.genreItems = genreRes
                    self.isLoading = false
                    
                    // Chọn mục đầu tiên của trang chủ làm mặc định
                    if let firstHome = homeRes.first {
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
        novels.removeAll()
        canLoadMore = true
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
                let results = try await ExtensionManager.shared.executeCustomScript(
                    localPath: ext.localPath,
                    downloadUrl: ext.downloadUrl,
                    scriptFileName: cat.script,
                    input: cat.input,
                    page: page,
                    configJson: ext.configJson
                )
                
                await MainActor.run {
                    if page == 1 {
                        self.novels = results
                        self.isLoadingNovels = false
                    } else {
                        self.novels.append(contentsOf: results)
                        self.isLoadingMore = false
                    }
                    self.canLoadMore = results.count >= 10
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
}

#Preview {
    DiscoveryView()
}
