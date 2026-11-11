import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// Nhận phụ đề Trung in sẵn ở dải dưới một khung phim bằng Vision, chạy trên máy (đọc phụ đề cứng, 1.3.830; ghép chữ 1.3.840).
///
/// - Cắt dải dưới (`stripTopRatio` → đáy) **trước** khi đưa vào Vision ⇒ khung Vision trả về chuẩn hoá theo dải, gốc
///   dưới-trái; quy đổi một lần sang khung chuẩn hoá theo **cả khung hình**, gốc trên-trái (không dùng `regionOfInterest`
///   để khỏi phải đoán hệ toạ độ).
/// - **Ghép chữ theo quy ước phụ đề Trung** (1.3.840 — trước đó câu dịch tầm bậy): phụ đề dùng **dấu cách thay dấu phẩy**
///   (`我知道 你不想去`) ⇒ khoảng trắng giữa hai chữ Hán đổi thành `，` để VietPhrase biết chỗ ngắt vế (không xoá đi cho hai
///   vế dính nhau). Vision hay cắt một dòng thành nhiều mảnh ở chỗ cách ⇒ gom mảnh theo **hàng** (chồng nhau theo chiều
///   dọc), trong hàng xếp **trái → phải**, nối bằng `，`.
/// - Lấy hàng dưới cùng + tối đa một hàng ngay trên nó. Hai hàng nối liền thành **một câu** (câu dài xuống dòng, như khối
///   bong bóng của truyện tranh); hàng bắt đầu bằng gạch ngang (thoại hai người) thì giữ xuống dòng.
/// - Bỏ mảnh không có chữ Hán, mảnh sát mép trái / phải (logo); hàng phải có ≥ `minimumHanCount` chữ Hán và tâm ngang trong
///   `centerXRange`.
/// - Hàm **chặn luồng gọi** tới khi Vision xong — chỉ gọi trên hàng đợi nền của engine.
/// - Các hằng là **giá trị khởi điểm chưa thử trên máy**.
enum VideoHardSubtitleRecognizer {
    /// Khối phụ đề nhận được.
    struct Recognition: Sendable, Equatable {
        /// Câu đưa vào dịch: các hàng đã ghép; chỉ có `"\n"` khi hàng sau là lời thoại riêng (bắt đầu bằng gạch ngang).
        let text: String
        /// Khung bao các hàng, chuẩn hoá theo cả khung hình, gốc trên-trái.
        let rect: CGRect
        /// Số hàng chữ trong khung (để lớp phủ tính cỡ chữ).
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
    /// Mảnh có tâm ngang ngoài khoảng này (sát mép) ⇒ logo / watermark, bỏ trước khi gom hàng.
    static let segmentCenterXRange: ClosedRange<CGFloat> = 0.05...0.95
    /// Hai mảnh cùng hàng khi phần chồng theo chiều dọc ≥ ngần này × chiều cao mảnh thấp hơn.
    static let sameRowOverlapRatio: CGFloat = 0.5
    /// Hàng trên được ghép khi mép dưới của nó cách mép trên hàng dưới cùng không quá ngần này lần chiều cao hàng dưới.
    static let stackedRowGapRatio: CGFloat = 1.6
    static let recognitionLanguages = ["zh-Hans", "zh-Hant"]

    private struct Piece {
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

    /// Khối phụ đề ở dải dưới của `pixelBuffer`; `nil` = không có hàng chữ Hán nào đạt điều kiện.
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
        let pieces: [Piece] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else { return nil }
            let text = joinClauses(candidate.string.split(whereSeparator: \.isWhitespace).map(String.init))
            guard hanCount(in: text) >= 1 else { return nil }
            // Vision: chuẩn hoá theo dải, gốc dưới-trái ⇒ chuẩn hoá theo cả khung, gốc trên-trái.
            let box = observation.boundingBox
            let rect = CGRect(
                x: box.minX,
                y: (1 - stripRatio) + (1 - box.maxY) * stripRatio,
                width: box.width,
                height: box.height * stripRatio
            )
            guard segmentCenterXRange.contains(rect.midX) else { return nil }
            return Piece(text: text, rect: rect)
        }
        let rows = groupRows(pieces).filter { row in
            hanCount(in: row.text) >= minimumHanCount && centerXRange.contains(row.rect.midX)
        }
        return bottomBlock(of: rows)
    }

    // MARK: - Ghép

    /// Gom mảnh theo hàng (chồng nhau theo chiều dọc), trong hàng xếp trái → phải rồi nối như vế câu.
    private static func groupRows(_ pieces: [Piece]) -> [Piece] {
        var rows: [[Piece]] = []
        for piece in pieces.sorted(by: { $0.rect.midY < $1.rect.midY }) {
            if let index = rows.firstIndex(where: { row in row.contains { isSameRow($0.rect, piece.rect) } }) {
                rows[index].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.compactMap { row in
            let ordered = row.sorted { $0.rect.minX < $1.rect.minX }
            guard let first = ordered.first else { return nil }
            let rect = ordered.dropFirst().reduce(first.rect) { $0.union($1.rect) }
            return Piece(text: joinClauses(ordered.map(\.text)), rect: rect)
        }
    }

    private static func isSameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap >= min(a.height, b.height) * sameRowOverlapRatio
    }

    /// Hàng dưới cùng + hàng gần nhất ngay trên nó (nếu đủ sát), trên xuống, ghép thành một câu.
    private static func bottomBlock(of rows: [Piece]) -> Recognition? {
        guard let bottom = rows.max(by: { $0.rect.maxY < $1.rect.maxY }) else { return nil }
        let reach = bottom.rect.minY - bottom.rect.height * stackedRowGapRatio
        let above = rows
            .filter { $0.rect.maxY <= bottom.rect.minY + bottom.rect.height * 0.25 && $0.rect.maxY >= reach }
            .max(by: { $0.rect.maxY < $1.rect.maxY })
        guard let above else {
            return Recognition(text: bottom.text, rect: bottom.rect, lineCount: 1)
        }
        let separator = startsWithDash(bottom.text) ? "\n" : ""
        return Recognition(text: above.text + separator + bottom.text, rect: above.rect.union(bottom.rect), lineCount: 2)
    }

    /// Nối các vế: giữa hai chữ Hán (dấu cách của phụ đề) ⇒ `，`; cạnh dấu câu toàn khổ ⇒ nối liền; còn lại ⇒ dấu cách.
    static func joinClauses(_ parts: [String]) -> String {
        var result = ""
        for part in parts where !part.isEmpty {
            if let last = result.unicodeScalars.last, let first = part.unicodeScalars.first {
                if isFullWidthPunctuation(last) || isFullWidthPunctuation(first) {
                    // nối liền
                } else if isHan(last) && isHan(first) {
                    result += "，"
                } else {
                    result += " "
                }
            }
            result += part
        }
        return result
    }

    private static func startsWithDash(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return first == "-" || first == "－" || first == "—" || first == "–"
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }

    private static func isFullWidthPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        (0x3000...0x303F).contains(scalar.value) || (0xFF00...0xFF65).contains(scalar.value)
    }

    static func hanCount(in text: String) -> Int {
        text.unicodeScalars.reduce(0) { count, scalar in isHan(scalar) ? count + 1 : count }
    }
}
