import Foundation

/// Tệp `.json` vừa xuất (mảng nguồn nguyên văn) — View trình bày share sheet bằng `.sheet(item:)`.
struct LegadoSourceExportFile: Identifiable, Sendable, Equatable {
    let url: URL
    /// Số nguồn có trong tệp.
    let count: Int
    /// Số nguồn bỏ qua vì không đọc được `source.json`.
    let skipped: Int

    var id: String { url.path }
}
