import Foundation

public struct TTSChapterInfo: Codable, Equatable {
    public let title: String
    public let url: String
    public let index: Int
    public var cachedContent: String?
    
    public init(title: String, url: String, index: Int, cachedContent: String? = nil) {
        self.title = title
        self.url = url
        self.index = index
        self.cachedContent = cachedContent
    }
}

public struct TTSExtensionInfo: Codable, Equatable {
    public let localPath: String
    public let downloadUrl: String
    public let configJson: String?
    
    public init(localPath: String, downloadUrl: String, configJson: String?) {
        self.localPath = localPath
        self.downloadUrl = downloadUrl
        self.configJson = configJson
    }
}
