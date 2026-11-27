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
    /// Cửa vào duy nhất: tra `TokenizeMemo` trước khi làm việc thật. Xem `TokenizeMemo` cho lý do phải có
    /// memo (mỗi dòng bị tokenize hai lần mỗi lần dựng lại chương).
    ///
    /// Từ 1.3.1016 tách từ **không** tra từ điển Pronouns (công tắc "Dịch đại từ" đã bỏ, cố định tắt): đại từ chỉ
    /// được dịch qua rule `<pn>` (`QuickTranslationDictionaryToken`); ngoài rule, cụm đó lấy nghĩa VP như mọi cụm khác.
    public static func tokenize(_ text: String, bookId: String?) -> [String] {
        guard !text.isEmpty else { return [] }

        return TokenizeMemo.shared.tokens(
            text: text,
            bookId: bookId,
            generation: TranslationReadContext.cacheGeneration(for: bookId)
        ) {
            tokenizeUncached(text, bookId: bookId)
        }
    }

    /// Mọi chỉ số ở đây là chỉ số **`Character`** trên `chars`, còn trie trả độ dài khớp theo **UTF-16** (luật 1.3.339).
    /// Độ dài trie phải đổi qua `characterCounts` trước khi cộng vào chỉ số: chữ ngoài BMP (𫄸 U+2B138 — một chữ, hai
    /// đơn vị) làm hai đơn vị lệch nhau, dùng thẳng là cắt lấn sang chữ sau và vượt cuối mảng (sập app ở panel Dịch khi
    /// thu hẹp cụm, 1.3.1080).
    private static func tokenizeUncached(_ text: String, bookId: String?) -> [String] {
        let chars = Array(text)
        let length = chars.count
        guard length > 0 else { return [] }
        // Mỗi ký tự dài ≥ 1 đơn vị ⇒ hai số đếm bằng nhau đúng khi mọi ký tự dài 1 đơn vị (gần như mọi dòng chữ Trung):
        // khi đó không dựng bảng và độ dài trie dùng thẳng như trước.
        let utf16Starts: [Int]? = text.utf16.count == length ? nil : Self.utf16StartTable(of: chars)

        let names = TranslationManager.shared.namesDict
        let customNames = TranslationManager.shared.customNamesDict
        let deletedNames = TranslationManager.shared.deletedNames
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
            if Task.isCancelled { return [] }
            let limit = min(length - i, 20)
            let checkText = String(chars[i..<(i + limit)])
            
            var nameLengths = Set<Int>()
            
            if let bookNames = bookNames {
                let lengths = bookNames.prefixMatchLengths(text: checkText, startIndex: 0)
                for matchLength in characterCounts(lengths, from: i, utf16Starts: utf16Starts) {
                    nameLengths.insert(matchLength)
                }
            }

            if let customNames = customNames {
                let lengths = customNames.prefixMatchLengths(text: checkText, startIndex: 0)
                for matchLength in characterCounts(lengths, from: i, utf16Starts: utf16Starts) {
                    nameLengths.insert(matchLength)
                }
            }

            if let names = names {
                let lengths = names.prefixMatchLengths(text: checkText, startIndex: 0)
                for matchLength in characterCounts(lengths, from: i, utf16Starts: utf16Starts) {
                    let matchedStr = String(chars[i..<(i + matchLength)])
                    if !deletedNames.contains(matchedStr) {
                        nameLengths.insert(matchLength)
                    }
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
            if Task.isCancelled { return [] }
            if occupiedIndices.contains(j) {
                j += 1
                continue
            }

            let maxLimit = nextNameStartAfter[j] - j
            let limit = min(maxLimit, 20)
            
            if limit >= 2 {
                let checkText = String(chars[j..<(j + limit)])
                var vpLengths = Set<Int>()
                
                // Ngưỡng "≥ 2" tính theo **chữ** (sau khi đổi đơn vị): một chữ ngoài BMP đứng lẻ dài 2 đơn vị nhưng chỉ
                // là một chữ, không được thành cụm VP.
                if let bookVP = bookVP {
                    let lengths = bookVP.prefixMatchLengths(text: checkText, startIndex: 0)
                    for matchLength in characterCounts(lengths, from: j, utf16Starts: utf16Starts) where matchLength >= 2 {
                        vpLengths.insert(matchLength)
                    }
                }

                if let customVP = customVP {
                    let lengths = customVP.prefixMatchLengths(text: checkText, startIndex: 0)
                    for matchLength in characterCounts(lengths, from: j, utf16Starts: utf16Starts) where matchLength >= 2 {
                        vpLengths.insert(matchLength)
                    }
                }

                if let vp = vp {
                    let lengths = vp.prefixMatchLengths(text: checkText, startIndex: 0)
                    for matchLength in characterCounts(lengths, from: j, utf16Starts: utf16Starts) where matchLength >= 2 {
                        let matchedStr = String(chars[j..<(j + matchLength)])
                        if !deletedVP.contains(matchedStr) {
                            vpLengths.insert(matchLength)
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

    /// `starts[k]` = offset UTF-16 của `chars[k]`; phần tử cuối (`starts[chars.count]`) = tổng số đơn vị.
    private static func utf16StartTable(of chars: [Character]) -> [Int] {
        var starts: [Int] = []
        starts.reserveCapacity(chars.count + 1)
        var offset = 0
        for char in chars {
            starts.append(offset)
            offset += char.utf16.count
        }
        starts.append(offset)
        return starts
    }

    /// Độ dài khớp của trie (UTF-16, tính từ ký tự `start`) ⇒ số `Character`. Bỏ độ dài kết thúc giữa một ký tự (nửa
    /// cặp surrogate, nửa cụm có dấu rời) — không có token nào cắt được ở đó. `utf16Starts == nil` ⇒ mỗi ký tự một đơn
    /// vị, trả nguyên mảng.
    ///
    /// Không vượt mảng: trie chỉ khớp trong `checkText` = `chars[start..<start + limit]`, nên ký tự kết thúc tìm được
    /// luôn ≤ `start + limit`.
    private static func characterCounts(_ utf16Lengths: [Int], from start: Int, utf16Starts: [Int]?) -> [Int] {
        guard let utf16Starts else { return utf16Lengths }
        return utf16Lengths.compactMap { (utf16Length: Int) -> Int? in
            let target = utf16Starts[start] + utf16Length
            // Mỗi ký tự ≥ 1 đơn vị ⇒ ký tự kết thúc nằm trong (start, start + utf16Length].
            var low = start + 1
            var high = min(start + utf16Length, utf16Starts.count - 1)
            while low <= high {
                let mid = (low + high) / 2
                if utf16Starts[mid] == target { return mid - start }
                if utf16Starts[mid] < target { low = mid + 1 } else { high = mid - 1 }
            }
            return nil
        }
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
        let scalars = char.unicodeScalars
        guard let scalar = scalars.first else { return false }
        // Chữ kèm dấu rời (NFD, vd "u" + U+0303 = "ũ") xét theo chữ gốc, để không bị tách khỏi từ.
        // Chỉ nhận dấu thuộc khối Combining Diacritical Marks (đủ mọi dấu tiếng Việt); ký tự nhiều
        // scalar khác (emoji, keycap "1️⃣") vẫn không phải chữ.
        let hasCombiningMarks = scalars.count > 1
        if hasCombiningMarks, !scalars.dropFirst().allSatisfy({ (0x300...0x36F).contains($0.value) }) {
            return false
        }
        let val = scalar.value
        // 1. Chữ số ASCII 0-9 (chỉ khi đứng một mình)
        if !hasCombiningMarks && val >= 0x30 && val <= 0x39 { return true }
        // 2. Chữ cái Latin (bắt buộc char.isLetter để loại trừ các symbol như × U+00D7, ÷ U+00F7)
        guard char.isLetter else { return false }
        if (val >= 0x41 && val <= 0x5A) || (val >= 0x61 && val <= 0x7A) { return true }
        if (val >= 0xC0 && val <= 0xFF) { return true }
        if (val >= 0x100 && val <= 0x24F) { return true }
        if (val >= 0x1EA0 && val <= 0x1EF9) { return true }
        return false
    }

    /// Dải chữ Hán ở `ChineseCharacterClassifier` (gồm cả khối mở rộng, 1.3.1081).
    internal static func isChineseCharacter(_ char: Character) -> Bool {
        ChineseCharacterClassifier.isHan(char)
    }
}
