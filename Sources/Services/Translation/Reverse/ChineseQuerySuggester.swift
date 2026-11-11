import Foundation

/// Gợi ý cách viết **chữ Hán** cho truy vấn gõ bằng âm Hán Việt ở màn Tìm: `đấu phá thương khung` ⇒ `斗破苍穹`,
/// `鬥破蒼穹`… Người dùng tự chọn; bấm Tìm vẫn tìm đúng chữ đã gõ.
///
/// 1. Tách 2–8 âm tiết; mỗi âm tiết ⇒ tập chữ có âm đó (`HanVietReverseIndex`). Xét từng âm tiết: âm mang dấu ⇒ khớp
///    đúng dấu; âm không dấu ⇒ khớp bỏ dấu (gõ dấu một phần vẫn ra). Âm tiết không ra chữ nào ⇒ không gợi ý.
/// 2. Mỗi vị trí bắt đầu: hỏi Name (tuỳ chỉnh, chung) và VietPhrase (tuỳ chỉnh, chung) các khoá **có thật** dài tới
///    6 chữ mà chữ thứ k thuộc tập của âm tiết thứ k (`FrozenTrieDictionary.keys(matchingCharacterSets:limit:)`, đi
///    cây có cắt nhánh — không thử mọi tổ hợp, không duyệt cả từ điển). Khoá nằm trong danh sách đã xoá chỉ bị bỏ ở từ
///    điển **chung** (từ điển tuỳ chỉnh vốn đã loại), giống `VietPhraseTokenizer`.
/// 3. Quy hoạch động ghép cả câu, giữ `pathsPerPosition` đường tốt nhất mỗi vị trí. Xếp: ít đoạn ⇒ ít đoạn một chữ ⇒
///    ít đoạn VietPhrase (Name trước) ⇒ ít đoạn phồn thể (giản thể trước) ⇒ thứ tự mã. Bỏ: đường trộn giản + phồn,
///    đường có quá nửa số âm tiết là đoạn một chữ (chỉ là đoán chữ đồng âm), đường nhiều hơn đường tốt nhất quá một đoạn.
///
/// Không dùng từ điển riêng truyện (màn Tìm không gắn truyện). Đồng bộ, vài ms (lần đầu sau khi từ điển đổi thêm thời
/// gian dựng bảng đảo) — caller gọi **ngoài main**.
enum ChineseQuerySuggester {
    static let minSyllables = 2
    static let maxSyllables = 8
    static let maxWordLength = 6
    /// Khoá tối đa mỗi từ điển cho mỗi vị trí bắt đầu (khoá dài được giữ trước).
    private static let keysPerLookup = 400
    /// Đoạn một chữ tối đa mỗi vị trí — chữ đơn chỉ để lấp chỗ, càng nhiều đồng âm càng là đoán.
    private static let singleCharacterEdgesPerStart = 16
    private static let pathsPerPosition = 16
    private static let traditionalToSimplified = StringTransform("Traditional-Simplified")
    private static let separators: Set<Character> = ["-", ",", ".", "_", "/", "·", ":", ";", "!", "?", "\"", "'"]

    private struct Edge {
        let end: Int
        let word: String
        let isName: Bool
        let isTraditional: Bool
        let isSimplified: Bool
    }

    private struct Path {
        var text = ""
        var segments = 0
        var singleSegments = 0
        var vietPhraseSegments = 0
        var traditionalSegments = 0
        var simplifiedSegments = 0

        func appending(_ edge: Edge, length: Int) -> Path {
            var next = self
            next.text += edge.word
            next.segments += 1
            if length == 1 { next.singleSegments += 1 }
            if !edge.isName { next.vietPhraseSegments += 1 }
            if edge.isTraditional { next.traditionalSegments += 1 }
            if edge.isSimplified { next.simplifiedSegments += 1 }
            return next
        }

        static func ranks(_ lhs: Path, before rhs: Path) -> Bool {
            (lhs.segments, lhs.singleSegments, lhs.vietPhraseSegments, lhs.traditionalSegments, lhs.text)
                < (rhs.segments, rhs.singleSegments, rhs.vietPhraseSegments, rhs.traditionalSegments, rhs.text)
        }
    }

