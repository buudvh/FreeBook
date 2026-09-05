import Foundation

/// Thứ tự và chiều so sánh của các tiêu chí phá tranh chấp khi **hai rule dịch cùng khớp và chồng
/// lên nhau**.
///
/// `QuickTranslationRuleEngine.select` so từng tiêu chí từ trên xuống và **dừng ở tiêu chí đầu tiên
/// phân định được** — tiêu chí bên dưới không được xét nữa. Hai tiêu chí **không** có mặt ở đây vì
/// chúng bị khoá, và không phải vì thận trọng:
///
/// - **Vị trí xuất hiện luôn đứng đầu.** `select` sort một lần rồi quét một pass với `cursor`; nếu
///   khoá chính không phải `start` thì vòng quét nhặt match theo thứ tự lộn xộn và `cursor` mất
///   nghĩa (một match ở vị trí 50 lấy trước sẽ đẩy cursor lên 54 và giết match ở vị trí 10). Hạ nó
///   xuống là thay thuật toán chọn, không phải đổi thứ tự.
/// - **Số dòng nguồn luôn đứng cuối**, và phải nằm **dưới** `scopeRank`: số dòng của bộ riêng và bộ
///   chung đều đếm từ 1 nên hai rule khác bộ có thể trùng số dòng; đưa nó lên trên `scopeRank` là
///   tạo ra cặp hoà mọi tiêu chí ⇒ thứ tự sort không xác định.
///
/// Mọi hoán vị của bốn tiêu chí còn lại vẫn là strict weak ordering hợp lệ — chúng là khoá tổng, so
/// theo cặp không phụ thuộc ngữ cảnh — nên `sorted(by:)` không có nguy cơ.
public enum QuickTranslationRulePriorityConfiguration {
    /// Bốn tiêu chí cho phép xếp lại và đổi chiều.
    public enum Key: String, CaseIterable, Hashable, Sendable {
        case literalLength
        case wildcardCapacity
        case matchLength
        case scopeRank

        public var title: String {
            switch self {
            case .literalLength: return "Số chữ ghim trong mẫu"
            case .wildcardCapacity: return "Hạn mức token"
            case .matchLength: return "Số chữ khớp được"
            case .scopeRank: return "Bộ rule riêng của truyện"
            }
        }

        public var systemImage: String {
            switch self {
            case .literalLength: return "pin"
            case .wildcardCapacity: return "gauge.with.dots.needle.33percent"
            case .matchLength: return "ruler"
            case .scopeRank: return "book.closed"
            }
        }

        /// Mô tả hiện dưới mỗi hàng ở màn cấu hình — người dùng phải hiểu được tiêu chí này đo gì
        /// mà không cần đọc code.
        public var explanation: String {
            switch self {
            case .literalLength:
                return "Số chữ Hán cố định trong mẫu, không tính token. <n>米 có 1 chữ ghim, <n>米<n>公分 có 3. Nhiều chữ ghim nghĩa là mẫu nhắm chính xác hơn."
            case .wildcardCapacity:
                return "Tổng số chữ TỐI ĐA mà các token được phép nuốt. Token viết trần như <n> tính 12 chữ, nên <n>米 là 12 còn <n>米<n> là 24. Đây là mức trần khai báo trong mẫu, không phải số chữ nuốt thật."
            case .matchLength:
                return "Số chữ rule thật sự nuốt được trên đoạn văn đang dịch. Trên 三米五: <n>米 nuốt 2 chữ, <n>米<n> nuốt 3 chữ."
            case .scopeRank:
                return "Rule trong bộ riêng của truyện thắng rule cùng hạng trong bộ chung."
            }
        }

        /// Nhãn của nút đổi chiều, viết theo lối "ai thắng" để khỏi phải suy luận tăng/giảm.
        public func directionLabel(descending: Bool) -> String {
            switch self {
            case .literalLength:
                return descending ? "Nhiều chữ ghim hơn thắng" : "Ít chữ ghim hơn thắng"
            case .wildcardCapacity:
                return descending ? "Hạn mức lớn hơn thắng" : "Hạn mức nhỏ hơn thắng"
            case .matchLength:
                return descending ? "Khớp được nhiều chữ hơn thắng" : "Khớp được ít chữ hơn thắng"
            case .scopeRank:
                return descending ? "Bộ chung thắng" : "Bộ riêng của truyện thắng"
            }
        }
    }

    /// Ba bộ thứ tự dựng sẵn. Người dùng vẫn kéo tay được, preset chỉ là lối đi nhanh.
    public enum Preset: String, CaseIterable, Hashable, Sendable {
        /// Mặc định của app từ 1.3.300.
        case lengthFirst
        /// Hành vi của bản VBook trên máy tính (`executeRules` của `ruleEngine.ts`).
        case referenceEngine
        /// Leftmost-longest thuần, giống tokenizer VietPhrase ở bước sau.
        case longestMatch

        public var title: String {
            switch self {
            case .lengthFirst: return "Ưu tiên độ dài"
            case .referenceEngine: return "Như engine gốc"
            case .longestMatch: return "Xuất hiện trước rồi dài hơn"
            }
        }

