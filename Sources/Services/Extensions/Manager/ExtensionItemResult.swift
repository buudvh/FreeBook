import Foundation

/// Một item danh sách do script trả về (`search`, script tuỳ chọn của tab Khám phá…).
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

    public init(
        name: String,
        author: String = "",
        description: String = "",
        content: String = "",
        cover: String = "",
        link: String = "",
        host: String = "",
        tag: String = "",
        type: String = ""
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
    }
}