    /// Các âm tiết của truy vấn khi nó **có thể** có gợi ý (2–8 âm tiết chữ Latin); `nil` khi chắc chắn không — đủ rẻ
    /// để View gọi trên main mà ẩn hàng chip ngay, không chờ debounce.
    static func syllables(of query: String) -> [HanVietReverseIndex.Syllable]? {
        let tokens = query.split { $0.isWhitespace || separators.contains($0) }
        guard (minSyllables...maxSyllables).contains(tokens.count) else { return nil }
        var result: [HanVietReverseIndex.Syllable] = []
        for token in tokens {
            guard let syllable = HanVietReverseIndex.Syllable(String(token)) else { return nil }
            result.append(syllable)
        }
        return result
    }

    nonisolated static func suggestions(for query: String, limit: Int = 6) -> [String] {
        guard limit > 0, let querySyllables = Self.syllables(of: query) else { return [] }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let snapshot = TranslationManager.shared.dictionaryState.snapshot()
        guard !snapshot.global.phienAm.isEmpty else { return [] }
        let reverseIndex = HanVietReverseIndex.index(phienAm: snapshot.global.phienAm, revision: snapshot.revision)
        var characterSets: [Set<UInt16>] = []
        for syllable in querySyllables {
            // Xét **từng** âm tiết: gõ dấu một phần ("đấu pha thương khung") thì âm không dấu vẫn khớp bỏ dấu.
            let characters = reverseIndex.characters(for: syllable, matchingDiacritics: syllable.hasDiacritics)
            guard !characters.isEmpty else { return [] }
            characterSets.append(characters)
        }
        let edges = wordEdges(characterSets: characterSets, global: snapshot.global)
        let results = bestPaths(edges: edges, syllableCount: querySyllables.count, limit: limit)
        // Không log từ khoá, chỉ số âm tiết.
        let ms = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        let edgeCount = edges.reduce(0) { $0 + $1.count }
        AppLogger.shared.log(
            "🔎 [HanSuggest] syllables=\(querySyllables.count) edges=\(edgeCount) results=\(results.count) ms=\(ms)"
        )
        return results
    }

    // MARK: - Từ có thật bắt đầu ở mỗi âm tiết

    private static func wordEdges(
        characterSets: [Set<UInt16>], global: TranslationDictionaryState.Global
    ) -> [[Edge]] {
        let sources: [(dictionary: FrozenTrieDictionary?, isName: Bool, deleted: Set<String>)] = [
            (global.customNames, true, []),
            (global.names, true, global.deletedNames),
            (global.customVietPhrase, false, []),
            (global.vietPhrase, false, global.deletedVietPhrase)
        ]
        var isNameByStart: [[String: Bool]] = []
        for start in characterSets.indices {
            let window = Array(characterSets[start..<min(start + maxWordLength, characterSets.count)])
            var isNameByWord: [String: Bool] = [:]
            for source in sources {
                guard let dictionary = source.dictionary else { continue }
                for word in dictionary.keys(matchingCharacterSets: window, limit: keysPerLookup)
                where !source.deleted.contains(word) {
                    isNameByWord[word] = (isNameByWord[word] ?? false) || source.isName
                }
            }
            isNameByStart.append(isNameByWord)
        }

        var usedUnits: Set<UInt16> = []
        for words in isNameByStart {
            for word in words.keys { usedUnits.formUnion(word.utf16) }
        }
        let scripts = scriptClasses(of: usedUnits)

        var edgesByStart: [[Edge]] = []
        for (start, isNameByWord) in isNameByStart.enumerated() {
            var edges: [Edge] = isNameByWord.map { word, isName in
                Edge(
                    end: start + word.utf16.count,
                    word: word,
                    isName: isName,
                    isTraditional: word.utf16.contains { scripts.traditional.contains($0) },
                    isSimplified: word.utf16.contains { scripts.simplified.contains($0) }
                )
            }
            // Name trước, giản thể trước, rồi thứ tự mã — quyết định chữ đơn nào được giữ khi cắt bớt.
            edges.sort { lhs, rhs in
                (lhs.isName ? 0 : 1, lhs.isTraditional ? 1 : 0, lhs.word)
                    < (rhs.isName ? 0 : 1, rhs.isTraditional ? 1 : 0, rhs.word)
            }
            var singles = 0
            edgesByStart.append(edges.filter { edge in
                guard edge.end == start + 1 else { return true }
                singles += 1
                return singles <= singleCharacterEdgesPerStart
            })
        }
        return edgesByStart
    }

