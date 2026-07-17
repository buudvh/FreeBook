import Foundation
import CoreText
import UIKit

public struct CoreTextPage {
    public let chapterIndex: Int
    public let pageIndex: Int
    public let range: NSRange
}

final class CoreTextPaginator {
    static let shared = CoreTextPaginator()
    
    private init() {}
    
    /// Phân chia NSAttributedString của một chương thành các trang có chiều cao cố định
    /// - Parameters:
    ///   - attributedString: Chuỗi văn bản đã định dạng kèm Custom Attributes
    ///   - bounds: Kích thước vùng hiển thị chữ thực tế trên một trang (thường là CGRect có size = màn hình - margins)
    ///   - chapterIndex: Chỉ số chương sách
    /// - Returns: Mảng các CoreTextPage lưu thông tin khoảng ký tự của từng trang
    func paginate(
        attributedString: NSAttributedString,
        bounds: CGRect,
        chapterIndex: Int
    ) -> [CoreTextPage] {
        var pages: [CoreTextPage] = []
        guard attributedString.length > 0 else { return [] }
        
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGPath(rect: bounds, transform: nil)
        
        var textPos = 0
        let textLen = attributedString.length
        var pageIdx = 0
        
        while textPos < textLen {
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(textPos, 0), path, nil)
            let frameRange = CTFrameGetVisibleStringRange(frame)
            
            // Đảm bảo không bị lặp vô tận nếu frame không chứa nổi 1 ký tự (tránh kẹt)
            guard frameRange.length > 0 else {
                let fallbackLength = min(1, textLen - textPos)
                pages.append(CoreTextPage(
                    chapterIndex: chapterIndex,
                    pageIndex: pageIdx,
                    range: NSRange(location: textPos, length: fallbackLength)
                ))
                textPos += fallbackLength
                pageIdx += 1
                continue
            }
            
            let nsRange = NSRange(location: frameRange.location, length: frameRange.length)
            pages.append(CoreTextPage(
                chapterIndex: chapterIndex,
                pageIndex: pageIdx,
                range: nsRange
            ))
            
            textPos += frameRange.length
            pageIdx += 1
        }
        
        return pages
    }
}
