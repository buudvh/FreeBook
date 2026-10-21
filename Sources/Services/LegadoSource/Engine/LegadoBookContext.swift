import Foundation

/// Ngữ cảnh "sách" mà JS thấy qua `book` (spec §6.6) và kho biến đi theo sách (§5.7).
///
/// Engine **không** tự ghi đĩa: luồng tạo/nạp đối tượng này (từ sách trên kệ, hoặc mới cho từng mục tìm kiếm), đặt vào
/// `LegadoEngineSession.book`, rồi sau khi chạy xong đọc `hasChanges` và lưu `variables`/`ruleVariables` vào sidecar.
///
/// - `variables`: kho của `book.putVariable/getVariable` (`book.variable` là chuỗi JSON của kho này).
/// - `ruleVariables`: kho của `java.put`/`@put` khi có ngữ cảnh sách (khuyến nghị §5.7 mục 1).
///
/// Thuộc tính ghi từ JS (`book.x = v`, `book.setX(v)`, `setReverseToc`, `setUseReplaceRule`) đổi bản sao trong ngữ cảnh
/// JS **và** được ghi nhận ở đây (spec §13.5): `scriptWrites` (mọi lệnh ghi), các ghi đè có kiểu (`typeOverride`,
/// `reverseTocOverride`, `useReplaceRuleOverride`, `imageStyleOverride`), còn `bookUrl`/`tocUrl`/`canUpdate`/`variable`
/// đổi thẳng thuộc tính tương ứng. Luồng quyết định lưu bền thuộc tính nào (engine không ghi đĩa).
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
    /// Loại nội dung **của sách** do JS ghi (`book.type = v` / `book.setType(v)`, spec §13.6) — giá trị thô; luồng nạp lại
    /// từ kho trạng thái cho lượt sau. `book.type` mà JS đọc = giá trị này, không có thì bitmask theo `type` của nguồn.
    var typeOverride: Int?
    /// `book.setReverseToc(b)` (§13.5): đảo mục lục theo sách, áp sau tiền tố `-` của rule.
    var reverseTocOverride: Bool?
    /// `book.setUseReplaceRule(b)` (§13.5, U53).
    var useReplaceRuleOverride: Bool?
    /// `book.imageStyle = s` (§8.5).
    var imageStyleOverride: String?

    private let lock = NSLock()
    private var variableStore: [String: String]
    private var ruleVariableStore: [String: String]
    private var writeStore: [String: LegadoEngineJSON] = [:]
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

    // MARK: - Ghi từ JS (spec §13.5)

    /// Mọi lệnh ghi thuộc tính từ JS kể từ khi tạo: tên trường (`bookUrl`, `type`, `setReverseToc`…) → giá trị cuối.
    var scriptWrites: [String: LegadoEngineJSON] {
        lock.lock()
        defer { lock.unlock() }
        return writeStore
    }

    /// Ghi nhận `book.<field> = value` (hoặc `book.setReverseToc(value)`…) từ JS.
    func recordScriptWrite(field: String, value: LegadoEngineJSON) {
        lock.lock()
        writeStore[field] = value
        lock.unlock()
        switch field {
        case "setReverseToc": reverseTocOverride = Self.truthy(value)
        case "setUseReplaceRule": useReplaceRuleOverride = Self.truthy(value)
        case "type":
            if let number = value.doubleValue, number.isFinite, abs(number) < 1_000_000_000 { typeOverride = Int(number) }
        case "imageStyle": imageStyleOverride = value.scalarString
        case "canUpdate": canUpdate = Self.truthy(value)
        case "bookUrl": bookUrl = value.scalarString
        case "tocUrl": tocUrl = value.scalarString
        case "variable": replaceVariables(withText: value.scalarString)
        default: break
        }
    }

    /// `book.variable = "…"`: object JSON ⇒ thay cả kho; rỗng ⇒ xoá kho; chuỗi khác ⇒ xoá kho rồi lưu vào khoá `custom`
    /// (khoá mà trình sửa "biến sách" dùng, spec §12.5).
    private func replaceVariables(withText text: String) {
        var replacement: [String: String] = [:]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entries = LegadoEngineJSONParser.parse(trimmed, lenient: true)?.objectEntries {
            for entry in entries { replacement[entry.key] = entry.value.scalarString }
        } else if !trimmed.isEmpty {
            replacement["custom"] = text
        }
        lock.lock()
        if variableStore != replacement {
            variableStore = replacement
            changed = true
        }
        lock.unlock()
    }

    static func truthy(_ value: LegadoEngineJSON) -> Bool {
        switch value {
        case .bool(let flag): return flag
        case .null: return false
        case .number(let number, _): return number != 0
        default: return LegadoRuleValue.isTruthy(value.scalarString)
        }
    }

    /// `book.type` mà JS đọc (spec §13.6, đính chính §15.3 mục 4): ghi đè của sách, không có thì **bitmask** theo
    /// `bookSourceType` (0 ⇒ 8, 1 ⇒ 32, 2 ⇒ 64, 3 ⇒ 128, 4 ⇒ 8 — U54).
    var scriptBookType: Int {
        if let typeOverride { return typeOverride }
        switch type {
        case 1: return 32
        case 2: return 64
        case 3: return 128
        default: return 8
        }
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
        case "type": return .fromNumber(Double(scriptBookType))
        case "imageStyle": return .string(imageStyleOverride ?? "")
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
