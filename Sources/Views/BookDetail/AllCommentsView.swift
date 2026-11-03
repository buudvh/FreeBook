import SwiftUI

struct AllCommentsView: View {
    let category: CategoryResult
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let isTranslationEnabled: Bool
    /// Host sách — ghép `category.input` tương đối thành URL dự phòng cho nút "Mở link lỗi".
    var host: String? = nil
    /// Tiện ích/nguồn của truyện — nguồn Legado thì cookie của trình duyệt "Mở link lỗi" được gộp vào kho của nguồn.
    var extensionPackageId: String? = nil
    
    @State private var comments: [ExtensionItemResult] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage = ""
    @State private var errorLink: SourceErrorLink? = nil
    @State private var openingErrorLink: SourceErrorLink? = nil
    @State private var currentPage = 1
    @State private var nextPageUrl: String? = nil
    @State private var retryCount = 0
    /// Trang kế lỗi hết lượt tự thử ⇒ chân danh sách hiện "Thử lại"; không tự nạp khi cuộn tới cho tới lúc bấm.
    @State private var loadMoreError: String? = nil
    /// Bị trình duyệt "Mở link lỗi" che lúc biến mất ⇒ `.task` lần hiện lại kế tiếp không tải chồng trước khi chép cookie
    /// (lượt thử lại của `.errorLinkBrowser` lo tải và cũng hạ cờ) — xem `ErrorLinkBrowserModifier`.
    @State private var skipsReappearLoad = false
    
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
                    if errorLink != nil {
                        ErrorLinkCaption(link: errorLink)
                            .padding(.horizontal)
                    }
                    HStack(spacing: 10) {
                        Button("Thử lại") {
                            Task {
                                await loadComments(page: 1)
                            }
                        }
                        .buttonStyle(.bordered)
                        ErrorLinkButton(link: errorLink, presenting: $openingErrorLink, style: .bordered)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(comments) { comment in
                        CommentRowView(
                            comment: comment,
                            avatarSize: 36,
                            localPath: localPath,
                            downloadUrl: downloadUrl,
                            configJson: configJson,
                            isTranslationEnabled: isTranslationEnabled,
                            host: host
                        )
                        // Mỗi bình luận một panel bo góc như kiểu Danh sách truyện, không vạch ngăn.
                        .bookListPanelRow()
                        .onAppear {
                            // Infinite Scroll: Khi cuộn tới phần tử cuối cùng và có trang tiếp theo
                            if comment.id == comments.last?.id && nextPageUrl != nil {
                                Task {
                                    await loadMoreComments()
                                }
                            }
                        }
                    }
                    
                    if let phase = footerPhase {
                        LoadMoreFooter(
                            phase: phase,
                            onAppear: { Task { await loadMoreComments() } },
                            onRetry: { Task { await retryLoadMoreComments() } }
                        )
                        .bookListPanelRowChrome()
                        .id(comments.count) // mỗi trang mới về là hàng chân mới ⇒ vòng xoay mới
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await loadComments(page: 1)
                }
            }
        }
        .backPageTitle((isTranslationEnabled && TranslateUtils.containsChinese(category.title)) ? TranslateUtils.translateMeta(category.title) : category.title)
        .task {
            if skipsReappearLoad {
                skipsReappearLoad = false
                return
            }
            await loadComments(page: 1)
        }
        .onDisappear {
            if openingErrorLink != nil { skipsReappearLoad = true }
        }
        .errorLinkBrowser(link: $openingErrorLink, packageId: extensionPackageId) {
            skipsReappearLoad = false
            Task { await loadComments(page: 1) }
        }
    }
    
    private func loadComments(page: Int) async {
        if page == 1 {
            await MainActor.run {
                isLoading = true
                errorMessage = ""
                errorLink = nil
                loadMoreError = nil
                retryCount = 0
            }
        } else {
            await MainActor.run {
                isLoadingMore = true
            }
        }
        
        do {
            let (results, nextPage) = try await SourceRuntime.shared.executeCustomScript(
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
                    self.errorLink = SourceErrorLink.resolve(from: error, fallback: category.input, host: host)
                    self.isLoading = false
                } else if self.retryCount < 3 {
                    // Giữ `isLoadingMore` trong lúc chờ: chân danh sách vẫn xoay, hàng cuối hiện lại không nạp chồng.
                    self.retryCount += 1
                    AppLogger.shared.log("🔄 Tự động tải lại bình luận trang \(page) (Lần thử \(self.retryCount))...")
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // Đợi 2 giây
                        await self.loadComments(page: page)
                    }
                } else {
                    self.isLoadingMore = false
                    self.loadMoreError = error.localizedDescription
                }
            }
        }
    }
    
    private func loadMoreComments() async {
        guard !isLoadingMore && nextPageUrl != nil && loadMoreError == nil else { return }
        await loadComments(page: currentPage + 1)
    }

    /// Nút "Thử lại" ở chân danh sách: xoá lỗi, tính lại lượt tự thử từ đầu.
    private func retryLoadMoreComments() async {
        loadMoreError = nil
        retryCount = 0
        await loadMoreComments()
    }

    /// Lỗi trang kế ⇒ "Thử lại"; còn trang ⇒ vòng xoay; hết trang ⇒ "Đã hết · N bình luận".
    private var footerPhase: LoadMoreFooter.Phase? {
        if let loadMoreError { return .failed(loadMoreError) }
        if nextPageUrl != nil { return .loading }
        return comments.isEmpty ? nil : .finished("\(comments.count) bình luận")
    }
}
