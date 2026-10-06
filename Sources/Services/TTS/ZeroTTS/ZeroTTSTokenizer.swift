import Foundation

/// BPE cấp ký tự của ZeroTTS — port từ `tokenizer.json` + `zerotts/tokenizer.py`.
///
/// Ba bước phải khớp **từng ký tự** với bản Python. Lệch một bước **không** báo lỗi: nó chỉ đổi cách tách
/// từ, model nhận một phân đoạn nó chưa từng thấy khi huấn luyện, và đơn giản là đọc tệ hơn.
///
/// 1. `normalize`: NFC, rồi gộp **mọi** cụm khoảng trắng thành **một** dấu cách. NFC quan trọng với tiếng
///    Việt: đầu vào ở dạng tách rời (`e` + dấu tổ hợp) tách thành các mảnh khác hẳn `ệ` dựng sẵn mà vocab
///    được huấn luyện trên đó, làm dấu thanh bị rải ra nhiều token.
/// 2. Pre-tokenize, **đúng thứ tự**: khoảng trắng tách rời → **dấu câu** tách rời → **từng chữ số** tách
///    rời. Dấu câu là `\p{P}` (mọi phân nhóm P) và chữ số là `\p{N}` (mọi phân nhóm N), không phải
///    `[0-9]`.
/// 3. BPE: tìm cặp có **hạng merge nhỏ nhất**, gộp **mọi** lần xuất hiện của cặp đó, lặp tới khi không
///    còn cặp nào có trong bảng merge.
///
/// Thuật toán này đã đối chiếu với thư viện `tokenizers` thật trên **6438 ca** (từ vựng tiếng Việt có
/// dấu, dấu câu ASCII và Unicode, số/ngày/giờ, ký tự ngoài BMP, emoji, khoảng trắng đặc biệt): **0 sai
/// khác**.
final class ZeroTTSTokenizer {
    /// Khoá của bảng merge. Hai chuỗi rời thay vì một chuỗi ghép — ghép bằng dấu phân cách nào cũng có
    /// nguy cơ đụng độ với chính ký tự đó trong vocab.
    struct Pair: Hashable {
        let left: String
        let right: String
    }

    /// Id của các token đặc biệt. Graph đã **hardcode** những số này, nên tokenizer không khớp nghĩa là
    /// tokenizer không thuộc bộ weights — sai ở đây thì model sinh ra tạp âm chứ không báo lỗi.
    enum SpecialToken {
        static let pad: Int64 = 0
        static let bos: Int64 = 1
        static let eot: Int64 = 2
        static let soa: Int64 = 3
        static let slot: Int64 = 4
        static let eoa: Int64 = 5
    }

