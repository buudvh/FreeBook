import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// Nhận phụ đề Trung in sẵn ở dải dưới một khung phim bằng Vision, chạy trên máy (dịch phụ đề cứng, 1.3.830).
///
/// - Cắt dải dưới (`stripTopRatio` → đáy) **trước** khi đưa vào Vision ⇒ khung Vision trả về chuẩn hoá theo dải, gốc
///   dưới-trái; quy đổi một lần sang khung chuẩn hoá theo **cả khung hình**, gốc trên-trái (không dùng `regionOfInterest`
///   để khỏi phải đoán hệ toạ độ).
/// - Giữ dòng có ≥ `minimumHanCount` chữ Hán, tâm ngang trong `centerXRange` (bỏ logo / watermark ở hai góc), rồi lấy khối
///   dưới cùng: dòng thấp nhất + tối đa một dòng ngay trên nó (phụ đề hai dòng).
/// - Hàm **chặn luồng gọi** tới khi Vision xong — chỉ gọi trên hàng đợi nền của engine.
/// - Các hằng là **giá trị khởi điểm chưa thử trên máy**.
enum VideoHardSubtitleRecognizer {
    /// Khối phụ đề nhận được.
    struct Recognition: Sendable, Equatable {
        /// Các dòng nối bằng `"\n"`, trên xuống, đã bỏ khoảng trắng (tiếng Trung không cách chữ).
        let text: String
        /// Khung bao các dòng, chuẩn hoá theo cả khung hình, gốc trên-trái.
        let rect: CGRect
        let lineCount: Int

        var hanCount: Int { VideoHardSubtitleRecognizer.hanCount(in: text) }
    }

    /// Dải dưới bắt đầu ở 70% chiều cao khung.
    static let stripTopRatio: CGFloat = 0.7
    /// Chiều cao chữ tối thiểu, tương đối với chiều cao **dải** (0,08 × 30% ≈ 2,4% chiều cao khung) — bỏ chữ li ti.
    static let minimumTextHeight: Float = 0.08
    static let minimumConfidence: Float = 0.3
    static let minimumHanCount = 2
    static let centerXRange: ClosedRange<CGFloat> = 0.15...0.85
    /// Dòng trên được ghép vào khối khi mép dưới của nó cách mép trên dòng dưới cùng không quá ngần này lần chiều cao dòng.
    static let stackedLineGapRatio: CGFloat = 1.6
    static let maximumLineCount = 2
    static let recognitionLanguages = ["zh-Hans", "zh-Hant"]

    private struct Line {
        let text: String
        let rect: CGRect
    }

    /// Vision trên máy có nhận được chữ Trung giản thể không (mức `.accurate`; mức `.fast` chỉ đọc chữ Latin).
    static func supportsChinese() -> Bool {
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = .accurate
        let supported = (try? probe.supportedRecognitionLanguages()) ?? []
        return supported.contains("zh-Hans")
    }

    /// Khối phụ đề ở dải dưới của `pixelBuffer`; `nil` = không có dòng chữ Hán nào đạt điều kiện.
    static func recognize(in pixelBuffer: CVPixelBuffer) throws -> Recognition? {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard width > 0, height > 0 else { return nil }
        let stripHeight = (height * (1 - stripTopRatio)).rounded(.down)
        guard stripHeight >= 8 else { return nil }
        // CIImage gốc dưới-trái ⇒ dải dưới là (0, 0, rộng, cao dải); extent đã ở gốc toạ độ, không cần dời.
        let strip = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: CGRect(x: 0, y: 0, width: width, height: stripHeight))

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = recognitionLanguages
        request.usesLanguageCorrection = true
        request.minimumTextHeight = minimumTextHeight
        let handler = VNImageRequestHandler(ciImage: strip, options: [:])
        try handler.perform([request])

        let stripRatio = stripHeight / height
        let lines: [Line] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else { return nil }
            let text = candidate.string.filter { !$0.isWhitespace }
            guard hanCount(in: text) >= minimumHanCount else { return nil }
            // Vision: chuẩn hoá theo dải, gốc dưới-trái ⇒ chuẩn hoá theo cả khung, gốc trên-trái.
            let box = observation.boundingBox
            let rect = CGRect(
                x: box.minX,
                y: (1 - stripRatio) + (1 - box.maxY) * stripRatio,
                width: box.width,
                height: box.height * stripRatio
            )
            guard centerXRange.contains(rect.midX) else { return nil }
            return Line(text: text, rect: rect)
        }
        return bottomBlock(of: lines)
    }

    /// Dòng thấp nhất + các dòng xếp chồng ngay trên nó (tối đa `maximumLineCount`), trên xuống.
    private static func bottomBlock(of lines: [Line]) -> Recognition? {
        guard let bottom = lines.max(by: { $0.rect.maxY < $1.rect.maxY }) else { return nil }
        let reach = bottom.rect.minY - bottom.rect.height * stackedLineGapRatio
        let block = lines
            .filter { $0.rect.maxY >= reach }
            .sorted { $0.rect.minY < $1.rect.minY }
            .suffix(maximumLineCount)
        guard let first = block.first else { return nil }
        let rect = block.dropFirst().reduce(first.rect) { $0.union($1.rect) }
        return Recognition(text: block.map(\.text).joined(separator: "\n"), rect: rect, lineCount: block.count)
    }

    static func hanCount(in text: String) -> Int {
        text.unicodeScalars.reduce(0) { count, scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ? count + 1 : count
        }
    }
}
