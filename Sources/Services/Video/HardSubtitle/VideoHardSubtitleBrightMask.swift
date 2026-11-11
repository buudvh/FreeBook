import CoreGraphics
import CoreVideo
import Foundation

/// Mặt nạ "điểm sáng" của dải dưới khung hình — bộ lọc rẻ trước Vision (dịch phụ đề cứng, 1.3.830).
///
/// Phụ đề in sẵn thường là chữ trắng / vàng viền đen ⇒ các điểm rất sáng ở dải dưới gần như đứng yên suốt một câu, kể cả khi
/// nền phim chuyển động. Hai khung có mặt nạ giống nhau (Jaccard ≥ ngưỡng) ⇒ cùng câu ⇒ khỏi chạy Vision.
///
/// - Đọc thẳng mặt phẳng độ sáng (Y) của buffer 4:2:0 hai mặt phẳng, lấy mẫu một lưới `columns` × `rows` điểm — không dựng ảnh.
/// - Ngưỡng theo dải màu của buffer: full range (0–255) và video range (16–235).
/// - Mặt nạ **chỉ** dùng để bỏ qua lượt giống lần trước. Mặt nạ rỗng không chứng minh là không có phụ đề (chữ màu nhạt dưới
///   ngưỡng) — engine vẫn chạy Vision thưa khi rỗng.
/// - Định dạng khác (10 bit, BGRA…) ⇒ `init` trả `nil` ⇒ engine coi như "đã đổi" và chạy Vision.
struct VideoHardSubtitleBrightMask: Sendable {
    static let columns = 128
    static let rows = 32
    static let fullRangeThreshold: UInt8 = 200
    static let videoRangeThreshold: UInt8 = 188
    /// Ít hơn số điểm này ⇒ coi là "gần như rỗng".
    static let nearlyEmptyCount = 12
    /// Jaccard từ ngưỡng này trở lên ⇒ cùng câu phụ đề.
    static let similarThreshold = 0.9

    private static let wordCount = (columns * rows + 63) / 64

    private(set) var bits: [UInt64]
    private(set) var brightCount: Int

    var isNearlyEmpty: Bool { brightCount < Self.nearlyEmptyCount }

    /// `stripTopRatio`: mép trên của dải, tính theo chiều cao khung (gốc trên-trái của bộ nhớ buffer).
    init?(pixelBuffer: CVPixelBuffer, stripTopRatio: CGFloat) {
        let threshold: UInt8
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            threshold = Self.fullRangeThreshold
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            threshold = Self.videoRangeThreshold
        default:
            return nil
        }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let top = min(height, max(0, Int((CGFloat(height) * stripTopRatio).rounded(.down))))
        let stripHeight = height - top
        guard width >= Self.columns, stripHeight >= Self.rows else { return nil }

        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var bits = [UInt64](repeating: 0, count: Self.wordCount)
        var count = 0
        for row in 0..<Self.rows {
            let y = top + (row * 2 + 1) * stripHeight / (Self.rows * 2)
            let rowStart = bytes + y * bytesPerRow
            for column in 0..<Self.columns {
                let x = (column * 2 + 1) * width / (Self.columns * 2)
                guard rowStart[x] >= threshold else { continue }
                let index = row * Self.columns + column
                bits[index >> 6] |= UInt64(1) << UInt64(index & 63)
                count += 1
            }
        }
        self.bits = bits
        self.brightCount = count
    }

    /// Jaccard của hai tập điểm sáng; cả hai rỗng ⇒ 1.
    func similarity(to other: VideoHardSubtitleBrightMask) -> Double {
        var intersection = 0
        var union = 0
        for index in 0..<min(bits.count, other.bits.count) {
            intersection += (bits[index] & other.bits[index]).nonzeroBitCount
            union += (bits[index] | other.bits[index]).nonzeroBitCount
        }
        guard union > 0 else { return 1 }
        return Double(intersection) / Double(union)
    }
}
