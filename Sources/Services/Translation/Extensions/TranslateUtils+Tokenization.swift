import Foundation

extension TranslateUtils {
    public static func getTranslationTokens(for sentence: String, bookId: String?) -> [TranslationWordToken] {
        let tokens = tokenize(sentence, bookId: bookId)
        var wordTokens: [TranslationWordToken] = []
        let phienAm = TranslationManager.shared.phienAmMap
        
        let nsSentence = sentence as NSString
        var currentUTF16Offset = 0
        let totalUTF16Length = nsSentence.length
        
        for token in tokens {
            let tokenUTF16Length = (token as NSString).length
            guard currentUTF16Offset + tokenUTF16Length <= totalUTF16Length else { break }
            let originalText = nsSentence.substring(with: NSRange(location: currentUTF16Offset, length: tokenUTF16Length))
            
            let (translatedToken, isMatched) = resolveTokenMeaning(for: token, bookId: bookId, phienAm: phienAm)
            
            let trimmedTrans = translatedToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if isMatched || !trimmedTrans.isEmpty || !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                wordTokens.append(TranslationWordToken(
                    originalText: originalText,
                    translatedText: isMatched ? trimmedTrans : (trimmedTrans.isEmpty ? originalText : trimmedTrans),
                    originalOffset: currentUTF16Offset,
                    originalLength: tokenUTF16Length
                ))
            }
            
            currentUTF16Offset += tokenUTF16Length
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
