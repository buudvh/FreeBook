import SwiftUI
import SwiftData

struct RepositoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Repository.name) private var repositories: [Repository]
    @Query private var allExtensions: [Extension]
    
    // Quản lý Tab chính của view
    @State private var selectedTab = 0 // 0: Tất cả tiện ích, 1: Danh sách kho
    @State private var renderedTab = 0
    
    // Trạng thái cho Tab 1: Cửa hàng tiện ích gộp
    @State private var showingAddRepo = false
    @State private var isRefreshingAll = false
    @State private var statusMessage = ""
    @State private var storeSearchQuery: String = ""
    @ObservedObject private var extensionManager = ExtensionManager.shared
    @State private var errorMessage = ""
    @State private var selectedExtensionForConfig: Extension? = nil
    
    // Bộ lọc và Trạng thái Sheet/Alert mới
    @State private var showingFilterSheet = false
    @State private var showingUninstallAllAlert = false
    @AppStorage("extFilterType") private var filterType: String = "all"
    @AppStorage("extFilterLocale") private var filterLocale: String = "all"
    @AppStorage("extFilterAuthor") private var filterAuthor: String = "all"
    
    // Lọc danh sách tác giả động từ database
    private var allAuthors: [String] {
        let authors = allExtensions.map { $0.author }
        return Array(Set(authors)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    // Lọc danh sách ngôn ngữ động từ database
    private var allLocales: [String] {
        let locales = allExtensions.map { $0.locale }
        return Array(Set(locales)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    // Lọc danh sách loại tiện ích động từ database (loại trừ comic)
    private var allTypes: [String] {
        let types = allExtensions.map { $0.type }.filter { $0 != "comic" }
        return Array(Set(types)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    // Danh sách tiện ích sau khi lọc theo các tiêu chí và tìm kiếm
    private var filteredExtensions: [Extension] {
        var result = allExtensions.filter { $0.type != "comic" } // Loại bỏ hoàn toàn comic
        
        // 1. Lọc theo Tác giả
        if filterAuthor != "all" {
            result = result.filter { $0.author == filterAuthor }
        }
        
        // 2. Lọc theo Loại tiện ích (Type Ext)
        if filterType != "all" {
            result = result.filter { $0.type == filterType }
        }
        
        // 3. Lọc theo Ngôn ngữ (Locale)
        if filterLocale != "all" {
            result = result.filter { $0.locale == filterLocale }
        }
        
        // 4. Lọc theo Từ khóa tìm kiếm
        let trimmedQuery = storeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(trimmedQuery) ||
                $0.sourceUrl.localizedCaseInsensitiveContains(trimmedQuery) ||
                $0.desc?.localizedCaseInsensitiveContains(trimmedQuery) ?? false
            }
        }
        
        // 5. Sắp xếp: đã cài đặt lên đầu, tiếp đến A-Z
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
                
                TabView(selection: $selectedTab) {
                    // TAB 0: CỬA HÀNG TIỆN ÍCH GỘP (HIỂN THỊ HẾT & BỘ LỌC)
                    VStack(spacing: 8) {
                        if renderedTab == 0 {
                            // Thanh hiển thị trạng thái bộ lọc
                            HStack {
                                Text("Đang hiển thị \(filteredExtensions.count) tiện ích")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if filterType != "all" || filterLocale != "all" || filterAuthor != "all" {
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
                            
                            // Thanh Tìm kiếm tiện ích + Nút Filter
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
                                
                                // Nút Filter bên cạnh ô tìm kiếm
                                Button(action: { showingFilterSheet = true }) {
                                    let isFiltering = filterType != "all" || filterLocale != "all" || filterAuthor != "all"
                                    Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                        .font(.title3)
                                        .foregroundColor(isFiltering ? .orange : .accentColor)
                                        .padding(8)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(10)
                                }
                            }
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
                                            Image(systemName: ext.type == "tts" ? "waveform" : "book.closed")
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
                                                Text("v\(ext.version)")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.blue.opacity(0.1))
                                                    .foregroundColor(.blue)
                                                    .cornerRadius(4)
                                                
                                                Text(getFlagEmoji(ext.locale))
                                                    .font(.subheadline)
                                            }
                                            
                                            // Badge Type, Tác giả
                                            HStack(spacing: 6) {
                                                // Badge Type
                                                Text(translateType(ext.type))
                                                    .font(.system(size: 9, weight: .semibold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(ext.type == "tts" ? Color.orange.opacity(0.12) : Color.purple.opacity(0.12))
                                                    .foregroundColor(ext.type == "tts" ? .orange : .purple)
                                                    .cornerRadius(4)
                                                
                                                // Badge Tác giả
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
                                        
                                        // Nút hành động
                                        if extensionManager.loadingStates[ext.packageId] == true {
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
                    }
                    .background(Color(.systemGroupedBackground).opacity(0.3))
                    .tag(0)
                    
                    // TAB 1: QUẢN LÝ KHO TIỆN ÍCH (Danh sách kho)
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
                                    .onDelete(perform: deleteRepository)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: selectedTab) { oldVal, newVal in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        renderedTab = newVal
                    }
                }
            }
            .navigationTitle("Kho Tiện Ích")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTab == 0 {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button(role: .destructive, action: { showingUninstallAllAlert = true }) {
                            Text("Xóa tất cả")
                                .foregroundColor(.red)
                        }
                        .disabled(allExtensions.filter { !$0.localPath.isEmpty }.isEmpty)
                    }
                }
                
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
            .alert("Xóa tất cả tiện ích?", isPresented: $showingUninstallAllAlert) {
                Button("Hủy", role: .cancel) { }
                Button("Xóa sạch", role: .destructive) {
                    uninstallAllExtensions()
                }
            } message: {
                Text("Hành động này sẽ gỡ cài đặt toàn bộ các tiện ích đã cài trong ứng dụng. Bạn có chắc chắn không?")
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
            .onAppear {
                renderedTab = selectedTab
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
                    // print("Lỗi cập nhật kho \(repo.name): \(error.localizedDescription)")
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
        
        extensionManager.loadingStates[ext.packageId] = true
        errorMessage = ""
        
        Task {
            do {
                let localFolder = try await ExtensionManager.shared.install(item: finalItem, packageId: ext.packageId)
                
                // Đọc file plugin.json nội bộ sau khi giải nén để cập nhật chính xác locale/type
                var localLocale = ext.locale
                var localType = ext.type
                var localVersion = ext.version
                var localAuthor = ext.author
                
                let localJsonUrl = URL(fileURLWithPath: localFolder).appendingPathComponent("plugin.json")
                if let jsonData = try? Data(contentsOf: localJsonUrl),
                   let localMeta = try? JSONDecoder().decode(ExtensionLocalMeta.self, from: jsonData) {
                    if let metaLocale = localMeta.locale, !metaLocale.isEmpty {
                        localLocale = metaLocale
                    }
                    if let metaType = localMeta.type, !metaType.isEmpty {
                        localType = metaType
                    }
                    if let metaVersion = localMeta.version {
                        localVersion = metaVersion
                    }
                    if let metaAuthor = localMeta.author, !metaAuthor.isEmpty {
                        localAuthor = metaAuthor
                    }
                }
                
                await MainActor.run {
                    ext.localPath = localFolder
                    ext.locale = localLocale
                    ext.type = localType
                    ext.version = localVersion
                    ext.author = localAuthor
                    try? modelContext.save()
                    extensionManager.loadingStates[ext.packageId] = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Lỗi cài đặt \(ext.name): \(error.localizedDescription)"
                    extensionManager.loadingStates[ext.packageId] = false
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
    
    private func uninstallAllExtensions() {
        let installed = allExtensions.filter { !$0.localPath.isEmpty }
        for ext in installed {
            ExtensionManager.shared.uninstall(localPath: ext.localPath)
            ext.localPath = ""
        }
        try? modelContext.save()
    }
    
    private func translateType(_ type: String) -> String {
        switch type {
        case "novel": return "Truyện chữ"
        case "chinese_novel": return "Truyện Trung"
        case "tts": return "Giọng đọc (TTS)"
        default: return type.capitalized
        }
    }
    
    private func getFlagEmoji(_ locale: String) -> String {
        let cleanLocale = locale.lowercased()
        if cleanLocale.contains("vi") {
            return "🇻🇳"
        } else if cleanLocale.contains("zh") || cleanLocale.contains("cn") {
            return "🇨🇳"
        } else if cleanLocale.contains("en") {
            return "🇺🇸"
        }
        return "🌐"
    }
}

// MARK: - Local Meta Decodable helper
private struct ExtensionLocalMeta: Codable {
    let name: String
    let version: Int?
    let author: String?
    let type: String?
    let locale: String?
}

// MARK: - FilterSheet
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let allAuthors: [String]
    let allLocales: [String]
    let allTypes: [String]
    
    @Binding var filterType: String
    @Binding var filterLocale: String
    @Binding var filterAuthor: String
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Loại tiện ích")) {
                    Picker("Loại", selection: $filterType) {
                        Text("Tất cả").tag("all")
                        ForEach(allTypes, id: \.self) { type in
                            Text(translateType(type)).tag(type)
                        }
                    }
                }
                
                Section(header: Text("Ngôn ngữ")) {
                    Picker("Ngôn ngữ", selection: $filterLocale) {
                        Text("Tất cả").tag("all")
                        ForEach(allLocales, id: \.self) { locale in
                            Text(translateLocale(locale)).tag(locale)
                        }
                    }
                }
                
                Section(header: Text("Tác giả")) {
                    Picker("Tác giả", selection: $filterAuthor) {
                        Text("Tất cả").tag("all")
                        ForEach(allAuthors, id: \.self) { author in
                            Text(author).tag(author)
                        }
                    }
                }
            }
            .navigationTitle("Bộ lọc tiện ích")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đặt lại") {
                        filterType = "all"
                        filterLocale = "all"
                        filterAuthor = "all"
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    private func translateType(_ type: String) -> String {
        switch type {
        case "novel": return "Truyện chữ (Novel)"
        case "chinese_novel": return "Truyện Trung Quốc (Chinese)"
        case "tts": return "Giọng đọc (TTS)"
        default: return type.capitalized
        }
    }
    
    private func translateLocale(_ locale: String) -> String {
        switch locale {
        case "vi_VN": return "Tiếng Việt"
        case "zh_CN": return "Tiếng Trung"
        case "en_US": return "Tiếng Anh"
        default: return locale
        }
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
