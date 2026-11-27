import Foundation

/// Mô hình **đoán tên Latin** của Lọc name local (công tắc "Ưu tiên tên Latin", plan
/// `Docs/Plans/2026-11-27-nghia-ten-tay-huyen.md` mục 3): bộ giải mã `translit_latin.json` định dạng 1, đúng `SPEC` của
/// `Tools/lac-export/export_translit.py` và bản tham chiếu `TranslitModel` trong
/// `Docs/Plans/local-name-filter-lac/name_meaning.py` (khớp `Model.predict` của công cụ học 6000/6000 mục VP).
///
/// - `translitChars`: tập "chữ phiên âm" — `LocalNameFilterProperNames.looksTransliterated` (≥ một nửa số chữ thuộc tập).
/// - `predict`: mỗi chữ Hán ↔ một đoạn chữ cái theo vị trí trong tên (S một mình / B đầu / M giữa / E cuối; thiếu thì thử
///   M, B, E); tìm chùm 16 với điểm = Σ log p(đoạn) + λ · LM chữ cái bậc 3 (làm trơn cộng hằng); hết tên cộng λ · LM("$");
///   lấy điểm cao nhất (hoà ⇒ giả thuyết sinh trước, như `sort` ổn định + `max` của Python); ít nguyên âm hơn
///   max(1, ⌊n × minVowelRatio⌋) ⇒ không đoán (弗克 ⇒ "Fk" bị bỏ). Viết hoa chữ đầu.
///
/// Bất biến sau khi dựng ⇒ dùng chung giữa các task.
final class LocalNameFilterLatinModel: Sendable {
    /// Một đoạn chữ cái ứng với một chữ Hán.
    struct Segment: Sendable {
        let text: String
        /// Chỉ số ký hiệu của từng chữ cái (`symbol(_:)`).
        let symbols: [UInt8]
        /// `log(p)` tính sẵn — cùng giá trị Python tính lại mỗi lần.
        let logProbability: Double
    }

    /// Vị trí của chữ trong tên — chỉ số vào mảng đoạn của một chữ.
    private enum Position: Int, CaseIterable {
        case single = 0, begin, middle, end

        init?(code: String) {
            switch code {
            case "S": self = .single
            case "B": self = .begin
            case "M": self = .middle
            case "E": self = .end
            default: return nil
            }
        }

        static func of(index: Int, count: Int) -> Position {
            if count == 1 { return .single }
            if index == 0 { return .begin }
            return index == count - 1 ? .end : .middle
        }
    }

    private struct Hypothesis {
        var text: String
        var score: Double
        /// Hai ký hiệu cuối của "^^" + text.
        var previous: UInt8
        var last: UInt8
    }

    static let beamWidth = 16
    /// a–z = 0…25, "^" = 26, "$" = 27, ký tự khác = 28 (không có trong dữ liệu ⇒ luôn đếm 0, như `dict.get(…, 0)`).
    private static let symbolCount = 29
    private static let caret: UInt8 = 26
    private static let dollar: UInt8 = 27
    private static let other: UInt8 = 28
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    /// "Chữ phiên âm" (code point).
    let translitChars: Set<UInt32>
    private let segments: [UInt32: [[Segment]]]
    private let trigram: [Double]
    private let context: [Double]
    private let lmWeight: Double
    private let smoothing: Double
    private let denominatorSmoothing: Double
    private let minVowelRatio: Double

    /// Đọc JSON đã kiểm sha256. Sai định dạng ⇒ `LACModelError.invalidFiles`.
    init(data: Data) throws {
        func invalid(_ why: String) -> LACModelError {
            LACModelError.invalidFiles("\(LocalNameFilterLatinModelStore.fileName): \(why)")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw invalid("không đọc được JSON")
        }
        guard (root["format"] as? NSNumber)?.intValue == 1 else { throw invalid("định dạng lạ") }
        guard let weight = (root["lmWeight"] as? NSNumber)?.doubleValue,
              let smoothing = (root["lmSmoothing"] as? NSNumber)?.doubleValue,
              let alphabet = (root["lmAlphabet"] as? NSNumber)?.intValue,
              let ratio = (root["minVowelRatio"] as? NSNumber)?.doubleValue,
              let chars = root["translitChars"] as? String,
              let rawSegments = root["segments"] as? [String: Any],
              let rawTrigram = root["trigram"] as? [String: Any],
              let rawContext = root["context"] as? [String: Any] else {
            throw invalid("thiếu trường")
        }
        lmWeight = weight
        self.smoothing = smoothing
        // Python: `ctx + smooth * alphabet` (số thực × số nguyên).
        denominatorSmoothing = smoothing * Double(alphabet)
        minVowelRatio = ratio
        translitChars = Set(chars.unicodeScalars.map(\.value))
        segments = try Self.decodeSegments(rawSegments, invalid: invalid)
        trigram = Self.decodeCounts(rawTrigram, length: 3)
        context = Self.decodeCounts(rawContext, length: 2)
    }

    // MARK: - Đoán

