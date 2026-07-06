import Foundation

enum PreprocessorSettingKey {
    static let numericNormalizationEnabled = "preprocessorNumericNormalizationEnabled"
    static let dictionaryReplacementEnabled = "preprocessorDictionaryReplacementEnabled"
    static let transliterationEnabled = "preprocessorTransliterationEnabled"
    static let debugLoggingEnabled = "preprocessorDebugLoggingEnabled"
}


private enum PreprocessorConfig {
    static let debugLoggingKey = PreprocessorSettingKey.debugLoggingEnabled
    static let transliterationCacheLimit = 4096
    static let transliterationCacheEvictionBatch = 512
}


private struct PreprocessorRuntimeConfig {
    let numericNormalizationEnabled: Bool
    let dictionaryReplacementEnabled: Bool
    let transliterationEnabled: Bool

    static func load() -> PreprocessorRuntimeConfig {
        let defaults = UserDefaults.standard

        func boolValue(for key: String, fallback defaultValue: Bool) -> Bool {
            guard defaults.object(forKey: key) != nil else { return defaultValue }
            return defaults.bool(forKey: key)
        }

        return PreprocessorRuntimeConfig(
            numericNormalizationEnabled: boolValue(for: PreprocessorSettingKey.numericNormalizationEnabled, fallback: true),
            dictionaryReplacementEnabled: boolValue(for: PreprocessorSettingKey.dictionaryReplacementEnabled, fallback: true),
            transliterationEnabled: boolValue(for: PreprocessorSettingKey.transliterationEnabled, fallback: true)
        )
    }
}