        public var explanation: String {
            switch self {
            case .lengthFirst:
                return "Chữ ghim → số chữ khớp → hạn mức → bộ riêng. Rule dịch được nhiều chữ hơn thì thắng, nên 三米五 ra \"3 mét 5\"."
            case .referenceEngine:
                return "Chữ ghim → hạn mức → số chữ khớp → bộ riêng. Giống bản VBook trên máy tính. Rule ít token thắng, nên 三米五 ra \"3 mét\" và chữ 五 được dịch riêng."
            case .longestMatch:
                return "Số chữ khớp → chữ ghim → hạn mức → bộ riêng. Rule khớp dài nhất luôn thắng, kể cả khi giành chỗ của rule literal viết tay: 五米三 ra \"5 mét 3\" thay vì \"năm mét\"."
            }
        }

        /// Ba preset chỉ khác nhau ở **vị trí** của `matchLength`; chiều so giữ nguyên ở cả ba.
        public var configuration: Configuration {
            switch self {
            case .lengthFirst:
                return Configuration(order: [.literalLength, .matchLength, .wildcardCapacity, .scopeRank])
            case .referenceEngine:
                return Configuration(order: [.literalLength, .wildcardCapacity, .matchLength, .scopeRank])
            case .longestMatch:
                return Configuration(order: [.matchLength, .literalLength, .wildcardCapacity, .scopeRank])
            }
        }
    }

    /// Bản chụp bất biến của một thứ tự ưu tiên. `select` nhận đúng struct này chứ không đọc
    /// `UserDefaults` hay file trong comparator — comparator chạy O(n log n) lần cho mỗi dòng văn.
    public struct Configuration: Sendable, Equatable {
        /// Chiều "thắng" mặc định của từng tiêu chí, giữ đúng hành vi engine gốc.
        public static let defaultDescending: Set<Key> = [.literalLength, .matchLength]

        public let order: [Key]
        public let descending: Set<Key>

        /// Mặc định của app: **Ưu tiên độ dài**.
        public static let `default` = Preset.lengthFirst.configuration

        /// Bù key thiếu và bỏ key trùng: dữ liệu hỏng vẫn ra cấu hình chạy được, không bao giờ throw.
        public init(order: [Key], descending: Set<Key> = Configuration.defaultDescending) {
            var seen: Set<Key> = []
            var sanitized: [Key] = []
            for key in order where seen.insert(key).inserted { sanitized.append(key) }
            for key in Key.allCases where !seen.contains(key) { sanitized.append(key) }
            self.order = sanitized
            self.descending = descending.intersection(Set(Key.allCases))
        }

        public func isDescending(_ key: Key) -> Bool { descending.contains(key) }

        /// Đảo chiều đúng một tiêu chí.
        public func togglingDirection(of key: Key) -> Configuration {
            var next = descending
            if next.contains(key) { next.remove(key) } else { next.insert(key) }
            return Configuration(order: order, descending: next)
        }

        public func reordering(to keys: [Key]) -> Configuration {
            Configuration(order: keys, descending: descending)
        }

        /// Chữ ký ổn định giữa các process cho khoá cache dịch — không dùng `hashValue`.
        public var signature: String {
            order.map { "\($0.rawValue)\(isDescending($0) ? "-" : "+")" }.joined(separator: ".")
        }

        public var matchingPreset: Preset? {
            Preset.allCases.first { $0.configuration == self }
        }
    }

    // MARK: - Cấu hình chung

    /// Khoá bắt đầu bằng chữ thường ASCII để `BackupSettingsArchiver` tự sao lưu.
    public static let orderDefaultsKey = "quickTranslateRulePriorityOrder"
    public static let descendingDefaultsKey = "quickTranslateRulePriorityDescending"

    /// Chưa có khoá hoặc khoá hỏng ⇒ `.default`. Cấu hình **chung**, dùng khi truyện không đặt riêng.
    public static func globalConfiguration() -> Configuration {
        decode(
            order: UserDefaults.standard.string(forKey: orderDefaultsKey),
            descending: UserDefaults.standard.string(forKey: descendingDefaultsKey)
        ) ?? .default
    }

    public static func storeGlobal(_ configuration: Configuration) {
        UserDefaults.standard.set(encodeOrder(configuration), forKey: orderDefaultsKey)
        UserDefaults.standard.set(encodeDescending(configuration), forKey: descendingDefaultsKey)
    }

    // MARK: - Mã hoá dùng chung cho UserDefaults và file riêng của truyện

    public static func encodeOrder(_ configuration: Configuration) -> String {
        configuration.order.map(\.rawValue).joined(separator: ",")
    }

    /// Giữ theo thứ tự `allCases` để chuỗi ổn định giữa hai lần ghi cùng cấu hình.
    public static func encodeDescending(_ configuration: Configuration) -> String {
        Key.allCases.filter { configuration.isDescending($0) }.map(\.rawValue).joined(separator: ",")
    }

    /// `nil` khi không đọc được tiêu chí nào — bên gọi tự quyết định fallback là `.default` (phạm vi
    /// chung) hay "kế thừa bộ chung" (phạm vi truyện).
    ///
    /// Chuỗi `descending` **rỗng là giá trị hợp lệ** (mọi tiêu chí đều so tăng dần), không phải lỗi.
    public static func decode(order: String?, descending: String?) -> Configuration? {
        guard let order, !order.isEmpty else { return nil }
        let keys = order.split(separator: ",").compactMap { Key(rawValue: String($0)) }
        guard !keys.isEmpty else { return nil }
        let flags = (descending ?? "").split(separator: ",").compactMap { Key(rawValue: String($0)) }
        return Configuration(order: keys, descending: Set(flags))
    }
}
