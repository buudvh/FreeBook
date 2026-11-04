import Foundation

/// Trạng thái UI của tab "Nguồn Legado" — một giá trị duy nhất `RepositoryManagerView` giữ bằng `@State`, để menu ⋯
/// trên toolbar (thuộc view cha) và danh sách (view con) cùng thấy bộ lọc đang chọn.
struct LegadoSourceTabState {
    enum GroupFilter: Hashable {
        case all
        case group(String)
        case ungrouped
    }

    enum PendingAlert: Identifiable {
        case importResult(LegadoImportSummary)
        case error(String)
        case confirmDeleteAll(count: Int)
        case confirmDeleteSubset(DeleteSubset)

        var id: String {
            switch self {
            case .importResult: return "importResult"
            case .error: return "error"
            case .confirmDeleteAll: return "confirmDeleteAll"
            case .confirmDeleteSubset: return "confirmDeleteSubset"
            }
        }
    }

    /// Tập nguồn chụp lúc bấm hàng ngăn kéo — bấm "Xoá" thì xoá đúng tập này, số trong hộp xác nhận khớp số sẽ xoá.
    struct DeleteSubset {
        enum Scope {
            /// Danh sách đang hiện (NSFW + nhóm + ô tìm).
            case visible
            /// Mọi nguồn đang tắt, không theo nhóm / ô tìm, kể cả nguồn 18+ đang ẩn.
            case disabled
        }

        let scope: Scope
        let packageIds: [String]
        /// Phạm vi danh sách đang hiện: "Nhóm: …" / "Tất cả nguồn" (+ từ khoá ô tìm).
        let scopeTitle: String
        /// Số nguồn 18+ đang ẩn nằm trong tập (chỉ phạm vi `disabled`).
        let hiddenNsfwCount: Int
    }

    /// Màn chi tiết của một nguồn (sheet có `NavigationStack` riêng).
    struct DetailRoute: Identifiable, Hashable {
        let packageId: String
        var id: String { packageId }
    }

    /// Lượt kiểm tra hàng loạt mở từ menu ⋯ (danh sách đang hiện).
    struct CheckRoute: Identifiable, Hashable {
        let packageIds: [String]
        /// Tiêu đề phạm vi: "Nhóm: …" / "Tất cả nguồn" (+ từ khoá ô tìm).
        let scopeTitle: String
        let id = UUID()
    }

    var query = ""
    var groupFilter: GroupFilter = .all
    /// Đang nhập / xoá tất cả / xuất — khoá menu và hiện vòng chờ.
    var isBusy = false
    var busyMessage = ""
    var showingFileImporter = false
    var showingURLPrompt = false
    var urlInput = ""
    /// Bấm "Nhập" ở sheet URL (1.3.624): việc nhập chạy ở `onDismiss` của sheet, để alert tổng kết không trình bày
    /// chồng lúc sheet còn đang đóng.
    var isURLImportPending = false
    var alert: PendingAlert?
    var detail: DetailRoute?
    var check: CheckRoute?
    var exportFile: LegadoSourceExportFile?

    /// Bỏ nguồn 18+ khi công tắc NSFW chung đang tắt — nền cho chip nhóm, "Đang bật x/y" và danh sách.
    func nsfwFiltered(
        _ all: [LegadoSourceSummary],
        includeNsfw: Bool,
        nsfwIds: Set<String>
    ) -> [LegadoSourceSummary] {
        guard !includeNsfw, !nsfwIds.isEmpty else { return all }
        return all.filter { !nsfwIds.contains($0.packageId) }
    }

    /// Danh sách đang hiện = NSFW + bộ lọc nhóm + ô tìm (khớp tên gốc, tên dịch, URL — không phân biệt hoa thường/dấu).
    /// Mọi thao tác "theo danh sách đang hiện / nhóm đang lọc" (bật/tắt, kiểm tra, xuất) đều dùng đúng hàm này.
    func visibleSummaries(
        _ all: [LegadoSourceSummary],
        includeNsfw: Bool,
        nsfwIds: Set<String>
    ) -> [LegadoSourceSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.isEmpty ? "" : LegadoSourceSummary.fold(trimmed)
        return nsfwFiltered(all, includeNsfw: includeNsfw, nsfwIds: nsfwIds).filter { summary in
            switch groupFilter {
            case .all: break
            case .group(let group): guard summary.groups.contains(group) else { return false }
            case .ungrouped: guard summary.groups.isEmpty else { return false }
            }
            return folded.isEmpty || summary.searchKey.contains(folded)
        }
    }

