import Foundation
import SwiftData
import CryptoKit

@Model
public final class Chapter {
    @Attribute(.unique) public var id: String // unique ID: bookId + "_" + hashOfUrl
    public var bookId: String // ID của sách sở hữu chương
    public var title: String
    public var url: String
    public var index: Int
    public var isCached: Bool = false
    public var offset: Int64 = 0 // Vị trí bắt đầu chương trong file .bin
    public var length: Int64 = 0 // Độ dài byte của chương trong file .bin
    public var titleTrans: String?
    public var host: String?
    
    public var book: Book?
    
    public init(id: String, bookId: String, title: String, url: String, index: Int, isCached: Bool = false, offset: Int64 = 0, length: Int64 = 0, titleTrans: String? = nil, host: String? = nil) {
        self.id = id
        self.bookId = bookId
        self.title = title
        self.url = url
        self.index = index
        self.isCached = isCached
        self.offset = offset
        self.length = length
        self.titleTrans = titleTrans
        self.host = host
    }
    
    public static func hashUrl(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let inputData = Data(trimmed.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    public static func generateId(bookId: String, url: String, index: Int) -> String {
        let suffix = url.isEmpty ? "index-\(index)" : hashUrl(url)
        return "\(bookId)_\(suffix)"
    }
}
