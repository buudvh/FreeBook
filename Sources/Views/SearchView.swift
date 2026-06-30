import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Extension> { ext in
        !ext.localPath.isEmpty && ext.isEnabled
    }) private var activeExtensions: [Extension]
    
    @State private var query = ""
    @State private var isSearching = false
    @State private var results: [SearchNovelResultWithExt] = []
    @State private var statusMessage = ""
    
    // Struct wrapper để biết kết quả từ extension nào
    struct SearchNovelResultWithExt: Identifiable {
        let id = UUID()
        let result: SearchNovelResult
        let ext: Extension
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Thanh tìm kiếm
                HStack {
                    TextField("Nhập tên truyện hoặc tác giả...", text: $query, onCommit: performSearch)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.none)
                    
                    Button(action: performSearch) {
                        Text("Tìm")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                if isSearching {
                    ProgressView("Đang tìm kiếm trên các nguồn...")
                        .padding()
                }
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }
                
                Group {
                    if results.isEmpty && !isSearching && !query.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "magnifyingglass.circle")
                                .resizable()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.secondary)
                            Text("Không tìm thấy kết quả")
                                .font(.headline)
                            Text("Hãy thử đổi từ khóa khác hoặc kiểm tra lại các tiện ích đã cài đặt.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            Spacer()
                        }
                    } else if activeExtensions.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "puzzlepiece.extension")
                                .resizable()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.secondary)
                            Text("Chưa cài tiện ích bóc tách truyện")
                                .font(.headline)
                            Text("Hãy đi tới phần Tiện Ích để cài đặt ít nhất một nguồn đọc truyện (Ví dụ: Truyenfull).")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            Spacer()
                        }
                    } else {
                        List(results) { item in
                            NavigationLink(destination: BookDetailView(
                                bookId: "\(item.ext.name.lowercased())_\(item.result.detailUrl)",
                                extensionPackageId: item.ext.packageId,
                                initialDetailUrl: item.result.detailUrl,
                                sourceName: item.ext.name
                            )) {
                                HStack(spacing: 12) {
                                    // Ảnh bìa
                                    AsyncImage(url: URL(string: item.result.coverUrl)) { image in
                                        image.resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color.gray.opacity(0.3)
                                            .overlay(Image(systemName: "book"))
                                    }
                                    .frame(width: 50, height: 70)
                                    .cornerRadius(6)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.result.title)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .lineLimit(2)
                                        
                                        Text(item.result.author)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        // Tag hiển thị nguồn
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
                    }
                }
            }
            .navigationTitle("Tìm Kiếm")
        }
    }
    
    private func performSearch() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        
        let extensionsToSearch = activeExtensions.filter { ext in
            // Lọc ra các ext của repo đang bật
            ext.repository?.isEnabled ?? true
        }
        
        guard !extensionsToSearch.isEmpty else {
            statusMessage = "Không có nguồn truyện nào đang hoạt động."
            return
        }
        
        isSearching = true
        results.removeAll()
        statusMessage = "Đang tìm trên \(extensionsToSearch.count) nguồn..."
        
        Task {
            // Chạy song song tìm kiếm trên tất cả các extension đang hoạt động
            await withTaskGroup(of: (Extension, [SearchNovelResult]?).self) { group in
                for ext in extensionsToSearch {
                    group.addTask {
                        do {
                            let extResults = try await ExtensionManager.shared.search(localPath: ext.localPath, query: trimmedQuery, page: 1, configJson: ext.configJson)
                            return (ext, extResults)
                        } catch {
                            print("Lỗi tìm kiếm trên \(ext.name): \(error.localizedDescription)")
                            return (ext, nil)
                        }
                    }
                }
                
                for await (ext, searchResults) in group {
                    if let searchResults = searchResults {
                        let wrapped = searchResults.map { SearchNovelResultWithExt(result: $0, ext: ext) }
                        await MainActor.run {
                            self.results.append(contentsOf: wrapped)
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.isSearching = false
                self.statusMessage = "Đã tìm thấy \(results.count) truyện."
            }
        }
    }
}

#Preview {
    SearchView()
}
