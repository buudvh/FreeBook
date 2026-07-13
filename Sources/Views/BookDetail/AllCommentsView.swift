import SwiftUI

struct AllCommentsView: View {
    let category: CategoryResult
    let localPath: String
    let downloadUrl: String
    let configJson: String
    
    @State private var comments: [SearchNovelResult] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage = ""
    @State private var currentPage = 1
    @State private var nextPageUrl: String? = nil
    @State private var retryCount = 0
    
    var body: some View {
        VStack {
            if isLoading && comments.isEmpty {
                ProgressView("Đang tải bình luận...")
                    .frame(maxHeight: .infinity)
            } else if !errorMessage.isEmpty && comments.isEmpty {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Thử lại") {
                        Task {
                            await loadComments(page: 1)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                    .foregroundColor(.secondary.opacity(0.6))
                                
                                Text(TranslateUtils.translateMeta(comment.name))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            
                            Text(TranslateUtils.translateMeta(comment.description.cleanHTML()))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .padding(.leading, 36)
                        }
                        .padding(.vertical, 4)
                        .onAppear {
                            // Infinite Scroll: Khi cuộn tới phần tử cuối cùng và có trang tiếp theo
                            if comment.id == comments.last?.id && nextPageUrl != nil {
                                Task {
                                    await loadMoreComments()
                                }
                            }
                        }
                    }
                    
                    if nextPageUrl != nil {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await loadComments(page: 1)
                }
            }
        }
        .navigationTitle(TranslateUtils.translateMeta(category.title))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadComments(page: 1)
        }
    }
    
    private func loadComments(page: Int) async {
        if page == 1 {
            await MainActor.run {
                isLoading = true
                errorMessage = ""
                retryCount = 0
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
                    self.comments = results
                } else {
                    self.comments.append(contentsOf: results)
                }
                self.nextPageUrl = nextPage
                self.currentPage = page
                self.isLoading = false
                self.isLoadingMore = false
                self.retryCount = 0 // Reset khi thành công
            }
        } catch {
            AppLogger.shared.log("❌ [AllCommentsView] loadComments error page \(page): \(error.localizedDescription)")
            await MainActor.run {
                if page == 1 {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                } else {
                    self.isLoadingMore = false
                    if self.retryCount < 3 {
                        self.retryCount += 1
                        AppLogger.shared.log("🔄 Tự động tải lại bình luận trang \(page) (Lần thử \(self.retryCount))...")
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000) // Đợi 2 giây
                            await self.loadComments(page: page)
                        }
                    }
                }
            }
        }
    }
    
    private func loadMoreComments() async {
        guard !isLoadingMore && nextPageUrl != nil else { return }
        await loadComments(page: currentPage + 1)
    }
}