    /// Chữ **riêng phồn thể** (đổi khi chuyển phồn → giản, giữ nguyên khi chuyển ngược) và chữ **riêng giản thể**
    /// (ngược lại). Chữ đổi cả hai chiều hoặc không đổi là trung tính. Chuyển cả lô trong một lần gọi, mỗi chữ một dòng
    /// để không ăn luật ghép cụm; số dòng lệch thì coi mọi chữ là trung tính (không bỏ nhầm đường nào).
    private static func scriptClasses(of units: Set<UInt16>) -> (traditional: Set<UInt16>, simplified: Set<UInt16>) {
        let ordered = units.sorted()
        let text = ordered.map { String(decoding: [$0], as: UTF16.self) }.joined(separator: "\n")
        guard !ordered.isEmpty,
              let toSimplified = text.applyingTransform(traditionalToSimplified, reverse: false)?
                .components(separatedBy: "\n"),
              let toTraditional = text.applyingTransform(traditionalToSimplified, reverse: true)?
                .components(separatedBy: "\n"),
              toSimplified.count == ordered.count, toTraditional.count == ordered.count
        else { return ([], []) }
        var traditional: Set<UInt16> = []
        var simplified: Set<UInt16> = []
        for (offset, unit) in ordered.enumerated() {
            let original = String(decoding: [unit], as: UTF16.self)
            let changesToSimplified = toSimplified[offset] != original
            let changesToTraditional = toTraditional[offset] != original
            if changesToSimplified && !changesToTraditional { traditional.insert(unit) }
            if changesToTraditional && !changesToSimplified { simplified.insert(unit) }
        }
        return (traditional, simplified)
    }

    // MARK: - Ghép cả câu

    private static func bestPaths(edges: [[Edge]], syllableCount: Int, limit: Int) -> [String] {
        var pending: [[Path]] = Array(repeating: [], count: syllableCount + 1)
        pending[0] = [Path()]
        for position in 0..<syllableCount {
            let current = pruned(pending[position])
            pending[position] = []
            guard !current.isEmpty else { continue }
            for edge in edges[position] {
                let length = edge.end - position
                for path in current {
                    let next = path.appending(edge, length: length)
                    // Tên truyện chỉ viết một kiểu chữ: trộn giản + phồn là ghép sai. Đoạn một chữ chỉ tăng dần nên
                    // vượt nửa số âm tiết ở đây là vượt ở cả câu ⇒ cắt sớm.
                    guard next.traditionalSegments == 0 || next.simplifiedSegments == 0,
                          next.singleSegments * 2 <= syllableCount else { continue }
                    pending[edge.end].append(next)
                }
            }
        }
        let complete = pruned(pending[syllableCount])
        guard let fewestSegments = complete.first?.segments else { return [] }
        return complete
            .filter { $0.segments <= fewestSegments + 1 }
            .prefix(limit)
            .map(\.text)
    }

    /// Sắp theo thứ hạng, bỏ chữ trùng (cùng chữ, cách tách khác), giữ `pathsPerPosition` đường.
    private static func pruned(_ paths: [Path]) -> [Path] {
        var seen: Set<String> = []
        var kept: [Path] = []
        for path in paths.sorted(by: Path.ranks) where seen.insert(path.text).inserted {
            kept.append(path)
            if kept.count == pathsPerPosition { break }
        }
        return kept
    }
}
