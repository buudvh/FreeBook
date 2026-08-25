import Foundation

/// Cấu hình runtime cho các token DSL của Quick Translate.
///
/// Giá trị chỉ sống trong `UserDefaults`, không đi vào file rule hay snapshot. Mỗi rule lưu lại
/// cú pháp token gốc lúc parse để `<w>` vẫn là một công tắc độc lập với `<ne>|<pn>|<vp>`.
public enum QuickTranslationRuleTokenSettings {
    /// Tám token được DSL hỗ trợ, theo đúng thứ tự dùng để tạo chữ ký cache ổn định.
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case numeral = "n"
        case digitwise = "y"
        case chapterLabel = "L"
        case name = "ne"
        case pronoun = "pn"
        case vietPhrase = "vp"
        case hanViet = "hv"
        case word = "w"

        /// Khóa cài đặt phải bắt đầu bằng chữ thường để `BackupSettingsArchiver` tự sao lưu.
        public var userDefaultsKey: String {
            switch self {
            case .numeral: return "quickTranslateRuleTokenNumeralEnabled"
            case .digitwise: return "quickTranslateRuleTokenDigitwiseEnabled"
            case .chapterLabel: return "quickTranslateRuleTokenChapterLabelEnabled"
            case .name: return "quickTranslateRuleTokenNameEnabled"
            case .pronoun: return "quickTranslateRuleTokenPronounEnabled"
            case .vietPhrase: return "quickTranslateRuleTokenVietPhraseEnabled"
            case .hanViet: return "quickTranslateRuleTokenHanVietEnabled"
            case .word: return "quickTranslateRuleTokenWordEnabled"
            }
        }

        public var syntax: String { "<\(rawValue)>" }
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
