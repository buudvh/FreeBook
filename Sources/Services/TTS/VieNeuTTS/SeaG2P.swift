import Foundation

/// Chuyển văn bản Việt/Anh thành chuỗi phoneme mà VieNeu-TTS v3 Turbo nhận vào.
///
/// Đây là bộ G2P **duy nhất** dùng được cho model này. Không thể thay bằng `EspeakPhonemizer` của
/// đường Piper: vocab của VieNeu chỉ 419 token và là bộ ký hiệu riêng của sea-g2p, khác hoàn toàn
/// IPA mà espeak sinh ra.
///
/// Cơ chế: tách token → tra từ điển nhị phân (`SeaG2PDictionary`) → với từ có cả cách đọc Việt và
/// Anh thì quyết định theo **ngôn ngữ của láng giềng gần nhất** → từ ngoài từ điển thì thử cắt
/// thành các âm tiết có trong từ điển, cuối cùng mới rơi xuống đọc từng ký tự.
///
/// **Không xử lý tag cảm xúc.** Bản thử nghiệm có đường `phonemizeTextWithEmotions` cắt câu tại mọi
/// `[...]` để dịch `[cười]`/`[thở dài]` thành `<|emotion_k|>`. FreeBook không dùng tag cảm xúc, mà
/// đường đó có tác dụng phụ thật: chú thích dạng `[1]` trong truyện sẽ **cắt câu làm nhiều mảnh**,
/// mỗi mảnh được phiên âm riêng nên ngữ điệu bị vỡ. Ở đây dấu ngoặc vuông đi qua như dấu câu thường.
///
/// Chuẩn hoá số, ngày, giờ, tiền tệ **không** nằm ở đây mà ở `TextPreprocessor` của FreeBook — bắt
/// buộc phải chạy trước. Ký hiệu phoneme này dùng **chữ số làm dấu thanh** (`aː2`, `a6j`, `iɛ6n`),
/// nên một chữ số thô lọt vào sẽ bị model đọc thành thanh điệu.
final class SeaG2P: @unchecked Sendable {
    private enum Language {
        case vietnamese
        case english
        /// Từ có cả hai cách đọc — ngôn ngữ được quyết định sau, theo láng giềng.
        case ambiguous
        case punctuation
    }

    private enum Reading {
        /// Một cách đọc duy nhất.
        case fixed(String)
        /// Hai cách đọc, chọn theo ngôn ngữ đã chốt.
        case bilingual(vietnamese: String, english: String)
        /// Không có trong từ điển — phải cắt hoặc đọc từng ký tự.
        case unknown
        case verbatim(String)
    }

