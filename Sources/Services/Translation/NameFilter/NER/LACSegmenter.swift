import Foundation

/// Bước 1 của LAC: tách từ sơ bộ trên `small_seg.dic` — bản viết lại `Segment.fast_cut` (LAC 2.1.2) trùng tới từng
/// điểm hoà (đặc tả: README của kho `LACModelMirror`; bản Python chép dòng-dòng đã trùng LAC 19.749 / 19.749 dòng truyện).
///
/// - Mọi vị trí tính theo **Unicode scalar** (như `str` Python), không theo `Character` / UTF-16 — chữ ngoài BMP (𫄸) là
///   một vị trí.
/// - Điểm một từ = `log(độ dài từ) - logTotal` (LAC lưu **độ dài** trong cây tiền tố, không phải số lần), cộng **đúng thứ
///   tự** `(logLength[e - i] - logTotal) + route[e + 1]` bằng `Double` lấy từ manifest ⇒ trùng Python tới từng bit, nên
///   các đường bằng điểm hoà giống hệt; hoà ⇒ điểm cuối lớn hơn (so tuple của `max` Python).
/// - Mảnh dài 1 là chữ / số ASCII dồn thành một từ (`re_eng` của LAC).
struct LACSegmenter: Sendable {
    private let trie: LACScalarTrie
    private let logTotal: Double
    private let logLength: [Double]

    /// Dựng từ `small_seg.dic` (dòng `từ số_lần`). Ném `invalidFiles` khi dòng sai dạng hoặc lệch hằng số manifest.
    init(dictionary data: Data, segment: LACManifest.Segment) throws {
        let name = LACModelMirror.segmentDictionaryName
        var trie = LACScalarTrie(reservingCapacity: 200_000)
        var total = 0
        try LACDictionaryParser.forEachLine(data, file: name) { line in
            guard let pair = LACDictionaryParser.splitPair(LACDictionaryParser.trimmed(line),
                                                           separator: LACDictionaryParser.space),
                  !pair.0.isEmpty, let value = LACDictionaryParser.integer(pair.1) else {
                throw LACModelError.invalidFiles("\(name) có dòng sai dạng")
            }
            total += value
            trie.insert(pair.0, payload: 1)
        }
        guard total == segment.dictTotalCount, trie.maxDepth == segment.maxWordLength,
              trie.maxDepth <= segment.logLength.count else {
            throw LACModelError.invalidFiles("\(name) lệch manifest")
        }
        self.trie = trie
        logTotal = segment.logTotal
        logLength = segment.logLength
    }

    /// Các từ theo thứ tự, dưới dạng khoảng vị trí scalar; nối lại phủ đúng `text`.
    func cut(_ text: [UInt32]) -> [Range<Int>] {
        let count = text.count
        guard count > 0 else { return [] }

        // Quy hoạch ngược; DAG của từng vị trí dựng ngay tại chỗ (cùng kết quả với dựng trước cả câu).
        var routeScore = [Double](repeating: 0, count: count + 1)
        var routeEnd = [Int](repeating: 0, count: count + 1)
        var ends: [Int] = []
        ends.reserveCapacity(logLength.count + 1)
        for head in stride(from: count - 1, through: 0, by: -1) {
            ends.removeAll(keepingCapacity: true)
            ends.append(head)
            var node = LACScalarTrie.root
            var end = head + 1
            while end <= count, let next = trie.child(of: node, text[end - 1]) {
                if trie.payload(of: next) >= 0 { ends.append(end - 1) }
                node = next
                end += 1
            }
            var bestScore = 0.0
            var bestEnd = -1
            for last in ends {
                let score = (logLength[last - head] - logTotal) + routeScore[last + 1]
                if bestEnd < 0 || score > bestScore || (score == bestScore && last > bestEnd) {
                    bestScore = score
                    bestEnd = last
                }
            }
            routeScore[head] = bestScore
            routeEnd[head] = bestEnd
        }

        var words: [Range<Int>] = []
        words.reserveCapacity(count)
        var bufferStart = -1
        var index = 0
        while index < count {
            let next = routeEnd[index] + 1
            if next - index == 1, Self.isASCIIAlphanumeric(text[index]) {
                if bufferStart < 0 { bufferStart = index }
            } else {
                if bufferStart >= 0 {
                    words.append(bufferStart..<index)
                    bufferStart = -1
                }
                words.append(index..<next)
            }
            index = next
        }
        if bufferStart >= 0 { words.append(bufferStart..<count) }
        return words
    }

    /// `[a-zA-Z0-9]` của `re_eng` (chỉ ASCII, không phải chữ / số Unicode nói chung).
    @inline(__always)
    private static func isASCIIAlphanumeric(_ value: UInt32) -> Bool {
        (0x30...0x39).contains(value) || (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value)
    }
}