    /// Tên Latin đoán cho một mảnh chữ Hán (không dấu ngăn), `nil` = không đoán được (chữ không có trong mô hình, hoặc
    /// quá ít nguyên âm).
    func predict(_ scalars: [UInt32]) -> String? {
        let count = scalars.count
        guard count > 0 else { return nil }
        var hypotheses = [Hypothesis(text: "", score: 0, previous: Self.caret, last: Self.caret)]
        for (index, scalar) in scalars.enumerated() {
            guard let options = candidates(scalar, Position.of(index: index, count: count)) else { return nil }
            var next: [Hypothesis] = []
            next.reserveCapacity(hypotheses.count * options.count)
            for hypothesis in hypotheses {
                for segment in options {
                    let model = languageModel(hypothesis.previous, hypothesis.last, segment.symbols)
                    next.append(Hypothesis(
                        text: hypothesis.text + segment.text,
                        score: hypothesis.score + segment.logProbability + lmWeight * model.score,
                        previous: model.previous,
                        last: model.last
                    ))
                }
            }
            // Sort ổn định theo điểm giảm dần: hoà điểm giữ thứ tự sinh.
            let order = next.indices.sorted { lhs, rhs in
                next[lhs].score != next[rhs].score ? next[lhs].score > next[rhs].score : lhs < rhs
            }
            hypotheses = order.prefix(Self.beamWidth).map { next[$0] }
        }
        var best: (text: String, score: Double)?
        for hypothesis in hypotheses {
            let total = hypothesis.score
                + lmWeight * languageModel(hypothesis.previous, hypothesis.last, [Self.dollar]).score
            if best == nil || total > best!.score { best = (hypothesis.text, total) }
        }
        guard let text = best?.text else { return nil }
        let vowelCount = text.reduce(0) { $0 + (Self.vowels.contains($1) ? 1 : 0) }
        let required = max(1, Int((Double(count) * minVowelRatio).rounded(.down)))
        guard vowelCount >= required else { return nil }
        return text.prefix(1).uppercased() + String(text.dropFirst())
    }

    /// Đoạn của chữ ở vị trí `position`; thiếu ⇒ thử M, rồi B, rồi E.
    private func candidates(_ scalar: UInt32, _ position: Position) -> [Segment]? {
        guard let byPosition = segments[scalar] else { return nil }
        for candidate in [position, .middle, .begin, .end] where !byPosition[candidate.rawValue].isEmpty {
            return byPosition[candidate.rawValue]
        }
        return nil
    }

    /// Σ log((trigram[w + c] + s) / (context[w] + s · alphabet)) dọc các chữ cái, `w` = hai ký hiệu trước.
    private func languageModel(_ previous: UInt8, _ last: UInt8, _ symbols: [UInt8])
        -> (score: Double, previous: UInt8, last: UInt8) {
        var first = previous
        var second = last
        var total = 0.0
        let size = Self.symbolCount
        for symbol in symbols {
            let contextIndex = Int(first) * size + Int(second)
            let numerator = trigram[contextIndex * size + Int(symbol)] + smoothing
            total += log(numerator / (context[contextIndex] + denominatorSmoothing))
            first = second
            second = symbol
        }
        return (total, first, second)
    }

    // MARK: - Đọc JSON

    private static func symbol(_ scalar: Unicode.Scalar) -> UInt8 {
        switch scalar.value {
        case 0x61...0x7A: return UInt8(scalar.value - 0x61)
        case 0x5E: return caret
        case 0x24: return dollar
        default: return other
        }
    }

    /// `{chữ: {"S"|"B"|"M"|"E": [[đoạn, xác suất], …]}}`, giữ đúng thứ tự trong file (thứ tự sinh giả thuyết).
    private static func decodeSegments(
        _ raw: [String: Any],
        invalid: (String) -> LACModelError
    ) throws -> [UInt32: [[Segment]]] {
        var result: [UInt32: [[Segment]]] = [:]
        result.reserveCapacity(raw.count)
        for (key, value) in raw {
            let scalars = Array(key.unicodeScalars)
            guard scalars.count == 1, let byPosition = value as? [String: Any] else { throw invalid("đoạn hỏng") }
            var lists = [[Segment]](repeating: [], count: Position.allCases.count)
            for (code, items) in byPosition {
                guard let position = Position(code: code), let items = items as? [Any] else { throw invalid("đoạn hỏng") }
                for item in items {
                    guard let pair = item as? [Any], pair.count == 2, let text = pair[0] as? String,
                          let probability = (pair[1] as? NSNumber)?.doubleValue, probability > 0, !text.isEmpty else {
                        throw invalid("đoạn hỏng")
                    }
                    lists[position.rawValue].append(Segment(
                        text: text, symbols: text.unicodeScalars.map(symbol), logProbability: log(probability)
                    ))
                }
            }
            result[scalars[0].value] = lists
        }
        return result
    }

    /// Bảng đếm theo chuỗi `length` ký hiệu ⇒ mảng phẳng. Khoá có ký tự ngoài a–z / ^ / $ bỏ qua (Python tra đúng chuỗi,
    /// dữ liệu không có khoá như vậy).
    private static func decodeCounts(_ raw: [String: Any], length: Int) -> [Double] {
        var table = [Double](repeating: 0, count: Int(pow(Double(symbolCount), Double(length))))
        for (key, value) in raw {
            let symbols = key.unicodeScalars.map(symbol)
            guard symbols.count == length, !symbols.contains(other),
                  let count = (value as? NSNumber)?.doubleValue else { continue }
            let index = symbols.reduce(0) { $0 * symbolCount + Int($1) }
            table[index] = count
        }
        return table
    }
}
