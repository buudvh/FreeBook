import SwiftUI

struct CommentSectionView: View {
    let category: CategoryResult
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let extensionPackageId: String
    let sourceName: String
    let isTranslationEnabled: Bool
    /// Host sách — ghép `category.input` tương đối thành URL dự phòng cho nút "Mở link lỗi".
    var host: String? = nil
    
    @State private var comments: [ExtensionItemResult] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var errorLink: SourceErrorLink? = nil
    @State private var openingErrorLink: SourceErrorLink? = nil
    @State private var nextPageUrl: String? = nil
    /// Bị trình duyệt "Mở link lỗi" che lúc biến mất ⇒ `.task` lần hiện lại kế tiếp không tải chồng trước khi chép cookie
    /// (lượt thử lại của `.errorLinkBrowser` lo tải và cũng hạ cờ) — xem `ErrorLinkBrowserModifier`.
    @State private var skipsReappearLoad = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 20)
                    Spacer()
                }
            } else if !errorMessage.isEmpty {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lỗi tải bình luận: \(errorMessage)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                        ErrorLinkCaption(link: errorLink)
                    }
                    Spacer()
                    ErrorLinkButton(link: errorLink, presenting: $openingErrorLink, style: .icon)
                    Button(action: {
                        Task {
                            await loadComments()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.05))
                .cornerRadius(8)
            } else if comments.isEmpty {
                Text("Chưa có bình luận nào")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            } else {
                let displayComments = Array(comments.prefix(3))
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(displayComments) { comment in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.secondary.opacity(0.6))
                                
                                let commentatorName = (isTranslationEnabled && TranslateUtils.containsChinese(comment.name)) ? TranslateUtils.translateMeta(comment.name) : comment.name
                                Text(commentatorName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if !comment.description.isEmpty {
                                    let cleanedDesc = comment.description.cleanHTML()
                                    let descText = (isTranslationEnabled && TranslateUtils.containsChinese(cleanedDesc)) ? TranslateUtils.translateMeta(cleanedDesc) : cleanedDesc
                                    Text(descText)
                                        .font(.caption2)
                                        .foregroundColor(.secondary.opacity(0.8))
                                }
                            }
                            
                            let rawCommentContent = !comment.content.isEmpty ? comment.content : comment.description
                            if !rawCommentContent.isEmpty {
                                let cleanedContent = rawCommentContent.cleanHTML()
                                let commentText = (isTranslationEnabled && TranslateUtils.containsChinese(cleanedContent)) ? TranslateUtils.translateMeta(cleanedContent) : cleanedContent
                                ExpandableTextView(
                                    text: commentText,
                                    lineLimit: 3,
                                    font: .footnote,
                                    foregroundColor: .secondary
                                )
                                .padding(.leading, 32)
                            }
                        }
                        
                        Divider()
                            .padding(.leading, 32)
                    }
                    
                    if comments.count > 3 || nextPageUrl != nil {
                        NavigationLink(destination: AllCommentsView(
                            category: category,
                            localPath: localPath,
                            downloadUrl: downloadUrl,
                            configJson: configJson,
                            isTranslationEnabled: isTranslationEnabled,
                            host: host,
                            extensionPackageId: extensionPackageId
                        )) {
                            HStack {
                                Spacer()
                                Text("Xem tất cả bình luận")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .task {
            if skipsReappearLoad {
                skipsReappearLoad = false
                return
            }
            await loadComments()
        }
        .onDisappear {
            if openingErrorLink != nil { skipsReappearLoad = true }
        }
        .errorLinkBrowser(link: $openingErrorLink, packageId: extensionPackageId) {
            skipsReappearLoad = false
            Task { await loadComments() }
        }
    }
    
    private func loadComments() async {
        await MainActor.run {
            isLoading = true
            errorMessage = ""
            errorLink = nil
        }
        
        do {
            let (results, nextPage) = try await SourceRuntime.shared.executeCustomScript(
                localPath: localPath,
                downloadUrl: downloadUrl,
                scriptFileName: category.script,
                input: category.input,
                page: 1,
                pageUrl: nil,
                configJson: configJson
            )
            
            await MainActor.run {
                self.comments = results
                self.nextPageUrl = nextPage
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.errorLink = SourceErrorLink.resolve(from: error, fallback: category.input, host: host)
                self.isLoading = false
            }
        }
    }
}
