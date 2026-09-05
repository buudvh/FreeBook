import Foundation

public enum VietPhraseTokenizer {
    private struct NameCandidate {
        let range: Range<Int>
        let length: Int
    }

    private struct VPCandidate {
        let range: Range<Int>
        let length: Int
    }
    /// Cửa vào duy nhất: đọc hai cờ runtime rồi tra `TokenizeMemo` trước khi làm việc thật.
    ///
    /// Hai cờ đọc **ở đây** chứ không trong thân hàm, để chúng vào được khoá memo. Xem `TokenizeMemo`
    /// cho lý do phải có memo (mỗi dòng bị tokenize hai lần mỗi lần dựng lại chương).
    public static func tokenize(_ text: String, bookId: String?) -> [String] {
        guard !text.isEmpty else { return [] }

        let isPronounsEnabled = UserDefaults.standard.bool(forKey: "isTranslationPronounsEnabled")
        let isLuatNhanEnabled = UserDefaults.standard.bool(forKey: "isTranslationLuatNhanEnabled")

        return TokenizeMemo.shared.tokens(
            text: text,
            bookId: bookId,
            isPronounsEnabled: isPronounsEnabled,
            isLuatNhanEnabled: isLuatNhanEnabled,
            generation: TranslateUtils.translationGenerationToken(for: bookId)
        ) {
            tokenizeUncached(
                text,
                bookId: bookId,
                isPronounsEnabled: isPronounsEnabled,
                isLuatNhanEnabled: isLuatNhanEnabled
            )
        }
    }

    private static func tokenizeUncached(
        _ text: String,
        bookId: String?,
        isPronounsEnabled: Bool,
        isLuatNhanEnabled: Bool
    ) -> [String] {
        let chars = Array(text)
        let length = chars.count
        guard length > 0 else { return [] }

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
        
        var candidates: [NameCandidate] = []
        var i = 0
        while i < length {
            let limit = min(length - i, 20)
            let checkText = String(chars[i..<(i + limit)])
            
            var nameLengths = Set<Int>()
            
            if let bookNames = bookNames {
                for match in bookNames.findAllPrefixMatches(text: checkText, startIndex: 0) {
                    nameLengths.insert(match.length)
                }
            }
            
            if let customNames = customNames {
                for match in customNames.findAllPrefixMatches(text: checkText, startIndex: 0) {
                    nameLengths.insert(match.length)
                }
            }
            
            if let names = names {
                for match in names.findAllPrefixMatches(text: checkText, startIndex: 0) {
                    let matchedStr = String(chars[i..<(i + match.length)])
                    if !deletedNames.contains(matchedStr) {
                        nameLengths.insert(match.length)
                    }
                }
            }
            
            if let pronouns = pronouns {
                for match in pronouns.findAllPrefixMatches(text: checkText, startIndex: 0) {
                    nameLengths.insert(match.length)
                }
            }
            
            if let luatNhan = luatNhan {
                for match in luatNhan.findAllPrefixMatches(text: checkText, startIndex: 0) {
                    nameLengths.insert(match.length)
                }
            }
            
            for len in nameLengths {
                candidates.append(NameCandidate(range: i..<(i + len), length: len))
            }
            i += 1
        }
        
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

        // `first(where:)` bên trong vòng `while` là O(n²) trên đoạn dài. Bảng "mốc bắt đầu kế tiếp"
        // dựng một lần, tra O(1) — xem `nextStartTable`.
        let nextNameStartAfter = Self.nextStartTable(
            starts: selectedNames.map { $0.range.lowerBound },
            length: length
        )

        var vpCandidates: [VPCandidate] = []
        var j = 0
        while j < length {
            if occupiedIndices.contains(j) {
                j += 1
                continue
            }

            let maxLimit = nextNameStartAfter[j] - j
            let limit = min(maxLimit, 20)
            
            if limit >= 2 {
                let checkText = String(chars[j..<(j + limit)])
                var vpLengths = Set<Int>()
                
                if let bookVP = bookVP {
                    for match in bookVP.findAllPrefixMatches(text: checkText, startIndex: 0) where match.length >= 2 {
                        vpLengths.insert(match.length)
                    }
                }
                
                if let customVP = customVP {
                    for match in customVP.findAllPrefixMatches(text: checkText, startIndex: 0) where match.length >= 2 {
                        vpLengths.insert(match.length)
                    }
                }
                
                if let vp = vp {
                    for match in vp.findAllPrefixMatches(text: checkText, startIndex: 0) where match.length >= 2 {
                        let matchedStr = String(chars[j..<(j + match.length)])
                        if !deletedVP.contains(matchedStr) {
                            vpLengths.insert(match.length)
                        }
                    }
                }
                
                for len in vpLengths {
                    vpCandidates.append(VPCandidate(range: j..<(j + len), length: len))
                }
            }
            j += 1
        }
        
        vpCandidates.sort { c1, c2 in
            if c1.length != c2.length {
                return c1.length > c2.length
            }
            return c1.range.lowerBound < c2.range.lowerBound
        }
        
        var selectedVPs: [VPCandidate] = []
        for candidate in vpCandidates {
            var isOverlapping = false
            for idx in candidate.range {
                if occupiedIndices.contains(idx) {
                    isOverlapping = true
                    break
                }
            }
            
            if !isOverlapping {
                selectedVPs.append(candidate)
                for idx in candidate.range {
                    occupiedIndices.insert(idx)
                }
            }
        }
        
        selectedVPs.sort { $0.range.lowerBound < $1.range.lowerBound }

        // Ba bảng tra O(1) cho vòng dựng output: hai bảng theo chỉ số bắt đầu, một bảng mốc kế tiếp
        // trên **hợp** hai tập (chính là `min` của hai `first(where:)` cũ).
        var nameByStart: [Int: NameCandidate] = [:]
        for candidate in selectedNames { nameByStart[candidate.range.lowerBound] = candidate }
        var vpByStart: [Int: VPCandidate] = [:]
        for candidate in selectedVPs { vpByStart[candidate.range.lowerBound] = candidate }
        let nextBoundaryAfter = Self.nextStartTable(
            starts: selectedNames.map { $0.range.lowerBound } + selectedVPs.map { $0.range.lowerBound },
            length: length
        )

        var output: [String] = []
        var currentIndex = 0

        while currentIndex < length {
            if let activeName = nameByStart[currentIndex] {
                output.append(String(chars[activeName.range]))
                currentIndex = activeName.range.upperBound
                continue
            }

            if let activeVP = vpByStart[currentIndex] {
                output.append(String(chars[activeVP.range]))
                currentIndex = activeVP.range.upperBound
                continue
            }

            let char = chars[currentIndex]
            if isChineseCharacter(char) {
                output.append(String(char))
                currentIndex += 1
                continue
            }

            let nextBoundary = nextBoundaryAfter[currentIndex]

            // 1. Chữ cái Latin & Chữ số ASCII (e.g. q92tT5, iPhone15, AK47, 14.8, ngày, tháng, năm...)
            if isLatinLetterOrNumber(char) {
                var end = currentIndex + 1
                while end < nextBoundary && isLatinLetterOrNumber(chars[end]) {
                    end += 1
                }
                if end < nextBoundary, (chars[end] == "." || chars[end] == ","),
                   isASCIIDigit(chars[end - 1]),
                   (end + 1 < nextBoundary), isASCIIDigit(chars[end + 1]),
                   chars[currentIndex..<end].allSatisfy({ isASCIIDigit($0) }) {
                    var decEnd = end + 1
                    while decEnd < nextBoundary && isASCIIDigit(chars[decEnd]) {
                        decEnd += 1
                    }
                    output.append(String(chars[currentIndex..<decEnd]))
                    currentIndex = decEnd
                    continue
                }
                output.append(String(chars[currentIndex..<end]))
                currentIndex = end
                continue
            }

            // 2. Khoảng trắng
            if char.isWhitespace {
                var end = currentIndex + 1
                while end < nextBoundary && chars[end].isWhitespace {
                    end += 1
                }
                output.append(String(chars[currentIndex..<end]))
                currentIndex = end
                continue
            }

            // 3. Ký tự hoặc dấu câu lặp lại (e.g. ……, ..., ---) hoặc đơn lẻ
            var end = currentIndex + 1
            while end < nextBoundary && chars[end] == char {
                end += 1
            }
            output.append(String(chars[currentIndex..<end]))
            currentIndex = end
        }
        
        return output
    }

