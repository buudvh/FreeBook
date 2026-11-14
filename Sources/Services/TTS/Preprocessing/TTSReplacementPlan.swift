import Foundation

/// Bộ luật thay thế TTS đã dựng sẵn cho một tầng (chung, hoặc riêng truyện đã gộp với chung) — 1.3.920.
///
/// Chạy **hai lượt** (anh Bửu chốt 2026-11-14):
/// 1. **Từ** — token từ của chữ gốc **bằng đúng** mẫu một luật chữ ⇒ thay cả token (phân biệt hoa thường).
///    `Hà` thay "Hà Nội" nhưng không đụng "Hàn"; `Kamar` không khớp gì trong "Kamar-Taj".
/// 2. **Ký hiệu** — token hoá **lại** kết quả lượt 1; trong từng token ký hiệu quét trái → phải, mỗi vị trí chọn
///    mẫu **dài nhất** khớp (`....` thắng `...`). Từ — kể cả từ lượt 1 vừa sinh ra, vd `Ca-ma` — không bao giờ bị
///    luật ký hiệu chạm; ký hiệu do luật chữ sinh ra (vd `Shield (tổ chức)`) vẫn được dọn.
///
/// Trong mỗi lượt kết quả không bị quét lại, nên thứ tự luật trong danh sách **không** ảnh hưởng kết quả.
/// Luật không phải đúng một token (`TTSReplacementTokenizer.singleToken` trả `nil`) bị bỏ qua — màn quản lý hiện
/// huy hiệu cho chúng (`TTSReplacementRuleValidator`).
struct TTSReplacementPlan: Sendable {
    private struct SymbolRule: Sendable {
        let pattern: [Character]
        let replacement: String
    }

    private var wordMap: [String: String] = [:]
    /// Luật ký hiệu theo ký tự đầu, mỗi nhóm xếp dài → ngắn để lấy mẫu dài nhất trước.
    private var symbolIndex: [Character: [SymbolRule]] = [:]

    static let empty = TTSReplacementPlan()

    var isEmpty: Bool { wordMap.isEmpty && symbolIndex.isEmpty }

    /// Lọc `isEnabled`, bỏ luật sai. Trùng mẫu thì luật **đứng trước** thắng — tầng riêng đứng trước tầng chung
    /// trong `mergedRules`, còn trong một tầng `addRule` / màn Sửa đã đè theo mẫu.
    static func compile(_ rules: [TTSReplacementRule]) -> TTSReplacementPlan {
        var plan = TTSReplacementPlan()
        var seenSymbols: Set<String> = []
        for rule in rules where rule.isEnabled {
            guard let token = TTSReplacementTokenizer.singleToken(rule.pattern) else { continue }
            switch token.kind {
            case .word:
                if plan.wordMap[token.text] == nil {
                    plan.wordMap[token.text] = rule.replacement
                }
            case .symbol:
                guard seenSymbols.insert(token.text).inserted, let first = token.text.first else { continue }
                plan.symbolIndex[first, default: []].append(
                    SymbolRule(pattern: Array(token.text), replacement: rule.replacement)
                )
            case .space:
                continue
            }
        }
        plan.symbolIndex = plan.symbolIndex.mapValues { group in
            group.sorted { $0.pattern.count > $1.pattern.count }
        }
        return plan
    }

    func apply(to text: String) -> String {
        guard !text.isEmpty, !isEmpty else { return text }
        let afterWords = wordMap.isEmpty ? text : replacingWords(in: text)
        return symbolIndex.isEmpty ? afterWords : replacingSymbols(in: afterWords)
    }

    // MARK: - Lượt 1: từ

    private func replacingWords(in text: String) -> String {
        var output = ""
        output.reserveCapacity(text.utf8.count)
        for token in TTSReplacementTokenizer.tokens(in: text) {
            if token.kind == .word, let replacement = wordMap[token.text] {
                output += replacement
            } else {
                output += token.text
            }
        }
        return output
    }

    // MARK: - Lượt 2: ký hiệu

    private func replacingSymbols(in text: String) -> String {
        var output = ""
        output.reserveCapacity(text.utf8.count)
        for token in TTSReplacementTokenizer.tokens(in: text) {
            guard token.kind == .symbol else {
                output += token.text
                continue
            }
            let characters = Array(token.text)
            var index = 0
            while index < characters.count {
                if let rule = longestSymbolRule(at: index, in: characters) {
                    output += rule.replacement
                    index += rule.pattern.count
                } else {
                    output.append(characters[index])
                    index += 1
                }
            }
        }
        return output
    }

    private func longestSymbolRule(at index: Int, in characters: [Character]) -> SymbolRule? {
        guard let candidates = symbolIndex[characters[index]] else { return nil }
        for rule in candidates where index + rule.pattern.count <= characters.count {
            if characters[index..<(index + rule.pattern.count)].elementsEqual(rule.pattern) {
                return rule
            }
        }
        return nil
    }
}
