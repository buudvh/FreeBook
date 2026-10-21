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

        var id: String {
            switch self {
            case .importResult: return "importResult"
            case .error: return "error"
            case .confirmDeleteAll: return "confirmDeleteAll"
            }
        }
    }

    var query = ""
    var groupFilter: GroupFilter = .all
    /// Đang nhập / xoá tất cả — khoá menu và hiện vòng chờ.
    var isBusy = false
    var busyMessage = ""
    var showingFileImporter = false
    var showingURLPrompt = false
    var urlInput = ""
    var alert: PendingAlert?

    /// Danh sách sau bộ lọc nhóm + ô tìm (khớp tên gốc, tên dịch, URL — không phân biệt hoa thường/dấu).
    func visibleSummaries(_ all: [LegadoSourceSummary]) -> [LegadoSourceSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.isEmpty ? "" : LegadoSourceSummary.fold(trimmed)
        return all.filter { summary in
            switch groupFilter {
            case .all: break
            case .group(let group): guard summary.groups.contains(group) else { return false }
            case .ungrouped: guard summary.groups.isEmpty else { return false }
            }
            return folded.isEmpty || summary.searchKey.contains(folded)
        }
    }

    /// Tiêu đề alert đang chờ.
    var alertTitle: String {
        switch alert {
        case .importResult(let summary): return "Đã nhập \(summary.importedCount) nguồn"
        case .error: return "Lỗi nguồn Legado"
        case .confirmDeleteAll: return "Xoá tất cả nguồn Legado?"
        case .none: return ""
        }
    }

    /// Nội dung alert: kết quả nhập gồm mới / cập nhật / giống hệt / bỏ qua theo lý do.
    var alertMessage: String {
        switch alert {
        case .importResult(let summary):
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
        case .error(let message):
            return message
        case .confirmDeleteAll(let count):
            return "Gỡ \(count) nguồn Legado khỏi ứng dụng. Tiện ích JavaScript không bị ảnh hưởng."
        case .none:
            return ""
        }
    }
}
