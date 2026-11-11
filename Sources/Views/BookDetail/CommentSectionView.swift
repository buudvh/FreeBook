import SwiftUI

/// Thẻ bình luận của tab Chi tiết (`BookDetailSectionCard`): tối đa 3 bình luận (`CommentRowView`, trả lời thu gọn)
/// cách nhau bằng vạch, cuối thẻ là nút "Xem tất cả bình luận" (`AllCommentsView`) khi còn nhiều hơn.
struct CommentSectionView: View {
    /// Tiêu đề thẻ (đã dịch nếu cần) — `BookDetailView` truyền `translateMetaIfNeeded(category.title)`.
    let title: String
    let category: CategoryResult
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let extensionPackageId: String
    let sourceName: String
    /// Phồn → giản + QT theo truyện đang mở, hoặc tiện ích dịch khi popup chọn (`BookDetailView.relatedText`, 1.3.853).
    let chineseText: BookDetailText
    /// Host sách — ghép `category.input` tương đối thành URL dự phòng cho nút "Mở link lỗi".
    var host: String? = nil
    /// Lượt kéo làm mới của màn Chi tiết — đổi số thì tải lại; back về (số không đổi) thì giữ kết quả.
    var refreshGeneration: Int = 0

    @State private var comments: [ExtensionItemResult] = []
    /// Lượt làm mới đã tải **thành công**. Lỗi thật / bị huỷ không ghi ⇒ lần hiện lại tự thử lại.
    @State private var loadedGeneration: Int? = nil
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var errorLink: SourceErrorLink? = nil
    @State private var openingErrorLink: SourceErrorLink? = nil
    @State private var nextPageUrl: String? = nil
    /// Bị trình duyệt "Mở link lỗi" che lúc biến mất ⇒ `.task` lần hiện lại kế tiếp không tải chồng trước khi chép cookie
    /// (lượt thử lại của `.errorLinkBrowser` lo tải và cũng hạ cờ) — xem `ErrorLinkBrowserModifier`.
    @State private var skipsReappearLoad = false
    
    var body: some View {
        BookDetailSectionCard(title: title) {
            content
        }
        .task(id: refreshGeneration) {
            if skipsReappearLoad {
                skipsReappearLoad = false
                return
            }
            guard loadedGeneration != refreshGeneration else { return }
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

    private var content: some View {
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.05))
                .cornerRadius(8)
            } else if comments.isEmpty {
                Text("Chưa có bình luận nào")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                let displayComments = Array(comments.prefix(3))
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(displayComments) { comment in
                        CommentRowView(
                            comment: comment,
                            avatarSize: 32,
                            localPath: localPath,
                            downloadUrl: downloadUrl,
                            configJson: configJson,
                            chineseText: chineseText,
                            host: host
                        )

                        // Vạch chỉ nằm **giữa** hai bình luận — dưới bình luận cuối là nút / mép thẻ.
                        if comment.id != displayComments.last?.id {
                            Divider()
                                .padding(.leading, 40)
                        }
                    }

                    if comments.count > 3 || nextPageUrl != nil {
                        NavigationLink(destination: AllCommentsView(
                            category: category,
                            localPath: localPath,
                            downloadUrl: downloadUrl,
                            configJson: configJson,
                            chineseText: chineseText,
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
                            .padding(.vertical, 10)
                            // Nền `secondarySystemBackground` của thẻ nuốt mất `secondary.opacity(0.05)` cũ.
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private func loadComments() async {
        let generation = refreshGeneration
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
                self.loadedGeneration = generation
            }
        } catch {
            // Rời màn giữa chừng không phải lỗi: giữ trạng thái đang tải, lần hiện lại tải tiếp.
            if ExtensionLoadError.unwrapped(error) is CancellationError { return }
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.errorLink = SourceErrorLink.resolve(from: error, fallback: category.input, host: host)
                self.isLoading = false
            }
        }
    }
}
