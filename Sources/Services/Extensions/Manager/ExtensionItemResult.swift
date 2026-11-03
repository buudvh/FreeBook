import Foundation

/// Một item danh sách do script trả về (`search`, script tuỳ chọn của tab Khám phá, bình luận…).
public struct ExtensionItemResult: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let author: String
    public let description: String
    public let content: String
    /// Đã resolve theo `ExtensionURLFormatter.resolveAssetURL` (host item → `source`).
    public let cover: String
    /// Nguyên văn từ script — khoá nhận diện sách, không resolve lúc parse.
    public let link: String
    public let host: String
    /// Nhãn ngắn hiện trên bìa ("Hoàn thành", "Hot"…); `""` khi không có.
    public let tag: String
    /// Loại nội dung của item (`stream`, `short`, rỗng = mở chi tiết), không phân biệt hoa thường.
    public let type: String
    /// Ảnh đại diện người bình luận (`avatar` của script bình luận), đã resolve như `cover`; `""` khi không có.
    public let avatar: String
    /// Trả lời lồng sẵn của bình luận (`replies` — hợp đồng), đã dàn phẳng còn một cấp.
    public let replies: [ExtensionItemResult]
    /// Trả lời tải khi bấm (`reply_source`); chỉ dùng khi `replies` rỗng.
    public let replySource: CommentReplySource?
    /// Tổng số trả lời script khai (`reply_count`); `nil` = không khai.
    public let replyCount: Int?

    public init(
        name: String,
        author: String = "",
        description: String = "",
        content: String = "",
        cover: String = "",
        link: String = "",
        host: String = "",
        tag: String = "",
        type: String = "",
        avatar: String = "",
        replies: [ExtensionItemResult] = [],
        replySource: CommentReplySource? = nil,
        replyCount: Int? = nil
    ) {
        self.name = name
        self.author = author
        self.description = description
        self.content = content
        self.cover = cover
        self.link = link
        self.host = host
        self.tag = tag
        self.type = type
        self.avatar = avatar
        self.replies = replies
        self.replySource = replySource
        self.replyCount = replyCount
    }
}
