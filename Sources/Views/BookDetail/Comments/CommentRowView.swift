import SwiftUI

/// Một bình luận — dùng chung cho thẻ bình luận của tab Chi tiết (`CommentSectionView`) và màn Tất cả bình luận
/// (`AllCommentsView`): avatar tròn, tên, dòng mô tả dưới tên, nội dung 3 dòng.
///
/// Có trả lời ⇒ hàng nút dưới nội dung: trái "Xem thêm" (mở chữ, của `ExpandableTextView`), phải "N trả lời" (xổ khối
/// `CommentRepliesBlock` ngay dưới bình luận). Hai nút độc lập; mặc định thu gọn. Trang tải về của trả lời
/// (`reply_source`) giữ ở đây nên thu gọn rồi mở lại không tải lại.
struct CommentRowView: View {
    let comment: ExtensionItemResult
    let avatarSize: CGFloat
    let localPath: String
    let downloadUrl: String
    let configJson: String
    /// Phồn → giản + QT hoặc tiện ích dịch (1.3.853): Chi tiết truyền chữ của truyện đang mở (`BookDetailView.relatedText`);
    /// màn xem phim còn đi init `isTranslationEnabled:` (chỉ QT, như trước).
    let chineseText: BookDetailText
    /// Host sách — `Referer` khi tải avatar.
    let host: String?

    @State private var showsReplies = false
    @State private var replyPage = CommentRepliesBlock.PageState()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CommentAvatarView(url: comment.avatar, referer: host, size: avatarSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.displayText(comment.name, chineseText: chineseText, stripsHTML: false))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                // Không có nội dung thì mô tả là thân bình luận — không lặp lại ở dòng dưới tên.
                if !comment.content.isEmpty, !comment.description.isEmpty {
                    Text(Self.displayText(comment.description, chineseText: chineseText))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                bodyText

                if showsReplies {
                    CommentRepliesBlock(
                        comment: comment,
                        page: $replyPage,
                        localPath: localPath,
                        downloadUrl: downloadUrl,
                        configJson: configJson,
                        chineseText: chineseText,
                        host: host,
                        onCollapse: toggleReplies
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Nhiều nút trong một hàng `List`: kiểu mặc định làm cả hàng kích hoạt mọi nút cùng lúc.
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var bodyText: some View {
        let raw = !comment.content.isEmpty ? comment.content : comment.description
        let text = Self.displayText(raw, chineseText: chineseText)
        let accessory = hasReplies ? AnyView(repliesToggle) : nil
        if !text.isEmpty {
            ExpandableTextView(
                text: text,
                lineLimit: 3,
                font: .footnote,
                foregroundColor: .secondary,
                toggleFont: .footnote,
                trailingAccessory: accessory
            )
        } else if let accessory {
            HStack {
                Spacer(minLength: 0)
                accessory
            }
        }
    }

    /// Có trả lời lồng sẵn (`replies`) hoặc nguồn tải khi bấm (`reply_source`).
    private var hasReplies: Bool {
        !comment.replies.isEmpty || comment.replySource != nil
    }

    /// Lồng sẵn ⇒ số trả lời có thật; tải khi bấm ⇒ số script khai (`reply_count`), không khai ⇒ "Xem trả lời".
    private var repliesLabel: String {
        let count = comment.replies.isEmpty ? comment.replyCount : comment.replies.count
        return count.map { "\($0) trả lời" } ?? "Xem trả lời"
    }

    private var repliesToggle: some View {
        Button(action: toggleReplies) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                    .font(.caption)
                Text(repliesLabel)
                    .font(.footnote)
                    .fontWeight(.medium)
                Image(systemName: showsReplies ? "chevron.up" : "chevron.down")
                    .font(.caption2)
            }
            .foregroundColor(.accentColor)
        }
    }

    private func toggleReplies() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showsReplies.toggle()
        }
    }

    /// Chữ hiển thị của bình luận / trả lời: bỏ HTML (trừ tên) rồi phồn → giản / QT hoặc tiện ích dịch.
    static func displayText(_ raw: String, chineseText: BookDetailText, stripsHTML: Bool = true) -> String {
        chineseText.meta(stripsHTML ? raw.cleanHTML() : raw)
    }

    /// Chỉ QT theo `options` (không tiện ích dịch).
    static func displayText(_ raw: String, options: ChineseTextPipeline.Options, stripsHTML: Bool = true) -> String {
        displayText(raw, chineseText: .quickOnly(options), stripsHTML: stripsHTML)
    }

    /// Đường cũ (chỉ dịch, không phồn → giản, từ điển chung) — giữ cho chỗ gọi chưa có cấu hình ba cấp.
    static func displayText(_ raw: String, translating: Bool, stripsHTML: Bool = true) -> String {
        displayText(raw, options: legacyOptions(translating: translating), stripsHTML: stripsHTML)
    }

    static func legacyOptions(translating: Bool) -> ChineseTextPipeline.Options {
        ChineseTextPipeline.Options(converts: false, translates: translating, dictionaryBookId: nil)
    }
}

extension CommentRowView {
    /// Init cũ của màn xem phim (`VideoWatchCommentsCard`): chỉ dịch theo công tắc, như trước 1.3.846.
    init(
        comment: ExtensionItemResult,
        avatarSize: CGFloat,
        localPath: String,
        downloadUrl: String,
        configJson: String,
        isTranslationEnabled: Bool,
        host: String?
    ) {
        self.init(
            comment: comment,
            avatarSize: avatarSize,
            localPath: localPath,
            downloadUrl: downloadUrl,
            configJson: configJson,
            chineseText: .quickOnly(Self.legacyOptions(translating: isTranslationEnabled)),
            host: host
        )
    }
}
