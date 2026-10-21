import Foundation

/// Một nguồn Legado đã cài thuộc loại chạy được (chữ, tranh, video), trả cho client debug (`legado.sources`) để chọn
/// nguồn nghiệm thu.
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

    /// Nguồn chạy được (`LegadoSourcePolicy.isSupportedInCurrentPhase`: chữ, tranh, video) trong bảng chụp
    /// `LegadoSourceRepository`, xếp theo tên gốc. Tên hàm giữ từ đợt 1. Gọi sau khi bảng chụp sẵn sàng.
    static func textSources() -> [LegadoCorpusSourceInfo] {
        LegadoSourceRepository.allSummariesSnapshot()
            .filter { LegadoSourcePolicy.isSupportedInCurrentPhase($0.kind) }
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
