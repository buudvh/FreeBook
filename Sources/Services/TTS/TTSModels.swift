import Foundation

public struct Voice: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public extension String {
    var toASCIIID: String {
        let lowercased = self.lowercased()
        let folding = lowercased.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        var result = ""
        var lastWasUnderscore = false
        
        for char in folding {
            if char.isASCII && (char.isLetter || char.isNumber) {
                result.append(char)
                lastWasUnderscore = false
            } else if !lastWasUnderscore {
                result.append("_")
                lastWasUnderscore = true
            }
        }
        
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if trimmed.isEmpty {
            var hash: UInt64 = 5381
            for byte in self.utf8 {
                hash = ((hash << 5) &+ hash) &+ UInt64(byte)
            }
            return "voice_" + String(hash)
        }
        return trimmed
    }
    
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public extension Voice {
    init(name: String) {
        self.name = name
        self.id = name.toASCIIID
    }
}

public struct TTSParagraph: Codable, Hashable, Sendable {
    public let text: String
    public let range: NSRange
    public let paragraphIndex: Int
    
    public init(text: String, range: NSRange, paragraphIndex: Int) {
        self.text = text
        self.range = range
        self.paragraphIndex = paragraphIndex
    }
}

public enum TTSError: LocalizedError {
    case badRequest(String)
    case notFound(String)
    case modelNotCached(String)
    case engineUnavailable(String)
    case internalError(String)

    public var errorDescription: String? {
        switch self {
        case .badRequest(let message),
             .notFound(let message),
             .modelNotCached(let message),
             .engineUnavailable(let message),
             .internalError(let message):
            return message
        }
    }
}

public struct TTSChapterInfo: Codable, Equatable, Sendable {
    public let title: String
    public let url: String
    public let index: Int
    /// Host của chương — cần thiết để repository fetch nội dung khi chưa cache local
    public var host: String?
    
    public init(title: String, url: String, index: Int, host: String? = nil) {
        self.title = title
        self.url = url
        self.index = index
        self.host = host
    }
}

public struct TTSExtensionInfo: Codable, Equatable, Sendable {
    public let packageId: String
    public let localPath: String
    public let downloadUrl: String
    public let configJson: String?
    
    public init(packageId: String, localPath: String, downloadUrl: String, configJson: String?) {
        self.packageId = packageId
        self.localPath = localPath
        self.downloadUrl = downloadUrl
        self.configJson = configJson
    }
}
