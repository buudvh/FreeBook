import CoreGraphics
import Foundation

/// Gộp kết quả nhận chữ của các khung liên tiếp thành "câu đang hiện" (dịch phụ đề cứng, 1.3.830).
///
/// - OCR hay đọc lệch vài chữ giữa hai khung của cùng một câu ⇒ giống ≥ `sameTextSimilarity` (khoảng cách sửa chữ, chỉ xét
///   chữ, bỏ dấu câu) là **cùng câu**: giữ câu cũ để khỏi dịch lại và chữ dịch khỏi nháy. Ngoại lệ: bản mới nhiều chữ Hán
///   hơn (lượt trước chụp lúc chữ đang hiện dần) ⇒ thay bằng bản mới.
/// - Phải trống `clearAfterEmptySamples` lượt liên tiếp mới xoá câu (tránh nháy khi một khung đọc trượt).
/// - Kiểu giá trị thuần, không tự chạy gì; engine giữ một bản trên main.
struct VideoHardSubtitleCueTracker {
    typealias Recognition = VideoHardSubtitleRecognizer.Recognition

    enum Change: Equatable {
        case none
        /// Không còn câu nào ⇒ ẩn bản dịch.
        case cleared
        /// Cùng câu, khung chữ dời chỗ.
        case moved(Recognition)
        /// Câu mới (hoặc bản đọc tốt hơn của câu đang hiện) ⇒ cần dịch.
        case started(Recognition)
    }

    static let sameTextSimilarity = 0.75
    static let clearAfterEmptySamples = 2
    /// Dời ít hơn ngần này (theo chiều cao khung) thì coi như đứng yên.
    static let moveTolerance: CGFloat = 0.02

    private(set) var current: Recognition?
    private var emptyStreak = 0

    mutating func reset() {
        current = nil
        emptyStreak = 0
    }

    mutating func accept(_ recognition: Recognition?) -> Change {
        guard let recognition else {
            guard current != nil else { return .none }
            emptyStreak += 1
            guard emptyStreak >= Self.clearAfterEmptySamples else { return .none }
            reset()
            return .cleared
        }
        emptyStreak = 0
        if let current, Self.similarity(current.text, recognition.text) >= Self.sameTextSimilarity {
            if recognition.hanCount > current.hanCount {
                self.current = recognition
                return .started(recognition)
            }
            guard Self.hasMoved(from: current.rect, to: recognition.rect) else { return .none }
            let moved = Recognition(text: current.text, rect: recognition.rect, lineCount: current.lineCount)
            self.current = moved
            return .moved(moved)
        }
        current = recognition
        return .started(recognition)
    }

    /// 1 − khoảng cách Levenshtein / độ dài dài hơn, trên các chữ cái / chữ số (bỏ dấu câu, xuống dòng).
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs.filter { $0.isLetter || $0.isNumber })
        let right = Array(rhs.filter { $0.isLetter || $0.isNumber })
        let longest = max(left.count, right.count)
        guard longest > 0 else { return 1 }
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        var previous = Array(0...right.count)
        var row = [Int](repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            row[0] = i
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &row)
        }
        return 1 - Double(previous[right.count]) / Double(longest)
    }

    private static func hasMoved(from old: CGRect, to new: CGRect) -> Bool {
        abs(old.midY - new.midY) > moveTolerance || abs(old.height - new.height) > moveTolerance
    }
}
