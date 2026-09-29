import Foundation

/// Phần DSP và tách văn bản của `VieNeuTTSEngine`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo, và vì đây là nhóm hàm **thuần** — không
/// chạm `ORTSession`, không chạm trạng thái thích nghi, nên đứng riêng thì đọc và kiểm được độc lập.
extension VieNeuTTSEngine {
    /// Lưới thời gian đã warp, port nguyên `u = linspace(0,1,n+1)` rồi
    /// `tg = u + sway × (cos(π/2·u) − 1 + u)`.
    ///
    /// `sway = 0` cho lưới đều. `sway = −1` dồn mẫu về hai đầu — bản tham chiếu khuyến nghị đúng cặp
    /// "8 steps + sway = −1", nên hai tham số này **không** được tách rời nhau.
    static func timeGrid(steps: Int, sway: Double) -> [Double] {
        guard steps > 0 else { return [0.0, 1.0] }
        return (0...steps).map { index in
            let u = Double(index) / Double(steps)
            return u + sway * (cos(Double.pi / 2 * u) - 1 + u)
        }
    }

    /// Nhiễu khởi tạo `x` — **chuẩn tắc**, không phải đều.
    ///
    /// Flow matching huấn luyện với prior Gaussian; đổi sang nhiễu đều vẫn chạy, vẫn ra tiếng, nhưng
    /// chất lượng tụt mà không có lỗi nào báo. Box–Muller sinh từng cặp để không phí một lần `log`.
    static func fillStandardNormal(_ values: inout [Float]) {
        var index = 0
        while index < values.count {
            let uniform = Double.random(in: Double.leastNormalMagnitude...1.0)
            let angle = 2 * Double.pi * Double.random(in: 0...1)
            let radius = (-2 * log(uniform)).squareRoot()
            values[index] = Float(radius * cos(angle))
            index += 1
            if index < values.count {
                values[index] = Float(radius * sin(angle))
                index += 1
            }
        }
    }

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
                result.append(contentsOf: splitByWords(part, limit: limit))
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

    /// Cắt theo **từ** — chỉ dùng cho một từ/mẩu đơn dài hơn trần, nơi không còn ranh giới nào tốt hơn.
    private static func splitByWords(_ text: String, limit: Int) -> [String] {
        var pieces: [String] = []
        var buffer = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            let piece = String(word)
            if buffer.isEmpty {
                buffer = piece
            } else if buffer.count + 1 + piece.count <= limit {
                buffer += " " + piece
            } else {
                pieces.append(buffer)
                buffer = piece
            }
            while buffer.count > limit {
                pieces.append(String(buffer.prefix(limit)))
                buffer = String(buffer.dropFirst(limit))
            }
        }
        if !buffer.isEmpty { pieces.append(buffer) }
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

    /// `(lead, tail)` — số mẫu im lặng ở đầu và cuối, đo bằng envelope `mean|x|` trên cửa sổ 10 ms.
    /// Port nguyên `edge_silence` với `EDGE_THRESH_DB = −45`.
    static func edgeSilence(_ samples: [Float], sampleRate: Int) -> (lead: Int, tail: Int) {
        let window = max(1, Int(0.01 * Double(sampleRate)))
        let windowCount = samples.count / window
        guard windowCount > 0 else { return (samples.count, 0) }

        let threshold = Float(pow(10.0, -45.0 / 20.0))
        var firstAbove = -1
        var lastAbove = -1
        for windowIndex in 0..<windowCount {
            let base = windowIndex * window
            var total: Float = 0
            for offset in 0..<window { total += abs(samples[base + offset]) }
            guard total / Float(window) > threshold else { continue }
            if firstAbove < 0 { firstAbove = windowIndex }
            lastAbove = windowIndex
        }
        guard firstAbove >= 0 else { return (samples.count, 0) }
        return (firstAbove * window, samples.count - (lastAbove + 1) * window)
    }

    /// Cắt im lặng model tự sinh ở hai đầu (giữ 0,04 s mỗi đầu) rồi fade cosine 0,015 s ở hai mép.
    /// Port nguyên `trim_and_fade` với `EDGE_KEEP_S = 0.04`, `EDGE_FADE_S = 0.015`.
    static func trimAndFade(_ samples: [Float], sampleRate: Int) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let (lead, tail) = edgeSilence(samples, sampleRate: sampleRate)
        let keep = Int(0.04 * Double(sampleRate))
        let start = max(0, lead - keep)
        let end = samples.count - max(0, tail - keep)
        guard start < end else { return samples }

        var output = Array(samples[start..<end])
        let fade = min(Int(0.015 * Double(sampleRate)), output.count / 2)
        guard fade > 1 else { return output }
        // `linspace(0, π, fade)` của numpy ⇒ mẫu số là `fade − 1`, không phải `fade`.
        for index in 0..<fade {
            let ramp = Float(0.5 - 0.5 * cos(Double.pi * Double(index) / Double(fade - 1)))
            output[index] *= ramp
            output[output.count - 1 - index] *= ramp
        }
        return output
    }
}
