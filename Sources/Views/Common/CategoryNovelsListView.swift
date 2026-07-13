import SwiftUI

struct CategoryNovelsListView: View {
    let category: CategoryResult
    let extensionPackageId: String
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let sourceName: String
    
    @State private var novels: [SearchNovelResult] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage = ""
    @State private var currentPage = 1
    @State private var nextPageUrl: String? = nil
    
    var body: some View {
        VStack {
            if isLoading && novels.isEmpty {
                ProgressView("Đang tải danh sách truyện...")
                    .frame(maxHeight: .infinity)
            } else if !errorMessage.isEmpty && novels.isEmpty {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Thử lại") {
                        Task {
                            await loadNovels(page: 1)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(novels) { novel in
                        NavigationLink(destination: BookDetailView(
                            bookId: novel.link,
                            extensionPackageId: extensionPackageId,
                            initialDetailUrl: novel.link,
                            sourceName: sourceName
                        )) {
                            HStack(alignment: .top, spacing: 12) {
                                BookCoverView(bookId: novel.link, coverUrl: novel.cover, width: 60, height: 80)
                                    .cornerRadius(6)
                                    .shadow(radius: 1)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(TranslateUtils.translateMeta(novel.name))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                    
                                    Text(TranslateUtils.translateAuthorHanViet(novel.author))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    
                                    if !novel.description.isEmpty {
                                        Text(TranslateUtils.translateMeta(novel.description.cleanHTML()))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // Phân trang
                    if nextPageUrl != nil || currentPage == 1 {
                        if isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else {
                            Button(action: {
                                Task {
                                    await loadMoreNovels()
                                }
                            }) {
                                HStack {
                                    Spacer()
                                    Text("Xem thêm truyện")
                                        .font(.subheadline)
                                        .foregroundColor(.accentColor)
                                    Spacer()
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await loadNovels(page: 1)
                }
            }
        }
        .navigationTitle(TranslateUtils.translateMeta(category.title))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadNovels(page: 1)
        }
    }
    
    private func loadNovels(page: Int) async {
        if page == 1 {
            await MainActor.run {
                isLoading = true
                errorMessage = ""
            }
        } else {
            await MainActor.run {
                isLoadingMore = true
            }
        }
        
        do {
            let (results, nextPage) = try await ExtensionManager.shared.executeCustomScript(
                localPath: localPath,
                downloadUrl: downloadUrl,
                scriptFileName: category.script,
                input: category.input,
                page: page,
                pageUrl: page == 1 ? nil : nextPageUrl,
                configJson: configJson
            )
            
            await MainActor.run {
                if page == 1 {
                    self.novels = results
                } else {
                    self.novels.append(contentsOf: results)
                }
                self.nextPageUrl = nextPage
                self.currentPage = page
                self.isLoading = false
                self.isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.isLoadingMore = false
            }
        }
    }
    
    private func loadMoreNovels() async {
        guard !isLoadingMore else { return }
        await loadNovels(page: currentPage + 1)
    }
}
