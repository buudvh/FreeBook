import Foundation

/// Ngữ cảnh "sách" mà JS thấy qua `book` (spec §6.6) và kho biến đi theo sách (§5.7).
///
/// Engine **không** tự ghi đĩa: luồng tạo/nạp đối tượng này (từ sách trên kệ, hoặc mới cho từng mục tìm kiếm), đặt vào
/// `LegadoEngineSession.book`, rồi sau khi chạy xong đọc `hasChanges` và lưu `variables`/`ruleVariables` vào sidecar.
///
/// - `variables`: kho của `book.putVariable/getVariable` (`book.variable` là chuỗi JSON của kho này).
/// - `ruleVariables`: kho của `java.put`/`@put` khi có ngữ cảnh sách (khuyến nghị §5.7 mục 1).
///
/// Thuộc tính ghi từ JS (`book.bookUrl = …`) chỉ đổi bản sao trong ngữ cảnh JS, không đổi đối tượng này (§6.6).
final class LegadoBookContext: @unchecked Sendable {
    var name: String
    var author: String
    var kind: String
    var coverUrl: String
    var intro: String
    var bookUrl: String
    var tocUrl: String
    /// `bookSourceUrl` của nguồn.
    var origin: String
    var originName: String
    var type: Int
    var latestChapterTitle: String
    var wordCount: String
    var durChapterIndex: Int
    var durChapterTitle: String
    var durChapterPos: Int
    var totalChapterNum: Int
    var customIntro: String
    var customTag: String
    var customCoverUrl: String
    var canUpdate: Bool
    var order: Int

    private let lock = NSLock()
    private var variableStore: [String: String]
    private var ruleVariableStore: [String: String]
    private var changed = false

    init(name: String = "", author: String = "", kind: String = "", coverUrl: String = "", intro: String = "",
         bookUrl: String = "", tocUrl: String = "", origin: String = "", originName: String = "", type: Int = 0,
         latestChapterTitle: String = "", wordCount: String = "", durChapterIndex: Int = 0, durChapterTitle: String = "",
         durChapterPos: Int = 0, totalChapterNum: Int = 0, customIntro: String = "", customTag: String = "",
         customCoverUrl: String = "", canUpdate: Bool = true, order: Int = 0,
         variables: [String: String] = [:], ruleVariables: [String: String] = [:]) {
        self.name = name
        self.author = author
        self.kind = kind
        self.coverUrl = coverUrl
        self.intro = intro
        self.bookUrl = bookUrl
        self.tocUrl = tocUrl
        self.origin = origin
        self.originName = originName
        self.type = type
        self.latestChapterTitle = latestChapterTitle
        self.wordCount = wordCount
        self.durChapterIndex = durChapterIndex
        self.durChapterTitle = durChapterTitle
        self.durChapterPos = durChapterPos
        self.totalChapterNum = totalChapterNum
        self.customIntro = customIntro
        self.customTag = customTag
        self.customCoverUrl = customCoverUrl
        self.canUpdate = canUpdate
        self.order = order
        self.variableStore = variables
        self.ruleVariableStore = ruleVariables
    }

    // MARK: - Kho biến

    /// Kho `book.putVariable` (bản chụp).
    var variables: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return variableStore
    }

    /// Kho `java.put`/`@put` của sách (bản chụp).
    var ruleVariables: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return ruleVariableStore
    }

    /// Có biến nào đổi kể từ lúc tạo hoặc lần `markSaved()` gần nhất.
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

    func ruleVariable(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return ruleVariableStore[key]
    }

    func setRuleVariable(_ value: String, forKey key: String) {
        lock.lock()
        if ruleVariableStore[key] != value {
            ruleVariableStore[key] = value
            changed = true
        }
        lock.unlock()
    }

    /// `book.variable`: chuỗi JSON của kho `book.putVariable` (khoá sắp xếp để ổn định).
    var variableJSON: String {
        let entries = variables.sorted { $0.key < $1.key }.map { (key: $0.key, value: LegadoEngineJSON.string($0.value)) }
        return LegadoEngineJSON.object(entries).compactText
    }

    // MARK: - JS

    /// Giá trị một thuộc tính cho `book.x` / `book.getX()`; tên lạ ⇒ `null`.
    func jsValue(field: String) -> LegadoEngineJSON {
        switch field {
        case "name": return .string(name)
        case "author": return .string(author)
        case "kind": return .string(kind)
        case "coverUrl": return .string(coverUrl)
        case "intro": return .string(intro)
        case "bookUrl": return .string(bookUrl)
        case "tocUrl": return .string(tocUrl)
        case "origin": return .string(origin)
        case "originName": return .string(originName)
        case "type": return .fromNumber(Double(type))
        case "latestChapterTitle", "lastChapter": return .string(latestChapterTitle)
        case "wordCount": return .string(wordCount)
        case "durChapterIndex": return .fromNumber(Double(durChapterIndex))
        case "durChapterTitle": return .string(durChapterTitle)
        case "durChapterPos": return .fromNumber(Double(durChapterPos))
        case "totalChapterNum": return .fromNumber(Double(totalChapterNum))
        case "customIntro": return .string(customIntro)
        case "customTag": return .string(customTag)
        case "customCoverUrl": return .string(customCoverUrl)
        case "canUpdate": return .bool(canUpdate)
        case "order": return .fromNumber(Double(order))
        case "group": return .fromNumber(0)
        case "variable": return .string(variableJSON)
        default: return .null
        }
    }
}
