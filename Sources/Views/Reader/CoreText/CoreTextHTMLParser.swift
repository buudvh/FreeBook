import Foundation
import UIKit

// Định nghĩa Custom Attributes cho NSAttributedString để lưu trữ metadata của từng đoạn văn
public extension NSAttributedString.Key {
    static let paragraphId = NSAttributedString.Key("FreeBook.paragraphId")
    static let originalText = NSAttributedString.Key("FreeBook.originalText")
    static let transText = NSAttributedString.Key("FreeBook.transText")
}

final class CoreTextHTMLParser {
    static let shared = CoreTextHTMLParser()
    
    private init() {}
    
    /// Bóc tách chuỗi HTML chứa metadata đoạn văn thành NSAttributedString sạch kèm Custom Attributes
    /// - Parameters:
    ///   - html: Chuỗi HTML do FreeBook tự sinh chứa các thẻ <div>
    ///   - font: Font chữ nền hiển thị trong trình đọc
    ///   - textColor: Màu chữ hiển thị trong trình đọc
    ///   - lineSpacing: Giãn dòng
    ///   - paragraphSpacing: Khoảng cách giữa các đoạn văn
    func parse(
        html: String,
        font: UIFont,
        textColor: UIColor,
        lineSpacing: CGFloat = 6.0,
        paragraphSpacing: CGFloat = 16.0
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = html.components(separatedBy: "\n")
        
        // Cấu hình ParagraphStyle chung cho các đoạn văn
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.alignment = .left
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        var isFirstParagraph = true
        
        for line in lines {
            // Chỉ xử lý các dòng chứa thẻ div của đoạn văn
            guard line.contains("<div") && line.contains("id=\"para-") else { continue }
            
            // 1. Trích xuất id
            guard let idRange = line.range(of: "id=\""),
                  let idEndRange = line[idRange.upperBound...].range(of: "\"") else { continue }
            let paragraphId = String(line[idRange.upperBound..<idEndRange.lowerBound])
            
            // 2. Trích xuất data-original
            guard let origRange = line.range(of: "data-original=\""),
                  let origEndRange = line[origRange.upperBound...].range(of: "\"") else { continue }
            let originalText = String(line[origRange.upperBound..<origEndRange.lowerBound]).htmlUnescaped()
            
            // 3. Trích xuất data-trans
            guard let transRange = line.range(of: "data-trans=\""),
                  let transEndRange = line[transRange.upperBound...].range(of: "\"") else { continue }
            let transText = String(line[transRange.upperBound..<transEndRange.lowerBound]).htmlUnescaped()
            
            // 4. Trích xuất nội dung chữ hiển thị
            guard let contentStartRange = line.range(of: ">"),
                  let contentEndRange = line.range(of: "</div>", options: .backwards) else { continue }
            let displayText = String(line[contentStartRange.upperBound..<contentEndRange.lowerBound]).htmlUnescaped()
            
            // Thêm ký tự xuống dòng phân tách giữa các đoạn văn
            if !isFirstParagraph {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            isFirstParagraph = false
            
            // 5. Append đoạn văn mới kèm Custom Attributes
            let startLoc = result.length
            result.append(NSAttributedString(string: displayText, attributes: baseAttributes))
            let range = NSRange(location: startLoc, length: displayText.count)
            
            result.addAttribute(.paragraphId, value: paragraphId, range: range)
            result.addAttribute(.originalText, value: originalText, range: range)
            result.addAttribute(.transText, value: transText, range: range)
        }
        
        return result
    }
}

// MARK: - String Extension for HTML Unescaping
private extension String {
    func htmlUnescaped() -> String {
        return self.replacingOccurrences(of: "&amp;", with: "&")
                   .replacingOccurrences(of: "&quot;", with: "\"")
                   .replacingOccurrences(of: "&#39;", with: "'")
                   .replacingOccurrences(of: "&lt;", with: "<")
                   .replacingOccurrences(of: "&gt;", with: ">")
                   .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
