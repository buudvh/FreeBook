import Foundation

/// Phương án A của đọc lai (1.3.934): một đoạn (chunk đã cắt, ≤ ~100 ký tự) có **tiếng nước ngoài** đủ để đáng đổi sang
/// Turbo không. Báo cáo `Docs/Reports/2026-11-14-vieneu-nano-turbo-theo-ngon-ngu.md` §1–2.
///
/// ## Vì sao thực chất chỉ là tiếng Anh
/// Nano và Turbo dùng **chung** đường chữ (`normalizeVietnameseText` → từ điển tiếng Nhật → sea-g2p); khác nhau chỉ ở model
/// âm thanh, và Turbo chỉ học Việt + Anh. Chữ Hán / kana thì **không** model nào đọc ⇒ đoạn có chúng luôn ở Nano (Turbo
/// gặp chữ Hán trong chuỗi phiên âm có thể ra tiếng lạ).
///
/// ## Luật (đo trên 200 chương truyện dịch Trung: 2 / 22.317 đoạn sang Turbo, đều là từ mượn)
/// Token "lạ" = chỉ chữ ASCII, dài ≥ 2, không phải âm tiết Việt không dấu (`VietnameseWordChecker`), không phải tiếng kêu
/// ("haha", "haizz"…), không phải viết tắt IN HOA ≤ 3 chữ ("HP", "NPC"), không thuộc vài từ mượn đọc kiểu Việt, không có
/// trong từ điển phiên âm tiếng Nhật đang bật. Đoạn sang Turbo khi có **≥ 2 token lạ** hoặc **1 token lạ dài ≥ 5 chữ** —
/// một từ Anh lẻ trong câu Việt giữ Nano: đổi giọng nghe tệ hơn giọng lơ lớ.
///
/// Chạy trên chữ **sau** `normalizeVietnameseText` + gấp macron — gần đúng chữ engine phiên âm. Tất định theo chữ ⇒ khoá
/// tổng hợp (`TTSSynthesisIdentity`) tính lại được ở mọi chỗ. Có đệm theo chữ (khoá tổng hợp và lượt tổng hợp hỏi cùng
/// một đoạn nhiều lần).
final class VieNeuForeignTextClassifier: @unchecked Sendable {
    struct Verdict: Sendable {
        let prefersTurbo: Bool
        /// Các token lạ — để log lý do đổi model.
        let foreignTokens: [String]
    }

    static let shared = VieNeuForeignTextClassifier()

    private static let tokenRegex = try! NSRegularExpression(pattern: "\\w+(?:['’]\\w+)*", options: [])
    private static let asciiWord = try! NSRegularExpression(pattern: "^[A-Za-z]+(?:['’][A-Za-z]+)*$", options: [])
    private static let interjection = try! NSRegularExpression(
        pattern: "^(?:(?:ha)+h?|(?:hi)+|(?:he)+|(?:ho)+|hai+z*|a+o+|h+m+|(?:ah|oh|uh|eh)+|ui+|oa+|ơ+)$",
        options: []
    )
    /// Từ mượn người Việt đọc theo kiểu Việt — gặp một mình thì giữ Nano.
    private static let vietnamizedLoanwords: Set<String> = [
        "ok", "okay", "top", "vip", "logic", "taxi", "tivi", "radio", "video", "audio", "pizza", "karaoke"
    ]
    private static let cacheLimit = 512

    private let lock = NSLock()
    private var cache: [String: Verdict] = [:]
    /// Khoá đã chuẩn hoá của từ điển phiên âm tiếng Nhật (khi bật) — từ đó sẽ thành chữ Việt ⇒ không tính là lạ.
    private var japaneseKeys: Set<String> = []

    func verdict(for text: String) -> Verdict {
        lock.lock()
        if let hit = cache[text] {
            lock.unlock()
            return hit
        }
        let dictionaryKeys = japaneseKeys
        lock.unlock()

        let result = Self.classify(text, japaneseKeys: dictionaryKeys)
        lock.lock()
        if cache.count >= Self.cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[text] = result
        lock.unlock()
        return result
    }

    /// Nạp lại khoá từ điển tiếng Nhật (engine bọc gọi lúc chuẩn bị). Từ điển tắt ⇒ tập rỗng.
    func refreshJapaneseDictionary() async {
        var keys: Set<String> = []
        if UserDefaults.standard.bool(forKey: VieNeuJapanesePreprocessor.dictionaryEnabledKey) {
            let table = await VieNeuJapaneseDictionary.shared.all()
            keys = Set(table.keys)
        }
        setJapaneseKeys(keys)
    }

    /// Đồng bộ để giữ `lock` ngoài ngữ cảnh `async`.
    private func setJapaneseKeys(_ keys: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        guard keys != japaneseKeys else { return }
        japaneseKeys = keys
        cache.removeAll(keepingCapacity: true)
    }

    // MARK: - Phân loại

    private static func classify(_ text: String, japaneseKeys: Set<String>) -> Verdict {
        if containsCJK(text) { return Verdict(prefersTurbo: false, foreignTokens: []) }
        let normalized = VieNeuJapanesePreprocessor.foldMacrons(TextPreprocessor.normalizeVietnameseText(text))
        let source = normalized as NSString
        let matches = tokenRegex.matches(in: normalized, options: [], range: NSRange(location: 0, length: source.length))
        let foreign = matches
            .map { source.substring(with: $0.range) }
            .filter { isForeign($0, japaneseKeys: japaneseKeys) }
        let prefersTurbo = foreign.count >= 2 || foreign.contains { $0.count >= 5 }
        return Verdict(prefersTurbo: prefersTurbo, foreignTokens: foreign)
    }

    private static func isForeign(_ token: String, japaneseKeys: Set<String>) -> Bool {
        guard token.count >= 2, matches(asciiWord, token) else { return false }
        let lower = token.lowercased()
        if VietnameseWordChecker.isVietnameseWord(lower) { return false }
        if matches(interjection, lower) { return false }
        if token.count <= 3, token == token.uppercased() { return false }
        if vietnamizedLoanwords.contains(lower) { return false }
        if !japaneseKeys.isEmpty, japaneseKeys.contains(VieNeuJapaneseDictionary.normalizedKey(token)) { return false }
        return true
    }

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: (string as NSString).length)) != nil
    }

    /// Chữ Hán (CJK + mở rộng A + tương thích) hoặc kana.
    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: return true
            default: return false
            }
        }
    }
}