enum PreprocessorRegex {
    static let url = try! NSRegularExpression(pattern: #"https?://\S+"#, options: [])
    static let www = try! NSRegularExpression(pattern: #"www\.\S+"#, options: [])
    static let email = try! NSRegularExpression(pattern: #"\S+@\S+\.\S+"#, options: [])

    static let doubleQuotes = try! NSRegularExpression(pattern: #"[\"“”„‟«»＂″]"#, options: [])
    static let singleQuotes = try! NSRegularExpression(pattern: #"['’‘‚‛＇‹›]"#, options: [])
    static let dashes = try! NSRegularExpression(pattern: #"[–—−]"#, options: [])
    static let ellipsis = try! NSRegularExpression(pattern: #"\.{3,}"#, options: [])
    static let repeatedSentencePunctuation = try! NSRegularExpression(pattern: #"([!?.])\1+"#, options: [])

    static let emoji = try! NSRegularExpression(
        pattern: "[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F900}-\u{1F9FF}]|[\u{1F018}-\u{1F270}]|[\u{238C}-\u{2454}]|[\u{20D0}-\u{20FF}]|\u{FE0F}|\u{200D}",
        options: []
    )
    static let bracketQuotes = try! NSRegularExpression(pattern: #"[']"#, options: [])
    static let doubleQuoteToSpace = try! NSRegularExpression(pattern: #"["“”]"#, options: [])
    static let whitespaceBeforePeriod = try! NSRegularExpression(pattern: #"\s—"#, options: [])
    static let underscoreWord = try! NSRegularExpression(pattern: #"\b_\b"#, options: [])
    static let nonDigitDash = try! NSRegularExpression(pattern: #"(?<!\d)-(?!\d)"#, options: [])
    static let allowedChars = try! NSRegularExpression(pattern: #"[^\u0000-\u024F\u1E00-\u1EFF\u3000-\u303F\u3040-\u30FF\uFF00-\uFFEF]"#, options: [])
    static let whitespaceCollapse = try! NSRegularExpression(pattern: #"\s+"#, options: [])

    static let thousandsSeparatedNumber = try! NSRegularExpression(pattern: #"(\d{1,3}(?:\.\d{3})+)(?=\s|$|[^\d.,])"#, options: [])

    static let yearRange = try! NSRegularExpression(pattern: #"(\d{4})\s*[-–—]\s*(\d{4})"#, options: [])
    static let dateRangeWithDayPrefix = try! NSRegularExpression(pattern: #"ngày\s+(\d{1,2})\s*[-–—]\s*(\d{1,2})\s*[/-]\s*(\d{1,2})(?:\s*[/-]\s*(\d{4}))?"#, options: [])
    static let dateRange = try! NSRegularExpression(pattern: #"(\d{1,2})\s*[-–—]\s*(\d{1,2})\s*[/-]\s*(\d{1,2})(?:\s*[/-]\s*(\d{4}))?"#, options: [])
    static let monthRangeYear = try! NSRegularExpression(pattern: #"(\d{1,2})\s*[-–—]\s*(\d{1,2})\s*[/-]\s*(\d{4})"#, options: [])
    static let sinhDate = try! NSRegularExpression(pattern: #"(Sinh|sinh)\s+ngày\s+(\d{1,2})[/-](\d{1,2})[/-](\d{4})"#, options: [])
    static let fullDate = try! NSRegularExpression(pattern: #"(\d{1,2})[/-](\d{1,2})[/-](\d{4})"#, options: [])
    static let monthYear = try! NSRegularExpression(pattern: #"(?:tháng\s+)?(\d{1,2})\s*[/-]\s*(\d{4})(?![\/-]\d)"#, options: [])
    static let dayMonth = try! NSRegularExpression(pattern: #"(\d{1,2})\s*[/-]\s*(\d{1,2})(?![\/-]\d)(?!\d+\s*%)"#, options: [])
    static let dayMonthWord = try! NSRegularExpression(pattern: #"(\d+)\s*tháng\s*(\d+)"#, options: [])
    static let monthOnly = try! NSRegularExpression(pattern: #"tháng\s*(\d+)"#, options: [])
    static let dayOnly = try! NSRegularExpression(pattern: #"ngày\s*(\d+)"#, options: [])
    static let timeHms = try! NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})(?::(\d{2}))?"#, options: [])
    static let timeCompactHM = try! NSRegularExpression(pattern: #"(\d{1,2})h(\d{2})(?![a-zà-ỹ])"#, options: [.caseInsensitive])
    static let timeCompactH = try! NSRegularExpression(pattern: #"(\d{1,2})h(?![a-zà-ỹ\d])"#, options: [.caseInsensitive])
    static let timeHourMinute = try! NSRegularExpression(pattern: #"(\d+)\s*giờ\s*(\d+)\s*phút"#, options: [])
    static let timeHourOnly = try! NSRegularExpression(pattern: #"(\d+)\s*giờ(?!\s*\d)"#, options: [])

    static let romanChars = try! NSRegularExpression(pattern: #"^[IVXLCDM]+$"#, options: [])
    static let romanInvalidRepeat = try! NSRegularExpression(pattern: #"([IVXLCD])\1{3,}|VV|LL|DD"#, options: [])
    static let romanWordBoundary = try! NSRegularExpression(pattern: #"[\wà-ỹ]"#, options: [.caseInsensitive])
    static let romanNumerals = try! NSRegularExpression(pattern: #"(^|[\s\W])([IVXLCDMivxlcdm]+)(?=[\s\W]|$)"#, options: [])

    static let currencyVND = try! NSRegularExpression(pattern: #"(\d+(?:,\d+)?)\s*(?:đồng|VND|vnđ)\b"#, options: [.caseInsensitive])
    static let currencyD = try! NSRegularExpression(pattern: #"(\d+(?:,\d+)?)[đđ](?![a-zà-ỹ])"#, options: [.caseInsensitive])
    static let dollarPrefix = try! NSRegularExpression(pattern: #"\$\s*(\d+(?:,\d+)?)"#, options: [])
    static let dollarSuffix = try! NSRegularExpression(pattern: #"(\d+(?:,\d+)?)\s*(?:USD|\$)"#, options: [.caseInsensitive])

    static let percentageRange = try! NSRegularExpression(pattern: #"(\d+)\s*[-–—]\s*(\d+)\s*%"#, options: [])
    static let percentageDecimal = try! NSRegularExpression(pattern: #"(\d+),(\d+)\s*%"#, options: [])
    static let percentageSingle = try! NSRegularExpression(pattern: #"(\d+)\s*%"#, options: [])

    static let phone0 = try! NSRegularExpression(pattern: #"0\d{9,10}"#, options: [])
    static let phone84 = try! NSRegularExpression(pattern: #"\+84\d{9,10}"#, options: [])

    static let decimal = try! NSRegularExpression(pattern: #"(\d+),(\d+)(?=\s|$|[^\d,])"#, options: [])
    static let digits = try! NSRegularExpression(pattern: #"\b\d+\b"#, options: [])

    static let wordTokens = try! NSRegularExpression(pattern: #"[a-zA-Z0-9_\u00C0-\u1EFF]+"#, options: [])
    static let wordChar = try! NSRegularExpression(pattern: #"[a-zA-Zà-ỹ]"#, options: [])
    static let token = try! NSRegularExpression(pattern: #"[a-zA-Z0-9_\u00C0-\u1EFF]+(?:[-.][a-zA-Z0-9_\u00C0-\u1EFF]+)*"#, options: [])

    static let asciiLettersOnly = try! NSRegularExpression(pattern: #"^[a-z]+$"#, options: [])
    static let romajiVowels = "aeiouyăâêôơưáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ"
    static let romajiSplit = try! NSRegularExpression(
        pattern: "([^" + romajiVowels + "]*[" + romajiVowels + "]+[^" + romajiVowels + "]*(?![" + romajiVowels + "]))",
        options: []
    )

    static let romajiDoubledConsonant = try! NSRegularExpression(pattern: #"([bcdfghjklmnpqrstvwxz])y"#, options: .caseInsensitive)
    static let romajiFinalY = try! NSRegularExpression(pattern: #"y$"#, options: .caseInsensitive)
}


final actor TextPreprocessor {
    static let shared = TextPreprocessor()

    private var wordMap: [String: String] = [:]
    private var acronymMap: [String: String] = [:]
    private var transliterationCache: [String: String] = [:]
    private var transliterationCacheOrder: [String] = []

    private struct UnitPatternSpec {
        let expansion: String
        let numericRegex: NSRegularExpression
        let spelledRegex: NSRegularExpression
    }

    private static let unitPatternSpecs: [UnitPatternSpec] = {
        let numberSpelledPattern = #"(?:(?:\b(?:một|hai|ba|bốn|năm|sáu|bảy|tám|chín|mười|không|trăm|nghìn|triệu|tỷ|lẻ|mốt|tư|lăm|phẩy)\b\s*)+)"#
        let sortedUnits = unitExpansions.keys.sorted { $0.count > $1.count }
        return sortedUnits.compactMap { unit in
            guard let expansion = unitExpansions[unit] else { return nil }
            let escapedUnit = NSRegularExpression.escapedPattern(for: unit)
            let numericPattern: String
            let spelledPattern: String

            if unit.count == 1 {
                numericPattern = #"(\d+)\s*"# + escapedUnit + #"(?!\s*[a-zA-Zà-ỹ])(?=\s*[^a-zA-Zà-ỹ]|$)"#
                spelledPattern = #"("# + numberSpelledPattern + #")\s*\b"# + escapedUnit + #"\b(?!\s*[a-zA-Zà-ỹ])(?=\s*[^a-zA-Zà-ỹ]|$)"#
            } else {
                numericPattern = #"(\d+)\s*"# + escapedUnit + #"(?=\s|[^\w]|$)"#
                spelledPattern = #"("# + numberSpelledPattern + #")\s*\b"# + escapedUnit + #"\b(?=\s|[^\w]|$)"#
            }

            return UnitPatternSpec(
                expansion: expansion,
                numericRegex: try! NSRegularExpression(pattern: numericPattern, options: [.caseInsensitive]),
                spelledRegex: try! NSRegularExpression(pattern: spelledPattern, options: [.caseInsensitive])
            )
        }
    }()

    func lookupAcronym(_ key: String) -> String? {
        return acronymMap[key]
    }

    func lookupWord(_ key: String) -> String? {
        return wordMap[key]
    }

    func getWordMap() -> [String: String] {
        return wordMap
    }

    static func getWordsURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        let rootURL = appSupport.appendingPathComponent("LocalTTS", isDirectory: true)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL.appendingPathComponent("non-vietnamese-words.plist")
    }

    func updateWord(key: String, value: String) async throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedVal = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        wordMap[trimmedKey] = trimmedVal
        try saveWordMapToDisk()

        // Invalidate transliteration cache
        transliterationCache.removeAll()
        transliterationCacheOrder.removeAll()
    }

    func deleteWord(key: String) async throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        wordMap.removeValue(forKey: trimmedKey)
        try saveWordMapToDisk()

        // Invalidate transliteration cache
        transliterationCache.removeAll()
        transliterationCacheOrder.removeAll()
    }

    private func saveWordMapToDisk() throws {
        guard let url = Self.getWordsURL() else {
            throw NSError(domain: "TextPreprocessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not locate non-vietnamese-words.plist URL"])
        }

        let plistData = try PropertyListSerialization.data(fromPropertyList: wordMap, format: .xml, options: 0)
        try plistData.write(to: url, options: .atomic)

        Self.preprocessLog("Saved \(wordMap.count) words to \(url.path)")
    }

    private init() {
        let loaded = Self.loadResourcesFromDisk()
        self.wordMap = loaded.wordMap
        self.acronymMap = loaded.acronymMap
    }

    private static func preprocessLog(_ message: @autoclosure () -> String) {
        AppLogger.shared.log(message())
    }

    private func storeTransliteration(_ value: String, for key: String) {
        if transliterationCache[key] == nil {
            if transliterationCache.count >= PreprocessorConfig.transliterationCacheLimit {
                let evictCount = min(PreprocessorConfig.transliterationCacheEvictionBatch, transliterationCacheOrder.count)
                if evictCount > 0 {
                    for staleKey in transliterationCacheOrder.prefix(evictCount) {
                        transliterationCache.removeValue(forKey: String(staleKey))
                    }
                    transliterationCacheOrder.removeFirst(evictCount)
                } else {
                    transliterationCache.removeAll(keepingCapacity: true)
                    transliterationCacheOrder.removeAll(keepingCapacity: true)
                }
            }
            transliterationCacheOrder.append(key)
        }
        transliterationCache[key] = value
    }

    func loadResources() {
        let loaded = Self.loadResourcesFromDisk()
        self.wordMap = loaded.wordMap
        self.acronymMap = loaded.acronymMap
    }

    private static func loadResourcesFromDisk() -> (wordMap: [String: String], acronymMap: [String: String]) {
        let fileManager = FileManager.default
        var wordMap: [String: String] = [:]
        var acronymMap: [String: String] = [:]
        
        // Try loading from Application Support directory
        if let appSupport = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let rootURL = appSupport.appendingPathComponent("LocalTTS", isDirectory: true)
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let wordsURL = rootURL.appendingPathComponent("non-vietnamese-words.plist")
            let acronymsURL = rootURL.appendingPathComponent("acronyms.plist")

            if fileManager.fileExists(atPath: wordsURL.path) {
                wordMap = Self.loadPlist(from: wordsURL)
            }
            if fileManager.fileExists(atPath: acronymsURL.path) {
                acronymMap = Self.loadPlist(from: acronymsURL)
            }
        }

        Self.preprocessLog("Loaded \(wordMap.count) non-Vietnamese words and \(acronymMap.count) acronyms.")
        return (wordMap, acronymMap)
    }

    // MARK: - Plist Loading Helper
    private static func loadPlist(from url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else {
            AppLogger.shared.log("Warning: Could not read Plist file at \(url.path)")
            return [:]
        }
        return dict
    }

    // MARK: - Regex Replacement Helper
    typealias MatchReplacer = (NSTextCheckingResult, NSString) -> String?

    private static func replaceMatches(in text: String, regex: NSRegularExpression, replacer: MatchReplacer) -> String {
        var result = text
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        for match in matches.reversed() {
            if let replacement = replacer(match, nsString) {
                result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }
        return result
    }

    private static func replaceMatches(in text: String, pattern: String, options: NSRegularExpression.Options = [], replacer: MatchReplacer) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        return replaceMatches(in: text, regex: regex, replacer: replacer)
    }

    // MARK: - Cleaners & Formatters
    private static func cleanText(_ text: String) -> String {
        var e = text
        e = e.replacingOccurrences(of: "&", with: " và ")
        e = e.replacingOccurrences(of: "@", with: " a còng ")
        e = e.replacingOccurrences(of: "#", with: " thăng ")
        e = e.replacingOccurrences(of: "*", with: "")
        e = e.replacingOccurrences(of: "_", with: " ")
        e = e.replacingOccurrences(of: "~", with: "")
        e = e.replacingOccurrences(of: "`", with: "")
        e = e.replacingOccurrences(of: "^", with: "")
        e = PreprocessorRegex.url.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: "")
        e = PreprocessorRegex.www.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: "")
        e = PreprocessorRegex.email.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: "")
        return e
    }

    private static func normalizeQuotesAndDashes(_ text: String) -> String {
        var e = text
        e = PreprocessorRegex.doubleQuotes.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: "\"")
        e = PreprocessorRegex.singleQuotes.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: "'")
        e = PreprocessorRegex.dashes.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: "-")
        e = PreprocessorRegex.ellipsis.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: "...")
        e = e.replacingOccurrences(of: "…", with: "...")
        e = PreprocessorRegex.repeatedSentencePunctuation.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: "$1")
        return e
    }

    private static func cleanEmojisAndSymbols(_ text: String) -> String {
        var e = text
        e = PreprocessorRegex.emoji.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: " ")
        e = PreprocessorRegex.bracketQuotes.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: " ")
        e = PreprocessorRegex.whitespaceBeforePeriod.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: ".")
        e = PreprocessorRegex.underscoreWord.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: " ")
        e = PreprocessorRegex.nonDigitDash.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: " ")
        e = PreprocessorRegex.allowedChars.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: " ")
        e = PreprocessorRegex.whitespaceCollapse.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: " ")
        return e.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatNumbers(_ text: String) -> String {
        return replaceMatches(in: text, regex: PreprocessorRegex.thousandsSeparatedNumber) { match, ns in
            let val = ns.substring(with: match.range(at: 1))
            return val.replacingOccurrences(of: ".", with: "")
        }
    }

    // MARK: - Unit, Ranges, Dates, Times, Currency
    private static let units: [String] = [
        "m","cm","mm","km","dm","hm","dam","inch","kg","g","mg","t","tấn","yến","lạng","ml","l","lít",
        "m²","m2","km²","km2","ha","cm²","cm2","m³","m3","cm³","cm3","km³","km3","s","sec","min","h",
        "hr","hrs","km/h","kmh","m/s","ms","mm/h","cm/s","°C","°F","°K","°R","°Re","°Ro","°N","°D"
    ]
    private static let currencies: [String] = ["đồng","VND","vnđ","đ","USD","$"]

    private static let unitsPattern: String = {
        let all = Array(Set(units + currencies))
        let escaped = all.map { NSRegularExpression.escapedPattern(for: $0) }
        let sorted = escaped.sorted { $0.count > $1.count }
        return sorted.joined(separator: "|")
    }()

    private static let unitsRangeRegex = try! NSRegularExpression(
        pattern: #"(\d+)\s*[-–—]\s*(\d+)\s*("# + unitsPattern + #")\b"#,
        options: [.caseInsensitive]
    )

    private static let unitsRatioRegex = try! NSRegularExpression(
        pattern: #"(\d+)\s*[/:]\s*(\d+)\s*("# + unitsPattern + #")\b"#,
        options: [.caseInsensitive]
    )

    private static func processUnitsRangeAndRatio(_ text: String) -> String {
        var e = text
        e = replaceMatches(in: e, regex: unitsRangeRegex) { match, ns in
            let i = ns.substring(with: match.range(at: 1))
            let l = ns.substring(with: match.range(at: 2))
            let h = ns.substring(with: match.range(at: 3))
            let p = h.lowercased() == "đ" ? "" : " "
            return "\(i) đến \(l)\(p)\(h)"
        }

        e = replaceMatches(in: e, regex: unitsRatioRegex) { match, ns in
            let i = ns.substring(with: match.range(at: 1))
            let l = ns.substring(with: match.range(at: 2))
            let h = ns.substring(with: match.range(at: 3))
            let p = h.lowercased() == "đ" ? "" : " "
            return "\(i) phần \(l)\(p)\(h)"
        }

        return e
    }

    private static func processYearRanges(_ text: String) -> String {
        return replaceMatches(in: text, regex: PreprocessorRegex.yearRange) { match, ns in
            let s = ns.substring(with: match.range(at: 1))
            let r = ns.substring(with: match.range(at: 2))
            return "\(VietnameseNumberSpeller.spell(s)) đến \(VietnameseNumberSpeller.spell(r))"
        }
    }

    private static func isValidDate(day: String, month: String, year: String? = nil) -> Bool {
        guard let d = Int(day), let m = Int(month) else { return false }
        if let yStr = year, let y = Int(yStr) {
            return d >= 1 && d <= 31 && m >= 1 && m <= 12 && y >= 1000 && y <= 9999
        }
        return d >= 1 && d <= 31 && m >= 1 && m <= 12
    }

    private static func isValidMonth(month: String) -> Bool {
        guard let m = Int(month) else { return false }
        return m >= 1 && m <= 12
    }

    private static func processDates(_ text: String) -> String {
        var e = text

        e = replaceMatches(in: e, regex: PreprocessorRegex.dateRangeWithDayPrefix) { match, ns in
            let o = ns.substring(with: match.range(at: 1))
            let c = ns.substring(with: match.range(at: 2))
            let a = ns.substring(with: match.range(at: 3))
            let g = match.range(at: 4).location != NSNotFound ? ns.substring(with: match.range(at: 4)) : nil
            if isValidDate(day: o, month: a, year: g) && isValidDate(day: c, month: a, year: g) {
                var res = "ngày \(VietnameseNumberSpeller.spell(o)) đến \(VietnameseNumberSpeller.spell(c)) tháng \(VietnameseNumberSpeller.spell(a))"
                if let yearVal = g {
                    res += " năm \(VietnameseNumberSpeller.spell(yearVal))"
                }
                return res
            }
            return nil
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.dateRange) { match, ns in
            let start = match.range.location
            let prefixLength = min(10, start)
            let prefixRange = NSRange(location: start - prefixLength, length: prefixLength)
            if prefixRange.location >= 0 {
                let prefix = ns.substring(with: prefixRange)
                if prefix.contains("ngày") || prefix.contains("đến") {
                    return nil
                }
            }

            let o = ns.substring(with: match.range(at: 1))
            let c = ns.substring(with: match.range(at: 2))
            let a = ns.substring(with: match.range(at: 3))
            let g = match.range(at: 4).location != NSNotFound ? ns.substring(with: match.range(at: 4)) : nil
            if isValidDate(day: o, month: a, year: g) && isValidDate(day: c, month: a, year: g) {
                var res = "\(VietnameseNumberSpeller.spell(o)) đến \(VietnameseNumberSpeller.spell(c)) tháng \(VietnameseNumberSpeller.spell(a))"
                if let yearVal = g {
                    res += " năm \(VietnameseNumberSpeller.spell(yearVal))"
                }
                return res
            }
            return nil
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.monthRangeYear) { match, ns in
            let o = ns.substring(with: match.range(at: 1))
            let c = ns.substring(with: match.range(at: 2))
            let a = ns.substring(with: match.range(at: 3))
            if isValidMonth(month: o) && isValidMonth(month: c), let y = Int(a), y >= 1000 && y <= 9999 {
                return "tháng \(VietnameseNumberSpeller.spell(o)) đến tháng \(VietnameseNumberSpeller.spell(c)) năm \(VietnameseNumberSpeller.spell(a))"
            }
            return nil
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.sinhDate) { match, ns in
            let o = ns.substring(with: match.range(at: 1))
            let c = ns.substring(with: match.range(at: 2))
            let a = ns.substring(with: match.range(at: 3))
            let g = ns.substring(with: match.range(at: 4))
            if isValidDate(day: c, month: a, year: g) {
                return "\(o) ngày \(VietnameseNumberSpeller.spell(c)) tháng \(VietnameseNumberSpeller.spell(a)) năm \(VietnameseNumberSpeller.spell(g))"
            }
            return nil
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.fullDate) { match, ns in
            let o = ns.substring(with: match.range(at: 1))
            let c = ns.substring(with: match.range(at: 2))
            let a = ns.substring(with: match.range(at: 3))
            if isValidDate(day: o, month: c, year: a) {
                return "ngày \(VietnameseNumberSpeller.spell(o)) tháng \(VietnameseNumberSpeller.spell(c)) năm \(VietnameseNumberSpeller.spell(a))"
            }
            return nil
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.monthYear) { match, ns in
            let end = match.range.location + match.range.length
            if end < ns.length {
                let rest = ns.substring(from: end)
                if let firstChar = rest.first, firstChar.isLetter || firstChar.isNumber {
                    return nil
                }
            }
            let o = ns.substring(with: match.range(at: 1))
            let c = ns.substring(with: match.range(at: 2))
            if isValidMonth(month: o), let y = Int(c), y >= 1000 && y <= 9999 {
                return "tháng \(VietnameseNumberSpeller.spell(o)) năm \(VietnameseNumberSpeller.spell(c))"
            }
            return nil
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.dayMonth) { match, ns in
            let o = ns.substring(with: match.range(at: 1))
            let c = ns.substring(with: match.range(at: 2))
            if isValidDate(day: o, month: c) {
                return "\(VietnameseNumberSpeller.spell(o)) tháng \(VietnameseNumberSpeller.spell(c))"
            }
            return nil
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.dayMonthWord) { match, ns in
            let o = ns.substring(with: match.range(at: 1))
            let c = ns.substring(with: match.range(at: 2))
            if isValidDate(day: o, month: c) {
                return "ngày \(VietnameseNumberSpeller.spell(o)) tháng \(VietnameseNumberSpeller.spell(c))"
            }
            return nil
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.monthOnly) { match, ns in
            let o = ns.substring(with: match.range(at: 1))
            if isValidMonth(month: o) {
                return "tháng \(VietnameseNumberSpeller.spell(o))"
            }
            return nil
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.dayOnly) { match, ns in
            let o = ns.substring(with: match.range(at: 1))
            if let d = Int(o), d >= 1 && d <= 31 {
                return "ngày \(VietnameseNumberSpeller.spell(o))"
            }
            return nil
        }

        return e
    }

    static func processTime(_ text: String) -> String {
        var e = text

        e = replaceMatches(in: e, regex: PreprocessorRegex.timeHms) { match, ns in
            let hr = ns.substring(with: match.range(at: 1))
            let min = ns.substring(with: match.range(at: 2))
            var replacement = "\(VietnameseNumberSpeller.spell(hr)) giờ"
            if match.range(at: 3).location != NSNotFound {
                let sec = ns.substring(with: match.range(at: 3))
                replacement += " \(VietnameseNumberSpeller.spell(min)) phút \(VietnameseNumberSpeller.spell(sec)) giây"
            } else {
                replacement += " \(VietnameseNumberSpeller.spell(min)) phút"
            }
            return replacement
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.timeCompactHM) { match, ns in
            let hrStr = ns.substring(with: match.range(at: 1))
            let minStr = ns.substring(with: match.range(at: 2))
            if let hr = Int(hrStr), let min = Int(minStr), hr >= 0 && hr <= 23 && min >= 0 && min <= 59 {
                return "\(VietnameseNumberSpeller.spell(hrStr)) giờ \(VietnameseNumberSpeller.spell(minStr))"
            }
            return nil
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.timeCompactH) { match, ns in
            let hrStr = ns.substring(with: match.range(at: 1))
            if let hr = Int(hrStr), hr >= 0 && hr <= 23 {
                return "\(VietnameseNumberSpeller.spell(hrStr)) giờ"
            }
            return nil
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.timeHourMinute) { match, ns in
            let s = ns.substring(with: match.range(at: 1))
            let r = ns.substring(with: match.range(at: 2))
            return "\(VietnameseNumberSpeller.spell(s)) giờ \(VietnameseNumberSpeller.spell(r)) phút"
        }

        e = replaceMatches(in: e, regex: PreprocessorRegex.timeHourOnly) { match, ns in
            let s = ns.substring(with: match.range(at: 1))
            return "\(VietnameseNumberSpeller.spell(s)) giờ"
        }

        return e
    }

    private static func romanToInt(_ roman: String) -> Int? {
        let a = roman.uppercased()
        let g: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]
        for char in a {
            if g[char] == nil { return nil }
        }
        var i = 0
        var l = 0
        let chars = Array(a)
        while l < chars.count {
            guard let h = g[chars[l]] else { return nil }
            let m = l + 1 < chars.count ? (g[chars[l+1]] ?? 0) : 0
            if h < m {
                let allowed: [Character: [Character]] = ["I": ["V", "X"], "X": ["L", "C"], "C": ["D", "M"]]
                guard let list = allowed[chars[l]], list.contains(chars[l+1]) else { return nil }
                i += m - h
                l += 2
            } else {
                i += h
                l += 1
            }
        }
        return i
    }

    private static func isValidRoman(_ roman: String) -> Bool {
        let a = roman.uppercased()
        if a.isEmpty { return false }

        if PreprocessorRegex.romanChars.firstMatch(in: a, options: [], range: NSRange(location: 0, length: a.utf16.count)) == nil {
            return false
        }

        if PreprocessorRegex.romanInvalidRepeat.firstMatch(in: a, options: [], range: NSRange(location: 0, length: a.utf16.count)) != nil {
            return false
        }

        let g: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]
        let chars = Array(a)
        for i in 0..<chars.count-1 {
            guard let m = g[chars[i]], let p = g[chars[i+1]] else { return false }
            if m < p {
                let allowed: [Character: [Character]] = ["I": ["V", "X"], "X": ["L", "C"], "C": ["D", "M"]]
                guard let list = allowed[chars[i]], list.contains(chars[i+1]) else { return false }
            }
        }

        guard let val = romanToInt(roman) else { return false }
        return val > 0
    }

    private static func processRomanNumerals(_ text: String, unlimited: Bool = false) -> String {
        return replaceMatches(in: text, regex: PreprocessorRegex.romanNumerals) { match, ns in
            let prefix = ns.substring(with: match.range(at: 1))
            let roman = ns.substring(with: match.range(at: 2))

            if !prefix.isEmpty && PreprocessorRegex.romanWordBoundary.firstMatch(in: prefix, options: [], range: NSRange(location: 0, length: prefix.utf16.count)) != nil {
                return nil
            }

            if roman != roman.uppercased() || !isValidRoman(roman) {
                return nil
            }

            guard let val = romanToInt(roman) else { return nil }
            if !unlimited && (val < 1 || val > 30) {
                return nil
            }

            return prefix + String(val)
        }
    }



    private static func processCurrency(_ text: String) -> String {
        var e = text

        while let match = PreprocessorRegex.currencyVND.firstMatch(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count)) {
            let nsString = e as NSString
            let val = nsString.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
            let replacement = "\(VietnameseNumberSpeller.spell(val)) đồng"
            e = nsString.replacingCharacters(in: match.range, with: replacement)
        }

        while let match = PreprocessorRegex.currencyD.firstMatch(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count)) {
            let nsString = e as NSString
            let val = nsString.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
            let replacement = "\(VietnameseNumberSpeller.spell(val)) đồng"
            e = nsString.replacingCharacters(in: match.range, with: replacement)
        }

        while let match = PreprocessorRegex.dollarPrefix.firstMatch(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count)) {
            let nsString = e as NSString
            let val = nsString.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
            let replacement = "\(VietnameseNumberSpeller.spell(val)) đô la"
            e = nsString.replacingCharacters(in: match.range, with: replacement)
        }

        while let match = PreprocessorRegex.dollarSuffix.firstMatch(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count)) {
            let nsString = e as NSString
            let val = nsString.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
            let replacement = "\(VietnameseNumberSpeller.spell(val)) đô la"
            e = nsString.replacingCharacters(in: match.range, with: replacement)
        }

        return e
    }

    private static func processPercentages(_ text: String) -> String {
        var e = text

        while let match = PreprocessorRegex.percentageRange.firstMatch(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count)) {
            let nsString = e as NSString
            let s = nsString.substring(with: match.range(at: 1))
            let r = nsString.substring(with: match.range(at: 2))
            let replacement = "\(VietnameseNumberSpeller.spell(s)) đến \(VietnameseNumberSpeller.spell(r)) phần trăm"
            e = nsString.replacingCharacters(in: match.range, with: replacement)
        }

        while let match = PreprocessorRegex.percentageDecimal.firstMatch(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count)) {
            let nsString = e as NSString
            let s = nsString.substring(with: match.range(at: 1))
            let r = nsString.substring(with: match.range(at: 2))
            let cleanedR = r.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
            let replacement = "\(VietnameseNumberSpeller.spell(s)) phẩy \(VietnameseNumberSpeller.spell(cleanedR.isEmpty ? "0" : cleanedR)) phần trăm"
            e = nsString.replacingCharacters(in: match.range, with: replacement)
        }

        while let match = PreprocessorRegex.percentageSingle.firstMatch(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count)) {
            let nsString = e as NSString
            let s = nsString.substring(with: match.range(at: 1))
            let replacement = "\(VietnameseNumberSpeller.spell(s)) phần trăm"
            e = nsString.replacingCharacters(in: match.range, with: replacement)
        }

        return e
    }

    private static func processPhoneNumbers(_ text: String) -> String {
        let phoneReplacer: MatchReplacer = { match, ns in
            let s = ns.substring(with: match.range)
            let digits = s.compactMap { char -> String? in
                guard let digit = Int(String(char)) else { return nil }
                return VietnameseNumberSpeller.spell(String(digit))
            }
            return digits.joined(separator: " ")
        }
        var e = replaceMatches(in: text, regex: PreprocessorRegex.phone0, replacer: phoneReplacer)
        e = replaceMatches(in: e, regex: PreprocessorRegex.phone84, replacer: phoneReplacer)
        return e
    }

    private static func processDecimals(_ text: String) -> String {
        return replaceMatches(in: text, regex: PreprocessorRegex.decimal) { match, ns in
            let s = ns.substring(with: match.range(at: 1))
            let r = ns.substring(with: match.range(at: 2))
            let leftSpelled = VietnameseNumberSpeller.spell(s)
            let cleanedR = r.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
            let rightSpelled = VietnameseNumberSpeller.spell(cleanedR.isEmpty ? "0" : cleanedR)
            return "\(leftSpelled) phẩy \(rightSpelled)"
        }
    }

    private static let unitExpansions: [String: String] = [
        "m": "mét", "cm": "xăng-ti-mét", "mm": "mi-li-mét", "km": "ki-lô-mét", "dm": "đề-xi-mét",
        "hm": "héc-tô-mét", "dam": "đề-ca-mét", "inch": "in", "kg": "ki-lô-gam", "g": "gam",
        "mg": "mi-li-gam", "t": "tấn", "tấn": "tấn", "yến": "yến", "lạng": "lạng", "ml": "mi-li-lít",
        "l": "lít", "lít": "lít", "m²": "mét vuông", "m2": "mét vuông", "km²": "ki-lô-mét vuông",
        "km2": "ki-lô-mét vuông", "ha": "héc-ta", "cm²": "xăng-ti-mét vuông", "cm2": "xăng-ti-mét vuông",
        "m³": "mét khối", "m3": "mét khối", "cm³": "xăng-ti-mét khối", "cm3": "xăng-ti-mét khối",
        "km³": "ki-lô-mét khối", "km3": "ki-lô-mét khối", "s": "giây", "sec": "giây", "min": "phút",
        "h": "giờ", "hr": "giờ", "hrs": "giờ", "km/h": "ki-lô-mét trên giờ", "kmh": "ki-lô-mét trên giờ",
        "m/s": "mét trên giây", "ms": "mét trên giây", "mm/h": "mi-li-mét trên giờ", "cm/s": "xăng-ti-mét trên giây",
        "°C": "độ C", "°F": "độ F", "°K": "độ K", "°R": "độ R", "°Re": "độ Re", "°Ro": "độ Ro",
        "°N": "độ N", "°D": "độ D"
    ]

    private static func processUnits(_ text: String) -> String {
        var e = text
        for spec in unitPatternSpecs {
            let expansion = spec.expansion

            e = replaceMatches(in: e, regex: spec.numericRegex) { match, ns in
                let val = ns.substring(with: match.range(at: 1))
                return val + " " + expansion
            }

            e = replaceMatches(in: e, regex: spec.spelledRegex) { match, ns in
                let start = match.range.location
                let length = match.range.length

                let prevIndex = start - 1
                let nextIndex = start + length

                if prevIndex >= 0 {
                    let prevChar = ns.substring(with: NSRange(location: prevIndex, length: 1))
                    if PreprocessorRegex.wordChar.firstMatch(in: prevChar, options: [], range: NSRange(location: 0, length: 1)) != nil {
                        return nil
                    }
                }
                if nextIndex < ns.length {
                    let nextChar = ns.substring(with: NSRange(location: nextIndex, length: 1))
                    if PreprocessorRegex.wordChar.firstMatch(in: nextChar, options: [], range: NSRange(location: 0, length: 1)) != nil {
                        return nil
                    }
                }

                let spelled = ns.substring(with: match.range(at: 1))
                return spelled.trimmingCharacters(in: .whitespacesAndNewlines) + " " + expansion
            }
        }
        return e
    }

    private static func processDigits(_ text: String) -> String {

        return replaceMatches(in: text, regex: PreprocessorRegex.digits) { match, ns in
            let n = ns.substring(with: match.range)
            return VietnameseNumberSpeller.spell(n)
        }
    }

    private static func processVietnameseText(_ text: String, config: PreprocessorRuntimeConfig, unlimitedRoman: Bool = false) -> String {
        // Self.preprocessLog("📝 [Vietnamese Normalizer] Starting preprocess for text: '\(text)'")
        var e = text

        //Self.preprocessLog("   - Running precomposedStringWithCanonicalMapping")
        e = text.precomposedStringWithCanonicalMapping

        //Self.preprocessLog("   - Running cleanText")
        e = cleanText(e)

        //Self.preprocessLog("   - Running normalizeQuotesAndDashes")
        e = normalizeQuotesAndDashes(e)

        if config.numericNormalizationEnabled {
        //Self.preprocessLog("   - Running formatNumbers")
        e = formatNumbers(e)

        //Self.preprocessLog("   - Running processUnitsRangeAndRatio")
        e = processUnitsRangeAndRatio(e)

        //Self.preprocessLog("   - Running processYearRanges")
        e = processYearRanges(e)

        //Self.preprocessLog("   - Running processDates")
        e = processDates(e)

        //Self.preprocessLog("   - Running processTime")
        e = processTime(e)

        //Self.preprocessLog("   - Running processRomanNumerals")
        e = processRomanNumerals(e, unlimited: unlimitedRoman)



        //Self.preprocessLog("   - Running processCurrency")
        e = processCurrency(e)

        //Self.preprocessLog("   - Running processPercentages")
        e = processPercentages(e)

        //Self.preprocessLog("   - Running processPhoneNumbers")
        e = processPhoneNumbers(e)

        //Self.preprocessLog("   - Running processDecimals")
        e = processDecimals(e)

        //Self.preprocessLog("   - Running processUnits")
        e = processUnits(e)

        //Self.preprocessLog("   - Running processDigits")
        e = processDigits(e)
        } else {
            // Self.preprocessLog("   - Numeric normalization disabled; skipping number/date/time/currency pipeline")
        }

        // Self.preprocessLog("   - Trimming and cleaning white spaces")
        e = PreprocessorRegex.whitespaceCollapse.stringByReplacingMatches(in: e, options: [], range: NSRange(location: 0, length: e.utf16.count), withTemplate: " ")
        e = e.trimmingCharacters(in: .whitespacesAndNewlines)

        // Self.preprocessLog("📝 [Vietnamese Normalizer] Finished. Output: '\(e)'")
        return e
    }

    enum DictionaryType {
        case acronym
        case word
    }

    private func replaceDictionaryWords(in text: String, type: DictionaryType, config: PreprocessorRuntimeConfig) -> String {
        let typeStr = type == .acronym ? "acronym" : "word"
        guard config.dictionaryReplacementEnabled else {
            // Self.preprocessLog("📖 [ReplaceDictionary] Type: \(typeStr), dictionary replacement disabled; skipping.")
            return text
        }
        // Self.preprocessLog("📖 [ReplaceDictionary] Type: \(typeStr), Input: '\(text)'")
        // Tìm toàn bộ các token là từ (word tokens) trong văn bản
        let regex = PreprocessorRegex.wordTokens

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else {
            // Self.preprocessLog("📖 [ReplaceDictionary] Type: \(typeStr), No word matches found.")
            return text
        }

        struct WordToken {
            let text: String
            let range: NSRange
        }

        let words = matches.map { WordToken(text: nsString.substring(with: $0.range).lowercased(), range: $0.range) }

        var result = ""
        var lastCopiedIndex = 0
        var i = 0

        while i < words.count {
            var matchedLength = 0
            var replacement: String? = nil
            var matchStartLoc = 0
            var matchEndLoc = 0

            // Tìm kiếm tham lam (greedy matching): thử khớp cụm từ tối đa 4 từ giảm dần về 1 từ
            for lookAhead in (1...4).reversed() {
                guard i + lookAhead <= words.count else { continue }

                let startLoc = words[i].range.location
                let lastWord = words[i + lookAhead - 1]
                let endLoc = lastWord.range.location + lastWord.range.length

                // Lấy cụm từ gốc từ văn bản ban đầu và chuẩn hóa khoảng trắng để đối chiếu
                let rawPhrase = nsString.substring(with: NSRange(location: startLoc, length: endLoc - startLoc)).lowercased()
                let phrase = PreprocessorRegex.whitespaceCollapse
                    .stringByReplacingMatches(in: rawPhrase, options: [], range: NSRange(location: 0, length: rawPhrase.utf16.count), withTemplate: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Tra cứu trực tiếp từ bộ nhớ của actor
                let matchedValue = (type == .acronym) ? acronymMap[phrase] : wordMap[phrase]

                if let match = matchedValue {
                    matchedLength = lookAhead
                    replacement = match
                    matchStartLoc = startLoc
                    matchEndLoc = endLoc
                    break
                }
            }

            if let match = replacement, matchedLength > 0 {
                // Sao chép đoạn văn bản không thay đổi từ lastCopiedIndex đến matchStartLoc
                if matchStartLoc > lastCopiedIndex {
                    result += nsString.substring(with: NSRange(location: lastCopiedIndex, length: matchStartLoc - lastCopiedIndex))
                }

                let replacementText = (type == .word) ? "\u{FEFF}\(match)\u{FEFF}" : match
                result += replacementText

                // Self.preprocessLog("   - Replaced phrase '\(nsString.substring(with: NSRange(location: matchStartLoc, length: matchEndLoc - matchStartLoc)))' with '\(replacementText)'")

                lastCopiedIndex = matchEndLoc
                i += matchedLength
            } else {
                i += 1
            }
        }

        // Sao chép đoạn văn bản còn lại từ lastCopiedIndex đến cuối
        if lastCopiedIndex < nsString.length {
            result += nsString.substring(with: NSRange(location: lastCopiedIndex, length: nsString.length - lastCopiedIndex))
        }

        // Self.preprocessLog("📖 [ReplaceDictionary] Type: \(typeStr), Output: '\(result)'")
        return result
    }

    private func transliterateToken(_ token: String, config: PreprocessorRuntimeConfig) -> String {
        guard config.transliterationEnabled else { return token }

        let folded = token.folding(options: .diacriticInsensitive, locale: nil)
        let cacheKey = folded.lowercased()

        if let cached = transliterationCache[cacheKey] {
            return cached
        }

        let transliterated: String
        if config.dictionaryReplacementEnabled, let dictMatch = lookupWord(cacheKey) {
            transliterated = dictMatch
        } else if JapaneseTransliterator.isJapaneseRomaji(cacheKey) {
            transliterated = JapaneseTransliterator.transliterateRomaji(cacheKey)
        } else if cacheKey.contains("-") || cacheKey.contains(".") {
            var partsResult = ""
            var currentPart = ""
            for char in cacheKey {
                if char == "-" || char == "." {
                    if !currentPart.isEmpty {
                        if !VietnameseWordChecker.isVietnameseWord(currentPart) {
                            if JapaneseTransliterator.isJapaneseRomaji(currentPart) {
                                partsResult += JapaneseTransliterator.transliterateRomaji(currentPart)
                            } else {
                                partsResult += EnglishTransliterator.transliterateWord(currentPart)
                            }
                        } else {
                            partsResult += currentPart
                        }
                        currentPart = ""
                    }
                    partsResult.append(char)
                } else {
                    currentPart.append(char)
                }
            }
            if !currentPart.isEmpty {
                if !VietnameseWordChecker.isVietnameseWord(currentPart) {
                    if JapaneseTransliterator.isJapaneseRomaji(currentPart) {
                        partsResult += JapaneseTransliterator.transliterateRomaji(currentPart)
                    } else {
                        partsResult += EnglishTransliterator.transliterateWord(currentPart)
                    }
                } else {
                    partsResult += currentPart
                }
            }
            transliterated = partsResult
        } else {
            transliterated = EnglishTransliterator.transliterateWord(cacheKey)
        }

        storeTransliteration(transliterated, for: cacheKey)
        return transliterated
    }

    // MARK: - Main Preprocess Pipeline
    func preprocess(_ text: String) -> String {
        // Self.preprocessLog("🚀 [Preprocess] Start preprocessing for: '\(text)'")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Self.preprocessLog("🚀 [Preprocess] Text is empty, returning empty string.")
            return ""
        }

        let runtimeConfig = PreprocessorRuntimeConfig.load()
        // Self.preprocessLog(
        //     "🚀 [Preprocess] Config snapshot: numeric=\(runtimeConfig.numericNormalizationEnabled), dictionary=\(runtimeConfig.dictionaryReplacementEnabled), transliteration=\(runtimeConfig.transliterationEnabled)"
        // )

        // 0. Chuyển đổi Hiragana/Katakana tiếng Nhật sang Romaji
        let pipelineInput: String
        if runtimeConfig.transliterationEnabled {
            // Self.preprocessLog("🚀 [Preprocess] Step 0a: Converting Japanese characters (Romaji)...")
            pipelineInput = JapaneseTransliterator.convertToRomaji(text)
        } else {
            // Self.preprocessLog("🚀 [Preprocess] Step 0a: Transliteration disabled; keeping original script.")
            pipelineInput = text
        }

        // Self.preprocessLog("🚀 [Preprocess] Step 0b: Running Vietnamese text processor...")
        let processedVi = Self.processVietnameseText(pipelineInput, config: runtimeConfig)

        // Self.preprocessLog("🚀 [Preprocess] Step 0c: Cleaning emojis and symbols...")
        let cleaned = Self.cleanEmojisAndSymbols(processedVi)

        let lowercased = cleaned.lowercased()

        // 1. Thay thế từ viết tắt (Acronyms) khi config bật
        var replacedText = lowercased
        if runtimeConfig.dictionaryReplacementEnabled {
            // Self.preprocessLog("🚀 [Preprocess] Step 1: Replacing acronyms...")
            replacedText = replaceDictionaryWords(in: lowercased, type: .acronym, config: runtimeConfig)

            // 2. Tiến hành khớp từ điển tiếng Anh và chạy bộ quy tắc
            // Self.preprocessLog("🚀 [Preprocess] Step 2: Translating English words...")
            replacedText = replaceDictionaryWords(in: replacedText, type: .word, config: runtimeConfig)
        } else {
            // Self.preprocessLog("🚀 [Preprocess] Step 1/2: Dictionary replacement disabled; skipping acronym and word maps.")
        }

        let shouldProcessTokens = runtimeConfig.dictionaryReplacementEnabled || runtimeConfig.transliterationEnabled

        var result = replacedText
        if shouldProcessTokens {
            let nsString = replacedText as NSString
            let matches = PreprocessorRegex.token.matches(in: replacedText, options: [], range: NSRange(location: 0, length: nsString.length))

            result = ""
            var lastOffset = 0

            // Self.preprocessLog("🚀 [Preprocess] Step 2b: Processing individual non-Vietnamese tokens...")
            for match in matches {
                if match.range.location > lastOffset {
                    let gapRange = NSRange(location: lastOffset, length: match.range.location - lastOffset)
                    result += nsString.substring(with: gapRange)
                }

                let token = nsString.substring(with: match.range)

                // Kiểm tra xem token này có phải đã được xử lý bởi từ điển (Sentinel check) hay không
                var isTranslatedByDict = false
                if match.range.location > 0 {
                    let prevCharRange = NSRange(location: match.range.location - 1, length: 1)
                    if nsString.substring(with: prevCharRange) == "\u{FEFF}" {
                        isTranslatedByDict = true
                    }
                }

                let processedToken: String
                if isTranslatedByDict {
                    processedToken = token
                } else if runtimeConfig.transliterationEnabled && token.count > 1 && token != "mc" && !VietnameseWordChecker.isVietnameseWord(token) {
                    // Tự động chuẩn hóa dấu phụ (ví dụ: ryū -> ryu, arigatō -> arigato)
                    processedToken = transliterateToken(token, config: runtimeConfig)
                } else {
                    processedToken = token
                }

                result += processedToken
                lastOffset = match.range.location + match.range.length
            }

            if lastOffset < nsString.length {
                let gapRange = NSRange(location: lastOffset, length: nsString.length - lastOffset)
                result += nsString.substring(with: gapRange)
            }
        }

        // Loại bỏ sentinel trước khi trả về kết quả
        let cleanedResult = result.replacingOccurrences(of: "\u{FEFF}", with: "")
        Self.preprocessLog("🚀 [Preprocess] Finish preprocessing. Output: '\(cleanedResult)'")
        return cleanedResult
    }
}
