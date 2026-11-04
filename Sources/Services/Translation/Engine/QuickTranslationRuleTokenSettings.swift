import Foundation

/// Cấu hình runtime cho các token DSL của Quick Translate.
///
/// Giá trị chỉ sống trong `UserDefaults`, không đi vào file rule hay snapshot. Mỗi rule lưu lại
/// cú pháp token gốc lúc parse để `<w>` vẫn là một công tắc độc lập với `<ne>|<pn>|<vp>`.
public enum QuickTranslationRuleTokenSettings {
    /// Mười tám token được DSL hỗ trợ, theo đúng thứ tự dùng để tạo chữ ký cache ổn định.
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
        /// Nối vào **cuối** danh sách (1.3.416) — xem ghi chú đầu `enum`: chèn vào giữa là làm chữ ký
        /// cache của mọi token phía sau trượt một bit.
        case hanNumeral = "hn"
        /// `<any>` — cụm ký tự bất kỳ (1.3.682), cũng nối vào **cuối**. Backtick chỉ để chắc chắn: `any`
        /// là từ khoá ngữ cảnh của Swift; nơi dùng vẫn viết `.any`.
        case `any` = "any"
        /// `<START>` / `<END>` — neo đầu dòng / cuối dòng (1.3.686), nối vào **cuối** sau `<any>`. Rộng 0
        /// và **không** sinh capture: thêm neo vào mẫu không làm `{i}` của các token khác đổi số.
        ///
        /// Trước 1.3.692 viết `<^>` / `<$>` (rawValue `^`/`$`). Rule cũ vẫn chạy nhờ `kind(forTokenName:)`;
        /// khoá `UserDefaults` giữ nguyên nên công tắc chung không mất trạng thái. Chữ ký cache đi theo
        /// thứ tự `allCases` chứ không theo rawValue nên đổi tên không làm trượt chữ ký.
        case lineStart = "START"
        case lineEnd = "END"
        /// `<[>` / `<]>` — một ký tự mở / đóng ngoặc thuộc **bộ ngoặc** (1.3.692), nối vào **cuối**. Rộng
        /// đúng 1 và **không** sinh capture như neo; `<]>` phải đóng đúng cặp với `<[>` đi trước nó.
        case openBracket = "["
        case closeBracket = "]"

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
            case .hanNumeral: return "quickTranslateRuleTokenHanNumeralEnabled"
            case .any: return "quickTranslateRuleTokenAnyEnabled"
            case .lineStart: return "quickTranslateRuleTokenLineStartEnabled"
            case .lineEnd: return "quickTranslateRuleTokenLineEndEnabled"
            case .openBracket: return "quickTranslateRuleTokenOpenBracketEnabled"
            case .closeBracket: return "quickTranslateRuleTokenCloseBracketEnabled"
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
            case .magnitude: return "<m> — cơ số 10 (mươi, trăm, hai mươi, chục vạn...)"
            case .latinLetters: return "<a> — chữ cái A-Z"
            case .hanNumeral: return "<hn> — số Hán đọc Hán-Việt"
            case .any: return "<any> — cụm ký tự bất kỳ (trừ xuống dòng)"
            case .lineStart: return "<START> — đầu dòng"
            case .lineEnd: return "<END> — cuối dòng"
            case .openBracket: return "<[> — mở ngoặc"
            case .closeBracket: return "<]> — đóng ngoặc"
            }
        }

        /// Token số, nhãn chương, `<any>`, neo dòng và ngoặc (token ký tự, không tra từ điển) đứng chung
        /// một nhóm ở cả hai màn cấu hình.
        public var isNumeralGroup: Bool {
            switch self {
            case .numeral, .digitwise, .hanDigits, .asciiDigits, .chapterLabel, .magnitude, .latinLetters,
                 .hanNumeral, .any, .lineStart, .lineEnd, .openBracket, .closeBracket:
                return true
            case .name, .pronoun, .vietPhrase, .hanViet, .word:
                return false
            }
        }

        /// `<START>` / `<END>`: neo rộng 0, không capture, không có độ dài.
        public var isLineAnchor: Bool {
            self == .lineStart || self == .lineEnd
        }

        /// `<[>` / `<]>`: đúng một ký tự ngoặc lấy trong bộ ngoặc, không có độ dài.
        public var isBracket: Bool {
            self == .openBracket || self == .closeBracket
        }

        /// Token **không** sinh `{i}` (neo dòng + ngoặc) — parser và màn sửa rule cùng hỏi thuộc tính
        /// này để không đánh số chip của chúng và không hiện thanh độ dài.
        public var isUncaptured: Bool {
            isLineAnchor || isBracket
        }

        /// Cách viết cũ vẫn được nhận khi đọc rule và cấu hình riêng truyện. **Không** dùng để ghi.
        private static let legacyTokenNames: [String: Kind] = ["^": .lineStart, "$": .lineEnd]

        /// Tên token (phần giữa `<` và `>`, không kèm `:min-max`) → loại token; nhận cả tên cũ `^`/`$`
        /// của neo dòng. Phân biệt hoa/thường như mọi tên token khác.
        public static func kind(forTokenName name: String) -> Kind? {
            Kind(rawValue: name) ?? legacyTokenNames[name]
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
