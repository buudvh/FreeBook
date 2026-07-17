import Foundation
import UIKit
import CoreText

final class CoreTextPageView: UIView {
    var attributedString: NSAttributedString? {
        didSet { setNeedsDisplay() }
    }
    
    var pageRange: NSRange? {
        didSet { setNeedsDisplay() }
    }
    
    var highlightRange: NSRange? {
        didSet { setNeedsDisplay() }
    }
    
    var contentInsets: UIEdgeInsets = .zero {
        didSet { setNeedsDisplay() }
    }
    
    var highlightColor: UIColor = UIColor.systemYellow.withAlphaComponent(0.3) {
        didSet { setNeedsDisplay() }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let attrString = attributedString,
              let range = pageRange,
              range.location != NSNotFound && range.length > 0 else { return }
        
        // 1. Cấu hình context CoreText (lật ngược trục Y)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        // 2. Định nghĩa vùng vẽ chữ thụt lề theo insets
        let drawingRect = rect.inset(by: contentInsets)
        let path = CGPath(rect: drawingRect, transform: nil)
        
        // 3. Khởi tạo framesetter và tạo frame
        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(range.location, range.length), path, nil)
        
        // 4. Vẽ nền highlight cho chữ đang phát TTS (nếu có)
        if let highlight = highlightRange, highlight.length > 0 {
            drawHighlight(for: highlight, in: frame, context: context, rect: rect)
        }
        
        // 5. Vẽ chữ CoreText lên màn hình
        CTFrameDraw(frame, context)
    }
    
    /// Vẽ nền màu cho khoảng ký tự đang highlight (Ví dụ khi đang nghe đọc TTS)
    private func drawHighlight(for highlight: NSRange, in frame: CTFrame, context: CGContext, rect: CGRect) {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        let lineCount = lines.count
        guard lineCount > 0 else { return }
        
        var origins = [CGPoint](repeating: .zero, count: lineCount)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &origins)
        
        context.saveGState()
        context.setFillColor(highlightColor.cgColor)
        
        for i in 0..<lineCount {
            let line = lines[i]
            let lineRange = CTLineGetStringRange(line)
            let nsLineRange = NSRange(location: lineRange.location, length: lineRange.length)
            
            // Tìm khoảng giao thoa giữa dòng hiện tại và highlightRange
            guard let intersection = nsLineRange.intersection(highlight) else { continue }
            
            // Tính toán vị trí X bắt đầu và kết thúc của vùng highlight trên dòng
            let startOffset = CTLineGetOffsetForStringIndex(line, intersection.location, nil)
            let endOffset = CTLineGetOffsetForStringIndex(line, intersection.location + intersection.length, nil)
            
            // Lấy thông số metric của dòng để tính chiều cao dòng
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let lineHeight = ascent + descent
            
            // Dựng hình chữ nhật highlight bao quanh dòng chữ tương ứng
            let origin = origins[i]
            let xPos = origin.x + startOffset
            let yPos = origin.y - descent // Chuyển dịch xuống mép dưới của chữ
            let width = endOffset - startOffset
            
            let highlightRect = CGRect(x: xPos, y: yPos, width: width, height: lineHeight)
            context.fill(highlightRect)
        }
        
        context.restoreGState()
    }
}

// MARK: - NSRange Intersection Helper
private extension NSRange {
    func intersection(_ other: NSRange) -> NSRange? {
        let maxStart = Swift.max(self.location, other.location)
        let minEnd = Swift.min(self.location + self.length, other.location + other.length)
        if maxStart < minEnd {
            return NSRange(location: maxStart, length: minEnd - maxStart)
        }
        return nil
    }
}
