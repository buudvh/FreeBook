import CoreGraphics
import Foundation

/// Gom các dòng Vision trả về thành khối chữ — mỗi khối thường là một bong bóng thoại. Hàm thuần, không I/O.
///
/// Hai dòng cùng khối khi: cao gần bằng nhau (≤ `maxLineHeightRatio` lần), khe dọc ≤ `maxVerticalGapRatio` × dòng thấp hơn,
/// và chồng nhau theo chiều ngang ≥ `minHorizontalOverlapRatio` × dòng hẹp hơn. Quan hệ lan truyền (A–B, B–C ⇒ A, B, C cùng
/// khối). Dịch theo khối thay vì theo dòng để VietPhrase thấy trọn câu thoại — câu Trung hay bị ngắt giữa chừng khi xuống
/// dòng trong bong bóng.
///
/// Chữ viết dọc (cột hẹp đứng cạnh nhau) không được gom — v1 chỉ nhắm chữ ngang của manhua.
enum ComicTextBlockGrouper {
    static let maxVerticalGapRatio: CGFloat = 0.8
    static let minHorizontalOverlapRatio: CGFloat = 0.3
    static let maxLineHeightRatio: CGFloat = 1.6
    /// Độ sáng trung bình (0…1) của vùng khối dưới mức này ⇒ nền tối.
    static let darkLumaThreshold: CGFloat = 0.45

    static func blocks(from lines: [ComicTextRecognizer.Line], image: CGImage) -> [ComicTextBlock] {
        guard !lines.isEmpty, image.width > 0, image.height > 0 else { return [] }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        // So khoảng cách trong điểm ảnh: toạ độ chuẩn hoá của hai trục không cùng thang.
        let rects = lines.map {
            CGRect(x: $0.rect.minX * width, y: $0.rect.minY * height, width: $0.rect.width * width, height: $0.rect.height * height)
        }

        var parent = Array(rects.indices)
        func root(_ index: Int) -> Int {
            var current = index
            while parent[current] != current {
                parent[current] = parent[parent[current]]
                current = parent[current]
            }
            return current
        }
        for first in rects.indices {
            for second in rects.indices where second > first && belongTogether(rects[first], rects[second]) {
                let a = root(first)
                let b = root(second)
                if a != b { parent[b] = a }
            }
        }

        var groups: [Int: [Int]] = [:]
        for index in rects.indices {
            groups[root(index), default: []].append(index)
        }

        let blocks = groups.values.map { indices -> ComicTextBlock in
            let ordered = indices.sorted { lhs, rhs in
                rects[lhs].minY != rects[rhs].minY ? rects[lhs].minY < rects[rhs].minY : rects[lhs].minX < rects[rhs].minX
            }
            let union = ordered.dropFirst().reduce(rects[ordered[0]]) { $0.union(rects[$1]) }
            let averageLineHeight = ordered.reduce(CGFloat(0)) { $0 + rects[$1].height } / CGFloat(ordered.count)
            return ComicTextBlock(
                x: Double(union.minX / width),
                y: Double(union.minY / height),
                width: Double(union.width / width),
                height: Double(union.height / height),
                text: joinedText(ordered.map { lines[$0].text }),
                lineHeight: Double(averageLineHeight / height),
                isDarkBackground: isDark(region: union, in: image)
            )
        }
        return blocks.sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
    }

    // MARK: - Luật gom

    private static func belongTogether(_ a: CGRect, _ b: CGRect) -> Bool {
        let shorter = min(a.height, b.height)
        let taller = max(a.height, b.height)
        guard shorter > 0, taller / shorter <= maxLineHeightRatio else { return false }
        // Âm khi hai dòng chồng nhau theo chiều dọc (cùng hàng) — khi đó chỉ còn luật chồng ngang quyết định.
        let verticalGap = max(a.minY, b.minY) - min(a.maxY, b.maxY)
        guard verticalGap <= shorter * maxVerticalGapRatio else { return false }
        let horizontalOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        return horizontalOverlap >= min(a.width, b.width) * minHorizontalOverlapRatio
    }

    /// Ghép các dòng của một khối: chữ Hán / dấu câu toàn khổ ở chỗ nối ⇒ ghép liền; chữ Latin hai bên ⇒ thêm một dấu cách.
    private static func joinedText(_ parts: [String]) -> String {
        var result = ""
        for part in parts {
            if let last = result.unicodeScalars.last,
               let first = part.unicodeScalars.first,
               !isWideScalar(last), !isWideScalar(first) {
                result += " "
            }
            result += part
        }
        return result
    }

    private static func isWideScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF, 0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }

    // MARK: - Màu nền

    /// Thu vùng khối về 8×8 điểm (nền trắng trước, để vùng trong suốt không thành "tối") rồi lấy độ sáng trung bình.
    /// Nét chữ chỉ chiếm phần nhỏ của bong bóng nên trung bình nghiêng về màu nền.
    private static func isDark(region: CGRect, in image: CGImage) -> Bool {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = region.integral.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1,
              let crop = image.cropping(to: clipped) else { return false }

        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            let target = CGRect(x: 0, y: 0, width: side, height: side)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(target)
            context.interpolationQuality = .medium
            context.draw(crop, in: target)
            return true
        }
        guard drawn else { return false }

        var total: CGFloat = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = CGFloat(pixels[offset])
            let green = CGFloat(pixels[offset + 1])
            let blue = CGFloat(pixels[offset + 2])
            total += (0.299 * red + 0.587 * green + 0.114 * blue) / 255
        }
        return total / CGFloat(side * side) < darkLumaThreshold
    }
}
