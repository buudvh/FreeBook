import Foundation

public struct TOCRule: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let rule: String
    public let example: String?
    public var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, rule, example, enabled
    }

    public init(id: String, name: String, rule: String, example: String? = nil, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.rule = rule
        self.example = example
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.rule = try container.decode(String.self, forKey: .rule)
        self.example = try container.decodeIfPresent(String.self, forKey: .example)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

public enum TOCRuleImportError: LocalizedError, Equatable, Sendable {
    case invalidJSON
    case fileTooLarge(maxKB: Int)
    case tooManyRules(count: Int, max: Int)
    case emptyID(index: Int)
    case idTooLong(index: Int)
    case emptyName(index: Int, id: String)
    case nameTooLong(index: Int)
    case duplicateID(id: String)
    case invalidRegex(ruleName: String, reason: String)
    case custom(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "File JSON không đúng cấu trúc danh sách quy tắc TOC."
        case .fileTooLarge(let maxKB):
            return "Kích thước file vượt quá giới hạn cho phép (tối đa \(maxKB)KB)."
        case .tooManyRules(let count, let max):
            return "Số lượng quy tắc trong file (\(count)) vượt quá giới hạn tối đa (\(max))."
        case .emptyID(let index):
            return "Quy tắc thứ \(index + 1) có ID rỗng."
        case .idTooLong(let index):
            return "Quy tắc thứ \(index + 1) có ID vượt quá 100 ký tự."
        case .emptyName(let index, let id):
            return "Quy tắc thứ \(index + 1) (ID: \(id)) có tên rỗng."
        case .nameTooLong(let index):
            return "Quy tắc thứ \(index + 1) có tên vượt quá 100 ký tự."
        case .duplicateID(let id):
            return "Phát hiện ID trùng lặp nội bộ trong file import: \"\(id)\"."
        case .invalidRegex(let ruleName, let reason):
            return "Quy tắc \"\(ruleName)\" chứa lỗi: \(reason)"
        case .custom(let msg):
            return msg
        }
    }
}

public struct TOCImportPreview: Equatable, Sendable {
    public let importedCount: Int
    public let newCount: Int
    public let updateCount: Int
    public let preservedCount: Int
    public let restoredDefaultCount: Int

    public init(importedCount: Int, newCount: Int, updateCount: Int, preservedCount: Int, restoredDefaultCount: Int) {
        self.importedCount = importedCount
        self.newCount = newCount
        self.updateCount = updateCount
        self.preservedCount = preservedCount
        self.restoredDefaultCount = restoredDefaultCount
    }
}

public actor TOCRuleSaveCoordinator {
    public static let shared = TOCRuleSaveCoordinator()
    private var previousSaveTask: Task<Bool, Never>? = nil

    public init() {}

    @discardableResult
    public func enqueue(_ rules: [TOCRule]) -> Task<Bool, Never> {
        let currentPrevious = previousSaveTask
        let newSaveTask = Task { () -> Bool in
            _ = await currentPrevious?.value
            return TranslateUtils.saveTOCRules(rules)
        }
        self.previousSaveTask = newSaveTask
        return newSaveTask
    }

    @discardableResult
    public func scheduleSave(_ rules: [TOCRule]) async -> Bool {
        let task = enqueue(rules)
        return await task.value
    }

    public func flush() async {
        _ = await previousSaveTask?.value
    }
}

public final class TranslateUtils {
    
    private static let translationCache = NSCache<NSString, NSString>()
    private static let cacheLock = NSLock()
    private static let tocRulesLock = NSLock()
    private static var chapterTitleCacheDict: [String: [String: String]] = [:]
    private static var cachedAllTOCRules: [TOCRule]? = nil
    private static var cachedTOCRules: [TOCRule]? = nil
    private static var cachedCompiledTOCRegexes: [NSRegularExpression]? = nil
    
