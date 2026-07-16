import SwiftUI
import Foundation

public struct ReaderPage: Identifiable, Equatable {
    public let id: Int // Chỉ số trang trong chương (0, 1, 2...)
    public let paragraphItems: [ParagraphItem] // Danh sách các đoạn văn (hoặc đoạn văn cắt nhỏ) trong trang này
    public let combinedOriginal: String // Chuỗi văn bản gốc gộp lại
    public let combinedTranslated: String // Chuỗi văn bản dịch gộp lại
    public let originalParagraphRanges: [Int: NSRange] // Ánh xạ paragraph ID -> NSRange trong combinedOriginal
    public let translatedParagraphRanges: [Int: NSRange] // Ánh xạ paragraph ID -> NSRange trong combinedTranslated

    public static func == (lhs: ReaderPage, rhs: ReaderPage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.paragraphItems == rhs.paragraphItems &&
               lhs.combinedOriginal == rhs.combinedOriginal &&
               lhs.combinedTranslated == rhs.combinedTranslated &&
               lhs.originalParagraphRanges == rhs.originalParagraphRanges &&
               lhs.translatedParagraphRanges == rhs.translatedParagraphRanges
    }
}

public enum ReaderPageHelper {
    
    /// Tính toán lề dưới động sao cho chiều cao hiển thị của trang luôn là bội số nguyên của chiều cao dòng (lineHeight)
    public static func gridAlignedBottomInset(
        renderSize: CGSize,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        contentInsets: UIEdgeInsets
    ) -> CGFloat {
        guard renderSize.height > 0 else { return contentInsets.bottom }
        
        let rawHeight = renderSize.height - contentInsets.top - contentInsets.bottom
        let lineHeight = max(1.0, fontSize + lineSpacing)
        let lineCount = floor(rawHeight / lineHeight)
        
        guard lineCount >= 1 else { return contentInsets.bottom }
        
        let alignedHeight = lineCount * lineHeight
        let alignedBottom = renderSize.height - contentInsets.top - alignedHeight
        
        return max(contentInsets.bottom, alignedBottom)
    }
    
    /// Chia danh sách ParagraphItem thành các ReaderPage dựa trên kích thước chữ và giới hạn ký tự ước lượng
    public static func paginate(
        paragraphItems: [ParagraphItem],
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        renderSize: CGSize,
        contentInsets: UIEdgeInsets
    ) -> [ReaderPage] {
        guard !paragraphItems.isEmpty else { return [] }
        
        // Tính toán giới hạn ký tự động trên mỗi trang tỷ lệ nghịch với fontSize.
        // Mức cơ bản: ~800 ký tự khi fontSize = 20pt.
        let baseFontSize: CGFloat = 20.0
        let baseCharLimit: CGFloat = 800.0
        let charLimit = Int(max(200.0, (baseFontSize / fontSize) * baseCharLimit))
        
        var pages: [ReaderPage] = []
        var currentPageParagraphs: [ParagraphItem] = []
        var currentLength = 0
        var pageId = 0
        
        // Hàm đóng trang hiện tại và lưu vào danh sách
        func commitCurrentPage() {
            guard !currentPageParagraphs.isEmpty else { return }
            
            var combinedOriginal = ""
            var combinedTranslated = ""
            var originalRanges: [Int: NSRange] = [:]
            var translatedRanges: [Int: NSRange] = [:]
            
            for item in currentPageParagraphs {
                // Xử lý chuỗi gốc (Original)
                let origText = item.original
                let origStart = combinedOriginal.count
                if !combinedOriginal.isEmpty {
                    combinedOriginal += "\n"
                }
                combinedOriginal += origText
                let origLen = origText.count
                originalRanges[item.id] = NSRange(location: origStart + (origStart > 0 ? 1 : 0), length: origLen)
                
                // Xử lý chuỗi dịch (Translated)
                let transText = item.translated
                let transStart = combinedTranslated.count
                if !combinedTranslated.isEmpty {
                    combinedTranslated += "\n"
                }
                combinedTranslated += transText
                let transLen = transText.count
                translatedRanges[item.id] = NSRange(location: transStart + (transStart > 0 ? 1 : 0), length: transLen)
            }
            
            let page = ReaderPage(
                id: pageId,
                paragraphItems: currentPageParagraphs,
                combinedOriginal: combinedOriginal,
                combinedTranslated: combinedTranslated,
                originalParagraphRanges: originalRanges,
                translatedParagraphRanges: translatedRanges
            )
            pages.append(page)
            
            // Reset
            currentPageParagraphs = []
            currentLength = 0
            pageId += 1
        }
        
        for item in paragraphItems {
            let itemLength = max(item.original.count, item.translated.count)
            
            // Trường hợp 1: Nếu thêm đoạn văn này vượt quá giới hạn trang
            if currentLength + itemLength > charLimit {
                // Nếu trang hiện tại đã có chữ, ta đóng trang đó trước
                if !currentPageParagraphs.isEmpty {
                    commitCurrentPage()
                }
                
                // Nếu bản thân đoạn văn này đã dài hơn giới hạn ký tự của một trang, ta phải chia nhỏ nó ra
                if itemLength > charLimit {
                    let subParagraphs = splitParagraph(item, charLimit: charLimit)
                    for subItem in subParagraphs {
                        currentPageParagraphs.append(subItem)
                        commitCurrentPage()
                    }
                } else {
                    currentPageParagraphs.append(item)
                    currentLength = itemLength
                }
            } else {
                // Trường hợp 2: Vừa vặn, gom vào trang hiện tại
                currentPageParagraphs.append(item)
                currentLength += itemLength + 1 // +1 cho ký tự xuống dòng '\n'
            }
        }
        
        // Đóng trang cuối cùng nếu còn dữ liệu
        if !currentPageParagraphs.isEmpty {
            commitCurrentPage()
        }
        
        return pages
    }
    
