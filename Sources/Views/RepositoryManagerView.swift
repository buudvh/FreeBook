import SwiftUI
import SwiftData

struct RepositoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Repository.name) private var repositories: [Repository]
    
    @State private var showingAddRepo = false
    @State private var isRefreshingAll = false
    @State private var statusMessage = ""
    
    var body: some View {
        NavigationStack {
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
                            
                            // Gợi ý kho mẫu
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
            .navigationTitle("Kho Tiện Ích")
            .toolbar {
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
            .sheet(isPresented: $showingAddRepo) {
                AddRepositoryView { name, url in
                    addNewRepository(name: name, url: url)
                }
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
        
        // Kiểm tra xem kho đã tồn tại chưa
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
                
                // Đồng bộ tiện ích trong kho mới
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
        // Lấy danh sách extension hiện tại thuộc kho này trong db
        let currentExts = repo.extensions
        
        for item in items {
            // Tạo packageId duy nhất từ tên
            let packageId = item.name.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let existingExt = currentExts.first(where: { $0.packageId == packageId }) {
                // Đã có, cập nhật metadata mới nếu có thay đổi
                existingExt.name = item.name
                existingExt.author = item.author ?? "Không rõ"
                existingExt.version = item.version ?? 1
                existingExt.sourceUrl = item.source ?? ""
                existingExt.iconUrl = item.icon
                existingExt.desc = item.description
                existingExt.type = item.type ?? "novel"
                existingExt.locale = item.locale ?? "vi_VN"
            } else {
                // Chưa có, thêm mới ở trạng thái chưa cài đặt (localPath = "")
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
                    localPath: "" // Trống nghĩa là chưa cài đặt
                )
                newExt.repository = repo
                modelContext.insert(newExt)
            }
        }
    }
    
    private func deleteRepository(offsets: IndexSet) {
        for index in offsets {
            let repo = repositories[index]
            // Xóa file cứng của các extension liên quan
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
