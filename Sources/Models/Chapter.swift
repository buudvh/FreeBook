import Foundation
import SwiftData

@Model
public final class Chapter {
    @Attribute(.unique) public var id: String // unique ID: bookId + "_" + url
    public var title: String
    public var url: String
    public var index: Int
    public var content: String? // Đối với truyện tranh, content chứa danh sách ảnh cách nhau bởi dấu xuống dòng (\n)
    public var isCached: Bool = false
    
    public var book: Book?
    
    public init(id: String, title: String, url: String, index: Int, content: String? = nil, isCached: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.index = index
        self.content = content
        self.isCached = isCached
    }
}
