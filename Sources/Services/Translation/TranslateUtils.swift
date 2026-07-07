import Foundation

public struct TOCRule: Codable, Identifiable {
    public let id: String
    public let name: String
    public let rule: String
    public let example: String?
    public var enabled: Bool
}

public final class TranslateUtils {
    
    private static let translationCache = NSCache<NSString, NSString>()
    
    public static func getFirstMeaning(of rawTranslation: String) -> String {
        if let idx = rawTranslation.firstIndex(where: { $0 == "/" || $0 == "¦" }) {
            return String(rawTranslation[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return rawTranslation
    }
    
    // Default TOC rules mapped from user preference
    private static let defaultTOCRules = [
        TOCRule(id: "db9e3730282741c9a42f01184e4bc68c", name: "x.第x章", rule: #"^\d{1,4}\.第[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}章.{0,50}$"#, example: "1.第1章", enabled: true),
        TOCRule(id: "rule0", name: "目录(去空白)", rule: #"(?<=[　\s])(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和]))).{0,30}$"#, example: "第一章 假装第一章前面 có khoảng trắng", enabled: true),
        TOCRule(id: "rule1", name: "目录", rule: #"^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$"#, example: "第一章", enabled: true),
        TOCRule(id: "rule3", name: "目录(古典、轻小说备用)", rule: #"^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|话|篇(?!张))).{0,30}$"#, example: "第一回", enabled: true),
        TOCRule(id: "rule10", name: "特殊符号 序号 标题", rule: #"(?<=[\s　])[【〔〖「『〈［\[](?:第|[Cc]hapter)[\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}[章节].{0,20}$"#, example: "【第一章", enabled: true)
    ]
    
    private static let punctuationMapping: [Character: String] = [
        "。": ". ", "．": ". ", "，": ", ", "、": ", ", "；": "; ", "：": ": ", "！": "! ", "？": "? ", "…": "... ",
        "（": "【", "）": "】",
        "〔": "【", "〕": "】",
        "【": "【", "】": "】",
        "〖": "【", "〗": "】",
        "〘": "【", "〙": "】",
        "〚": "【", "〛": "】",
        "『": "【", "』": "】",
        "《": "【", "》": "】",
        "〈": "【", "〉": "】",
        "｛": "【", "｝": "】",
        "「": "【", "」": "】",
        "(": "【", ")": "】",
        "{": "【", "}": "】",
        "～": "~", "—": "-", "　": " "
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
        "篇": "篇",
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
    
    public static func translateMeta(_ text: String?, bookId: String? = nil) -> String {
        return translateText(text, isMeta: true, bookId: bookId)
    }
    
    public static func translateContent(_ text: String?, bookId: String? = nil) -> String {
        return translateText(text, isMeta: false, bookId: bookId)
    }
    
    public static func translateChapterTitle(_ text: String, bookId: String? = nil) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        
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
                
                return "\(translatedPre)\(unitVal) \(numberVal)\(translatedPost)".trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        if let match = titleNumberRegex.firstMatch(in: trimmed, options: [], range: range),
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
            
            return "\(translatedPre)\(unitVal) \(numberVal)\(translatedPost)".trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return translateMeta(trimmed, bookId: bookId)
    }
    
    private static func translateText(_ text: String?, isMeta: Bool, bookId: String?) -> String {
        guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text ?? "" }
        
        // Nếu từ điển chưa load xong, trả về văn bản gốc và không lưu cache dịch
        guard TranslationManager.shared.isVietPhraseLoaded else {
            return text
        }
        
        let md5 = JSCrypto.md5(text)
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
        
        var translatedWords: [String] = []
        let names = TranslationManager.shared.namesDict
        let pronouns = TranslationManager.shared.pronounsDict
        let luatNhan = TranslationManager.shared.luatNhanDict
        let vp = TranslationManager.shared.vietPhraseDict
        let phienAm = TranslationManager.shared.phienAmMap
        
        var bookVP: TrieDictionary? = nil
        var bookNames: TrieDictionary? = nil
        if let bid = bookId {
            let bookDicts = TranslationManager.shared.getBookDictionaries(for: bid)
            bookVP = bookDicts.vietPhrase
            bookNames = bookDicts.names
        }
        
        for token in tokens {
            if token == "的" || token == "了" || token == "著" {
                continue
            }
            
            var translation: String? = nil
            
            if let bookNames = bookNames,
               let match = bookNames.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            if translation == nil,
               let names = names,
               let match = names.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            if translation == nil,
               let pronouns = pronouns,
               let match = pronouns.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            if translation == nil,
               let luatNhan = luatNhan,
               let match = luatNhan.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            if translation == nil,
               let bookVP = bookVP,
               let match = bookVP.findLongestMatch(text: token, startIndex: 0),
               match.length == token.count {
                translation = match.value
            }
            
            if translation == nil,
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
                } else {
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
                }
            }
        }
        
        return postProcessText(translatedWords.joined(separator: " "))
    }
    
    private static func tokenize(_ text: String, bookId: String?) -> [String] {
        var output: [String] = []
        let chars = Array(text)
        let length = chars.count
        var currentIndex = 0
        
        let names = TranslationManager.shared.namesDict
        let pronouns = TranslationManager.shared.pronounsDict
        let luatNhan = TranslationManager.shared.luatNhanDict
        let vp = TranslationManager.shared.vietPhraseDict
        
        var bookVP: TrieDictionary? = nil
        var bookNames: TrieDictionary? = nil
        if let bid = bookId {
            let bookDicts = TranslationManager.shared.getBookDictionaries(for: bid)
            bookVP = bookDicts.vietPhrase
            bookNames = bookDicts.names
        }
        
        while currentIndex < length {
            var longestMatchLen = 0
            
            let limit = min(length - currentIndex, 20)
            let checkText = String(chars[currentIndex..<(currentIndex + limit)])
            
            if let bookNames = bookNames,
               let match = bookNames.findLongestMatch(text: checkText, startIndex: 0) {
                longestMatchLen = match.length
            }
            
            if let names = names,
               let match = names.findLongestMatch(text: checkText, startIndex: 0) {
                if match.length > longestMatchLen {
                    longestMatchLen = match.length
                }
            }
            
            if let pronouns = pronouns,
               let match = pronouns.findLongestMatch(text: checkText, startIndex: 0) {
                if match.length > longestMatchLen {
                    longestMatchLen = match.length
                }
            }
            
            if let luatNhan = luatNhan,
               let match = luatNhan.findLongestMatch(text: checkText, startIndex: 0) {
                if match.length > longestMatchLen {
                    longestMatchLen = match.length
                }
            }
            
            if let bookVP = bookVP,
               let match = bookVP.findLongestMatch(text: checkText, startIndex: 0) {
                if match.length > longestMatchLen {
                    longestMatchLen = match.length
                }
            }
            
            if let vp = vp,
               let match = vp.findLongestMatch(text: checkText, startIndex: 0) {
                if match.length > longestMatchLen {
                    longestMatchLen = match.length
                }
            }
            
            if longestMatchLen > 0 {
                let matchedStr = String(chars[currentIndex..<(currentIndex + longestMatchLen)])
                output.append(matchedStr)
                currentIndex += longestMatchLen
            } else {
                let char = chars[currentIndex]
                if isChineseCharacter(char) {
                    output.append(String(char))
                    currentIndex += 1
                } else {
                    var end = currentIndex + 1
                    while end < length && !isChineseCharacter(chars[end]) {
                        end += 1
                    }
                    let nonChineseStr = String(chars[currentIndex..<end])
                    output.append(nonChineseStr)
                    currentIndex = end
                }
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
        
        result = result.replacingOccurrences(of: "“", with: "\"")
        result = result.replacingOccurrences(of: "”", with: "\"")
        result = result.replacingOccurrences(of: "‘", with: "\"")
        result = result.replacingOccurrences(of: "’", with: "\"")
        
        let multiSpaces = try! NSRegularExpression(pattern: #" +"#, options: [])
        result = multiSpaces.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result), withTemplate: " ")
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public static func getActiveTOCRules() -> [TOCRule] {
        let url = TranslationManager.shared.translateDirectory.appendingPathComponent("toc_rules.json")
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([TOCRule].self, from: data) {
            return list.filter { $0.enabled }
        }
        
        if !FileManager.default.fileExists(atPath: url.path) {
            if let data = try? JSONEncoder().encode(defaultTOCRules) {
                try? data.write(to: url)
            }
        }
        
        return defaultTOCRules.filter { $0.enabled }
    }
    
    public static func saveTOCRules(_ rules: [TOCRule]) {
        let url = TranslationManager.shared.translateDirectory.appendingPathComponent("toc_rules.json")
        if let data = try? JSONEncoder().encode(rules) {
            try? data.write(to: url)
        }
    }
    
    public static func clearCache() {
        translationCache.removeAllObjects()
    }
    
    // MARK: - Tokenizer for interactive reader selection
    
    public static func getTranslationTokens(for sentence: String, bookId: String?) -> [TranslationWordToken] {
        var output: [TranslationWordToken] = []
        let chars = Array(sentence)
        let length = chars.count
        var currentIndex = 0
        
        let names = TranslationManager.shared.namesDict
        let pronouns = TranslationManager.shared.pronounsDict
        let luatNhan = TranslationManager.shared.luatNhanDict
        let vp = TranslationManager.shared.vietPhraseDict
        let phienAm = TranslationManager.shared.phienAmMap
        
        var bookVP: TrieDictionary? = nil
        var bookNames: TrieDictionary? = nil
        if let bid = bookId {
            let bookDicts = TranslationManager.shared.getBookDictionaries(for: bid)
            bookVP = bookDicts.vietPhrase
            bookNames = bookDicts.names
        }
        
        while currentIndex < length {
            var longestMatchLen = 0
            
            let limit = min(length - currentIndex, 20)
            let checkText = String(chars[currentIndex..<(currentIndex + limit)])
            
            if let bookNames = bookNames,
               let match = bookNames.findLongestMatch(text: checkText, startIndex: 0) {
                longestMatchLen = match.length
            }
            
            if let names = names,
               let match = names.findLongestMatch(text: checkText, startIndex: 0) {
                if match.length > longestMatchLen {
                    longestMatchLen = match.length
                }
            }
            
            if let pronouns = pronouns,
               let match = pronouns.findLongestMatch(text: checkText, startIndex: 0) {
                if match.length > longestMatchLen {
                    longestMatchLen = match.length
                }
            }
            
            if let luatNhan = luatNhan,
               let match = luatNhan.findLongestMatch(text: checkText, startIndex: 0) {
                if match.length > longestMatchLen {
                    longestMatchLen = match.length
                }
            }
            
            if let bookVP = bookVP,
               let match = bookVP.findLongestMatch(text: checkText, startIndex: 0) {
                if match.length > longestMatchLen {
                    longestMatchLen = match.length
                }
            }
            
            if let vp = vp,
               let match = vp.findLongestMatch(text: checkText, startIndex: 0) {
                if match.length > longestMatchLen {
                    longestMatchLen = match.length
                }
            }
            
            let tokenStr: String
            let matchedLen: Int
            
            if longestMatchLen > 0 {
                tokenStr = String(chars[currentIndex..<(currentIndex + longestMatchLen)])
                matchedLen = longestMatchLen
            } else {
                let char = chars[currentIndex]
                if isChineseCharacter(char) {
                    tokenStr = String(char)
                    matchedLen = 1
                } else {
                    var end = currentIndex + 1
                    while end < length && !isChineseCharacter(chars[end]) {
                        end += 1
                    }
                    tokenStr = String(chars[currentIndex..<end])
                    matchedLen = end - currentIndex
                }
            }
            
            let translatedToken: String
            let isMatched: Bool
            
            if tokenStr == "的" || tokenStr == "了" || tokenStr == "著" {
                translatedToken = ""
                isMatched = false
            } else {
                let rawTranslation = translateMeta(tokenStr, bookId: bookId)
                if rawTranslation == tokenStr {
                    isMatched = false
                    if tokenStr.count == 1, isChineseCharacter(tokenStr.first!) {
                        translatedToken = phienAm[tokenStr] ?? tokenStr
                    } else {
                        var phienAmList: [String] = []
                        for c in tokenStr {
                            phienAmList.append(phienAm[String(c)] ?? String(c))
                        }
                        translatedToken = phienAmList.joined(separator: " ")
                    }
                } else {
                    isMatched = true
                    translatedToken = TranslateUtils.getFirstMeaning(of: rawTranslation)
                }
            }
            
            let trimmedTrans = translatedToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if isMatched || !trimmedTrans.isEmpty || !tokenStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.append(TranslationWordToken(
                    originalText: tokenStr,
                    translatedText: isMatched ? trimmedTrans : (trimmedTrans.isEmpty ? tokenStr : trimmedTrans),
                    originalOffset: currentIndex,
                    originalLength: matchedLen
                ))
            }
            
            currentIndex += matchedLen
        }
        
        return output
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

public struct SentenceRange {
    public let text: String
    public let range: NSRange
    
    public init(text: String, range: NSRange) {
        self.text = text
        self.range = range
    }
}
