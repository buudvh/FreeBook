import Foundation

/// Phân loại NSFW cho **nguồn Legado** — hàm thuần, không I/O (chỉ đọc bảng chụp có lock của danh sách nguồn).
///
/// Khác tiện ích JS ở hai điểm:
/// - **Không** dùng mô tả (`bookSourceComment` = `Extension.desc`) cho heuristic từ khoá: ghi chú nguồn hay nhắc
///   `java.…` nên khớp nhầm từ khoá `jav` (đo trên 3689 nguồn của corpus: 41 nguồn bị gắn nhầm chỉ vì ghi chú).
/// - Xét thêm **nhóm** (`bookSourceGroup`): người chia sẻ hay đánh dấu nguồn 18+ bằng 🔞 ở nhóm (256 nguồn) hoặc tên
///   (263 nguồn); tổng 317 nguồn có 🔞 ở tên hoặc nhóm.
///
/// Thứ tự: người dùng tự đánh dấu (`nsfwOverride`) → cờ tự khai trong `plugin.json` (`metadata.nsfw`, kho nguồn
/// Legado tự ghi lúc nhập) → dấu hiệu trên tên + nhóm + tên miền.
extension ExtensionNsfwClassifier {
    /// So **chuỗi con** trên tên + nhóm nguyên văn (chưa gấp). Cố ý **không** có 同人/耽美/腐 (đồng nhân, đam mỹ —
    /// không phải dấu hiệu 18+) và 色/黄 đơn lẻ (灰色, 月色, 黄易…).
    static let legadoMarkers: [String] = [
        "🔞", "18禁", "成人", "色情", "色欲", "涩涩", "肉文", "肉肉", "纯肉", "辣肉", "肉书", "肉色", "肉电子"
    ]

    /// So chuỗi con trên tên + nhóm đã gấp (chữ thường, bỏ dấu) — bổ sung cho từ khoá chung của tiện ích JS.
    static let legadoFoldedMarkers: [String] = ["r18"]

    /// Bản ghi nguồn Legado trong kho tiện ích: nhóm tra ở bảng chụp danh sách nguồn (chưa nạp ⇒ chỉ xét tên).
    nonisolated static func isLegadoNsfw(_ ext: Extension) -> Bool {
        let groups = LegadoSourceRepository.summarySnapshot(packageId: ext.packageId)?.groups ?? []
        return isLegadoNsfw(ext, groups: groups)
    }

    nonisolated static func isLegadoNsfw(_ ext: Extension, groups: [String]) -> Bool {
        if let override = ext.nsfwOverride { return override }
        if ext.isNsfw == true { return true }
        return isLegadoNsfw(name: ext.name, groups: groups, sourceUrl: ext.sourceUrl)
    }

    /// Luật trên dữ liệu thô của nguồn — kho dùng lúc ghi `plugin.json` (cờ `metadata.nsfw`).
    nonisolated static func isLegadoNsfw(name: String, groups: [String], sourceUrl: String) -> Bool {
        let raw = ([name] + groups).joined(separator: " ")
        if legadoMarkers.contains(where: { raw.contains($0) }) { return true }
        let folded = normalized(raw)
        if legadoFoldedMarkers.contains(where: { folded.contains($0) }) { return true }
        if matchesKeyword(in: folded) { return true }
        let source = sourceUrl.lowercased()
        return !source.isEmpty && domainKeywords.contains { source.contains($0) }
    }
}
