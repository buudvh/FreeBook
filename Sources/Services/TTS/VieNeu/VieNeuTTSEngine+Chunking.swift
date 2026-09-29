import Foundation

/// Tách văn bản thành chunk — **bản port trung thành** của `pack_sentences_into_chunks` trong
/// `vieneu_utils/core_utils.py`.
///
/// Tách khỏi `VieNeuTTSEngine+Audio.swift` vì trần **400 dòng vật lý** của repo: file đó đã lên **432** sau
/// khi thêm phần khớp âm lượng. Đây là ranh giới tự nhiên — *tách chunk* là việc trên **chữ**, còn
/// `+Audio` là việc trên **mẫu âm thanh**.
extension VieNeuTTSEngine {
    /// `RE_SENTENCE_FINDALL` của bản tham chiếu: `[^.!?]+[.!?]*|[.!?]+`.
    private static let sentenceRegex = try! NSRegularExpression(pattern: "[^.!?]+[.!?]*|[.!?]+", options: [])
    /// `RE_MINOR_PUNCT` của bản tham chiếu: chỗ cắt phụ trong một câu quá dài.
    private static let minorPunctuationRegex = try! NSRegularExpression(pattern: "(?<=[,;:\\-–—])[ \\t]+", options: [])
    /// `CHUNK_TAIL_SLACK` — xem `fits(current:adding:limit:)`.
    private static let tailSlack = 15

    /// Tách văn bản thành các chunk theo **CÂU**, đúng thuật toán của bản tham chiếu
    /// (`normalize_to_chunks_v3_with_gaps` → `pack_sentences_into_chunks`): chia đoạn theo `\n`, chia câu
    /// trong mỗi đoạn, rồi **gói nguyên câu** vào chunk ≤ `limit`. Ranh giới chunk vì thế **luôn** rơi vào
    /// ranh giới câu; chỉ khi một câu **đơn** dài hơn trần mới phải cắt phụ — trước theo dấu ngắt trong
    /// câu (`,;:-–—`), sau cùng mới theo từ.
    ///
    /// Đây là bản sửa cho lỗi **"cắt chunk giữa đường"**: bản trước gói theo **từ**, nên một câu dài bị cắt
    /// làm hai và chỗ nối nghe thành một khoảng nghỉ giữa câu. Bản tham chiếu không bao giờ làm vậy.
    static func splitIntoChunks(_ text: String, limit: Int) -> [Chunk] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard limit > 0 else { return [Chunk(text: trimmed, gap: .sentence)] }