    /// `table[i]` = mốc bắt đầu **nhỏ nhất lớn hơn `i`**, hoặc `length` khi không còn mốc nào.
    ///
    /// Thay cho `starts.first(where: { $0 > i })` gọi trong vòng lặp: dựng một pass ngược O(n), tra
    /// O(1). Kết quả bằng đúng biểu thức cũ, kể cả khi `starts` rỗng (mọi phần tử là `length`).
    private static func nextStartTable(starts: [Int], length: Int) -> [Int] {
        var isStart = [Bool](repeating: false, count: length + 1)
        for start in starts where start >= 0 && start < length {
            isStart[start] = true
        }

        var table = [Int](repeating: length, count: length + 1)
        var best = length
        for index in stride(from: length - 1, through: 0, by: -1) {
            table[index] = best
            if isStart[index] { best = index }
        }
        return table
    }

    internal static func isASCIIDigit(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1 else { return false }
        return scalar.value >= 0x30 && scalar.value <= 0x39
    }

    internal static func isLatinLetterOrNumber(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1 else { return false }
        let val = scalar.value
        // 1. Chữ số ASCII 0-9
        if val >= 0x30 && val <= 0x39 { return true }
        // 2. Chữ cái Latin (bắt buộc char.isLetter để loại trừ các symbol như × U+00D7, ÷ U+00F7)
        guard char.isLetter else { return false }
        if (val >= 0x41 && val <= 0x5A) || (val >= 0x61 && val <= 0x7A) { return true }
        if (val >= 0xC0 && val <= 0xFF) { return true }
        if (val >= 0x100 && val <= 0x24F) { return true }
        if (val >= 0x1EA0 && val <= 0x1EF9) { return true }
        return false
    }

    internal static func isChineseCharacter(_ char: Character) -> Bool {
        guard let code = char.unicodeScalars.first?.value else { return false }
        return (code >= 0x4E00 && code <= 0x9FFF) ||
               (code >= 0x3400 && code <= 0x4DBF) ||
               (code >= 0x20000 && code <= 0x2A6DF)
    }
}
