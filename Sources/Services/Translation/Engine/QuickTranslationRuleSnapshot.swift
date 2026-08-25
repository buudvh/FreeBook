import Foundation

/// Bản chụp **bất biến** của bộ rule đang chạy. Compile một lần khi nạp, không compile theo từng lần
/// dịch. `generation` đi vào cache key dịch và vào `translationGenerationToken` để snapshot
/// Reader/TTS cũ bị loại đúng lúc.
public struct QuickTranslationRuleSnapshot: Sendable {
    /// Bộ rule **không** đi kèm app: nó là một file trên máy ở `translate/QuickTranslateRules.txt`.
    /// Ba case dưới đây chỉ nói *lần nạp này lấy text từ đâu*, để màn quản lý báo đúng cho người dùng.
    public enum Source: Sendable {
        /// Nạp từ file đã có trên máy (lúc khởi động, hoặc sau khi khôi phục backup).
        case local
        /// Vừa tải từ HuggingFace — cùng dataset với VietPhrase/PhienAm.
        case downloaded
        /// Vừa nhập từ file người dùng chọn.
        case imported

        public var label: String {
            switch self {
            case .local: return "Bộ rule trên máy"
            case .downloaded: return "Vừa tải từ HuggingFace"
            case .imported: return "File vừa nhập"
            }
        }
    }

    public let generation: Int
    public let source: Source
    /// MD5 rút gọn của văn bản nguồn — đủ để đối chiếu bản đang chạy, không log nội dung.
    public let sourceHash: String
    public let rules: [QuickTranslationCompiledRule]
    public let literalIndex: QuickTranslationLiteralIndex
    /// Lỗi/cảnh báo của lần nạp này (đã cắt bớt để không phình bộ nhớ với file 17k dòng).
    public let issues: [QuickTranslationRuleIssue]
    /// Tổng số cảnh báo trước khi cắt, để UI báo đúng con số.
    public let warningCount: Int
    public let loadedAt: Date

    public var ruleCount: Int { rules.count }

    public init(
        generation: Int,
        source: Source,
        sourceHash: String,
        rules: [QuickTranslationCompiledRule],
        issues: [QuickTranslationRuleIssue],
        warningCount: Int,
        loadedAt: Date = Date()
    ) {
        self.generation = generation
        self.source = source
        self.sourceHash = sourceHash
        self.rules = rules
        self.literalIndex = QuickTranslationLiteralIndex(rules: rules)
        self.issues = issues
        self.warningCount = warningCount
        self.loadedAt = loadedAt
    }
}