    /// Chia nhỏ một đoạn văn quá dài thành các đoạn văn con nhỏ hơn dựa trên dấu câu
    private static func splitParagraph(_ item: ParagraphItem, charLimit: Int) -> [ParagraphItem] {
        let originalText = item.original
        let translatedText = item.translated
        
        let originalSentences = splitIntoSentences(originalText)
        let translatedSentences = splitIntoSentences(translatedText)
        
        var result: [ParagraphItem] = []
        var currentOriginal = ""
        var currentTranslated = ""
        var subId = 0
        
        let maxSentences = max(originalSentences.count, translatedSentences.count)
        
        for i in 0..<maxSentences {
            let orig = i < originalSentences.count ? originalSentences[i] : ""
            let trans = i < translatedSentences.count ? translatedSentences[i] : ""
            
            if currentOriginal.count + orig.count > charLimit || currentTranslated.count + trans.count > charLimit {
                if !currentOriginal.isEmpty || !currentTranslated.isEmpty {
                    result.append(ParagraphItem(
                        id: item.id, // Vẫn giữ nguyên ID gốc để đồng bộ TTS/dịch
                        original: currentOriginal,
                        translated: currentTranslated,
                        isTitle: item.isTitle
                    ))
                    currentOriginal = ""
                    currentTranslated = ""
                    subId += 1
                }
            }
            
            if !currentOriginal.isEmpty { currentOriginal += " " }
            currentOriginal += orig
            
            if !currentTranslated.isEmpty { currentTranslated += " " }
            currentTranslated += trans
        }
        
        if !currentOriginal.isEmpty || !currentTranslated.isEmpty {
            result.append(ParagraphItem(
                id: item.id,
                original: currentOriginal,
                translated: currentTranslated,
                isTitle: item.isTitle
            ))
        }
        
        return result
    }
    
    /// Phân tích chuỗi thành các câu dựa trên các dấu ngắt câu phổ biến
    private static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var currentSentence = ""
        let sentenceBoundary: CharacterSet = ["。", "！", "？", "!", "?", "\n", "\r"]
        
        for char in text {
            currentSentence.append(char)
            if let unicodeScalar = char.unicodeScalars.first, sentenceBoundary.contains(unicodeScalar) {
                let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                currentSentence = ""
            }
        }
        
        let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sentences.append(trimmed)
        }
        
        return sentences.isEmpty ? [text] : sentences
    }
}