    public static func getFirstMeaning(of rawTranslation: String) -> String {
        let separators = CharacterSet(charactersIn: "/¦|")
        let components = rawTranslation.components(separatedBy: separators)
        if let first = components.first {
            return first.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return rawTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
        // Default TOC rules mapped from user preference
    private static let defaultTOCRules = [
        TOCRule(id: "rule1", name: "Số thứ tự + 第x章", rule: #"^\d{1,4}\.第[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}章.{0,50}$"#, example: "1.第1章", enabled: true),
        TOCRule(id: "rule2", name: "Mục lục (Khoảng trắng đầu dòng)", rule: #"(?<=[　\s])(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和]))).{0,100}$"#, example: " 第一章 开始", enabled: true),
        TOCRule(id: "rule3", name: "Mục lục Tiêu chuẩn (Chương/Tập/Quyển)", rule: #"^[ 　	]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,100}$"#, example: "第一章 序幕", enabled: true),
        TOCRule(id: "rule4", name: "Mục lục Cổ điển / Light Novel (Hồi/Thoại)", rule: #"^[ 　	]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|话|篇(?!张))).{0,100}$"#, example: "第一回 风云再起", enabled: true),
        TOCRule(id: "rule5", name: "Ngoặc đặc biệt [Chương x]", rule: #"(?<=[\s　])[【〔〖「『〈［\[](?:第|[Cc]hapter)[\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}[章节].{0,100}$"#, example: " 【第一章 序幕", enabled: true),
        TOCRule(id: "rule6", name: "第 + Số Ả Rập + 章 + Tiêu đề", rule: #"^第(\d+)章\s+(.+)$"#, example: "第1章 七杀剑与先天满魂力", enabled: true),
        TOCRule(id: "rule7", name: "Số + Dấu phân cách + Tiêu đề", rule: #"^[ 　	]{0,4}\d{1,5}[:：,.， 、_—\-].{1,100}$"#, example: "1、这个就是标题", enabled: true),
        TOCRule(id: "rule8", name: "第x章 (Linh hoạt khoảng trắng & Tiêu đề dài)", rule: #"^[ 	　]*第\s*[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}\s*章\s*.{0,150}$"#, example: " 第54章 帝天组问题少年少女局", enabled: true),
        TOCRule(id: "rule9", name: "Số Hán tự đơn thuần (Ví dụ: 一百七十)", rule: #"(?<=[　\s])[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,12}[ 　	]{0,4}$"#, example: " 一百七十", enabled: false),
        TOCRule(id: "rule10", name: "Mục lục Khớp cả Giới thiệu / Văn án", rule: #"(?<=[　\s])(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|篇(?!张))).{0,100}$"#, example: " 简介 作品介绍", enabled: false),
        TOCRule(id: "rule11", name: "Số Ả Rập đơn thuần (Ví dụ: 12)", rule: #"(?<=[　\s])\d+\.?[ 　	]{0,4}$"#, example: " 12", enabled: false),
        TOCRule(id: "rule12", name: "Chính văn + Tiêu đề / Số thứ tự", rule: #"^[ 　\t]{0,4}正文[ 　]{1,4}.{0,100}$"#, example: "正文 常山赵子龙", enabled: false),
        TOCRule(id: "rule13", name: "Tiêu đề Tiếng Anh (Chapter/Section/Part)", rule: #"^[ 　	]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO][.、]|[Ee]pisode|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\s{0,4}\d{1,4}.{0,100}$"#, example: "Chapter 1 The Beginning", enabled: false),
        TOCRule(id: "rule14", name: "Chapter + Số (Chapter 1)", rule: #"^[ 　	]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][Oo]\.|[Ee]pisode)\s{0,4}\d{1,4}.{0,100}$"#, example: "Chapter 1", enabled: false),
        TOCRule(id: "rule15", name: "Ký tự biểu cảm / Ngôi sao (☆★✦)", rule: #"(?:^|[\s　]{1,4})(?:[☆★✦✧].{1,30}|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$"#, example: "☆、晋江作者最喜欢的格式", enabled: false),
        TOCRule(id: "rule16", name: "Quyển / Chương + Số thứ tự", rule: #"^[ 	　]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[卷章][\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ 　]{0,4}.{0,100}$"#, example: "卷五 开元盛世", enabled: false),
        TOCRule(id: "rule17", name: "Tiêu đề ngắn viết sát lề (Dưới 20 ký tự)", rule: #"^\S.{1,20}$"#, example: "20字以内顶格写的都是标题", enabled: false),
        TOCRule(id: "rule18", name: "Tên sách / Tiêu đề + (Số)", rule: #"^[一-龥]{1,20}[ 　	]{0,4}[(（][\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[)）][ 　	]{0,4}$"#, example: "标题后面数字有括号(12)", enabled: false),
        TOCRule(id: "rule19", name: "Tên sách / Tiêu đề + Số", rule: #"^[一-龥]{1,20}[ 　	]{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[ 　	]{0,4}$"#, example: "标题后面数字没有括号124", enabled: false),
        TOCRule(id: "rule20", name: "Dấu bằng bao quanh === Tiêu đề ===", rule: #"\={3,6}(.{1,40}?)\="#, example: "===起这种标题干什么===", enabled: false),
        TOCRule(id: "rule21", name: "Quy tắc mở rộng nâng cao", rule: #"(?im)^.{0,6}(?:[引楔]子|正文(?!完|结)|[引序前]言|[序终]章|扉页|[上中下][部篇卷]|卷首语|后记|尾声|番外|={2,4}|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|页[、 　]|集(?![合和])|部(?![分是门落])|篇(?!张))).{0,100}$|^.{0,6}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟a-z]{1,8}[、. 　].{0,100}$"#, example: "第1章 激进规则,适配更多非常用格式", enabled: false)
    ]

    private static let punctuationMapping: [Character: String] = [
        "。": ". ",
        "．": ". ",
        "，": ", ",
        "、": ", ",
        "；": "; ",
        "：": ": ",
        "！": "! ",
        "？": "? ",
        "…": "... ",

        //"（": "【",
        //"）": "】",
        //"〔": "【",
        //"〕": "】",
        //"【": "【",
        //"】": "】",
        //"〖": "【",
        //"〗": "】",
        //"〘": "【",
        //"〙": "】",
        //"〚": "【",
        //"〛": "】",
        //"『": "【",
        //"』": "】",
        //"《": "【",
        //"》": "】",
        //"〈": "【",
        //"〉": "】",
        //"｛": "【",
        //"｝": "】",
        //"「": "【",
        //"」": "】",
        //"(": "【",
        //")": "】",
        //"{": "【",
        //"}": "】",
        //"[": "【",
        //"]": "】",
        //"［": "【",
        //"］": "】",
        //"<": "【",
        //">": "】",
        //"＜": "【",
        //"＞": "】",
        //"﹙": "【",
        //"﹚": "】",
        //"﹛": "【",
        //"﹜": "】",
        //"﹝": "【",
        //"﹞": "】",


        "～": "~",
        "—": "-",
        "　": " "
    ]
    
    private static let chapterUnitMap: [String: String] = [
        "卷": "Quyển",
        "回": "Hồi",
        "章": "Chương",
        "幕": "Màn",
        "折": "Chiết",
        "节": "Tiết",
        "集": "Tập",
        "部": "Bộ",
        "篇": "Thiên",
        "话": "Thoại"
    ]
    
    public static var isTranslationEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isTranslationEnabled")
    }
    
    public static func containsChinese(_ text: String) -> Bool {
        return text.contains { char in
            guard let code = char.unicodeScalars.first?.value else { return false }
            return code >= 0x4E00 && code <= 0x9FFF
        }
    }
    
    public static func translateAuthorHanViet(_ author: String) -> String {
        guard !author.isEmpty else { return author }
        guard containsChinese(author) else { return author }
        let phienAm = TranslationManager.shared.phienAmMap
        var list: [String] = []
        for char in author {
            let charStr = String(char)
            if let mapped = phienAm[charStr] {
                list.append(mapped)
            } else {
                list.append(charStr)
            }
        }
        return list.joined(separator: " ").capitalized
    }
    
    public static func translateMeta(_ text: String?, bookId: String? = nil) -> String {
        return translateText(text, isMeta: true, bookId: bookId)
    }
    
    public static func translateContent(_ text: String?, bookId: String? = nil) -> String {
        return translateText(text, isMeta: false, bookId: bookId)
    }

    public static func translateContentWithMapping(_ text: String?, bookId: String? = nil) -> TranslatedTextResult {
        let original = text ?? ""
        let translated = translateContent(original, bookId: bookId)
        return TranslatedTextResult(
            text: translated,
            spans: buildTranslationSpans(original: original, translated: translated, bookId: bookId)
        )
    }

    public static func translateChapterTitleWithMapping(_ text: String, bookId: String? = nil) -> TranslatedTextResult {
        let translated = translateChapterTitle(text, bookId: bookId)
        return TranslatedTextResult(
            text: translated,
            spans: buildTranslationSpans(original: text, translated: translated, bookId: bookId)
        )
    }

    public static func untranslatedTextResult(_ text: String) -> TranslatedTextResult {
        let length = (text as NSString).length
        let spans = length > 0
            ? [TranslationSpan(originalLocation: 0, originalLength: length, translatedLocation: 0, translatedLength: length)]
            : []
        return TranslatedTextResult(text: text, spans: spans)
    }
    
    public static func translateChapterTitle(_ text: String, bookId: String? = nil) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        
        let bid = bookId ?? "global"
        
        cacheLock.lock()
        let cached = chapterTitleCacheDict[bid]?[trimmed]
        cacheLock.unlock()
        
        if let cached = cached {
            return cached
        }
        
        let translated: String
        let enabledRules = getActiveTOCRules()
        var matchedRule = false
        
        for rule in enabledRules {
            if let regex = try? NSRegularExpression(pattern: rule.rule, options: [.caseInsensitive]) {
                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                if regex.firstMatch(in: trimmed, options: [], range: range) != nil {
                    matchedRule = true
                    break
                }
            }
        }
        
        let titleNumberRegex = try! NSRegularExpression(pattern: #"(第\s*[0-9一二三四五六七八九十百千零〇两壹贰叁肆伍陆柒捌玖拾佰仟]+\s*[卷回章节幕折集部篇话])"#, options: [])
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        
        if matchedRule, let match = titleNumberRegex.firstMatch(in: trimmed, options: [], range: range) {
            if let matchRange = Range(match.range(at: 1), in: trimmed) {
                let matchedPrefix = String(trimmed[matchRange])
                
                let numberPartRegex = try! NSRegularExpression(pattern: #"([0-9一二三四五六七八九十百千零〇两壹贰叁肆伍陆柒捌玖拾佰仟]+)"#, options: [])
                let unitPartRegex = try! NSRegularExpression(pattern: #"([卷回章节幕折集部篇话])"#, options: [])
                
                let prefixRange = NSRange(matchedPrefix.startIndex..<matchedPrefix.endIndex, in: matchedPrefix)
                
                var numberVal = ""
                var unitVal = "Chương"
                
                if let numMatch = numberPartRegex.firstMatch(in: matchedPrefix, options: [], range: prefixRange),
                   let numRange = Range(numMatch.range(at: 1), in: matchedPrefix) {
                    let numStr = String(matchedPrefix[numRange])
                    numberVal = String(chineseNumberToInt(numStr))
                }
                
                if let unitMatch = unitPartRegex.firstMatch(in: matchedPrefix, options: [], range: prefixRange),
                   let unitRange = Range(unitMatch.range(at: 1), in: matchedPrefix) {
                    let unitStr = String(matchedPrefix[unitRange])
                    unitVal = chapterUnitMap[unitStr] ?? "Chương"
                }
                
                let preMatch = String(trimmed[..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let postMatch = String(trimmed[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                let translatedPre = preMatch.isEmpty ? "" : translateMeta(preMatch, bookId: bookId) + " "
                let translatedPost = postMatch.isEmpty ? "" : ": " + translateMeta(postMatch, bookId: bookId)
                
                translated = "\(translatedPre)\(unitVal) \(numberVal)\(translatedPost)".trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                translated = translateMeta(trimmed, bookId: bookId)
            }
        } else if let match = titleNumberRegex.firstMatch(in: trimmed, options: [], range: range),
                  let matchRange = Range(match.range(at: 1), in: trimmed) {
            let matchedPrefix = String(trimmed[matchRange])
            
            let numberPartRegex = try! NSRegularExpression(pattern: #"([0-9一二三四五六七八九十百千零〇两壹贰叁肆伍陆柒捌玖拾佰仟]+)"#, options: [])
            let unitPartRegex = try! NSRegularExpression(pattern: #"([卷回章节幕折集部篇话])"#, options: [])
            
            let prefixRange = NSRange(matchedPrefix.startIndex..<matchedPrefix.endIndex, in: matchedPrefix)
            
            var numberVal = ""
            var unitVal = "Chương"
            
            if let numMatch = numberPartRegex.firstMatch(in: matchedPrefix, options: [], range: prefixRange),
               let numRange = Range(numMatch.range(at: 1), in: matchedPrefix) {
                let numStr = String(matchedPrefix[numRange])
                numberVal = String(chineseNumberToInt(numStr))
            }
            
            if let unitMatch = unitPartRegex.firstMatch(in: matchedPrefix, options: [], range: prefixRange),
               let unitRange = Range(unitMatch.range(at: 1), in: matchedPrefix) {
                let unitStr = String(matchedPrefix[unitRange])
                unitVal = chapterUnitMap[unitStr] ?? "Chương"
            }
            
            let preMatch = String(trimmed[..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let postMatch = String(trimmed[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            let translatedPre = preMatch.isEmpty ? "" : translateMeta(preMatch, bookId: bookId) + " "
            let translatedPost = postMatch.isEmpty ? "" : ": " + translateMeta(postMatch, bookId: bookId)
            
            translated = "\(translatedPre)\(unitVal) \(numberVal)\(translatedPost)".trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            translated = translateMeta(trimmed, bookId: bookId)
        }
        
        cacheLock.lock()
        if chapterTitleCacheDict[bid] == nil {
            chapterTitleCacheDict[bid] = [:]
        }
        chapterTitleCacheDict[bid]?[trimmed] = translated
        cacheLock.unlock()
        
        return translated
    }
    
    private static func translateText(_ text: String?, isMeta: Bool, bookId: String?) -> String {
        guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text ?? "" }
        guard containsChinese(text) else { return text }
        
        // Nếu từ điển chưa load xong, trả về văn bản gốc và không lưu cache dịch
        guard TranslationManager.shared.isVietPhraseLoaded else {
            return text
        }
        
        let md5 = text.md5()
        let cacheKey = "translate|vietphrase|v2|\(isMeta ? "meta" : "content")|\(bookId ?? "global")|\(md5)" as NSString
        
        if let cached = translationCache.object(forKey: cacheKey) {
            return cached as String
        }
        
        let translated = performTranslation(text, bookId: bookId)
        translationCache.setObject(translated as NSString, forKey: cacheKey)
        return translated
    }
    
    private static func performTranslation(_ text: String, bookId: String?) -> String {
        var converted = ""
        for char in text {
            converted.append(punctuationMapping[char] ?? String(char))
        }
        
        let tokens = tokenize(converted, bookId: bookId)
        
        let isPronounsEnabled = UserDefaults.standard.bool(forKey: "isTranslationPronounsEnabled")
        let isLuatNhanEnabled = UserDefaults.standard.bool(forKey: "isTranslationLuatNhanEnabled")
        
        var translatedWords: [String] = []
        let names = TranslationManager.shared.namesDict
        let customNames = TranslationManager.shared.customNamesDict
        let deletedNames = TranslationManager.shared.deletedNames
        let pronouns = isPronounsEnabled ? TranslationManager.shared.pronounsDict : nil
        let luatNhan = isLuatNhanEnabled ? TranslationManager.shared.luatNhanDict : nil
        let vp = TranslationManager.shared.vietPhraseDict
        let customVP = TranslationManager.shared.customVietPhraseDict
        let deletedVP = TranslationManager.shared.deletedVietPhrase
        let phienAm = TranslationManager.shared.phienAmMap
        
        var bookVP: TrieDictionary? = nil
        var bookNames: TrieDictionary? = nil
        if let bid = bookId {
            let bookDicts = TranslationManager.shared.getBookDictionaries(for: bid)
            bookVP = bookDicts.vietPhrase
            bookNames = bookDicts.names
        }
        
        for token in tokens {            
            var translation: String? = nil
            
            // 1. Book Names
            if let bookNames = bookNames,
               let match = bookNames.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            // 2. Custom Names
            if translation == nil,
               let customNames = customNames,
               let match = customNames.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            // 3. Base Names (exclude deleted)
            if translation == nil,
               !deletedNames.contains(token),
               let names = names,
               let match = names.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            // 4. Pronouns
            if translation == nil,
               let pronouns = pronouns,
               let match = pronouns.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            // 5. LuatNhan
            if translation == nil,
               let luatNhan = luatNhan,
               let match = luatNhan.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            // 6. Book VietPhrase
            if translation == nil,
               let bookVP = bookVP,
               let match = bookVP.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            // 7. Custom VietPhrase
            if translation == nil,
               let customVP = customVP,
               let match = customVP.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            // 8. Base VietPhrase (exclude deleted)
            if translation == nil,
               !deletedVP.contains(token),
               let vp = vp,
               let match = vp.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            if let found = translation {
                translatedWords.append(getFirstMeaning(of: found))
            } else {
                if token.count == 1, isChineseCharacter(token.first!) {
                    translatedWords.append(phienAm[token] ?? token)
                } else if containsChinese(token) {
                    var phienAmList: [String] = []
                    var hasPhienAm = false
                    for char in token {
                        if let mapped = phienAm[String(char)] {
                            phienAmList.append(mapped)
                            hasPhienAm = true
                        } else {
                            phienAmList.append(String(char))
                        }
                    }
                    translatedWords.append(hasPhienAm ? phienAmList.joined(separator: " ") : token)
                } else {
                    translatedWords.append(token)
                }
            }
        }
        
        return postProcessText(translatedWords.joined(separator: " "))
    }
    
    private struct NameCandidate {
        let range: Range<Int>
        let length: Int
    }

    private static func isAlphanumeric(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private static func isASCIIAlphanumeric(_ char: Character) -> Bool {
        guard char.unicodeScalars.count == 1,
              let scalar = char.unicodeScalars.first else { return false }
        return (scalar.value >= 48 && scalar.value <= 57)
            || (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
    }

    private static func asciiAlphanumericRunEnd(in chars: [Character], from start: Int, upperBound: Int) -> Int {
        var end = start
        while end < upperBound && isASCIIAlphanumeric(chars[end]) {
            end += 1
        }
        return end
    }

    private static func tokenize(_ text: String, bookId: String?) -> [String] {
        let chars = Array(text)
        let length = chars.count
        guard length > 0 else { return [] }
        
        let isPronounsEnabled = UserDefaults.standard.bool(forKey: "isTranslationPronounsEnabled")
        let isLuatNhanEnabled = UserDefaults.standard.bool(forKey: "isTranslationLuatNhanEnabled")
        
        let names = TranslationManager.shared.namesDict
        let customNames = TranslationManager.shared.customNamesDict
        let deletedNames = TranslationManager.shared.deletedNames
        let pronouns = isPronounsEnabled ? TranslationManager.shared.pronounsDict : nil
        let luatNhan = isLuatNhanEnabled ? TranslationManager.shared.luatNhanDict : nil
        let vp = TranslationManager.shared.vietPhraseDict
        let customVP = TranslationManager.shared.customVietPhraseDict
        let deletedVP = TranslationManager.shared.deletedVietPhrase
        
        var bookVP: TrieDictionary? = nil
        var bookNames: TrieDictionary? = nil
        if let bid = bookId {
            let bookDicts = TranslationManager.shared.getBookDictionaries(for: bid)
            bookVP = bookDicts.vietPhrase
            bookNames = bookDicts.names
        }
        
        // --- BƯỚC 1: TÌM TẤT CẢ ỨNG VIÊN NAME TRÊN TOÀN CÂU ---
        var candidates: [NameCandidate] = []
        var i = 0
        while i < length {
            if isASCIIAlphanumeric(chars[i]) {
                i = asciiAlphanumericRunEnd(in: chars, from: i, upperBound: length)
                continue
            }

            let limit = min(length - i, 20)
            let checkText = String(chars[i..<(i + limit)])
            
            var maxNameLen = 0
            
            // 1. Book Names
            if let bookNames = bookNames,
               let match = bookNames.findLongestMatch(text: checkText, startIndex: 0) {
                maxNameLen = max(maxNameLen, match.length)
            }
            
            // 2. Custom Names
            if let customNames = customNames,
               let match = customNames.findLongestMatch(text: checkText, startIndex: 0) {
                maxNameLen = max(maxNameLen, match.length)
            }
            
            // 3. Base Names
            if let names = names,
               let match = names.findLongestMatch(text: checkText, startIndex: 0) {
                let matchedStr = String(chars[i..<(i + match.length)])
                if !deletedNames.contains(matchedStr) {
                    maxNameLen = max(maxNameLen, match.length)
                }
            }
            
            // 4. Pronouns
            if let pronouns = pronouns,
               let match = pronouns.findLongestMatch(text: checkText, startIndex: 0) {
                maxNameLen = max(maxNameLen, match.length)
            }
            
            // 5. LuatNhan
            if let luatNhan = luatNhan,
               let match = luatNhan.findLongestMatch(text: checkText, startIndex: 0) {
                maxNameLen = max(maxNameLen, match.length)
            }
            
            if maxNameLen > 0 {
                candidates.append(NameCandidate(range: i..<(i + maxNameLen), length: maxNameLen))
            }
            i += 1
        }
        
        // --- BƯỚC 2: GIẢI QUYẾT TRANH CHẤP CHỒNG LẤN ---
        candidates.sort { c1, c2 in
            if c1.length != c2.length {
                return c1.length > c2.length
            }
            return c1.range.lowerBound < c2.range.lowerBound
        }
        
        var selectedNames: [NameCandidate] = []
        var occupiedIndices = Set<Int>()
        
        for candidate in candidates {
            var isOverlapping = false
            for idx in candidate.range {
                if occupiedIndices.contains(idx) {
                    isOverlapping = true
                    break
                }
            }
            
            if !isOverlapping {
                selectedNames.append(candidate)
                for idx in candidate.range {
                    occupiedIndices.insert(idx)
                }
            }
        }
        
        selectedNames.sort { $0.range.lowerBound < $1.range.lowerBound }
        
        // --- BƯỚC 3: PHÂN TÁCH CÁC VÙNG CÒN LẠI BẰNG VIETPHRASE & DẤU CÂU ---
        var output: [String] = []
        var currentIndex = 0
        
        while currentIndex < length {
            if isASCIIAlphanumeric(chars[currentIndex]) {
                let end = asciiAlphanumericRunEnd(in: chars, from: currentIndex, upperBound: length)
                output.append(String(chars[currentIndex..<end]))
                currentIndex = end
                continue
            }

            if let activeName = selectedNames.first(where: { $0.range.lowerBound == currentIndex }) {
                let matchedStr = String(chars[activeName.range])
                output.append(matchedStr)
                currentIndex = activeName.range.upperBound
                continue
            }
            
            let nextNameStart = selectedNames.first(where: { $0.range.lowerBound > currentIndex })?.range.lowerBound ?? length
            let maxLimit = nextNameStart - currentIndex
            let limit = min(maxLimit, 20)
            
            if limit > 0 {
                let checkText = String(chars[currentIndex..<(currentIndex + limit)])
                var longestVPLen = 0
                
                // 1. Book VietPhrase
                if let bookVP = bookVP,
                   let match = bookVP.findLongestMatch(text: checkText, startIndex: 0) {
                    longestVPLen = max(longestVPLen, match.length)
                }
                
                // 2. Custom VietPhrase
                if let customVP = customVP,
                   let match = customVP.findLongestMatch(text: checkText, startIndex: 0) {
                    longestVPLen = max(longestVPLen, match.length)
                }
                
                // 3. Base VietPhrase
                if let vp = vp,
                   let match = vp.findLongestMatch(text: checkText, startIndex: 0) {
                    let matchedStr = String(chars[currentIndex..<(currentIndex + match.length)])
                    if !deletedVP.contains(matchedStr) {
                        longestVPLen = max(longestVPLen, match.length)
                    }
                }
                
                if longestVPLen > 0 {
                    let matchedStr = String(chars[currentIndex..<(currentIndex + longestVPLen)])
                    output.append(matchedStr)
                    currentIndex += longestVPLen
                } else {
                    let char = chars[currentIndex]
                    if isChineseCharacter(char) {
                        output.append(String(char))
                        currentIndex += 1
                    } else {
                        // Tối ưu hóa phân tách dấu câu độc lập:
                        // Chỉ gom nhóm các chữ cái/chữ số Latin (Sto9, iOS, 100...)
                        if isAlphanumeric(char) {
                            var end = currentIndex + 1
                            while end < nextNameStart && isAlphanumeric(chars[end]) {
                                end += 1
                            }
                            let alphanumericStr = String(chars[currentIndex..<end])
                            output.append(alphanumericStr)
                            currentIndex = end
                        } else {
                            // Dấu câu hoặc khoảng trắng: chỉ gom nhóm các ký tự GIỐNG NHAU liên tiếp (ví dụ: .... hoặc ???)
                            var end = currentIndex + 1
                            while end < nextNameStart && chars[end] == char {
                                end += 1
                            }
                            let punctuationStr = String(chars[currentIndex..<end])
                            output.append(punctuationStr)
                            currentIndex = end
                        }
                    }
                }
            } else {
                currentIndex += 1
            }
        }
        
        return output
    }
    
    private static func isChineseCharacter(_ char: Character) -> Bool {
        guard let code = char.unicodeScalars.first?.value else { return false }
        return code >= 0x4E00 && code <= 0x9FFF
    }
    
    private static func chineseNumberToInt(_ numberStr: String) -> Int {
        if let val = Int(numberStr) {
            return val
        }
        
        let digits: [Character: Int] = [
            "零": 0, "〇": 0,
            "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
            "壹": 1, "贰": 2, "叁": 3, "肆": 4, "伍": 5,
            "陆": 6, "柒": 7, "捌": 8, "玖": 9
        ]
        
        var result = 0
        var temp = 0
        
        for char in numberStr {
            if let val = digits[char] {
                temp = val
            } else {
                switch char {
                case "十", "拾":
                    if temp == 0 { temp = 1 }
                    result += temp * 10
                    temp = 0
                case "百", "佰":
                    result += temp * 100
                    temp = 0
                case "千", "仟":
                    result += temp * 1000
                    temp = 0
                case "万":
                    result += temp
                    result *= 10000
                    temp = 0
                default:
                    if let digit = Int(String(char)) {
                        temp = digit
                    }
                }
            }
        }
        result += temp
        return result
    }
    
    private static func postProcessText(_ input: String) -> String {
        let lines = input.components(separatedBy: .newlines)
        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result = trimmedLines.joined(separator: "\n")
        
        let trimSpacesBefore = try! NSRegularExpression(pattern: #" +([,.?!\}\]>”’\):】])"#, options: [])
        result = trimSpacesBefore.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result), withTemplate: "$1")
        
        let trimSpacesAfter = try! NSRegularExpression(pattern: #"([\{\[\(“‘\(【]) +"#, options: [])
        result = trimSpacesAfter.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result), withTemplate: "$1")
        
        var nsString = result as NSString
        let capitalizeRegex = try! NSRegularExpression(pattern: #"(^\s*|[.!?“‘”’\[【-]\s*)(\p{Ll})"#, options: [.anchorsMatchLines])
        let matches = capitalizeRegex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
        
        let offset = 0
        for match in matches {
            if match.numberOfRanges == 3 {
                let range2 = match.range(at: 2)
                let actualRange = NSRange(location: range2.location + offset, length: range2.length)
                let char = nsString.substring(with: actualRange)
                let upper = char.uppercased()
                nsString = nsString.replacingCharacters(in: actualRange, with: upper) as NSString
            }
        }
        result = nsString as String
        
        // Giữ nguyên các dấu ngoặc kép cong (curly quotes) theo yêu cầu người dùng
        // result = result.replacingOccurrences(of: "“", with: "\"")
        // result = result.replacingOccurrences(of: "”", with: "\"")
        // result = result.replacingOccurrences(of: "‘", with: "\"")
        // result = result.replacingOccurrences(of: "’", with: "\"")
        
        let multiSpaces = try! NSRegularExpression(pattern: #" +"#, options: [])
        result = multiSpaces.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result), withTemplate: " ")
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public static func invalidateTOCRulesCache() {
        tocRulesLock.lock()
        defer { tocRulesLock.unlock() }
        cachedAllTOCRules = nil
        cachedTOCRules = nil
        cachedCompiledTOCRegexes = nil
    }

    public static func getDefaultTOCRules() -> [TOCRule] {
        return defaultTOCRules
    }

    public static func getAllTOCRules() -> [TOCRule] {
        tocRulesLock.lock()
        defer { tocRulesLock.unlock() }
        return getAllTOCRulesUnlocked()
    }

    public static func getActiveTOCRules() -> [TOCRule] {
        tocRulesLock.lock()
        defer { tocRulesLock.unlock() }
        return getActiveTOCRulesUnlocked()
    }

    public static func getCompiledActiveTOCRegexes() -> [NSRegularExpression] {
        tocRulesLock.lock()
        defer { tocRulesLock.unlock() }

        if let cachedRegexes = cachedCompiledTOCRegexes {
            return cachedRegexes
        }

        let active = getActiveTOCRulesUnlocked()
        let compiled = active.compactMap { try? NSRegularExpression(pattern: $0.rule, options: [.caseInsensitive]) }
        cachedCompiledTOCRegexes = compiled
        return compiled
    }

    private static func getAllTOCRulesUnlocked() -> [TOCRule] {
        if let cached = cachedAllTOCRules {
            return cached
        }
        let url = TranslationManager.shared.translateDirectory.appendingPathComponent("toc_rules.json")
        let all: [TOCRule]
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([TOCRule].self, from: data) {
            all = list
        } else {
            if !FileManager.default.fileExists(atPath: url.path) {
                if let data = try? JSONEncoder().encode(defaultTOCRules) {
                    try? data.write(to: url)
                }
            } else {
                AppLogger.shared.log("❌ Lỗi decode file toc_rules.json, fallback về defaultTOCRules")
            }
            all = defaultTOCRules
        }
        cachedAllTOCRules = all
        let active = all.filter { $0.enabled }
        cachedTOCRules = active
        cachedCompiledTOCRegexes = active.compactMap { try? NSRegularExpression(pattern: $0.rule, options: [.caseInsensitive]) }
        return all
    }

    private static func getActiveTOCRulesUnlocked() -> [TOCRule] {
        if let cached = cachedTOCRules {
            return cached
        }
        let all = getAllTOCRulesUnlocked()
        let active = all.filter { $0.enabled }
        cachedTOCRules = active
        cachedCompiledTOCRegexes = active.compactMap { try? NSRegularExpression(pattern: $0.rule, options: [.caseInsensitive]) }
        return active
    }
    
    @discardableResult
    public static func saveTOCRules(_ rules: [TOCRule]) -> Bool {
        tocRulesLock.lock()
        defer { tocRulesLock.unlock() }

        let url = TranslationManager.shared.translateDirectory.appendingPathComponent("toc_rules.json")
        guard let data = try? JSONEncoder().encode(rules) else { return false }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ Lỗi ghi file toc_rules.json: \(error.localizedDescription)")
            return false
        }

        let enabledRules = rules.filter { $0.enabled }
        cachedAllTOCRules = rules
        cachedTOCRules = enabledRules
        cachedCompiledTOCRegexes = enabledRules.compactMap { try? NSRegularExpression(pattern: $0.rule, options: [.caseInsensitive]) }

        clearChapterTitleCacheUnlocked()
        return true
    }

    @discardableResult
    public static func resetTOCRulesToDefault() -> Bool {
        return saveTOCRules(defaultTOCRules)
    }

    public static func validateTOCRulePattern(_ pattern: String) -> String? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Chuỗi mẫu Regex không được để trống." }
        if trimmed.count > 250 { return "Độ dài Regex không được vượt quá 250 ký tự." }
        do {
            _ = try NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])
            return nil
        } catch {
            return "Cú pháp Regex không hợp lệ: \(error.localizedDescription)"
        }
    }

    public static func validateImportedTOCRules(_ data: Data, maxSizeBytes: Int = 500 * 1024, maxRuleCount: Int = 100) -> Result<[TOCRule], TOCRuleImportError> {
        if data.count > maxSizeBytes {
            return .failure(.fileTooLarge(maxKB: maxSizeBytes / 1024))
        }

        guard let list = try? JSONDecoder().decode([TOCRule].self, from: data) else {
            return .failure(.invalidJSON)
        }

        if list.count > maxRuleCount {
            return .failure(.tooManyRules(count: list.count, max: maxRuleCount))
        }

        var seenIDs = Set<String>()
        for (index, item) in list.enumerated() {
            let trimmedID = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedID.isEmpty {
                return .failure(.emptyID(index: index))
            }
            if trimmedID.count > 100 {
                return .failure(.idTooLong(index: index))
            }
            if trimmedName.isEmpty {
                return .failure(.emptyName(index: index, id: trimmedID))
            }
            if trimmedName.count > 100 {
                return .failure(.nameTooLong(index: index))
            }
            if seenIDs.contains(trimmedID) {
                return .failure(.duplicateID(id: trimmedID))
            }
            seenIDs.insert(trimmedID)

            if let patternError = validateTOCRulePattern(item.rule) {
                return .failure(.invalidRegex(ruleName: item.name, reason: patternError))
            }
        }

        return .success(list)
    }

    public static func calculateImportPreview(current: [TOCRule], imported: [TOCRule], isMerge: Bool) -> TOCImportPreview {
        let importedCount = imported.count
        let importedIDs = Set(imported.map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) })

        if isMerge {
            let existingIDs = Set(current.map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) })
            let updateCount = imported.filter { existingIDs.contains($0.id.trimmingCharacters(in: .whitespacesAndNewlines)) }.count
            let newCount = imported.filter { !existingIDs.contains($0.id.trimmingCharacters(in: .whitespacesAndNewlines)) }.count
            let preservedCount = current.filter { !importedIDs.contains($0.id.trimmingCharacters(in: .whitespacesAndNewlines)) }.count
            return TOCImportPreview(
                importedCount: importedCount,
                newCount: newCount,
                updateCount: updateCount,
                preservedCount: preservedCount,
                restoredDefaultCount: 0
            )
        } else {
            let defaultRules = defaultTOCRules
            let restoredDefaultCount = defaultRules.filter { !importedIDs.contains($0.id.trimmingCharacters(in: .whitespacesAndNewlines)) }.count
            return TOCImportPreview(
                importedCount: importedCount,
                newCount: 0,
                updateCount: 0,
                preservedCount: 0,
                restoredDefaultCount: restoredDefaultCount
            )
        }
    }

    public static func mergeTOCRules(current: [TOCRule], imported: [TOCRule]) -> [TOCRule] {
        var result = current
        var existingIndexMap = [String: Int]()
        for (idx, rule) in current.enumerated() {
            existingIndexMap[rule.id] = idx
        }

        var newRulesToAppend = [TOCRule]()
        for impRule in imported {
            let sanitized = TOCRule(
                id: impRule.id.trimmingCharacters(in: .whitespacesAndNewlines),
                name: impRule.name.trimmingCharacters(in: .whitespacesAndNewlines),
                rule: impRule.rule.trimmingCharacters(in: .whitespacesAndNewlines),
                example: impRule.example?.trimmingCharacters(in: .whitespacesAndNewlines),
                enabled: impRule.enabled
            )
            if let idx = existingIndexMap[sanitized.id] {
                result[idx] = sanitized
            } else {
                newRulesToAppend.append(sanitized)
            }
        }

        result.append(contentsOf: newRulesToAppend)
        return result
    }

    public static func replaceTOCRules(imported: [TOCRule]) -> [TOCRule] {
        var result = imported.map { impRule in
            TOCRule(
                id: impRule.id.trimmingCharacters(in: .whitespacesAndNewlines),
                name: impRule.name.trimmingCharacters(in: .whitespacesAndNewlines),
                rule: impRule.rule.trimmingCharacters(in: .whitespacesAndNewlines),
                example: impRule.example?.trimmingCharacters(in: .whitespacesAndNewlines),
                enabled: impRule.enabled
            )
        }
        let importedIDs = Set(result.map(\.id))

        for defaultRule in defaultTOCRules {
            if !importedIDs.contains(defaultRule.id) {
                result.append(defaultRule)
            }
        }

        return result
    }

    public static func isMatchingTOCRule(_ line: String, compiledRegexes: [NSRegularExpression]? = nil) -> Bool {
        let regexes = compiledRegexes ?? getCompiledActiveTOCRegexes()
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        for regex in regexes {
            if regex.firstMatch(in: line, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    public static func isMatchingTOCRule(_ line: String, rules: [TOCRule]) -> Bool {
        let enabledRules = rules.filter { $0.enabled }
        let compiled = enabledRules.compactMap { try? NSRegularExpression(pattern: $0.rule, options: [.caseInsensitive]) }
        return isMatchingTOCRule(line, compiledRegexes: compiled)
    }

    public static func isChapterHeaderLine(_ line: String, compiledTOCRegexes: [NSRegularExpression]? = nil) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 100 else { return false }

        // 1. Configurable TOC Rules (matching raw line)
        if isMatchingTOCRule(line, compiledRegexes: compiledTOCRegexes) {
            return true
        }

        // 2. Legacy Vietnamese / English chapter keywords (matching trimmed line)
        let chapterKeywords = ["chương", "chapter", "quyển", "tập", "tiết", "hồi", "phần", "tự", "vĩ thanh", "mở đầu", "lời mở đầu", "phiên ngoại", "mục", "第"]
        let lowerTrimmed = trimmed.lowercased()
        for keyword in chapterKeywords {
            if lowerTrimmed.hasPrefix(keyword) {
                return true
            }
        }

        // 3. Legacy numeric fallback (strictly unindented)
        let hasIndentation = line.hasPrefix(" ") || line.hasPrefix("\t") || line.hasPrefix("　")
        if !hasIndentation {
            let firstWord = lowerTrimmed.components(separatedBy: .whitespaces).first ?? ""
            if firstWord.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil {
                return true
            }
        }

        return false
    }

    private static func clearChapterTitleCacheUnlocked() {
        cacheLock.lock()
        chapterTitleCacheDict.removeAll()
        cacheLock.unlock()
    }
    
    public static func clearChapterTitleCache(for bookId: String) {
        cacheLock.lock()
        chapterTitleCacheDict.removeValue(forKey: bookId)
        cacheLock.unlock()
    }
    
    public static func clearChapterTitleCache() {
        cacheLock.lock()
        chapterTitleCacheDict.removeAll()
        cacheLock.unlock()
    }
    
    public static func clearCache() {
        translationCache.removeAllObjects()
        clearChapterTitleCache()
        invalidateTOCRulesCache()
    }

    private static func buildTranslationSpans(
        original: String,
        translated: String,
        bookId: String?
    ) -> [TranslationSpan] {
        guard !original.isEmpty, !translated.isEmpty else { return [] }
        if original == translated {
            return untranslatedTextResult(original).spans
        }

        let translatedNSString = translated as NSString
        let tokens = getTranslationTokens(for: original, bookId: bookId)
        var cursor = 0
        var spans: [TranslationSpan] = []

        for token in tokens {
            let candidate = postProcessText(token.translatedText)
            guard !candidate.isEmpty, cursor <= translatedNSString.length else { continue }

            let searchRange = NSRange(location: cursor, length: translatedNSString.length - cursor)
            guard let translatedRange = findTranslatedTokenRange(
                candidate,
                in: translated,
                searchRange: searchRange
            ) else {
                return []
            }

            spans.append(TranslationSpan(
                originalLocation: token.originalOffset,
                originalLength: token.originalLength,
                translatedLocation: translatedRange.location,
                translatedLength: translatedRange.length
            ))
            cursor = NSMaxRange(translatedRange)
        }

        return spans
    }

    private static func findTranslatedTokenRange(
        _ tokenText: String,
        in translated: String,
        searchRange: NSRange
    ) -> NSRange? {
        let translatedNSString = translated as NSString
        let literalRange = translatedNSString.range(
            of: tokenText,
            options: [.caseInsensitive],
            range: searchRange
        )
        if literalRange.location != NSNotFound {
            return literalRange
        }

        let parts = tokenText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        let pattern = parts
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: #"\s+"#)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return regex.firstMatch(in: translated, options: [], range: searchRange)?.range
    }
    
    // MARK: - Tokenizer for interactive reader selection
    
    public static func getTranslationTokens(for sentence: String, bookId: String?) -> [TranslationWordToken] {
        var converted = ""
        for char in sentence {
            converted.append(punctuationMapping[char] ?? String(char))
        }
        
        let tokens = tokenize(converted, bookId: bookId)
        var wordTokens: [TranslationWordToken] = []
        let phienAm = TranslationManager.shared.phienAmMap
        
        var currentIndex = 0
        let chars = Array(sentence)
        let length = chars.count
        
        for token in tokens {
            let tokenLen = token.count
            guard currentIndex + tokenLen <= length else { break }
            let originalText = String(chars[currentIndex..<(currentIndex + tokenLen)])
            
            let translatedToken: String
            let isMatched: Bool
            
            let rawTranslation = translateMeta(token, bookId: bookId)
            if rawTranslation == token {
                isMatched = false
                if token.count == 1, isChineseCharacter(token.first!) {
                    translatedToken = phienAm[token] ?? token
                } else if containsChinese(token) {
                    var phienAmList: [String] = []
                    for c in token {
                        phienAmList.append(phienAm[String(c)] ?? String(c))
                    }
                    translatedToken = phienAmList.joined(separator: " ")
                } else {
                    translatedToken = token
                }
            } else {
                isMatched = true
                translatedToken = getFirstMeaning(of: rawTranslation)
            }
            
            let trimmedTrans = translatedToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if isMatched || !trimmedTrans.isEmpty || !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                wordTokens.append(TranslationWordToken(
                    originalText: originalText,
                    translatedText: isMatched ? trimmedTrans : (trimmedTrans.isEmpty ? originalText : trimmedTrans),
                    originalOffset: currentIndex,
                    originalLength: tokenLen
                ))
            }
            
            currentIndex += tokenLen
        }
        
        return wordTokens
    }
    
    public static func getSentenceRanges(in text: String) -> [SentenceRange] {
        var tempText = text
        tempText = tempText.replacingOccurrences(of: "...", with: ",,,")
        tempText = tempText.replacingOccurrences(of: "..", with: ",,")
        
        let pattern = #"[^。！？\n\r.!?]+[。！？\n\r.!?]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [SentenceRange(text: text, range: NSRange(location: 0, length: (text as NSString).length))]
        }
        
        let nsText = text as NSString
        let nsTempText = tempText as NSString
        let matches = regex.matches(in: tempText, options: [], range: NSRange(location: 0, length: nsTempText.length))
        
        return matches.map { match in
            let matchRange = match.range
            let substring = nsText.substring(with: matchRange)
            return SentenceRange(text: substring, range: matchRange)
        }
    }
    
    public static func snapToToken(
        sentence: String,
        selectionOffset: Int,
        selectionLength: Int,
        bookId: String?
    ) -> (offset: Int, length: Int) {
        let tokens = getTranslationTokens(for: sentence, bookId: bookId)
        guard !tokens.isEmpty else { return (selectionOffset, selectionLength) }
        
        let selectionEnd = selectionOffset + selectionLength
        var overlappingTokens: [TranslationWordToken] = []
        
        for token in tokens {
            let tokenEnd = token.originalOffset + token.originalLength
            let maxStart = max(token.originalOffset, selectionOffset)
            let minEnd = min(tokenEnd, selectionEnd)
            if maxStart < minEnd {
                overlappingTokens.append(token)
            }
        }
        
        if let first = overlappingTokens.first, let last = overlappingTokens.last {
            let start = first.originalOffset
            let end = last.originalOffset + last.originalLength
            return (start, end - start)
        }
        
        return (selectionOffset, selectionLength)
    }
}

public struct TranslationWordToken: Identifiable, Hashable {
    public var id = UUID()
    public let originalText: String
    public let translatedText: String
    public let originalOffset: Int
    public let originalLength: Int
    
    public init(originalText: String, translatedText: String, originalOffset: Int, originalLength: Int) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.originalOffset = originalOffset
        self.originalLength = originalLength
    }
}

public struct TranslationSpan: Codable, Equatable, Hashable, Sendable {
    public let originalLocation: Int
    public let originalLength: Int
    public let translatedLocation: Int
    public let translatedLength: Int

    public init(
        originalLocation: Int,
        originalLength: Int,
        translatedLocation: Int,
        translatedLength: Int
    ) {
        self.originalLocation = originalLocation
        self.originalLength = originalLength
        self.translatedLocation = translatedLocation
        self.translatedLength = translatedLength
    }

    public var originalRange: NSRange {
        NSRange(location: originalLocation, length: originalLength)
    }

    public var translatedRange: NSRange {
        NSRange(location: translatedLocation, length: translatedLength)
    }
}

public struct TranslatedTextResult: Codable, Equatable, Sendable {
    public let text: String
    public let spans: [TranslationSpan]

    public init(text: String, spans: [TranslationSpan]) {
        self.text = text
        self.spans = spans
    }
}

public struct SentenceRange {
    public let text: String
    public let range: NSRange
    
    public init(text: String, range: NSRange) {
        self.text = text
        self.range = range
    }
}
