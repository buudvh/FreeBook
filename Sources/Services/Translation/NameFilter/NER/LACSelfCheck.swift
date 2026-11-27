import Foundation

/// Tự kiểm bộ gán nhãn vừa nạp với `lac_golden.json` (203 câu tự viết + chuỗi từ ngẫu nhiên kèm kết quả của LAC gốc),
/// một lần mỗi lần nạp.
///
/// - Tách từ + id + độ dài phải trùng **100%** (thuần tất định, không có số thực khác nền tảng) — lệch ⇒ `selfCheckFailed`.
/// - Nhãn cuối (`outWords` / `outTags`) cho lệch tối đa `maxOutputMismatches` câu: embedding fp16, thứ tự cộng của
///   Accelerate khác numpy / Paddle nên vài câu sát ngưỡng có thể đổi nhãn (bản Python fp16 lệch 2 / 3203 câu truyện).
///
/// Đây là kênh gỡ lỗi duy nhất trên máy (không đính debugger được): lệch thì log `❌` mẫu đầu tiên, bước lệch, chuỗi
/// mong đợi và chuỗi app ra.
enum LACSelfCheck {
    static let maxOutputMismatches = 3

    struct Summary {
        let samples: Int
        /// Câu có dãy id nhãn thô khác LAC (thông tin; có thể khác mà nhãn cuối vẫn trùng).
        let tagIDMismatches: Int
        let outputMismatches: Int
    }

    private struct Sample: Decodable {
        let text: String
        let words: [String]
        let ids: [Int32]
        let wordLength: [Int]
        let tagIds: [Int]
        let outWords: [String]
        let outTags: [String]
    }

    static func run(_ tagger: LACTagger, golden data: Data, expectedCount: Int) throws -> Summary {
        let samples: [Sample]
        do {
            samples = try JSONDecoder().decode([Sample].self, from: data)
        } catch {
            throw LACModelError.invalidFiles("\(LACModelMirror.goldenName) không đọc được")
        }
        guard samples.count == expectedCount else {
            throw LACModelError.invalidFiles("\(LACModelMirror.goldenName) có \(samples.count) mẫu, cần \(expectedCount)")
        }

        var tagIDMismatches = 0
        var outputMismatches: [String] = []
        for (index, sample) in samples.enumerated() {
            if index % 16 == 0 { try Task.checkCancellation() }
            let result = tagger.analyze(sample.text)
            guard sameScalars(result.words, sample.words) else {
                throw failure(stage: "tách từ", index: index, sample: sample,
                              expected: joined(sample.words), actual: joined(result.words))
            }
            guard result.ids == sample.ids else {
                throw failure(stage: "id", index: index, sample: sample,
                              expected: joined(sample.ids.map { "\($0)" }), actual: joined(result.ids.map { "\($0)" }))
            }
            guard result.lengths == sample.wordLength else {
                throw failure(stage: "độ dài", index: index, sample: sample,
                              expected: joined(sample.wordLength.map { "\($0)" }),
                              actual: joined(result.lengths.map { "\($0)" }))
            }
            if result.tagIDs != sample.tagIds { tagIDMismatches += 1 }
            let words = result.tokens.map(\.text)
            let tags = result.tokens.map(\.tag)
            if !sameScalars(words, sample.outWords) || tags != sample.outTags {
                outputMismatches.append("#\(index) «\(clipped(sample.text))» LAC: \(pairs(sample.outWords, sample.outTags))"
                    + " — app: \(pairs(words, tags))")
            }
        }

        if outputMismatches.count > maxOutputMismatches {
            AppLogger.shared.log("❌ 🧠 [LAC] Tự kiểm: nhãn lệch \(outputMismatches.count) / \(samples.count) câu (cho phép "
                + "\(maxOutputMismatches)), id nhãn thô lệch \(tagIDMismatches) câu")
            for line in outputMismatches.prefix(3) {
                AppLogger.shared.log("❌ 🧠 [LAC] Tự kiểm lệch nhãn \(line)")
            }
            throw LACModelError.selfCheckFailed("nhãn lệch \(outputMismatches.count) / \(samples.count) câu")
        }
        for line in outputMismatches {
            AppLogger.shared.log("🧠 [LAC] Tự kiểm lệch nhãn (trong ngưỡng) \(line)")
        }
        return Summary(samples: samples.count, tagIDMismatches: tagIDMismatches,
                       outputMismatches: outputMismatches.count)
    }

    private static func failure(stage: String, index: Int, sample: Sample, expected: String, actual: String) -> Error {
        AppLogger.shared.log("❌ 🧠 [LAC] Tự kiểm: \(stage) lệch ở mẫu #\(index) «\(clipped(sample.text))» — LAC: "
            + "\(clipped(expected)) — app: \(clipped(actual))")
        return LACModelError.selfCheckFailed("\(stage) lệch ở mẫu #\(index)")
    }

    /// So từng code point (`String ==` của Swift so tương đương chính tắc, lỏng hơn Python).
    private static func sameScalars(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.unicodeScalars.elementsEqual($1.unicodeScalars) }
    }

    private static func joined(_ items: [String]) -> String {
        items.joined(separator: "|")
    }

    private static func pairs(_ words: [String], _ tags: [String]) -> String {
        clipped(zip(words, tags).map { "\($0)/\($1)" }.joined(separator: " "))
    }

    private static func clipped(_ text: String, limit: Int = 160) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}
