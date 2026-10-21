import Foundation

/// Ngữ cảnh "chương" mà JS thấy qua `chapter` (spec §6.6) và kho `chapter.putVariable` (§5.7).
/// Như `LegadoBookContext`: engine không ghi đĩa; luồng nạp/lưu `variables` theo `hasChanges`.
final class LegadoChapterContext: @unchecked Sendable {
    var title: String
    var url: String
    var index: Int
    var baseUrl: String
    var bookUrl: String
    /// `updateTime` của mục lục (chuỗi phụ).
    var tag: String
    var isVip: Bool
    var isVolume: Bool
    var isPay: Bool
    var resourceUrl: String

    private let lock = NSLock()
    private var variableStore: [String: String]
    private var changed = false

    init(title: String = "", url: String = "", index: Int = 0, baseUrl: String = "", bookUrl: String = "",
         tag: String = "", isVip: Bool = false, isVolume: Bool = false, isPay: Bool = false, resourceUrl: String = "",
         variables: [String: String] = [:]) {
        self.title = title
        self.url = url
        self.index = index
        self.baseUrl = baseUrl
        self.bookUrl = bookUrl
        self.tag = tag
        self.isVip = isVip
        self.isVolume = isVolume
        self.isPay = isPay
        self.resourceUrl = resourceUrl
        self.variableStore = variables
    }

    var variables: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return variableStore
    }

    var hasChanges: Bool {
        lock.lock()
        defer { lock.unlock() }
        return changed
    }

    func markSaved() {
        lock.lock()
        changed = false
        lock.unlock()
    }

    func variable(_ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return variableStore[key] ?? ""
    }

    /// `nil` ⇒ xoá khoá.
    func setVariable(_ value: String?, forKey key: String) {
        lock.lock()
        if variableStore[key] != value {
            variableStore[key] = value
            changed = true
        }
        lock.unlock()
    }

    var variableJSON: String {
        let entries = variables.sorted { $0.key < $1.key }.map { (key: $0.key, value: LegadoEngineJSON.string($0.value)) }
        return LegadoEngineJSON.object(entries).compactText
    }

    func jsValue(field: String) -> LegadoEngineJSON {
        switch field {
        case "title": return .string(title)
        case "url": return .string(url)
        case "index": return .fromNumber(Double(index))
        case "baseUrl": return .string(baseUrl)
        case "bookUrl": return .string(bookUrl)
        case "tag": return .string(tag)
        case "isVip": return .bool(isVip)
        case "isVolume": return .bool(isVolume)
        case "isPay": return .bool(isPay)
        case "resourceUrl": return .string(resourceUrl)
        case "variable": return .string(variableJSON)
        default: return .null
        }
    }
}
