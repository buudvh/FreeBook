import SwiftUI
import SwiftData

struct RepositoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Repository.name) private var repositories: [Repository]
    @Query private var allExtensions: [Extension]
    
    // Quản lý Tab chính của view
    @State private var selectedTab = 0 // 0: Tất cả tiện ích, 1: Danh sách kho
    
    // Trạng thái cho Tab 0: Danh sách kho
    @State private var showingAddRepo = false
    @State private var isRefreshingAll = false
    @State private var statusMessage = ""
    
    // Trạng thái cho Tab 1: Cửa hàng tiện ích gộp
    @State private var selectedRepoId: String = "all" // "all" hoặc repository.url
    @State private var selectedAuthor: String = "all" // "all" hoặc tên tác giả
    @State private var storeSearchQuery: String = ""
    @State private var loadingStates: [String: Bool] = [:] // packageId: isDownloading
    @State private var errorMessage = ""
    @State private var selectedExtensionForConfig: Extension? = nil
    
    // Lọc danh sách tác giả động từ database
    private var allAuthors: [String] {
        let authors = allExtensions.map { $0.author }
        return Array(Set(authors)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    // Danh sách tiện ích sau khi lọc theo các tiêu chí và tìm kiếm
    private var filteredExtensions: [Extension] {
        var result = allExtensions
        
        // 1. Lọc theo Kho
        if selectedRepoId != "all" {
            result = result.filter { $0.repository?.url == selectedRepoId }
        }
        
        // 2. Lọc theo Tác giả
        if selectedAuthor != "all" {
            result = result.filter { $0.author == selectedAuthor }
        }
        
        // 3. Lọc theo Từ khóa tìm kiếm
        let trimmedQuery = storeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(trimmedQuery) ||
                $0.sourceUrl.localizedCaseInsensitiveContains(trimmedQuery) ||
                $0.desc?.localizedCaseInsensitiveContains(trimmedQuery) ?? false
            }
        }
        
        // 4. Sắp xếp: đã cài đặt lên đầu, tiếp đến A-Z
        return result.sorted { ext1, ext2 in
            let isInstalled1 = !ext1.localPath.isEmpty
            let isInstalled2 = !ext2.localPath.isEmpty
            
            if isInstalled1 != isInstalled2 {
                return isInstalled1 && !isInstalled2
            }
            
            return ext1.name.localizedCaseInsensitiveCompare(ext2.name) == .orderedAscending
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Tất cả tiện ích").tag(0)
                    Text("Danh sách kho").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.systemGroupedBackground))
                
                if selectedTab == 1 {
                    // TAB 1: QUẢN LÝ KHO TIỆN ÍCH (Danh sách kho)
                    List {
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
                                    NavigationLink(destination: ExtensionStoreView(repository: repo)) {
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
                                            
                                            Toggle("", isOn: Binding(
                                                get: { repo.isEnabled },
                                                set: { val in
                                                    repo.isEnabled = val
                                                    try? modelContext.save()
                                                }
                                            ))
                                            .labelsHidden()
                                        }
                                    }
                                }
                                .onDelete(perform: deleteRepository)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    // TAB 1: CỬA HÀNG TIỆN ÍCH GỘP (HIỂN THỊ HẾT & BỘ LỌC)
                    VStack(spacing: 8) {
                        // Thanh bộ lọc ngang
                        HStack(spacing: 12) {
                            // Lọc theo Kho
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Kho tiện ích")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Picker("Kho", selection: $selectedRepoId) {
                                    Text("Tất cả kho").tag("all")
                                    ForEach(repositories) { repo in
                                        Text(repo.name).tag(repo.url)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                            }
                            
                            Spacer()
                            
                            // Lọc theo Tác giả
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tác giả")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Picker("Tác giả", selection: $selectedAuthor) {
                                    Text("Tất cả tác giả").tag("all")
                                    ForEach(allAuthors, id: \.self) { author in
                                        Text(author).tag(author)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(Color(.systemBackground))
                        
                        // Thanh Tìm kiếm tiện ích
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
                        .padding(.horizontal)
                        
                        Divider()
                        
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }
                        
                        // Danh sách tiện ích gộp
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
                                HStack(alignment: .top, spacing: 12) {
                                    // Icon tiện ích
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
                                        Image(systemName: ext.type == "comic" ? "comicbook" : "book.closed")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 32, height: 32)
                                            .padding(6)
                                            .background(Color.secondary.opacity(0.2))
                                            .foregroundColor(.accentColor)
                                            .cornerRadius(8)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(ext.name)
                                                .font(.headline)
                                            Text("v\(ext.version)")
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.1))
                                                .foregroundColor(.blue)
                                                .cornerRadius(4)
                                        }
                                        
                                        Text(ext.sourceUrl)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                        
                                        HStack(spacing: 8) {
                                            if let repo = ext.repository {
                                                Text(repo.name)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 2)
                                                    .background(Color.gray.opacity(0.1))
                                                    .cornerRadius(4)
                                            }
                                            Text("Tác giả: \(ext.author)")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    
                                    // Nút hành động
                                    if loadingStates[ext.packageId] == true {
                                        ProgressView()
                                            .frame(width: 60)
                                    } else {
                                        if ext.localPath.isEmpty {
                                            Button(action: {
                                                installExtension(ext)
                                            }) {
                                                Text("Cài đặt")
                                                    .font(.subheadline)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(Color.accentColor)
                                                    .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            HStack(spacing: 8) {
                                                Text("Đã cài")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                                    .fontWeight(.semibold)
                                                
                                                Button(action: {
                                                    selectedExtensionForConfig = ext
                                                }) {
                                                    Image(systemName: "gearshape")
                                                        .foregroundColor(.blue)
                                                        .padding(6)
                                                        .background(Color.blue.opacity(0.1))
                                                        .cornerRadius(6)
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button(action: {
                                                    uninstallExtension(ext)
                                                }) {
                                                    Image(systemName: "trash")
                                                        .foregroundColor(.red)
                                                        .padding(6)
                                                        .background(Color.red.opacity(0.1))
                                                        .cornerRadius(6)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listStyle(.plain)
                        }
                    }
                    .background(Color(.systemGroupedBackground).opacity(0.3))
                }
            }
            .navigationTitle("Kho Tiện Ích")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTab == 1 {
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
            .sheet(isPresented: $showingAddRepo) {
                AddRepositoryView { name, url in
                    addNewRepository(name: name, url: url)
                }
            }
            .sheet(item: $selectedExtensionForConfig) { ext in
                ExtensionConfigView(ext: ext)
            }
            .onAppear {
                if repositories.isEmpty {
                    addSampleRepository()
                }
            }
        }
    }
    
    private func addSampleRepository() {
        addNewRepository(name: "Kho mặc định (buudvh)", url: "https://raw.githubusercontent.com/buudvh/leech_story_ext/main/plugin.json")
    }
    
    private func addNewRepository(name: String, url: String) {
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
                
                let newRepo = Repository(url: trimmedUrl, name: name.isEmpty ? "Kho Tiện Ích Mới" : name)
                modelContext.insert(newRepo)
                
                syncExtensions(for: newRepo, with: items)
                try? modelContext.save()
                
                await MainActor.run {
                    statusMessage = "Đã nhập thành công kho '\(newRepo.name)' với \(items.count) nguồn truyện."
                    isRefreshingAll = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Lỗi khi tải kho truyện: \(error.localizedDescription)"
                    isRefreshingAll = false
                }
            }
        }
    }
    
    private func refreshAllRepositories() {
        guard !repositories.isEmpty else { return }
        isRefreshingAll = true
        statusMessage = "Đang cập nhật lại các kho..."
        
        Task {
            var updatedCount = 0
            for repo in repositories {
                do {
                    let items = try await ExtensionManager.shared.fetchRegistry(from: repo.url)
                    syncExtensions(for: repo, with: items)
                    repo.lastUpdated = Date()
                    updatedCount += 1
                } catch {
                    print("Lỗi cập nhật kho \(repo.name): \(error.localizedDescription)")
                }
            }
            try? modelContext.save()
            
            await MainActor.run {
                statusMessage = "Đã cập nhật \(updatedCount) kho tiện ích."
                isRefreshingAll = false
            }
        }
    }
    
    private func syncExtensions(for repo: Repository, with items: [ExtensionRegistryItem]) {
        let currentExts = repo.extensions
        
        for item in items {
            let packageId = item.name.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let existingExt = currentExts.first(where: { $0.packageId == packageId }) {
                existingExt.name = item.name
                existingExt.author = item.author ?? "Không rõ"
                existingExt.version = item.version ?? 1
                existingExt.sourceUrl = item.source ?? ""
                existingExt.iconUrl = item.icon
                existingExt.desc = item.description
                existingExt.type = item.type ?? "novel"
                existingExt.locale = item.locale ?? "vi_VN"
                existingExt.downloadUrl = item.path
            } else {
                let newExt = Extension(
                    packageId: packageId,
                    name: item.name,
                    author: item.author ?? "Không rõ",
                    version: item.version ?? 1,
                    sourceUrl: item.source ?? "",
                    iconUrl: item.icon,
                    desc: item.description,
                    type: item.type ?? "novel",
                    locale: item.locale ?? "vi_VN",
                    localPath: "",
                    downloadUrl: item.path
                )
                newExt.repository = repo
                modelContext.insert(newExt)
            }
        }
    }
    
    private func deleteRepository(offsets: IndexSet) {
        for index in offsets {
            let repo = repositories[index]
            for ext in repo.extensions {
                if !ext.localPath.isEmpty {
                    ExtensionManager.shared.uninstall(localPath: ext.localPath)
                }
            }
            modelContext.delete(repo)
        }
        try? modelContext.save()
        statusMessage = "Đã xóa kho tiện ích."
    }
    
    private func installExtension(_ ext: Extension) {
        var downloadUrl = ext.downloadUrl
        if downloadUrl.isEmpty, let repo = ext.repository {
            if let repoUrl = URL(string: repo.url) {
                let baseRepoUrl = repoUrl.deletingLastPathComponent().absoluteString
                downloadUrl = "\(baseRepoUrl)extensions/\(ext.packageId)/plugin.zip"
            } else {
                downloadUrl = repo.url.replacingOccurrences(of: "plugin.json", with: "extensions/\(ext.packageId)/plugin.zip")
            }
        }
        
        let finalItem = ExtensionRegistryItem(
            name: ext.name,
            author: ext.author,
            path: downloadUrl,
            version: ext.version,
            source: ext.sourceUrl,
            icon: ext.iconUrl,
            description: ext.desc,
            type: ext.type,
            locale: ext.locale
        )
        
        loadingStates[ext.packageId] = true
        errorMessage = ""
        
        Task {
            do {
                let localFolder = try await ExtensionManager.shared.install(item: finalItem, packageId: ext.packageId)
                await MainActor.run {
                    ext.localPath = localFolder
                    try? modelContext.save()
                    loadingStates[ext.packageId] = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Lỗi cài đặt \(ext.name): \(error.localizedDescription)"
                    loadingStates[ext.packageId] = false
                }
            }
        }
    }
    
    private func uninstallExtension(_ ext: Extension) {
        guard !ext.localPath.isEmpty else { return }
        ExtensionManager.shared.uninstall(localPath: ext.localPath)
        ext.localPath = ""
        try? modelContext.save()
    }
}

// MARK: - AddRepositoryView Sheet
struct AddRepositoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    
    var onAdd: (String, String) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Thông tin kho mới")) {
                    TextField("Tên kho truyện (Tùy chọn)", text: $name)
                    TextField("Link plugin.json của kho truyện", text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.none)
                }
            }
            .navigationTitle("Nhập Kho Tiện Ích")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Nhập") {
                        onAdd(name, url)
                        dismiss()
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