        var chunks: [Chunk] = []
        let paragraphs = trimmed
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        for paragraph in paragraphs {
            let packed = packSentences(sentences(of: paragraph), limit: limit)
            guard !packed.isEmpty else { continue }
            if !chunks.isEmpty {
                // Ranh giới với ĐOẠN trước là ngắt đoạn, không phải ngắt câu — ghi đè lên chunk cuối của
                // đoạn trước, đúng cách bản tham chiếu gán `"para"` cho `gaps[i-1]`.
                let previous = chunks[chunks.count - 1]
                chunks[chunks.count - 1] = Chunk(text: previous.text, gap: .paragraph)
            }
            for piece in packed {
                chunks.append(Chunk(text: piece, gap: classifyGap(piece)))
            }
        }
        return chunks.isEmpty ? [Chunk(text: trimmed, gap: .sentence)] : chunks
    }

    /// `_classify_gap`: hết câu (`.!?`) → `.sentence`; còn lại (`,;:` hoặc cắt cưỡng bức giữa câu) →
    /// `.minor`.
    private static func classifyGap(_ chunk: String) -> Chunk.Gap {
        guard let last = chunk.trimmingCharacters(in: .whitespacesAndNewlines).last else { return .minor }
        return ".!?…。！？".contains(last) ? .sentence : .minor
    }

    /// `RE_SENTENCE_FINDALL` — tách câu nhưng **giữ** dấu kết câu ở cuối mẩu.
    private static func sentences(of paragraph: String) -> [String] {
        let nsParagraph = paragraph as NSString
        let matches = sentenceRegex.matches(
            in: paragraph,
            options: [],
            range: NSRange(location: 0, length: nsParagraph.length)
        )
        return matches.map { nsParagraph.substring(with: $0.range) }
    }

    /// `pack_sentences_into_chunks`: gói nguyên câu, greedy, giữ thứ tự.
    private static func packSentences(_ sentences: [String], limit: Int) -> [String] {
        var chunks: [String] = []
        var buffer = ""

        for sentence in sentences {
            let piece = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }

            if piece.count > limit {
                if !buffer.isEmpty { chunks.append(buffer); buffer = "" }
                for part in splitLongPart(piece, limit: limit) {
                    if fits(current: buffer.count, adding: part.count, limit: limit) {
                        buffer = buffer.isEmpty ? part : buffer + " " + part
                    } else {
                        if !buffer.isEmpty { chunks.append(buffer) }
                        buffer = part
                    }
                }
            } else if fits(current: buffer.count, adding: piece.count, limit: limit) {
                buffer = buffer.isEmpty ? piece : buffer + " " + piece
            } else {
                if !buffer.isEmpty { chunks.append(buffer) }
                buffer = piece
            }
        }
        if !buffer.isEmpty { chunks.append(buffer) }
        return chunks
    }

    /// `_fits`: vừa trần, **hoặc** phần thêm đủ ngắn để hưởng `tailSlack`. Nhờ luật này mà không sinh ra
    /// mảnh vụn kiểu `"phương."` đứng riêng rồi bị dán sang câu sau.
    private static func fits(current: Int, adding: Int, limit: Int) -> Bool {
        let total = current == 0 ? adding : current + 1 + adding
        let slack = min(tailSlack, limit / 8)
        return total <= limit || (adding <= slack && total <= limit + slack)
    }

    /// Câu dài hơn trần: cắt theo dấu ngắt trong câu trước, phần nào vẫn quá dài mới cắt theo từ.
    private static func splitLongPart(_ sentence: String, limit: Int) -> [String] {
        var result: [String] = []
        for part in splitOnMinorPunctuation(sentence) {
            if part.count <= limit {
                result.append(part)
            } else {
                result.append(contentsOf: splitLongWords(part, limit: limit))
            }
        }
        return result
    }

    private static func splitOnMinorPunctuation(_ text: String) -> [String] {
        let nsText = text as NSString
        let matches = minorPunctuationRegex.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return [text] }
        var parts: [String] = []
        var start = 0
        for match in matches {
            parts.append(nsText.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = match.range.location + match.range.length
        }
        parts.append(nsText.substring(from: start))
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Từ nối: cắt **trước** chúng thì mệnh đề còn nguyên (`_CONN_WORDS`).
    private static let connectorWords: Set<String> = [
        "và", "nhưng", "hoặc", "song", "rồi", "nên", "vì", "nếu", "khi", "để", "do", "bởi"
    ]
    /// Cặp hai từ là **một** từ nối — cắt trước cả cặp, và **không** cắt lọt vào giữa cặp (`_CONN_PAIRS`).
    private static let connectorPairs: Set<String> = [
        "sau khi", "trước khi", "trong khi", "mỗi khi", "đến khi", "tới khi",
        "cho nên", "cho đến", "bởi vì", "nếu như", "tuy nhiên", "thế nhưng",
        "vì vậy", "vì thế", "do đó", "sau đó"
    ]
    /// Ký tự bị gọt ở hai đầu token trước khi so khớp (`_CONN_STRIP`).
    private static let connectorStrip = CharacterSet(charactersIn: "\"'“”‘’()[]«»…")
    /// Từ mà lớp đọc số sinh ra. Cắt giữa hai từ này là **xẻ đôi một con số**
    /// ("…hai nghìn | không trăm ba mươi mốt") — người dùng nghe thành "ngắt nghỉ bất thường khi đang đọc số".
    private static let numberWords: Set<String> = [
        "không", "một", "mốt", "hai", "ba", "bốn", "tư", "năm", "lăm", "sáu", "bảy", "tám", "chín",
        "mười", "mươi", "trăm", "nghìn", "ngàn", "triệu", "tỷ", "tỉ", "linh", "lẻ", "phẩy", "chấm"
    ]

    /// Từ **dẫn số**: cắt ngay sau chúng rồi từ kế là số thì **cũng** là xẻ đôi một con số.
    ///
    /// Bản tham chiếu chỉ chặn cắt giữa **hai từ số**, nên "tháng | sáu" lọt — đúng chỗ người dùng nghe
    /// thấy ("chỗ đọc số ngắt nghỉ chưa hay"). Nhưng chính bản tham chiếu ghi *"chặn thừa một chút còn
    /// hơn xẻ đôi năm 2031"*, nên mở rộng tập chặn là **đúng tinh thần** của nó, không phải lệch.
    private static let numberIntroducers: Set<String> = [
        "tháng", "ngày", "giờ", "phút", "giây", "tuổi", "khoảng", "độ", "số", "trang",
        "chương", "phần", "quyển", "tập", "mục", "điều", "quãng", "hồi", "chặng"
    ]

    private static func connectorKey(_ token: String) -> String {
        token.trimmingCharacters(in: connectorStrip).lowercased()
    }

    private static func isNumberWord(_ token: String) -> Bool {
        let key = connectorKey(token)
        return numberWords.contains(key) || (!key.isEmpty && key.allSatisfy { $0.isNumber })
    }

    /// Độ dài của `words[start..<end]` khi nối bằng dấu cách (`_span_len`).
    private static func spanLength(_ words: [String], _ start: Int, _ end: Int) -> Int {
        guard end > start else { return 0 }
        var total = 0
        for index in start..<end { total += words[index].count }
        return total + (end - start - 1)
    }

    /// `_balanced_cut`: chọn điểm cắt ≤ trần và **gần đích** nhất — ưu tiên cắt trước một từ nối (mảnh
    /// trái đủ dài), không lọt vào giữa cặp từ nối, và **không bao giờ xẻ đôi một con số**.
    private static func balancedCut(_ words: [String], start: Int, target: Double, limit: Int, minLeft: Int) -> Int {
        var bestNatural: (distance: Double, index: Int)?
        var bestPlain: (distance: Double, index: Int)?
        var endCap = start + 1

        var index = start + 1
        while index < words.count {
            let left = spanLength(words, start, index)
            if left > limit { break }
            endCap = index

            let key = connectorKey(words[index])
            let previous = connectorKey(words[index - 1])
            let next = index + 1 < words.count ? connectorKey(words[index + 1]) : ""
            let distance = abs(Double(left) - target)
            let insidePair = connectorPairs.contains("\(previous) \(key)")
            let natural = (connectorWords.contains(key) || connectorPairs.contains("\(key) \(next)"))
                && !connectorWords.contains(previous)

            if natural, !insidePair, left >= minLeft, bestNatural == nil || distance < bestNatural!.distance {
                bestNatural = (distance, index)
            }
            // Hai luật chặn: giữa **hai từ số**, và ngay sau một từ **dẫn số** khi từ kế là số.
            let splitsNumber = (isNumberWord(words[index - 1]) && isNumberWord(words[index]))
                || (numberIntroducers.contains(previous) && isNumberWord(words[index]))
            let plainOK = !insidePair && !splitsNumber
            if plainOK, bestPlain == nil || distance < bestPlain!.distance {
                bestPlain = (distance, index)
            }
            index += 1
        }

        if let bestNatural { return bestNatural.index }
        if let bestPlain { return bestPlain.index }
        // Hết chỗ hợp lệ (token khổng lồ, chuỗi cặp chồng lấn): cắt sát trần, lùi khỏi cặp.
        var end = endCap
        while end > start + 1, connectorPairs.contains("\(connectorKey(words[end - 1])) \(connectorKey(words[end]))") {
            end -= 1
        }
        return end
    }

    /// `_split_long_part`: chia **đều** thành `ceil(rest / limit)` mảnh, không greedy. Bản greedy cũ để
    /// lại mảnh vụn ở cuối và điểm cắt "gần trần" thường trúng chỗ tệ — chính là chỗ xẻ đôi một con số.
    private static func splitLongWords(_ text: String, limit: Int) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 1 else { return [text] }
        let minLeft = limit / 3

        var pieces: [String] = []
        var start = 0
        while start < words.count {
            let rest = spanLength(words, start, words.count)
            if rest <= limit {
                pieces.append(words[start...].joined(separator: " "))
                break
            }
            // Trần **tương đối**: phần dư sau chỗ đầy trần mà chỉ là một mẩu thì gộp luôn.
            var full = start + 1
            while full < words.count, spanLength(words, start, full + 1) <= limit { full += 1 }
            if fits(current: spanLength(words, start, full), adding: spanLength(words, full, words.count), limit: limit) {
                pieces.append(words[start...].joined(separator: " "))
                break
            }
            let pieceCount = Int(ceil(Double(rest) / Double(limit)))
            let end = balancedCut(words, start: start, target: Double(rest) / Double(pieceCount), limit: limit, minLeft: minLeft)
            pieces.append(words[start..<end].joined(separator: " "))
            start = end
        }
        return pieces
    }

    /// Khoảng nghỉ cho một loại ranh giới. Lấy từ **đúng khoá `UserDefaults`** mà đường NghiTTS dùng
    /// (`paragraphPauseDuration` / `sentencePauseDuration` / `phrasePauseDuration`) ⇒ chỉnh trong Cấu hình
    /// NghiTTS là cả hai engine cùng đổi.
    static func pauseSeconds(for gap: Chunk.Gap) -> Double {
        let defaults = UserDefaults.standard
        func value(_ key: String, fallback: Double) -> Double {
            let stored = defaults.double(forKey: key)
            return stored > 0 ? stored : fallback
        }
        switch gap {
        case .paragraph: return value("paragraphPauseDuration", fallback: 0.5)
        case .sentence: return value("sentencePauseDuration", fallback: 0.3)
        case .minor: return value("phrasePauseDuration", fallback: 0.15)
        }
    }

    /// Một mẩu văn bản kèm **loại ranh giới** sau nó.
    ///
    /// `Gap` là bản port của `_classify_gap` trong bản tham chiếu: ranh giới được phân loại theo **dấu câu
    /// kết thúc chunk**, không theo độ dài chunk. Nhờ vậy khoảng nghỉ đặt đúng chỗ — hết câu nghỉ dài, ngắt
    /// trong câu nghỉ ngắn — thay vì mọi khe đều một hằng số.
    struct Chunk {
        enum Gap {
            /// Hai chunk khác **đoạn** (cách nhau bởi `\n`) — nghỉ dài nhất.
            case paragraph
            /// Hết câu (`.!?`) — nghỉ vừa.
            case sentence
            /// Ngắt trong câu (`,;:`) hoặc chỗ cắt cưỡng bức vì câu quá dài — nghỉ ngắn.
            case minor
        }

        let text: String
        let gap: Gap
    }
}