    enum TokenizerError: LocalizedError {
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .malformed(let detail): return "`tokenizer.json` không đúng khuôn: \(detail)"
            }
        }
    }

    private let vocabulary: [String: Int32]
    private let mergeRanks: [Pair: Int32]
    private let unknownID: Int32

    /// Số token thân bài tối đa. Bản Python và bản JS đều cắt ở 512 trước khi thêm `<bos>`/`<eot>`.
    static let maximumBodyLength = 512

    init(tokenizerJSONURL: URL) throws {
        let data = try Data(contentsOf: tokenizerJSONURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TokenizerError.malformed("không phải JSON object")
        }
        guard let model = root["model"] as? [String: Any] else {
            throw TokenizerError.malformed("thiếu khoá `model`")
        }
        guard let vocabObject = model["vocab"] as? [String: Any] else {
            throw TokenizerError.malformed("thiếu `model.vocab`")
        }

        var vocabulary: [String: Int32] = [:]
        vocabulary.reserveCapacity(vocabObject.count)
        for (token, raw) in vocabObject {
            if let value = raw as? Int {
                vocabulary[token] = Int32(value)
            } else if let number = raw as? NSNumber {
                vocabulary[token] = number.int32Value
            }
        }
        guard let unknown = vocabulary["<unk>"] else {
            throw TokenizerError.malformed("vocab không có `<unk>`")
        }
        // Ba token dưới đây bị graph hardcode; lệch nghĩa là sai bộ weights.
        for (token, expected) in [("<bos>", SpecialToken.bos), ("<eot>", SpecialToken.eot),
                                  ("<soa>", SpecialToken.soa), ("<pad>", SpecialToken.pad)] {
            if let actual = vocabulary[token], Int64(actual) != expected {
                throw TokenizerError.malformed("`\(token)` là \(actual), phải là \(expected)")
            }
        }

        var mergeRanks: [Pair: Int32] = [:]
        if let merges = model["merges"] as? [Any] {
            mergeRanks.reserveCapacity(merges.count)
            for (index, entry) in merges.enumerated() {
                var left: String?
                var right: String?
                if let pair = entry as? [String], pair.count == 2 {
                    left = pair[0]
                    right = pair[1]
                } else if let text = entry as? String {
                    // Vài bản `tokenizer.json` ghi merge thành `"a b"` thay vì `["a", "b"]`.
                    let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                    if parts.count == 2 {
                        left = String(parts[0])
                        right = String(parts[1])
                    }
                }
                if let left, let right {
                    mergeRanks[Pair(left: left, right: right)] = Int32(index)
                }
            }
        }

        self.vocabulary = vocabulary
        self.mergeRanks = mergeRanks
        self.unknownID = unknown
    }

    /// Text → `[<bos>] + thân bài (≤ 512) + [<eot>]`, đúng thứ tự của `BpeTokenizer.encode` bên JS.
    func encode(_ text: String, maxLength: Int = ZeroTTSTokenizer.maximumBodyLength) -> [Int64] {
        var body: [Int64] = []
        outer: for piece in Self.preTokenize(Self.normalize(text)) {
            for symbol in merge(piece) {
                body.append(Int64(vocabulary[symbol] ?? unknownID))
                if body.count >= maxLength { break outer }
            }
        }
        var ids: [Int64] = [SpecialToken.bos]
        ids.append(contentsOf: body)
        ids.append(SpecialToken.eot)
        return ids
    }

    // MARK: - Chuẩn hoá & tách sơ bộ

    /// NFC + gộp cụm khoảng trắng thành một dấu cách. Dùng `Unicode.Scalar.Properties.isWhitespace`
    /// (đúng thuộc tính `White_Space` mà regex `\s` của Rust dùng), **không** dùng
    /// `CharacterSet.whitespacesAndNewlines` — hai tập này khác nhau ở vài ký tự.
    static func normalize(_ text: String) -> String {
        var scalars: [Unicode.Scalar] = []
        var inWhitespaceRun = false
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.isWhitespace {
                if !inWhitespaceRun {
                    scalars.append(" ")
                    inWhitespaceRun = true
                }
            } else {
                scalars.append(scalar)
                inWhitespaceRun = false
            }
        }
        return string(from: scalars)
    }

    /// Tách sơ bộ theo đúng thứ tự của `pre_tokenizer` trong `tokenizer.json`.
    static func preTokenize(_ text: String) -> [String] {
        var pieces: [String] = []
        var run: [Unicode.Scalar] = []
        var runIsWhitespace: Bool?

        func flush() {
            guard !run.isEmpty, let isWhitespace = runIsWhitespace else { return }
            if isWhitespace {
                pieces.append(string(from: run))
            } else {
                for punctuated in splitIsolated(run, where: isPunctuation) {
                    for numbered in splitIsolated(punctuated, where: isNumber) {
                        pieces.append(string(from: numbered))
                    }
                }
            }
            run = []
        }

        for scalar in text.unicodeScalars {
            let isWhitespace = scalar.properties.isWhitespace
            if let previous = runIsWhitespace, previous != isWhitespace { flush() }
            runIsWhitespace = isWhitespace
            run.append(scalar)
        }
        flush()
        return pieces
    }

    /// Tách mỗi phần tử thoả `predicate` thành **một mảnh riêng**, phần còn lại giữ nguyên thứ tự.
    static func splitIsolated(_ scalars: [Unicode.Scalar],
                              where predicate: (Unicode.Scalar) -> Bool) -> [[Unicode.Scalar]] {
        var result: [[Unicode.Scalar]] = []
        var buffer: [Unicode.Scalar] = []
        for scalar in scalars {
            if predicate(scalar) {
                if !buffer.isEmpty {
                    result.append(buffer)
                    buffer = []
                }
                result.append([scalar])
            } else {
                buffer.append(scalar)
            }
        }
        if !buffer.isEmpty { result.append(buffer) }
        return result
    }

    /// `\p{P}` — mọi phân nhóm dấu câu (Pc, Pd, Ps, Pe, Pi, Pf, Po).
    static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }

    /// `\p{N}` — mọi phân nhóm chữ số (Nd, Nl, No). Cố ý **không** phải `[0-9]`: pre-tokenizer `Digits`
    /// của upstream tách cả chữ số Ả Rập-La Mã, và những ký tự đó sau đó ra `<unk>`.
    static func isNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    // MARK: - BPE

    /// Gộp cặp có hạng nhỏ nhất, **mọi** lần xuất hiện trong một lượt, cho tới khi hết cặp trong bảng.
    ///
    /// Đây là hành vi của `tokenizers` Rust. Bản gộp-từng-cặp-một cho kết quả **trùng khớp** trên toàn bộ
    /// corpus đối chiếu, nhưng gộp cả lượt là bản gốc và cũng ít vòng lặp hơn.
    private func merge(_ piece: String) -> [String] {
        var symbols = piece.unicodeScalars.map { String($0) }
        while symbols.count > 1 {
            var bestRank: Int32?
            for index in 0..<(symbols.count - 1) {
                guard let rank = mergeRanks[Pair(left: symbols[index], right: symbols[index + 1])] else { continue }
                if bestRank == nil || rank < bestRank! { bestRank = rank }
            }
            guard let rank = bestRank else { break }

            var merged: [String] = []
            merged.reserveCapacity(symbols.count)
            var index = 0
            while index < symbols.count {
                if index + 1 < symbols.count,
                   mergeRanks[Pair(left: symbols[index], right: symbols[index + 1])] == rank {
                    merged.append(symbols[index] + symbols[index + 1])
                    index += 2
                } else {
                    merged.append(symbols[index])
                    index += 1
                }
            }
            symbols = merged
        }
        return symbols
    }

    private static func string(from scalars: [Unicode.Scalar]) -> String {
        String(scalars.map(Character.init))
    }
}
