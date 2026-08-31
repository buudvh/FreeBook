import Foundation

/// Bộ tách token byte-level BPE tương thích `tokenizer.json` của HuggingFace.
///
/// Vocab chỉ 419 token vì input của model **không phải chữ thô mà là chuỗi phoneme** do
/// `SeaG2P` sinh ra. Nghĩa là bộ này không thể thay bằng `EspeakPhonemizer` của đường Piper:
/// bộ ký hiệu hoàn toàn khác nhau.
///
/// Port từ bản thử nghiệm, thêm hai thứ: `MergeValue` được lồng vào trong (mỗi file một type
/// chính) và một cache BPE theo từ, vì cùng một âm tiết tiếng Việt xuất hiện rất nhiều lần trong
/// một chương.
final class VieNeuTokenizer: @unchecked Sendable {
    private enum MergeValue: Decodable {
        case string(String)
        case pair([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .string(text)
            } else if let items = try? container.decode([String].self) {
                self = .pair(items)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "merge không phải String hay [String]")
            }
        }

        /// Khoá tra cứu `"a b"`. `tokenizer.json` mới lưu merge dạng `["a","b"]`, bản cũ lưu `"a b"`.
        var lookupKey: String? {
            switch self {
            case .string(let text): return text
            case .pair(let items): return items.count == 2 ? "\(items[0]) \(items[1])" : nil
            }
        }
    }

    private struct TokenizerJSON: Decodable {
        struct Model: Decodable {
            let vocab: [String: Int]
            let merges: [MergeValue]
        }
        let model: Model
    }

    private let vocab: [String: Int]
    private let merges: [String: Int]
    private let byteToUnicode: [UInt8: Character]
    private let splitRegex: NSRegularExpression
    private let unknownTokenID: Int?

    /// Cache kết quả BPE theo từ. Một chương truyện lặp lại rất nhiều âm tiết giống nhau nên
    /// cache này cắt phần lớn công việc của `applyBPE`.
    private var bpeCache: [String: [String]] = [:]
    private let cacheLock = NSLock()

    init(jsonURL: URL) throws {
        let json = try JSONDecoder().decode(TokenizerJSON.self, from: try Data(contentsOf: jsonURL))
        self.vocab = json.model.vocab

        var table: [String: Int] = [:]
        table.reserveCapacity(json.model.merges.count)
        for (rank, merge) in json.model.merges.enumerated() {
            if let key = merge.lookupKey { table[key] = rank }
        }
        self.merges = table
        self.byteToUnicode = Self.buildByteToUnicode()
        self.unknownTokenID = json.model.vocab["<|unk|>"]

        // Khuôn pre-tokenizer GPT-2 chuẩn.
        let pattern = #"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"#
        self.splitRegex = try NSRegularExpression(pattern: pattern, options: [])
    }

    /// Bảng byte → ký tự in được của byte-level BPE: byte không in được được đẩy lên vùng U+0100
    /// trở lên để chuỗi trung gian luôn là text hợp lệ.
    private static func buildByteToUnicode() -> [UInt8: Character] {
        var printable: Set<Int> = []
        for byte in 33...126 { printable.insert(byte) }
        for byte in 161...172 { printable.insert(byte) }
        for byte in 174...255 { printable.insert(byte) }

        var mapping: [UInt8: Character] = [:]
        var shifted = 0
        for byte in 0...255 {
            if printable.contains(byte) {
                mapping[UInt8(byte)] = Character(UnicodeScalar(byte)!)
            } else {
                mapping[UInt8(byte)] = Character(UnicodeScalar(256 + shifted)!)
                shifted += 1
            }
        }
        return mapping
    }

    func encode(text: String) -> [Int64] {
        let nsString = text as NSString
        let matches = splitRegex.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        )

        var ids: [Int64] = []
        ids.reserveCapacity(nsString.length)
        for match in matches {
            let piece = nsString.substring(with: match.range)
            for token in bpeTokens(for: mapToByteLevel(piece)) {
                if let id = vocab[token] {
                    ids.append(Int64(id))
                } else if let unknownTokenID {
                    ids.append(Int64(unknownTokenID))
                }
            }
        }
        return ids
    }

    private func mapToByteLevel(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            if let character = byteToUnicode[byte] { result.append(character) }
        }
        return result
    }

    private func bpeTokens(for token: String) -> [String] {
        if token.isEmpty { return [] }

        cacheLock.lock()
        if let cached = bpeCache[token] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let result = applyBPE(token)

        cacheLock.lock()
        // Chốt trần để một chương lạ toàn từ mới không làm cache phình vô hạn.
        if bpeCache.count < 20_000 { bpeCache[token] = result }
        cacheLock.unlock()
        return result
    }

    private func applyBPE(_ token: String) -> [String] {
        if vocab[token] != nil { return [token] }

        var word = token.map(String.init)
        while word.count >= 2 {
            var bestRank = Int.max
            var bestIndex = -1
            for index in 0..<(word.count - 1) {
                if let rank = merges["\(word[index]) \(word[index + 1])"], rank < bestRank {
                    bestRank = rank
                    bestIndex = index
                }
            }
            guard bestIndex >= 0 else { break }

            let left = word[bestIndex]
            let right = word[bestIndex + 1]
            var merged: [String] = []
            merged.reserveCapacity(word.count)
            var index = 0
            while index < word.count {
                if index < word.count - 1, word[index] == left, word[index + 1] == right {
                    merged.append(left + right)
                    index += 2
                } else {
                    merged.append(word[index])
                    index += 1
                }
            }
            word = merged
        }
        return word
    }
}
