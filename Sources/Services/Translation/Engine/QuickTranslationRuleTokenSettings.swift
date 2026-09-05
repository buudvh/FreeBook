import Foundation

/// Cấu hình runtime cho các token DSL của Quick Translate.
///
/// Giá trị chỉ sống trong `UserDefaults`, không đi vào file rule hay snapshot. Mỗi rule lưu lại
/// cú pháp token gốc lúc parse để `<w>` vẫn là một công tắc độc lập với `<ne>|<pn>|<vp>`.
public enum QuickTranslationRuleTokenSettings {
    /// Mười hai token được DSL hỗ trợ, theo đúng thứ tự dùng để tạo chữ ký cache ổn định.
    ///
    /// Token mới **phải thêm vào cuối**: `Configuration.signature` là chuỗi bit theo thứ tự
    /// `allCases`, nên chèn vào giữa làm mọi chữ ký cũ trượt một bit và cache dịch của người dùng
    /// biến thành sai lệch âm thầm.
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case numeral = "n"
        case digitwise = "y"
        case hanDigits = "h"
        case asciiDigits = "d"
        case chapterLabel = "L"
        case name = "ne"
        case pronoun = "pn"
        case vietPhrase = "vp"
        case hanViet = "hv"
        case word = "w"
        case magnitude = "m"
        case latinLetters = "a"

        /// Khóa cài đặt phải bắt đầu bằng chữ thường để `BackupSettingsArchiver` tự sao lưu.
        public var userDefaultsKey: String {
            switch self {
            case .numeral: return "quickTranslateRuleTokenNumeralEnabled"
            case .digitwise: return "quickTranslateRuleTokenDigitwiseEnabled"
            case .hanDigits: return "quickTranslateRuleTokenHanDigitsEnabled"
            case .asciiDigits: return "quickTranslateRuleTokenAsciiDigitsEnabled"
            case .chapterLabel: return "quickTranslateRuleTokenChapterLabelEnabled"
            case .name: return "quickTranslateRuleTokenNameEnabled"
            case .pronoun: return "quickTranslateRuleTokenPronounEnabled"
            case .vietPhrase: return "quickTranslateRuleTokenVietPhraseEnabled"
            case .hanViet: return "quickTranslateRuleTokenHanVietEnabled"
            case .word: return "quickTranslateRuleTokenWordEnabled"
            case .magnitude: return "quickTranslateRuleTokenMagnitudeEnabled"
            case .latinLetters: return "quickTranslateRuleTokenLatinLettersEnabled"
            }
        }

        public var syntax: String { "<\(rawValue)>" }

        /// Nhãn hiển thị, dùng chung cho màn công tắc chung và màn đặt riêng theo truyện — hai chỗ
        /// viết khác nhau về cùng một token là nguồn nhầm lẫn.
        public var label: String {
            switch self {
            case .numeral: return "<n> — số"
            case .digitwise: return "<y> — đọc từng chữ số"
            case .hanDigits: return "<h> — chữ số Hán"
            case .asciiDigits: return "<d> — chữ số 0-9 (kể cả full-width)"
            case .chapterLabel: return "<L> — nhãn chương"
            case .name: return "<ne> — tên riêng"
            case .pronoun: return "<pn> — đại từ"
            case .vietPhrase: return "<vp> — VietPhrase"
            case .hanViet: return "<hv> — một chữ Hán-Việt"
            case .word: return "<w> — cụm từ điển"
            case .magnitude: return "<m> — bậc số Hán (十 → 10, 百 → 100)"
            case .latinLetters: return "<a> — chữ cái A-Z"
            }
        }

        /// Token số và nhãn chương đứng chung một nhóm ở cả hai màn cấu hình.
        public var isNumeralGroup: Bool {
            switch self {
            case .numeral, .digitwise, .hanDigits, .asciiDigits, .chapterLabel, .magnitude, .latinLetters:
                return true
            case .name, .pronoun, .vietPhrase, .hanViet, .word:
                return false
            }
        }
    }

    /// Bản chụp bất biến để một lượt rewrite không đọc `UserDefaults` theo từng rule.
    public struct Configuration: Sendable, Equatable {
        private let enabledKinds: Set<Kind>

        public static let allEnabled = Configuration(enabledKinds: Set(Kind.allCases))

        public init(enabledKinds: Set<Kind>) {
            self.enabledKinds = enabledKinds
        }

        public func isEnabled(_ kind: Kind) -> Bool {
            enabledKinds.contains(kind)
        }

        /// Không dùng `hashValue`: thứ tự `allCases` làm chữ ký ổn định giữa các process.
        public var signature: String {
            Kind.allCases.map { isEnabled($0) ? "1" : "0" }.joined()
        }
    }

    /// Khóa không tồn tại phải giữ hành vi phiên bản cũ: mọi token đều bật.
    public static func currentConfiguration() -> Configuration {
        Configuration(enabledKinds: Set(Kind.allCases.filter { isEnabled($0) }))
    }

    public static func isEnabled(_ kind: Kind) -> Bool {
        UserDefaults.standard.object(forKey: kind.userDefaultsKey) as? Bool ?? true
    }
}
