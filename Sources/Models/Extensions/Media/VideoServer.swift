import Foundation

/// Một server phát của một tập phim, ánh xạ từ kết quả `chap.js` của tiện ích video (`VideoTrackMapper`).
///
/// `data` là chuỗi **opaque**: truyền nguyên văn từng byte vào `track.js`, không trim, không encode, không
/// `cleanAndResolveUrl`. `title` đã được khử trùng (" (2)", " (3)"…) nên dùng làm `id` được.
public struct VideoServer: Sendable, Hashable, Identifiable {
    public let title: String
    public let data: String

    public var id: String { title }

    public init(title: String, data: String) {
        self.title = title
        self.data = data
    }
}
