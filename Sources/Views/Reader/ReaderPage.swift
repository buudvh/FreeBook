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
    
    /// Chia danh sách ParagraphItem thành các ReaderPage dựa trên kích thước chữ và giới hạn ký tự ước lượng hình học
    public static func paginate(
        paragraphItems: [ParagraphItem],
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        renderSize: CGSize,
        contentInsets: UIEdgeInsets
    ) -> [ReaderPage] {
        guard !paragraphItems.isEmpty else { return [] }
        
        // 1. Tính toán giới hạn ký tự động trên mỗi trang dựa trên kích thước màn hình thực tế và cỡ chữ
        let rawHeight = renderSize.height - contentInsets.top - contentInsets.bottom
        let lineHeight = max(1.0, fontSize + lineSpacing)
        let lineCount = floor(rawHeight / lineHeight)
        
        let charWidth = fontSize * 0.55 // Ước lượng chiều rộng trung bình ký tự tiếng Việt
        let rawWidth = renderSize.width - contentInsets.left - contentInsets.right
        let charsPerLine = rawWidth / charWidth
        
        // charLimit = số dòng * số ký tự mỗi dòng
        let charLimit = Int(max(200.0, lineCount * charsPerLine))
        
        var pages: [ReaderPage] = []
        var currentPageParagraphs: [ParagraphItem] = []
        var currentLength = 0
        var pageId = 0
        
        // Trạng thái lưu trữ tạm của đoạn văn đang chia dở giữa ranh giới trang
        var pendingOriginalSentences: [String] = []
        var pendingTranslatedSentences: [String] = []
        var pendingItemId: Int? = nil
        var pendingIsTitle = false
        
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
        
        var i = 0
        while i < paragraphItems.count || pendingItemId != nil {
            let origSentences: [String]
            let transSentences: [String]
            let itemId: Int
            let isTitle: Bool
            
            if let pId = pendingItemId {
                // Nạp tiếp phần câu chưa chia xong ở trang trước
                origSentences = pendingOriginalSentences
                transSentences = pendingTranslatedSentences
                itemId = pId
                isTitle = pendingIsTitle
                
                pendingItemId = nil
                pendingOriginalSentences = []
                pendingTranslatedSentences = []
            } else {
                // Đọc đoạn văn tiếp theo
                let item = paragraphItems[i]
                origSentences = splitIntoSentences(item.original)
                transSentences = splitIntoSentences(item.translated)
                itemId = item.id
                isTitle = item.isTitle
                i += 1
            }
            
            // Tiêu đề chương (nếu hiển thị) luôn nằm ở đầu trang 1
            if isTitle {
                if !currentPageParagraphs.isEmpty {
                    commitCurrentPage()
                }
                let titleLen = max(origSentences.joined(separator: " ").count, transSentences.joined(separator: " ").count)
                // Tiêu đề to (1.5x) và spacing lớn, quy đổi sang độ dài ký tự thường để ước lượng không gian chiếm dụng
                let equivalentLen = Int(Double(titleLen) * 2.2) + 120
                
                currentPageParagraphs.append(ParagraphItem(
                    id: itemId,
                    original: origSentences.joined(separator: " "),
                    translated: transSentences.joined(separator: " "),
                    isTitle: true
                ))
                currentLength += equivalentLen
                continue
            }
            
            var origGommed = ""
            var transGommed = ""
            var sentenceIdx = 0
            let maxSentences = max(origSentences.count, transSentences.count)
            
            while sentenceIdx < maxSentences {
                let origS = sentenceIdx < origSentences.count ? origSentences[sentenceIdx] : ""
                let transS = sentenceIdx < transSentences.count ? transSentences[sentenceIdx] : ""
                let sentenceLength = max(origS.count, transS.count)
                
                // Nếu thêm câu này làm tràn trang
                if currentLength + sentenceLength > charLimit {
                    if !currentPageParagraphs.isEmpty || !origGommed.isEmpty || !transGommed.isEmpty {
                        // Lưu phần đã gom của đoạn văn hiện tại vào trang này trước khi đóng
                        if !origGommed.isEmpty || !transGommed.isEmpty {
                            currentPageParagraphs.append(ParagraphItem(
                                id: itemId,
                                original: origGommed,
                                translated: transGommed,
                                isTitle: isTitle
                            ))
                        }
                        commitCurrentPage()
                        
                        // Đẩy các câu còn lại của đoạn văn sang pending để trang sau xử lý tiếp
                        pendingItemId = itemId
                        pendingIsTitle = isTitle
                        pendingOriginalSentences = Array(origSentences[sentenceIdx...])
                        pendingTranslatedSentences = Array(transSentences[sentenceIdx...])
                        break
                    } else {
                        // Trang hiện tại rỗng nhưng bản thân câu này quá dài: gom câu này vào trang và đóng ngay lập tức
                        origGommed = origS
                        transGommed = transS
                        currentPageParagraphs.append(ParagraphItem(
                            id: itemId,
                            original: origGommed,
                            translated: transGommed,
                            isTitle: isTitle
                        ))
                        commitCurrentPage()
                        
                        if sentenceIdx + 1 < maxSentences {
                            pendingItemId = itemId
                            pendingIsTitle = isTitle
                            pendingOriginalSentences = Array(origSentences[(sentenceIdx + 1)...])
                            pendingTranslatedSentences = Array(transSentences[(sentenceIdx + 1)...])
                        }
                        break
                    }
                } else {
                    // Gom câu vào đoạn văn hiện tại trên trang
                    if !origGommed.isEmpty { origGommed += " " }
                    origGommed += origS
                    
                    if !transGommed.isEmpty { transGommed += " " }
                    transGommed += transS
                    
                    currentLength += sentenceLength + 1 // +1 ký tự space/newline
                    sentenceIdx += 1
                }
            }
            
            // Nếu đã gom hết các câu mà không bị ngắt trang giữa chừng
            if pendingItemId == nil && (!origGommed.isEmpty || !transGommed.isEmpty) {
                currentPageParagraphs.append(ParagraphItem(
                    id: itemId,
                    original: origGommed,
                    translated: transGommed,
                    isTitle: isTitle
                ))
            }
        }
        
        // Đóng trang cuối cùng nếu còn dữ liệu
        if !currentPageParagraphs.isEmpty {
            commitCurrentPage()
        }
        
        return pages
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
