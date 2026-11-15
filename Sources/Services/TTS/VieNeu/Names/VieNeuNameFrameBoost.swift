import Foundation

/// **Thêm khung cho đoạn có tên riêng** của VieNeu Nano (1.3.952, anh Bửu duyệt "Miễn phí + tối thiểu 10%").
///
/// ## Vì sao
/// Nano không có căn chữ ↔ khung tường minh: bộ đoán độ dài chỉ cho **tổng** số khung, model tự rải chữ. Âm tiết ngắn của
/// tên phiên âm ("gô cu" → nghe thành "gu") hay bị nuốt giữa đoạn. Đo 30 lượt trên PC với câu "Son Gô Cu cười trả lời…":
/// bám chữ (CFG 2–6), biên độ nhiễu, sway, 16 bước, cách viết phiên âm đều **không** giảm (anh Bửu nghe: lượt nào mất thì
/// mất ở mọi mức CFG — nhiễu khởi đầu quyết định). Chỉ **số khung** có tác dụng, giảm đều theo nấc:
/// 62 khung 8/30 lượt mất → +4% 5 → +9% 3 → +14% 2 → +20% 1 → +29% 0.
///
/// ## Vì sao "miễn phí"
/// Trên máy Nano chạy Core ML theo **cỡ khung cố định** (bucket): đoạn 44 khung vẫn tính trọn cỡ 64. Khung thêm cho tới
/// trần cỡ đang dùng **không tốn phép tính nào** (`VieNeuFlowBackend.freeFrameCeiling`). Chương Dragon Ball trong log
/// build 1280: 16/19 đoạn có tên được thêm ≥ 10% miễn phí, 14 đoạn được gần đủ 30%.
///
/// ## Ba chế độ
/// - `off`: như trước 1.3.952.
/// - `free`: chỉ thêm trong phần miễn phí (tối đa `maximumBoost`). Chạy ORT (chưa có Core ML / đoạn lùi) ⇒ không thêm.
/// - `freeWithMinimum` (mặc định): như `free`, nhưng đoạn sát trần cỡ khung vẫn được thêm ít nhất `minimumBoost` bằng cách
///   nhảy lên cỡ lớn hơn — đã trả tiền cho cỡ lớn thì dùng luôn phần trống của nó. Không nhảy khi cỡ lớn hơn không có
///   (vượt cỡ lớn nhất ⇒ Core ML lùi ORT, đắt gấp đôi). Chạy ORT ⇒ thêm đúng `minimumBoost`.
///
/// Đoạn được thêm khung **đọc chậm hơn** đúng bằng mức thêm (không bù ở tốc độ phát). Chỉ Nano; Turbo không qua đây.
enum VieNeuNameFrameBoost {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case off
        case free
        case freeWithMinimum

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return "Tắt"
            case .free: return "Miễn phí"
            case .freeWithMinimum: return "Ít nhất 10%"
            }
        }
    }

    static let modeKey = "vieneuNameFrameBoostMode"
    static let defaultMode: Mode = .freeWithMinimum
    /// Trần mức thêm: +29% khung là mức đo được 0/30 lượt mất; thêm nữa chỉ làm đoạn đọc chậm.
    static let maximumBoost = 0.30
    static let minimumBoost = 0.10

    /// Chưa có khoá ⇒ `defaultMode`.
    static var mode: Mode {
        get { UserDefaults.standard.string(forKey: modeKey).flatMap(Mode.init(rawValue:)) ?? defaultMode }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    // MARK: - Nhận đoạn có tên

    private static let leadingConsonants: Set<Character> = Set("BCDĐGHKLMNPQRSTVX")
    private static let innerConsonants: Set<Character> = Set("bcdđghklmnpqrstvx")
    private static let plainVowels: Set<Character> = Set("aăâeêioôơuưy")

    /// Đoạn có tên phiên âm theo âm tiết — một trong hai dấu hiệu:
    /// 1. ≥ 2 âm tiết do `VieNeuJapaneseNameReader` sinh (mỗi âm tiết bọc `SeaG2P.rawPhonemeOpen`): Kaio, Saiyan, Naruto.
    /// 2. ≥ 2 chữ **viết hoa** đứng liền nhau, mỗi chữ là âm tiết mở không dấu thanh (tên người dùng tự phiên âm bằng thay
    ///    thế từ: "Gô Cu", "Na Ru Tô"). Dấu câu sau một chữ cắt chuỗi liền nhau ("Ta! Ta đi" không tính).
    ///
    /// Tên Hán Việt ("Hàn Lập") không dính: có dấu thanh hoặc phụ âm cuối. `text` là chữ của **một chunk** engine.
    static func isNameChunk(_ text: String) -> Bool {
        var markedSyllables = 0
        var run = 0
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            let marks = word.reduce(0) { $1 == SeaG2P.rawPhonemeOpen ? $0 + 1 : $0 }
            if marks > 0 {
                markedSyllables += marks
                if markedSyllables >= 2 { return true }
                run = 0
                continue
            }
            var characters = Array(word)
            while let first = characters.first, first.isPunctuation || first.isSymbol { characters.removeFirst() }
            var endsClause = false
            while let last = characters.last, last.isPunctuation || last.isSymbol {
                characters.removeLast()
                endsClause = true
            }
            if isLightCapitalizedSyllable(characters) {
                run += 1
                if run >= 2 { return true }
            } else {
                run = 0
            }
            if endsClause { run = 0 }
        }
        return false
    }

    /// Chữ hoa đầu + tối đa 2 phụ âm thường + đúng một nguyên âm không dấu thanh, không phụ âm cuối: "Gô", "Cu", "Kha".
    private static func isLightCapitalizedSyllable(_ characters: [Character]) -> Bool {
        guard characters.count >= 2, characters.count <= 4 else { return false }
        guard leadingConsonants.contains(characters[0]), plainVowels.contains(characters[characters.count - 1]) else {
            return false
        }
        for index in 1..<(characters.count - 1) where !innerConsonants.contains(characters[index]) {
            return false
        }
        return true
    }

    // MARK: - Số khung

    /// Số khung của một đoạn có tên. `base` = số khung engine đã tính (sau khi trả khung của ký hiệu dẫn), `limit` = trần
    /// khung của một chunk, `freeCeiling(T)` = trần cỡ khung Core ML chứa `T` khung (`nil` = chạy ORT / vượt cỡ lớn nhất).
    static func frames(base: Int, mode: Mode, limit: Int, freeCeiling: (Int) -> Int?) -> Int {
        guard mode != .off, base > 0 else { return base }
        let target = min(limit, Int((Double(base) * (1 + maximumBoost)).rounded()))
        guard target > base else { return base }

        let baseCeiling = freeCeiling(base)
        let free = baseCeiling.map { max(base, min(target, $0)) } ?? base
        guard mode == .freeWithMinimum else { return free }

        let minimum = min(target, Int((Double(base) * (1 + minimumBoost)).rounded()))
        if free >= minimum { return free }
        // Chạy ORT: không có phần miễn phí, trả đúng mức tối thiểu.
        guard baseCeiling != nil else { return minimum }
        // Core ML: nhảy cỡ để đủ mức tối thiểu rồi dùng luôn phần trống của cỡ mới; không có cỡ lớn hơn thì thôi.
        guard let largerCeiling = freeCeiling(minimum) else { return free }
        return max(minimum, min(target, largerCeiling))
    }
}
