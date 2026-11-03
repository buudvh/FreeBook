import SwiftUI

/// Khối trả lời xổ ra ngay dưới một bình luận (`CommentRowView`), thụt vào với vạch dọc bên trái.
///
/// - `replies` lồng sẵn (hợp đồng) ⇒ hiện ngay, không gọi mạng.
/// - Không có mà có `reply_source` (khoá riêng của FreeBook) ⇒ lần mở đầu gọi `script(input, page)` qua `SourceRuntime`
///   như script bình luận; còn trang kế thì có "Tải thêm trả lời". Trang đã tải nằm trong `page` của hàng cha.
struct CommentRepliesBlock: View {
    /// Trang trả lời đã tải từ `reply_source` — hàng cha giữ để thu gọn / mở lại không tải lại.
    struct PageState {
        var replies: [ExtensionItemResult] = []
        var nextPage: String? = nil
        /// Số trang đã tải xong; `0` = chưa tải.
        var loadedPage = 0
        var isLoading = false
        var errorMessage: String? = nil
    }

    let comment: ExtensionItemResult
    @Binding var page: PageState
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let isTranslationEnabled: Bool
    let host: String?
    let onCollapse: () -> Void

    /// Lồng sẵn thắng nguồn tải khi bấm.
    private var source: CommentReplySource? {
        comment.replies.isEmpty ? comment.replySource : nil
    }

    private var replies: [ExtensionItemResult] {
        comment.replies.isEmpty ? page.replies : comment.replies
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(replies) { reply in
                ReplyRow(reply: reply, isTranslationEnabled: isTranslationEnabled, host: host)
            }
            status
            footer
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 2)
        }
        .padding(.top, 4)
        .task {
            guard source != nil, page.loadedPage == 0 else { return }
            await load()
        }
    }

    @ViewBuilder
    private var status: some View {
        if page.isLoading {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Đang tải trả lời…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if let errorMessage = page.errorMessage {
            HStack(spacing: 8) {
                Text("Lỗi tải trả lời: \(errorMessage)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("Thử lại") {
                    Task { await load() }
                }
                .font(.caption.weight(.medium))
                .foregroundColor(.accentColor)
            }
        } else if source != nil, page.loadedPage > 0, replies.isEmpty {
            Text("Chưa có trả lời")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        let canLoadMore = source != nil && page.nextPage != nil && !page.isLoading && page.errorMessage == nil
        // Khối ngắn thì nút "N trả lời ⌃" của hàng cha còn ngay trên — chỉ khối dài mới cần "Thu gọn" ở đáy.
        let showsCollapse = replies.count > 3
        if canLoadMore || showsCollapse {
            HStack(spacing: 16) {
                if canLoadMore {
                    Button("Tải thêm trả lời") {
                        Task { await load() }
                    }
                }
                if showsCollapse {
                    Button(action: onCollapse) {
                        HStack(spacing: 4) {
                            Text("Thu gọn")
                            Image(systemName: "chevron.up")
                                .font(.caption2)
                        }
                    }
                }
            }
            .font(.caption.weight(.medium))
            .foregroundColor(.accentColor)
        }
    }

    /// Tải trang kế của `reply_source` (trang 1 khi chưa tải). Lỗi giữ trang đã có; rời màn giữa chừng không phải lỗi.
    @MainActor
    private func load() async {
        guard let source, !page.isLoading else { return }
        let pageNumber = page.loadedPage + 1
        page.isLoading = true
        page.errorMessage = nil
        do {
            let (results, nextPage) = try await SourceRuntime.shared.executeCustomScript(
                localPath: localPath,
                downloadUrl: downloadUrl,
                scriptFileName: source.script,
                input: source.input,
                page: pageNumber,
                pageUrl: pageNumber == 1 ? nil : page.nextPage,
                configJson: configJson
            )
            page.replies.append(contentsOf: results)
            // Trang rỗng hoặc token rỗng ⇒ hết; không thì "Tải thêm" lặp mãi một trang.
            page.nextPage = results.isEmpty ? nil : ExtensionHostResolver.nonEmpty(nextPage)
            page.loadedPage = pageNumber
            page.isLoading = false
        } catch {
            page.isLoading = false
            if ExtensionLoadError.unwrapped(error) is CancellationError { return }
            AppLogger.shared.log("❌ [CommentRepliesBlock] Lỗi tải trả lời trang \(pageNumber): \(error.localizedDescription)")
            page.errorMessage = error.localizedDescription
        }
    }

    /// Một trả lời: avatar nhỏ, tên, mô tả, nội dung 3 dòng có "Xem thêm" nhỏ.
    private struct ReplyRow: View {
        let reply: ExtensionItemResult
        let isTranslationEnabled: Bool
        let host: String?

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                CommentAvatarView(url: reply.avatar, referer: host, size: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(CommentRowView.displayText(reply.name, translating: isTranslationEnabled, stripsHTML: false))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    if !reply.content.isEmpty, !reply.description.isEmpty {
                        Text(CommentRowView.displayText(reply.description, translating: isTranslationEnabled))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    let raw = !reply.content.isEmpty ? reply.content : reply.description
                    let text = CommentRowView.displayText(raw, translating: isTranslationEnabled)
                    if !text.isEmpty {
                        ExpandableTextView(
                            text: text,
                            lineLimit: 3,
                            font: .footnote,
                            foregroundColor: .secondary,
                            toggleFont: .caption
                        )
                    }
                }
            }
        }
    }
}
