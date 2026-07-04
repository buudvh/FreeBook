import Foundation
import SwiftData

@Model
public final class Extension {
    @Attribute(.unique) public var packageId: String // Tên duy nhất (ví dụ: folder name)
    public var name: String
    public var author: String
    public var version: Int
    public var sourceUrl: String
    public var iconUrl: String?
    public var desc: String?
    public var type: String // "novel" hoặc "comic" hoặc "chinese_novel"
    public var locale: String // "vi_VN", "zh_CN", ...
    public var localPath: String // Thư mục lưu các file JS giải nén
    public var isEnabled: Bool = true
    public var configJson: String = "{}" // Lưu cấu hình đã chỉnh sửa dạng JSON
    public var downloadUrl: String = "" // Lưu đường dẫn tải file zip tiện ích
    public var isPinned: Bool = false
    
    public var repository: Repository?
    
    public init(packageId: String, name: String, author: String, version: Int, sourceUrl: String, iconUrl: String? = nil, desc: String? = nil, type: String, locale: String, localPath: String, isEnabled: Bool = true, configJson: String = "{}", downloadUrl: String = "", isPinned: Bool = false) {
        self.packageId = packageId
        self.name = name
        self.author = author
        self.version = version
        self.sourceUrl = sourceUrl
        self.iconUrl = iconUrl
        self.desc = desc
        self.type = type
        self.locale = locale
        self.localPath = localPath
        self.isEnabled = isEnabled
        self.configJson = configJson
        self.downloadUrl = downloadUrl
        self.isPinned = isPinned
    }
}
