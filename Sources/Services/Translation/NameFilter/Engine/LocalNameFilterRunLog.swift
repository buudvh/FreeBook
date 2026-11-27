import Foundation

/// Dòng log `🔎 [LọcName] Xong…` cuối một lượt lọc name local. Giữ dạng cũ (các phần nối bằng " · ", lý do bỏ đúng tên
/// bản thử Python) và thêm phần của bản LAC: chế độ, thời gian chuẩn bị model / gắn nhãn / lọc phía LAC, số theo loại, số
/// name đã có, số hàng bước hợp + luật (e), lý do bỏ của bộ luật tách riêng ("luật bỏ").
enum LocalNameFilterRunLog {
    static func write(
        _ report: LocalNameFilterEngine.Report,
        metrics: LocalNameFilterRun.Metrics,
        total: Int,
        hanCount: Int,
        stoppedEarly: Bool,
        hasPronouns: Bool,
        usesLAC: Bool,
        taggedLines: Int
    ) {
        let snapshot = report.snapshot
        let stopNote = stoppedEarly ? " (bấm Dừng)" : ""
        let unreadableNote = metrics.unreadable > 0 ? " (\(metrics.unreadable) không đọc được)" : ""
        let titleNote = hasPronouns ? String(report.titleCount) : "tắt (chưa nạp Pronouns)"
        var parts: [String] = [
            "🔎 [LọcName] Xong\(stopNote): \(metrics.processed)/\(total) chương\(unreadableNote), \(hanCount) chữ Hán",
            usesLAC ? "LAC" : "chỉ bộ luật (model tự kiểm lệch)",
            "model \(metrics.modelMs) ms",
            "đọc \(metrics.readMs) ms"
        ]
        if usesLAC { parts.append("gắn nhãn \(metrics.lacMs) ms (\(taggedLines) dòng)") }
        parts.append(contentsOf: [
            "lượt 1 \(metrics.passOneMs) ms",
            "lượt 2 \(report.passTwoMs) ms",
            "luật \(report.rulesMs) ms"
        ])
        if usesLAC { parts.append("lọc LAC \(report.lacFilterMs) ms") }
        parts.append(contentsOf: [
            "cập nhật \(metrics.updates) lần",
            "giữ \(snapshot.names.count)",
            "đã có \(snapshot.knownCount)",
            "theo loại [\(categories(snapshot))]"
        ])
        if usesLAC { parts.append("hợp \(report.unionAdded) · (e) \(report.rescued)") }
        parts.append("bỏ [\(joined(snapshot.droppedByReason))]")
        if let ruleDropped = report.ruleDroppedByReason { parts.append("luật bỏ [\(joined(ruleDropped))]") }
        parts.append("danh xưng \(titleNote)")
        AppLogger.shared.log(parts.joined(separator: " · "))
    }

    private static func categories(_ snapshot: LocalNameFilter.Snapshot) -> String {
        var counts: [LocalNameFilter.Category: Int] = [:]
        for name in snapshot.names { counts[name.category, default: 0] += 1 }
        return LocalNameFilter.Category.allCases
            .compactMap { category in counts[category].map { "\(category.label)=\($0)" } }
            .joined(separator: ", ")
    }

    private static func joined(_ reasons: [String: Int]) -> String {
        reasons
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}
