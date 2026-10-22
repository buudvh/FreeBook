import Foundation

/// Policy **thuần** (không state) cho chỗ nào được thấy / chạy nguồn Legado.
///
/// Dùng ở màn Kho (tách nguồn Legado khỏi danh sách tiện ích JS) và — ở bước nối sau — Tìm kiếm, Khám phá, Đổi
/// nguồn. Bật/tắt đọc bảng chụp nonisolated của `LegadoSourceRepository`, nên gọi được từ thread bất kỳ.
public enum LegadoSourcePolicy {
    public static func isLegado(_ ext: Extension) -> Bool {
        LegadoSourceIdentity.isLegado(ext)
    }

    /// Bỏ nguồn Legado — danh sách chỉ dành cho tiện ích JavaScript.
    public static func excludingLegado(_ extensions: [Extension]) -> [Extension] {
        extensions.filter { !LegadoSourceIdentity.isLegado($0) }
    }

    public static func onlyLegado(_ extensions: [Extension]) -> [Extension] {
        extensions.filter { LegadoSourceIdentity.isLegado($0) }
    }

    /// Chữ, tranh (spec §8) và video (spec §9) đều chạy được; chỉ loại không lưu (`unsupported`) bị chặn.
    public static func isSupportedInCurrentPhase(_ kind: LegadoSourceKind) -> Bool {
        kind != .unsupported
    }

    /// Nguồn Legado, loại đã hỗ trợ, và **đang bật**. Trước khi danh sách nạp xong (`LegadoSourceRepository
    /// .isSnapshotReady == false`) mọi nguồn coi như tắt.
    public static func isRunnable(_ ext: Extension) -> Bool {
        guard let kind = LegadoSourceIdentity.kind(of: ext), isSupportedInCurrentPhase(kind) else { return false }
        return LegadoSourceRepository.isEnabled(packageId: ext.packageId)
    }

    /// Chạy được và có Khám phá: `enabledExplore` bật và có `exploreUrl` + rule danh sách (spec §5.2.4).
    public static func isExplorable(_ ext: Extension) -> Bool {
        guard isRunnable(ext), let summary = LegadoSourceRepository.summarySnapshot(packageId: ext.packageId) else {
            return false
        }
        return summary.enabledExplore && summary.hasExploreRules
    }

    /// Chạy được, không có Khám phá dùng được nhưng có rule tìm kiếm ⇒ Khám phá hiện danh mục tìm nhanh
    /// (`LegadoQuickSearch`).
    public static func isQuickSearchable(_ ext: Extension) -> Bool {
        guard isRunnable(ext), let summary = LegadoSourceRepository.summarySnapshot(packageId: ext.packageId) else {
            return false
        }
        return LegadoQuickSearch.applies(hasSearchRules: summary.hasSearchRules, hasExploreRules: summary.hasExploreRules,
                                         enabledExplore: summary.enabledExplore)
    }

    /// Chạy được và có rule tìm kiếm.
    public static func isSearchable(_ ext: Extension) -> Bool {
        guard isRunnable(ext), let summary = LegadoSourceRepository.summarySnapshot(packageId: ext.packageId) else {
            return false
        }
        return summary.hasSearchRules
    }
}
