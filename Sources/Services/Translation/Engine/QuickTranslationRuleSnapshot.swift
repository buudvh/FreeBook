import Foundation

/// Bản chụp **bất biến** của bộ rule đang chạy. Compile một lần khi nạp, không compile theo từng lần
/// dịch. `generation` đi vào cache key dịch và vào `translationGenerationToken` để snapshot
/// Reader/TTS cũ bị loại đúng lúc.
public struct QuickTranslationRuleSnapshot: Sendable {
    /// Handle chỉ dùng trong bộ nhớ cho từng hàng màn quản lý. Nó không đi vào file rule,
    /// backup hay SwiftData; `sourceLine` vẫn chỉ là toạ độ vật lý ngắn hạn của file.
    public struct Row: Identifiable, Sendable {
        public let id: UUID
        public let ruleIndex: Int

        public init(id: UUID, ruleIndex: Int) {
            self.id = id
            self.ruleIndex = ruleIndex
        }
    }

    /// Bộ rule **không** đi kèm app: nó là một file trên máy ở `translate/QuickTranslateRules.txt`.
    /// Bốn case dưới đây chỉ nói *lần nạp này lấy text từ đâu*, để màn quản lý báo đúng cho người dùng.
    public enum Source: Sendable {
        /// Nạp từ file đã có trên máy (lúc khởi động, hoặc sau khi khôi phục backup).
        case local
        /// Vừa tải từ HuggingFace — cùng dataset với VietPhrase/PhienAm.
        case downloaded
        /// Vừa nhập từ file người dùng chọn.
        case imported
        /// Vừa thêm/sửa/xoá một rule ngay trong app.
        case edited

        public var label: String {
            switch self {
            case .local: return "Bộ rule trên máy"
            case .downloaded: return "Vừa tải từ HuggingFace"
            case .imported: return "File vừa nhập"
            case .edited: return "Vừa sửa trong app"
            }
        }
    }

    public let generation: Int
    public let source: Source
    /// MD5 rút gọn của văn bản nguồn — đủ để đối chiếu bản đang chạy, không log nội dung.
    public let sourceHash: String
    /// SHA-256 đầy đủ chỉ dùng để chặn thao tác theo hàng khi file đã đổi ngoài snapshot.
    public let sourceRevision: String
    public let rules: [QuickTranslationCompiledRule]
    /// Cặp handle/index song song với `rules`; không dùng `sourceLine` làm định danh UI.
    public let rows: [Row]
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
        sourceRevision: String,
        rules: [QuickTranslationCompiledRule],
        rowIDs: [UUID],
        issues: [QuickTranslationRuleIssue],
        warningCount: Int,
        loadedAt: Date = Date()
    ) {
        self.generation = generation
        self.source = source
        self.sourceHash = sourceHash
        self.sourceRevision = sourceRevision
        self.rules = rules
        let identifiers = rowIDs.count == rules.count ? rowIDs : rules.map { _ in UUID() }
        self.rows = rules.indices.map { Row(id: identifiers[$0], ruleIndex: $0) }
        self.literalIndex = QuickTranslationLiteralIndex(rules: rules)
        self.issues = issues
        self.warningCount = warningCount
        self.loadedAt = loadedAt
    }
}
