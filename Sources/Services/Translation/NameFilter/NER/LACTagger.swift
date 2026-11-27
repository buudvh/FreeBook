import Foundation

/// Bộ gán nhãn LAC chạy trên máy: tách từ sơ bộ (`LACSegmenter`) ⇒ id (`LACVocabulary`) ⇒ mạng + Viterbi (`LACNetwork`)
/// ⇒ gộp nhãn (bước 4, `parse_result` của LAC 2.1.2). Nạp bằng `LACTagger.load(from:manifest:)`, phát ra qua
/// `LACModel.prepare`.
///
/// Bất biến sau khi nạp ⇒ `tag(_:)` gọi song song từ nhiều luồng được; mọi bộ đệm cấp theo từng lần gọi.
final class LACTagger: LACTagging {
    /// Kết quả từng bước của một câu — `LACSelfCheck` so với `lac_golden.json`.
    struct Analysis {
        let words: [String]
        let ids: [Int32]
        let lengths: [Int]
        let tagIDs: [Int]
        let tokens: [LACToken]
    }

    /// Dòng dài hơn chừng này chữ (vd cả chương dồn một dòng) cắt thành nhiều đoạn sau dấu hết câu rồi gán nhãn từng đoạn:
    /// bộ đệm mạng ~4,3 KB mỗi chữ, bộ lọc lại chạy song song nhiều chương. Dòng ngắn hơn chạy nguyên dòng như LAC.
    static let maxPieceLength = 2_000

    private let segmenter: LACSegmenter
    private let vocabulary: LACVocabulary
    private let network: LACNetwork
    private let labels: LACLabelTable

    init(segmenter: LACSegmenter, vocabulary: LACVocabulary, network: LACNetwork, labels: LACLabelTable) {
        self.segmenter = segmenter
        self.vocabulary = vocabulary
        self.network = network
        self.labels = labels
    }

    func tag(_ line: String) -> [LACToken] {
        let scalars = Array(line.unicodeScalars)
        guard !scalars.isEmpty else { return [] }
        guard scalars.count > Self.maxPieceLength else { return run(scalars).tokens }
        var tokens: [LACToken] = []
        for piece in Self.pieces(of: scalars) {
            tokens += run(Array(scalars[piece])).tokens
        }
        return tokens
    }

    /// Cả dòng (không cắt đoạn), kèm kết quả từng bước.
    func analyze(_ line: String) -> Analysis {
        let scalars = Array(line.unicodeScalars)
        let result = run(scalars)
        let words = result.words.map { Self.text(scalars[$0]) }
        return Analysis(words: words, ids: result.ids, lengths: result.lengths, tagIDs: result.tagIDs,
                        tokens: result.tokens)
    }

    private func run(_ scalars: [Unicode.Scalar])
        -> (words: [Range<Int>], ids: [Int32], lengths: [Int], tagIDs: [Int], tokens: [LACToken]) {
        guard !scalars.isEmpty else { return ([], [], [], [], []) }
        let values = scalars.map(\.value)
        let words = segmenter.cut(values)
        let (ids, lengths) = vocabulary.encode(values, words: words)
        let tagIDs = network.decode(ids)
        return (words, ids, lengths, tagIDs, merge(scalars, lengths: lengths, tagIDs: tagIDs))
    }

    /// Bước 4: id `k` phủ `lengths[k]` chữ; chữ đầu mở từ mới khi chưa có từ nào hoặc nhãn kết thúc bằng `B` / `S`, ngược
    /// lại nối vào từ trước; nhãn của từ = nhãn (bỏ hậu tố) của chữ cuối. Chữ thứ hai trở đi của id nhiều chữ mang
    /// `base-I` ⇒ luôn nối, nhãn vẫn `base`.
    private func merge(_ scalars: [Unicode.Scalar], lengths: [Int], tagIDs: [Int]) -> [LACToken] {
        guard lengths.count == tagIDs.count else { return [LACToken(text: Self.text(scalars[...]), tag: "")] }
        var ranges: [Range<Int>] = []
        var tags: [Int] = []
        var position = 0
        for (index, length) in lengths.enumerated() {
            let tagID = tagIDs[index]
            let end = min(position + length, scalars.count)
            if ranges.isEmpty || labels.opensWord[tagID] {
                ranges.append(position..<end)
                tags.append(tagID)
            } else {
                ranges[ranges.count - 1] = ranges[ranges.count - 1].lowerBound..<end
                tags[tags.count - 1] = tagID
            }
            position = end
        }
        return zip(ranges, tags).map { LACToken(text: Self.text(scalars[$0]), tag: labels.bases[$1]) }
    }

    /// Cắt dòng dài thành các đoạn ≤ `maxPieceLength`, ưu tiên ngay sau dấu hết câu gần cuối đoạn nhất.
    private static func pieces(of scalars: [Unicode.Scalar]) -> [Range<Int>] {
        let enders: Set<UInt32> = [0x3002, 0xFF01, 0xFF1F, 0xFF1B, 0x21, 0x3F, 0x3B, 0x2026] // 。！？；!?;…
        var result: [Range<Int>] = []
        var start = 0
        while start < scalars.count {
            var end = min(start + maxPieceLength, scalars.count)
            if end < scalars.count {
                var cut = end
                while cut > start + 1, !enders.contains(scalars[cut - 1].value) { cut -= 1 }
                if cut > start + 1 { end = cut }
            }
            result.append(start..<end)
            start = end
        }
        return result
    }

    private static func text(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}
