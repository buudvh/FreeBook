import SwiftUI
import SwiftData

struct SearchNovelResultWithExt: Identifiable {
    let id = UUID()
    let result: SearchNovelResult
    let ext: Extension
}

struct SearchView: View {
    let activeExtensions: [Extension]
    let selectedExtension: Extension?
    
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchAllSources = false
    @State private var searchResults: [SearchNovelResultWithExt] = []
    @State private var searchStatusMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Thanh Tìm Kiếm
            HStack(spacing: 8) {
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
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                
                Button(action: performSearch) {
                    Text("Tìm")
                        .bold()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            
            Toggle(isOn: $searchAllSources) {
                Text("Tìm trên tất cả nguồn đã cài")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            .padding(.horizontal)
            .padding(.vertical, 6)
            
            Divider()
            
            if isSearching {
                ProgressView(searchAllSources ? "Đang tìm trên các nguồn..." : "Đang tìm trên nguồn hiện tại...")
                    .frame(maxHeight: .infinity)
            } else if !searchResults.isEmpty {
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
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Nhập từ khóa để tìm kiếm truyện")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle("Tìm Kiếm")
        .navigationBarTitleDisplayMode(.inline)
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
