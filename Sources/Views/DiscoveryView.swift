import SwiftUI
import SwiftData

struct DiscoveryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Extension> { ext in
        !ext.localPath.isEmpty && ext.isEnabled
    }) private var activeExtensions: [Extension]
    
    @State private var selectedExtensionId: String = ""
    @State private var isLoading = false
    @State private var genres: [String: String] = [:]
    @State private var selectedGenre: String? = nil
    @State private var genreNovels: [SearchNovelResult] = []
    @State private var isLoadingNovels = false
    @State private var errorMessage = ""
    
    private var selectedExtension: Extension? {
        activeExtensions.first(where: { $0.packageId == selectedExtensionId })
    }
    
    var body: some View {
        NavigationStack {
            VStack {
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
                    // Picker chọn nguồn truyện
                    Picker("Chọn Nguồn", selection: $selectedExtensionId) {
                        Text("-- Chọn Nguồn --").tag("")
                        ForEach(activeExtensions) { ext in
                            Text(ext.name).tag(ext.packageId)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                    .onChange(of: selectedExtensionId) { _, newValue in
                        if !newValue.isEmpty {
                            loadGenres()
                        } else {
                            genres.removeAll()
                            selectedGenre = nil
                            genreNovels.removeAll()
                        }
                    }
                    
                    if isLoading {
                        ProgressView("Đang tải danh mục...")
                            .frame(maxHeight: .infinity)
                    } else if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.subheadline)
                            .padding()
                            .frame(maxHeight: .infinity)
                    } else if selectedGenre != nil {
                        // Hiển thị danh sách truyện của thể loại đang chọn
                        VStack(alignment: .leading) {
                            HStack {
                                Button(action: { selectedGenre = nil }) {
                                    HStack {
                                        Image(systemName: "chevron.left")
                                        Text("Quay lại danh mục")
                                    }
                                }
                                Spacer()
                                Text(selectedGenre ?? "")
                                    .fontWeight(.bold)
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                            
                            if isLoadingNovels {
                                ProgressView("Đang tải danh sách truyện...")
                                    .frame(maxHeight: .infinity)
                            } else {
                                List(genreNovels) { novel in
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
                            }
                        }
                    } else {
                        // Hiển thị Grid các thể loại
                        ScrollView {
                            if genres.isEmpty {
                                Text("Tiện ích này không hỗ trợ duyệt danh mục hoặc đang trống.")
                                    .foregroundColor(.gray)
                                    .padding(.top, 40)
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(Array(genres.keys).sorted(), id: \.self) { key in
                                        Button(action: {
                                            selectGenre(name: key)
                                        }) {
                                            Text(key)
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
                    }
                }
            }
            .navigationTitle("Khám Phá")
            .onAppear {
                // Tự động chọn nguồn đầu tiên nếu có và chưa chọn
                if selectedExtensionId.isEmpty, let first = activeExtensions.first {
                    selectedExtensionId = first.packageId
                    loadGenres()
                }
            }
        }
    }
    
    private func loadGenres() {
        guard let ext = selectedExtension else { return }
        isLoading = true
        errorMessage = ""
        selectedGenre = nil
        genreNovels.removeAll()
        
        Task {
            do {
                let result = try await ExtensionManager.shared.genre(localPath: ext.localPath, configJson: ext.configJson)
                await MainActor.run {
                    self.genres = result
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Không thể tải danh mục: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func selectGenre(name: String) {
        guard let ext = selectedExtension else { return }
        selectedGenre = name
        isLoadingNovels = true
        
        Task {
            do {
                // Trong VBook, duyệt thể loại chạy qua hàm search với từ khóa là link thể loại hoặc tên thể loại
                let query = genres[name] ?? name
                let result = try await ExtensionManager.shared.search(localPath: ext.localPath, query: query, page: 1, configJson: ext.configJson)
                
                await MainActor.run {
                    self.genreNovels = result
                    self.isLoadingNovels = false
                }
            } catch {
                print("Lỗi duyệt thể loại: \(error)")
                await MainActor.run {
                    self.isLoadingNovels = false
                }
            }
        }
    }
}

#Preview {
    DiscoveryView()
}
