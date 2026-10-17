import Foundation

/// Một dòng mục lục do script `toc` trả về.
public struct ChapterResult: Equatable {
    public let name: String
    /// URL chương **nguyên văn** từ script — khoá nhận diện chương, không resolve lúc parse.
    public let url: String
    /// Host của dòng: thiếu khoá `host` ⇒ `source` của tiện ích; `host: ""` ⇒ `""` (hợp đồng extension).
    public let host: String
    /// Dòng `type: "section"` — tiêu đề nhóm tập (nhiều server), không mở được. Chỉ gắn cho truyện tranh/video;
    /// truyện chữ giữ dòng này như chương thường để chỉ số chương đã lưu không lệch.
    public let isSection: Bool

    public init(name: String, url: String, host: String, isSection: Bool = false) {
        self.name = name
        self.url = url
        self.host = host
        self.isSection = isSection
    }
}
