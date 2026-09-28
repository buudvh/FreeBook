import Foundation

/// Tầng "chữ → token → phoneme" của `SeaG2P`.
///
/// Tách khỏi `SeaG2P.swift` vì bản gốc 509 dòng vượt trần 400 dòng vật lý của repo. Các thành viên
/// riêng tư ở đây (`propagateLanguage`, `trimEnd`, `emotionTagToken`, `ensureTerminalPunct`) vẫn giữ
/// `private` được vì chúng chỉ được dùng trong **chính file này** — Swift giới hạn `private` theo file,
/// không theo type.
extension SeaG2P {
    func phonemize(text: String) -> String {
        let nsString = text as NSString
        let matches = Self.reToken.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        var tokens: [Token] = []

        for match in matches {
            if let enTagRange = Range(match.range(at: 1), in: text) {
                let enTag = String(text[enTagRange])
                let contentRange = NSRange(location: 0, length: enTag.utf16.count)
                let content = Self.reTagStrip.stringByReplacingMatches(in: enTag, options: [], range: contentRange, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)

                let nsContent = content as NSString
                let scalls = Self.reTagContent.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

                for scall in scalls {
                    if let swRange = Range(scall.range(at: 1), in: content) {
                        let word = String(content[swRange])
                        let lw = word.lowercased()
                        var phoneVal: String? = nil

                        if let p = cachedLookupMerged(word: lw) {
                            phoneVal = p.replacingOccurrences(of: "<en>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        } else if let (_, en) = cachedLookupCommon(word: lw) {
                            if !en.isEmpty {
                                phoneVal = en.replacingOccurrences(of: "<en>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }

                        tokens.append(Token(lang: "en", content: word, phone: phoneVal, isExplicitEn: true))
                    } else if let spRange = Range(scall.range(at: 2), in: content) {
                        let sp = String(content[spRange])
                        tokens.append(Token(lang: "punct", content: sp, phone: sp, isExplicitEn: true))
                    }
                }
            } else if let wordRange = Range(match.range(at: 2), in: text) {
                let word = String(text[wordRange])
                let lw = word.lowercased()

                if let p = cachedLookupMerged(word: lw) {
                    let lang = p.contains("<en>") ? "en" : "vi"
                    tokens.append(Token(lang: lang, content: word, phone: p.replacingOccurrences(of: "<en>", with: "").trimmingCharacters(in: .whitespacesAndNewlines), isExplicitEn: false))
                } else if let (vi, en) = cachedLookupCommon(word: lw) {
                    tokens.append(Token(lang: "common", content: word, phone: "\u{1F}\(vi.trimmingCharacters(in: .whitespacesAndNewlines))\u{1F}\(en.replacingOccurrences(of: "<en>", with: "").trimmingCharacters(in: .whitespacesAndNewlines))\u{1F}", isExplicitEn: false))
                } else {
                    let hasViAccent = lw.contains { Self.viAccents.contains($0) }
                    tokens.append(Token(lang: hasViAccent ? "vi" : "en", content: word, phone: nil, isExplicitEn: false))
                }
            } else if let punctRange = Range(match.range(at: 3), in: text) {
                let punct = String(text[punctRange])
                tokens.append(Token(lang: "punct", content: punct, phone: punct, isExplicitEn: false))
            }
        }

        propagateLanguage(&tokens)

        var result: [String] = []
        for t in tokens {
            if t.lang == "punct" {
                result.append(t.content)
            } else {
                let phone: String
                if let p = t.phone {
                    if p.hasPrefix("\u{1F}") && p.hasSuffix("\u{1F}") {
                        let parts = p.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
                        if parts.count >= 3 {
                            let viVal = parts[1]
                            let enVal = parts[2]
                            if t.lang == "en" {
                                var pVal = enVal
                                if t.content.lowercased() == "a" && !t.isExplicitEn {
                                    pVal = "ɐ"
                                }
                                phone = pVal
                            } else {
                                phone = viVal
                            }
                        } else {
                            phone = p
                        }
                    } else {
                        var pVal = p
                        if t.lang == "en" && t.content.lowercased() == "a" && !t.isExplicitEn {
                            pVal = "ɐ"
                        }
                        phone = pVal
                    }
                } else {
                    let lw = t.content.lowercased()
                    phone = segmentOOV(word: lw, lang: t.lang) ?? charFallback(content: t.content, lang: t.lang)
                }
                result.append(phone.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        let joined = result.joined(separator: " ")
        return joined
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " !", with: "!")
            .replacingOccurrences(of: " ?", with: "?")
            .replacingOccurrences(of: " ;", with: ";")
            .replacingOccurrences(of: " :", with: ":")
    }

    private func propagateLanguage(_ tokens: inout [Token]) {
        let n = tokens.count
        var i = 0
        while i < n {
            if tokens[i].lang == "common" {
                let start = i
                while i < n && tokens[i].lang == "common" { i += 1 }
                let end = i - 1

                let isStopPunct = { (t: Token) -> Bool in
                    return t.content.count == 1 && ".!?;:()[]{}".contains(t.content.first!)
                }

                var leftAnchor: String? = nil
                var leftDist = 999
                for l in stride(from: start - 1, through: 0, by: -1) {
                    if isStopPunct(tokens[l]) { break }
                    if tokens[l].lang == "vi" || tokens[l].lang == "en" {
                        leftAnchor = tokens[l].lang
                        leftDist = start - l
                        break
                    }
                }

                var rightAnchor: String? = nil
                var rightDist = 999
                for r in (end + 1)..<n {
                    if isStopPunct(tokens[r]) { break }
                    if tokens[r].lang == "vi" || tokens[r].lang == "en" {
                        rightAnchor = tokens[r].lang
                        rightDist = r - end
                        break
                    }
                }

                let finalLang: String
                if let l = leftAnchor, let r = rightAnchor {
                    finalLang = (rightDist <= leftDist) ? r : l
                } else if let l = leftAnchor {
                    finalLang = l
                } else if let r = rightAnchor {
                    finalLang = r
                } else {
                    finalLang = "vi"
                }

                for idx in start...end {
                    tokens[idx].lang = finalLang
                }
            } else {
                i += 1
            }
        }
    }

    private func trimEnd(_ s: String) -> String {
        var end = s.endIndex
        while end > s.startIndex {
            let prev = s.index(before: end)
            if s[prev].isWhitespace {
                end = prev
            } else {
                break
            }
        }
        return String(s[..<end])
    }

    func applyPuncNorm(text: String) -> String {
        let trimmed = trimEnd(text) // Keep leading whitespace, trim trailing
        if trimmed.isEmpty { return trimmed }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).filter { w in
            w.contains { $0.isLetter || $0.isNumber }
        }

        let trailingPunctAndWhitespace = CharacterSet(charactersIn: ",.!?;:\u{2024}\u{2025}\u{2026}").union(.whitespacesAndNewlines)
        let sentenceEnd = Set(",.!?")

        if words.count <= 4 {
            var stripped = trimmed
            while let last = stripped.last, last.unicodeScalars.allSatisfy({ trailingPunctAndWhitespace.contains($0) }) {
                stripped.removeLast()
            }
            let finalStripped = trimEnd(stripped)
            if finalStripped.isEmpty { return "." }
            return "\(finalStripped)."
        } else {
            if let last = trimmed.last, sentenceEnd.contains(last) {
                return trimmed
            } else {
                return "\(trimmed)."
            }
        }
    }

    private func emotionTagToken(tag: String) -> String? {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("<|") { return t }
        guard t.hasPrefix("[") && t.hasSuffix("]") else { return nil }
        let inner = t.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let k = Self.emotionTags[inner] {
            return "<|emotion_\(k)|>"
        }
        return nil
    }

    /// Đầu vào chính thức mà engine dùng: tách câu theo tag cảm xúc rồi phonemize từng phần.
    ///
    /// Trả về chuỗi **có thể chứa** `<|emotion_k|>`; `VieNeuConfig.applyingEmotionTags` thay chúng bằng
    /// `①`…`③` trước khi mã hoá id — đúng thứ tự `phonemize_text_with_emotions` → `encode_phones` của
    /// bản tham chiếu.
    func phonemizeTextWithEmotions(text: String) -> String {
        if !text.contains("[") && !text.contains("<|emotion_") {
            return phonemize(text: applyPuncNorm(text: text))
        }

        let nsString = text as NSString
        let matches = Self.reEmotionSplit.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        var parts: [String] = []
        var lastOffset = 0
        for match in matches {
            let range = match.range
            parts.append(nsString.substring(with: NSRange(location: lastOffset, length: range.location - lastOffset)))
            parts.append(nsString.substring(with: range))
            lastOffset = range.location + range.length
        }
        parts.append(nsString.substring(from: lastOffset))

        var out = ""
        let attachingPunct = Set(".,!?;:…)]}\"'’”")

        for (i, part) in parts.enumerated() {
            if i % 2 == 1 {
                if let token = emotionTagToken(tag: part) {
                    out = out.isEmpty ? token : "\(out) \(token)"
                    continue
                }
            }

            let trimmedPart = trimEnd(part)
            guard !trimmedPart.isEmpty else { continue }
            let ph = phonemize(text: trimmedPart)
            if ph.isEmpty { continue }

            if out.isEmpty {
                out = ph
            } else if let firstChar = ph.first, attachingPunct.contains(firstChar) {
                out += ph
            } else {
                out += " " + ph
            }
        }

        return ensureTerminalPunct(out)
    }

    private func ensureTerminalPunct(_ phones: String) -> String {
        let s = trimEnd(phones)
        if s.isEmpty { return s }
        let terminalPunct = Set(".!?")
        let weakTrailing = Set(",;:… \t")
        if let last = s.last, terminalPunct.contains(last) {
            return s
        }
        var stripped = s
        while let last = stripped.last, weakTrailing.contains(last) {
            stripped.removeLast()
        }
        return stripped.isEmpty ? phones : "\(stripped)."
    }
}
