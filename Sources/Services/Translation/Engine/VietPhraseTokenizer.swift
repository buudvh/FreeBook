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
    public static func tokenize(_ text: String, bookId: String?) -> [String] {
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
        
        var vpCandidates: [VPCandidate] = []
        var j = 0
        while j < length {
            if occupiedIndices.contains(j) {
                j += 1
                continue
            }
            
            let nextNameStart = selectedNames.first(where: { $0.range.lowerBound > j })?.range.lowerBound ?? length
            let maxLimit = nextNameStart - j
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
        
        var output: [String] = []
        var currentIndex = 0
        
        while currentIndex < length {
            if let activeName = selectedNames.first(where: { $0.range.lowerBound == currentIndex }) {
                output.append(String(chars[activeName.range]))
                currentIndex = activeName.range.upperBound
                continue
            }
            
            if let activeVP = selectedVPs.first(where: { $0.range.lowerBound == currentIndex }) {
                output.append(String(chars[activeVP.range]))
                currentIndex = activeVP.range.upperBound
                continue
            }

            if isASCIIAlphanumeric(chars[currentIndex]) {
                let nextBoundary = min(
                    selectedNames.first(where: { $0.range.lowerBound > currentIndex })?.range.lowerBound ?? length,
                    selectedVPs.first(where: { $0.range.lowerBound > currentIndex })?.range.lowerBound ?? length
                )
                var end = currentIndex + 1
                while end < nextBoundary && isASCIIAlphanumeric(chars[end]) {
                    end += 1
                }
                output.append(String(chars[currentIndex..<end]))
                currentIndex = end
                continue
            }
            
            let char = chars[currentIndex]
            if isChineseCharacter(char) {
                output.append(String(char))
                currentIndex += 1
            } else {
                let nextBoundary = min(
                    selectedNames.first(where: { $0.range.lowerBound > currentIndex })?.range.lowerBound ?? length,
                    selectedVPs.first(where: { $0.range.lowerBound > currentIndex })?.range.lowerBound ?? length
                )
                if isAlphanumeric(char) {
                    var end = currentIndex + 1
                    while end < nextBoundary && isAlphanumeric(chars[end]) {
                        end += 1
                    }
                    output.append(String(chars[currentIndex..<end]))
                    currentIndex = end
                } else {
                    var end = currentIndex + 1
                    while end < nextBoundary && chars[end] == char {
                        end += 1
                    }
                    output.append(String(chars[currentIndex..<end]))
                    currentIndex = end
                }
            }
        }
        
        return output
    }

    private static func isAlphanumeric(_ char: Character) -> Bool {
        return char.isLetter || char.isNumber
    }

    private static func isASCIIAlphanumeric(_ char: Character) -> Bool {
        guard let code = char.asciiValue else { return false }
        return (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
    }

    internal static func isChineseCharacter(_ char: Character) -> Bool {
        guard let code = char.unicodeScalars.first?.value else { return false }
        return (code >= 0x4E00 && code <= 0x9FFF) ||
               (code >= 0x3400 && code <= 0x4DBF) ||
               (code >= 0x20000 && code <= 0x2A6DF)
    }
}
