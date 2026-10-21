import Foundation

/// Một nguồn Legado **chữ** đã cài, trả cho client debug (`legado.sources`) để chọn nguồn nghiệm thu.
///
/// Chỉ thông tin hiển thị — không đường dẫn, không `source.json`, không cấu hình. `extensions.list` không còn chứa
/// nguồn Legado (chúng không có script JS), nên đây là đường duy nhất client biết `packageId` của chúng.
public struct LegadoCorpusSourceInfo: Codable, Sendable, Equatable {
    public let packageId: String
    public let name: String
    public let enabled: Bool
    public let hasSearchRules: Bool
    public let hasExploreRules: Bool

    public init(packageId: String, name: String, enabled: Bool, hasSearchRules: Bool, hasExploreRules: Bool) {
        self.packageId = packageId
        self.name = name
        self.enabled = enabled
        self.hasSearchRules = hasSearchRules
        self.hasExploreRules = hasExploreRules
    }

    /// Nguồn chữ trong bảng chụp `LegadoSourceRepository`, xếp theo tên gốc. Gọi sau khi bảng chụp sẵn sàng.
    static func textSources() -> [LegadoCorpusSourceInfo] {
        LegadoSourceRepository.allSummariesSnapshot()
            .filter { $0.kind == .text }
            .map { summary in
                LegadoCorpusSourceInfo(
                    packageId: summary.packageId,
                    name: summary.name,
                    enabled: summary.isEnabled,
                    hasSearchRules: summary.hasSearchRules,
                    hasExploreRules: summary.hasExploreRules
                )
            }
            .sorted { lhs, rhs in
                lhs.name == rhs.name ? lhs.packageId < rhs.packageId : lhs.name < rhs.name
            }
    }
}