    private struct Token {
        var language: Language
        let content: String
        let reading: Reading
        /// Nằm trong `<en>...</en>` do người viết chỉ định — dùng để bỏ qua vài luật riêng.
        let isExplicitEnglish: Bool
    }

    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"(?i)(<en>.*?</en>)|(\w+(?:['’]\w+)*)|([^\w\s])"#
    )
    private static let taggedContentRegex = try! NSRegularExpression(
        pattern: #"(\w+(?:['’]\w+)*)|([^\w\s])"#
    )
    private static let tagStripRegex = try! NSRegularExpression(pattern: #"(?i)</?en>"#)

    private static let vietnameseAccents = Set("àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ")
    private static let vowels = Set("aeiouyàáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵ")
    private static let stopPunctuation = Set(".!?;:()[]{}")
    private static let terminalPunctuation = Set(".!?")
    private static let weakTrailing = Set(",;:… \t")

    private let dictionary: SeaG2PDictionary
    private let lock = NSLock()
    private var segmentationCache: [String: String?] = [:]

    init(dictionaryURL: URL) throws {
        self.dictionary = try SeaG2PDictionary(url: dictionaryURL)
    }

    /// Đường vào duy nhất: chốt dấu câu cuối rồi phiên âm.
    func phonemes(for text: String) -> String {
        phonemize(applyPunctuationNormalisation(text))
    }

    // MARK: - Phiên âm

    private func phonemize(_ text: String) -> String {
        let nsText = text as NSString
        let matches = Self.tokenRegex.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )

        var tokens: [Token] = []
        tokens.reserveCapacity(matches.count)

        for match in matches {
            if match.range(at: 1).location != NSNotFound {
                appendExplicitEnglish(nsText.substring(with: match.range(at: 1)), into: &tokens)
            } else if match.range(at: 2).location != NSNotFound {
                tokens.append(makeWordToken(nsText.substring(with: match.range(at: 2))))
            } else if match.range(at: 3).location != NSNotFound {
                let mark = nsText.substring(with: match.range(at: 3))
                tokens.append(Token(language: .punctuation, content: mark, reading: .verbatim(mark), isExplicitEnglish: false))
            }
        }

        resolveAmbiguousLanguages(&tokens)

        var pieces: [String] = []
        pieces.reserveCapacity(tokens.count)
        for token in tokens {
            pieces.append(render(token))
        }

        return tidySpacingBeforePunctuation(pieces.joined(separator: " "))
    }

    /// `<en>...</en>` — người viết đã chỉ định tiếng Anh, nên chỉ lấy cách đọc tiếng Anh.
    private func appendExplicitEnglish(_ tagged: String, into tokens: inout [Token]) {
        let stripped = Self.tagStripRegex
            .stringByReplacingMatches(
                in: tagged,
                options: [],
                range: NSRange(location: 0, length: (tagged as NSString).length),
                withTemplate: ""
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let nsStripped = stripped as NSString
        let inner = Self.taggedContentRegex.matches(
            in: stripped,
            options: [],
            range: NSRange(location: 0, length: nsStripped.length)
        )

        for match in inner {
            if match.range(at: 1).location != NSNotFound {
                let word = nsStripped.substring(with: match.range(at: 1))
                let lowercased = word.lowercased()
                var reading = Reading.unknown
                if let phoneme = dictionary.mergedPhoneme(for: lowercased) {
                    reading = .fixed(phoneme)
                } else if let entry = dictionary.commonEntry(for: lowercased), !entry.english.isEmpty {
                    reading = .fixed(entry.english)
                }
                tokens.append(Token(language: .english, content: word, reading: reading, isExplicitEnglish: true))
            } else if match.range(at: 2).location != NSNotFound {
                let mark = nsStripped.substring(with: match.range(at: 2))
                tokens.append(Token(language: .punctuation, content: mark, reading: .verbatim(mark), isExplicitEnglish: true))
            }
        }
    }

    private func makeWordToken(_ word: String) -> Token {
        let lowercased = word.lowercased()

        if let raw = dictionary.mergedRawPhoneme(for: lowercased) {
            let language: Language = raw.contains("<en>") ? .english : .vietnamese
            let cleaned = raw
                .replacingOccurrences(of: "<en>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Token(language: language, content: word, reading: .fixed(cleaned), isExplicitEnglish: false)
        }

        if let entry = dictionary.commonEntry(for: lowercased) {
            return Token(
                language: .ambiguous,
                content: word,
                reading: .bilingual(vietnamese: entry.vietnamese, english: entry.english),
                isExplicitEnglish: false
            )
        }

        // Có dấu tiếng Việt thì gần như chắc chắn là tiếng Việt; không có thì đoán tiếng Anh.
        let hasAccent = lowercased.contains { Self.vietnameseAccents.contains($0) }
        return Token(
            language: hasAccent ? .vietnamese : .english,
            content: word,
            reading: .unknown,
            isExplicitEnglish: false
        )
    }

    private func render(_ token: Token) -> String {
        switch token.reading {
        case .verbatim(let text):
            return text
        case .fixed(let phoneme):
            return applySingleLetterRule(phoneme, token: token)
        case .bilingual(let vietnamese, let english):
            let chosen = token.language == .english
                ? (english.isEmpty ? vietnamese : english)
                : (vietnamese.isEmpty ? english : vietnamese)
            return applySingleLetterRule(chosen.trimmingCharacters(in: .whitespacesAndNewlines), token: token)
        case .unknown:
            let lowercased = token.content.lowercased()
            let language = token.language
            let segmented = segmentOutOfVocabulary(lowercased, language: language)
            return (segmented ?? characterByCharacter(token.content, language: language))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// "a" đứng một mình trong dòng tiếng Anh đọc là `ɐ` (mạo từ không nhấn), trừ khi người viết đã
    /// bọc `<en>` — lúc đó giữ đúng cách đọc trong từ điển.
    private func applySingleLetterRule(_ phoneme: String, token: Token) -> String {
        guard token.language == .english,
              !token.isExplicitEnglish,
              token.content.lowercased() == "a" else { return phoneme }
        return "ɐ"
    }

    /// Từ mơ hồ (có cả cách đọc Việt và Anh) lấy ngôn ngữ của láng giềng **gần nhất**, không vượt
    /// qua dấu ngắt câu. Không có láng giềng nào thì mặc định tiếng Việt.
    private func resolveAmbiguousLanguages(_ tokens: inout [Token]) {
        let count = tokens.count
        var index = 0
        while index < count {
            guard tokens[index].language == .ambiguous else {
                index += 1
                continue
            }

            let start = index
            while index < count && tokens[index].language == .ambiguous { index += 1 }
            let end = index - 1

            var leftLanguage: Language?
            var leftDistance = Int.max
            var cursor = start - 1
            while cursor >= 0 {
                if isStop(tokens[cursor]) { break }
                if tokens[cursor].language == .vietnamese || tokens[cursor].language == .english {
                    leftLanguage = tokens[cursor].language
                    leftDistance = start - cursor
                    break
                }
                cursor -= 1
            }

            var rightLanguage: Language?
            var rightDistance = Int.max
            cursor = end + 1
            while cursor < count {
                if isStop(tokens[cursor]) { break }
                if tokens[cursor].language == .vietnamese || tokens[cursor].language == .english {
                    rightLanguage = tokens[cursor].language
                    rightDistance = cursor - end
                    break
                }
                cursor += 1
            }

            let resolved: Language
            if let left = leftLanguage, let right = rightLanguage {
                resolved = rightDistance <= leftDistance ? right : left
            } else {
                resolved = leftLanguage ?? rightLanguage ?? .vietnamese
            }
            for position in start...end { tokens[position].language = resolved }
        }
    }

    private func isStop(_ token: Token) -> Bool {
        token.content.count == 1 && Self.stopPunctuation.contains(token.content.first!)
    }

    // MARK: - Từ ngoài từ điển

    /// Cắt một từ lạ thành dãy âm tiết **có trong từ điển** bằng quy hoạch động, ưu tiên mảnh dài
    /// nhất trước. Chỉ nhận mảnh có cả nguyên âm và phụ âm để không cắt ra những mảnh vô nghĩa.
    private func segmentOutOfVocabulary(_ word: String, language: Language) -> String? {
        let cacheKey = "\(word)|\(language == .english ? "en" : "vi")"
        lock.lock()
        if let cached = segmentationCache[cacheKey] { lock.unlock(); return cached }
        lock.unlock()

        let characters = Array(word)
        let length = characters.count
        var best = [String?](repeating: nil, count: length + 1)
        best[0] = ""

        for start in 0..<length {
            guard let prefix = best[start] else { continue }
            var end = length
            while end > start {
                let segment = String(characters[start..<end])
                if hasVowelAndConsonant(segment), let phoneme = segmentPhoneme(segment, language: language) {
                    if best[end] == nil {
                        best[end] = prefix.isEmpty ? phoneme : "\(prefix) \(phoneme)"
                    }
                }
                end -= 1
            }
        }

        let result = best[length]
        lock.lock()
        if segmentationCache.count >= 5_000 { segmentationCache.removeAll(keepingCapacity: true) }
        segmentationCache[cacheKey] = result
        lock.unlock()
        return result
    }

    private func segmentPhoneme(_ segment: String, language: Language) -> String? {
        let lowercased = segment.lowercased()
        if let phoneme = dictionary.mergedPhoneme(for: lowercased) { return phoneme }
        if let entry = dictionary.commonEntry(for: lowercased) {
            if language == .english && !entry.english.isEmpty { return entry.english }
            return entry.vietnamese.isEmpty ? entry.english : entry.vietnamese
        }
        return nil
    }

    private func hasVowelAndConsonant(_ text: String) -> Bool {
        var vowel = false
        var consonant = false
        for character in text.lowercased() {
            if Self.vowels.contains(character) {
                vowel = true
            } else if character.isLetter {
                consonant = true
            }
            if vowel && consonant { return true }
        }
        return false
    }

    /// Chốt cuối: đọc từng ký tự. Ký tự không tra được thì giữ nguyên — bất biến "không bộ phiên âm
    /// nào được trả rỗng" của repo, mất chữ còn tệ hơn đọc sai.
    private func characterByCharacter(_ content: String, language: Language) -> String {
        var pieces: [String] = []
        for character in content {
            let lowercased = String(character).lowercased()
            if let phoneme = dictionary.mergedPhoneme(for: lowercased) {
                pieces.append(phoneme)
            } else if let entry = dictionary.commonEntry(for: lowercased) {
                if language == .english && !entry.english.isEmpty {
                    pieces.append(entry.english)
                } else {
                    pieces.append(entry.vietnamese.isEmpty ? entry.english : entry.vietnamese)
                }
            } else {
                pieces.append(lowercased)
            }
        }
        return pieces.joined()
    }

    // MARK: - Dấu câu

    /// Luật `punc_norm` của sea-g2p: câu ngắn (≤ 4 từ) ép dấu cuối về đúng một `.`; câu dài thiếu
    /// dấu kết thúc thì thêm `.`. Model được train với mọi chunk kết thúc bằng dấu câu hợp lệ, thiếu
    /// nó thì stop token dễ bắn trượt và model "nói thêm".
    func applyPunctuationNormalisation(_ text: String) -> String {
        let trimmed = trimTrailingWhitespace(text)
        guard !trimmed.isEmpty else { return trimmed }

        let wordCount = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
            .count

        if wordCount <= 4 {
            var stripped = trimmed
            while let last = stripped.last,
                  last.isWhitespace || ",.!?;:\u{2024}\u{2025}\u{2026}".contains(last) {
                stripped.removeLast()
            }
            let cleaned = trimTrailingWhitespace(stripped)
            return cleaned.isEmpty ? "." : "\(cleaned)."
        }

        if let last = trimmed.last, ",.!?".contains(last) { return trimmed }
        return "\(trimmed)."
    }

    private func trimTrailingWhitespace(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let previous = text.index(before: end)
            guard text[previous].isWhitespace else { break }
            end = previous
        }
        return String(text[..<end])
    }

    /// Dấu câu được tách thành token riêng nên khi join bằng khoảng trắng sẽ thành `từ .` — dán lại.
    private func tidySpacingBeforePunctuation(_ text: String) -> String {
        var result = text
        for mark in [".", ",", "!", "?", ";", ":"] {
            result = result.replacingOccurrences(of: " \(mark)", with: mark)
        }
        return result
    }

    /// Chốt để chuỗi phoneme luôn kết thúc bằng `.`/`!`/`?`.
    func ensureTerminalPunctuation(_ phonemes: String) -> String {
        let trimmed = trimTrailingWhitespace(phonemes)
        guard !trimmed.isEmpty else { return trimmed }
        if let last = trimmed.last, Self.terminalPunctuation.contains(last) { return trimmed }
        var stripped = trimmed
        while let last = stripped.last, Self.weakTrailing.contains(last) { stripped.removeLast() }
        return stripped.isEmpty ? phonemes : "\(stripped)."
    }
}