    /// Chip nhóm tính trên danh sách sau lọc NSFW: nhiều nguồn trước, cùng số thì theo tên dịch (cùng luật repository).
    static func groupCounts(_ pool: [LegadoSourceSummary]) -> (counts: [LegadoSourceGroupCount], ungrouped: Int) {
        var counts: [String: (translated: String, count: Int)] = [:]
        var ungrouped = 0
        for summary in pool {
            if summary.groups.isEmpty { ungrouped += 1 }
            for (index, group) in summary.groups.enumerated() {
                let translated = index < summary.translatedGroups.count ? summary.translatedGroups[index] : group
                counts[group] = (translated, (counts[group]?.count ?? 0) + 1)
            }
        }
        let sorted = counts
            .map { LegadoSourceGroupCount(group: $0.key, translatedGroup: $0.value.translated, count: $0.value.count) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count
                    ? LegadoSourceSummary.fold(lhs.translatedGroup) < LegadoSourceSummary.fold(rhs.translatedGroup)
                    : lhs.count > rhs.count
            }
        return (sorted, ungrouped)
    }

    /// Tiêu đề phạm vi cho màn kiểm tra hàng loạt (nhóm đang lọc + ô tìm).
    func scopeTitle(groupLabel: (String) -> String) -> String {
        var title: String
        switch groupFilter {
        case .all: title = "Tất cả nguồn"
        case .group(let group): title = "Nhóm: \(groupLabel(group))"
        case .ungrouped: title = "Chưa nhóm"
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { title += " · tìm \"\(trimmed)\"" }
        return title
    }

    /// Tiêu đề alert đang chờ.
    var alertTitle: String {
        switch alert {
        case .importResult(let summary): return "Đã nhập \(summary.importedCount) nguồn"
        case .error: return "Lỗi nguồn Legado"
        case .confirmDeleteAll: return "Xoá tất cả nguồn Legado?"
        case .confirmDeleteSubset(let subset):
            switch subset.scope {
            case .visible: return "Xoá nguồn Legado đang hiện?"
            case .disabled: return "Xoá nguồn Legado đang tắt?"
            }
        case .none: return ""
        }
    }

    /// Nội dung alert: kết quả nhập gồm mới / cập nhật / giống hệt / bỏ qua theo lý do.
    var alertMessage: String {
        switch alert {
        case .importResult(let summary):
            return Self.importSummaryMessage(summary)
        case .error(let message):
            return message
        case .confirmDeleteAll(let count):
            return "Gỡ \(count) nguồn Legado khỏi ứng dụng. Tiện ích JavaScript không bị ảnh hưởng."
        case .confirmDeleteSubset(let subset):
            return Self.deleteSubsetMessage(subset)
        case .none:
            return ""
        }
    }

    private static func deleteSubsetMessage(_ subset: DeleteSubset) -> String {
        let count = subset.packageIds.count
        var message: String
        switch subset.scope {
        case .visible:
            message = "Gỡ \(count) nguồn Legado đang hiện (\(subset.scopeTitle)) khỏi ứng dụng."
        case .disabled:
            message = "Gỡ \(count) nguồn Legado đang tắt trong toàn bộ danh sách khỏi ứng dụng"
            message += subset.hiddenNsfwCount > 0 ? ", kể cả \(subset.hiddenNsfwCount) nguồn 18+ đang ẩn." : "."
        }
        return message + " Truyện trên kệ dùng các nguồn này sẽ thành truyện mất nguồn."
    }

    /// Nhóm đang lọc không còn nguồn nào (vừa xoá hết) ⇒ về "Tất cả", để chip đang chọn không biến mất khỏi hàng chip.
    mutating func resetGroupFilterIfEmpty(groups: [LegadoSourceGroupCount], ungroupedCount: Int) {
        switch groupFilter {
        case .all:
            return
        case .group(let group):
            if !groups.contains(where: { $0.group == group }) { groupFilter = .all }
        case .ungrouped:
            if ungroupedCount == 0 { groupFilter = .all }
        }
    }

    /// Dùng chung cho alert tổng kết của tab và của liên kết `legado://`.
    static func importSummaryMessage(_ summary: LegadoImportSummary) -> String {
        var lines = ["Mới: \(summary.added)", "Cập nhật: \(summary.updated)"]
        if summary.unchanged > 0 { lines.append("Giống hệt (không ghi lại): \(summary.unchanged)") }
        if summary.skippedCount > 0 {
            lines.append("Bỏ qua: \(summary.skippedCount) (\(summary.skippedLines.joined(separator: ", ")))")
        }
        if !summary.writeErrors.isEmpty {
            lines.append("Lỗi ghi: \(summary.writeErrors.prefix(3).joined(separator: "; "))")
        }
        if let indexError = summary.indexError { lines.append("Lỗi lưu danh sách: \(indexError)") }
        lines.append("Nguồn giữ trạng thái bật/tắt trong tệp.")
        return lines.joined(separator: "\n")
    }
}
