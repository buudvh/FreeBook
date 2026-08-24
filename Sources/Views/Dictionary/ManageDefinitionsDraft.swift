import Foundation

/// Bản nháp các nghĩa đang sửa trong màn "Quản lý nghĩa từ".
///
/// Mỗi nghĩa là một hàng có `id` riêng chứ không tra theo chuỗi nữa: nghĩa giờ sửa được tại chỗ nên
/// nội dung không còn là khoá ổn định, và hai nghĩa trùng chữ vẫn phải là hai hàng khác nhau để
/// nút lên/xuống và nút xoá biết chính xác đang tác động vào hàng nào.
struct ManageDefinitionsDraft {
    struct Row: Identifiable, Equatable {
        let id: UUID
        var text: String
        /// Xoá mềm: hàng vẫn hiện (gạch ngang) để hoàn tác được trước khi đóng màn.
        var isDeleted: Bool
        /// Chỉ đúng với hàng rỗng **đọc từ đĩa** (chuỗi nghĩa bắt đầu bằng `/`). Hàng như vậy phải
        /// được giữ khi ghi lại, còn ô trống người dùng vừa thêm mà không nhập gì thì bỏ.
        let preservesEmpty: Bool

        init(id: UUID = UUID(), text: String, isDeleted: Bool = false, preservesEmpty: Bool = false) {
            self.id = id
            self.text = text
            self.isDeleted = isDeleted
            self.preservesEmpty = preservesEmpty
        }
    }

    /// Bốn nhóm từ điển sửa được ở màn này, theo thứ tự hiển thị. Các nhóm khác trong
    /// `[DictionaryMatchInfo]` (Phiên âm, Xưng hô, Luật nhân…) chỉ đọc nên không có mặt ở đây.
    static let editableSources = [
        "Names (Riêng)",
        "Names (Chung)",
        "VietPhrase (Riêng)",
        "VietPhrase (Chung)"
    ]

    private var rowsBySource: [String: [Row]] = [:]

    init(matches: [DictionaryMatchInfo]) {
        for source in Self.editableSources {
            let translation = matches.first(where: { $0.source == source })?.translation ?? ""
            rowsBySource[source] = Self.splitMeanings(translation).map {
                Row(text: $0, preservesEmpty: $0.isEmpty)
            }
        }
    }

    // MARK: - Đọc

    func rows(for source: String) -> [Row] {
        rowsBySource[source] ?? []
    }

    func text(rowId: UUID, source: String) -> String {
        rows(for: source).first(where: { $0.id == rowId })?.text ?? ""
    }

    /// Danh sách nghĩa thật sẽ ghi xuống đĩa: bỏ hàng đã xoá mềm, bỏ ô trống người dùng chưa nhập,
    /// bỏ trùng nhưng giữ nguyên thứ tự đang thấy trên màn hình.
    func activeMeanings(for source: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for row in rows(for: source) where !row.isDeleted {
            let trimmed = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty && !row.preservesEmpty { continue }
            guard seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    // MARK: - Sửa

    mutating func setText(_ text: String, rowId: UUID, source: String) {
        guard let index = rowsBySource[source]?.firstIndex(where: { $0.id == rowId }) else { return }
        rowsBySource[source]?[index].text = text
    }

    mutating func setDeleted(_ isDeleted: Bool, rowId: UUID, source: String) {
        guard let index = rowsBySource[source]?.firstIndex(where: { $0.id == rowId }) else { return }
        rowsBySource[source]?[index].isDeleted = isDeleted
    }

    /// Đổi chỗ hàng ở `index` với hàng liền kề theo `offset` (-1 lên, +1 xuống). Ngoài dải thì bỏ qua.
    mutating func move(source: String, from index: Int, by offset: Int) {
        guard var rows = rowsBySource[source] else { return }
        let target = index + offset
        guard rows.indices.contains(index), rows.indices.contains(target) else { return }
        rows.swapAt(index, target)
        rowsBySource[source] = rows
    }

    /// Chèn một ô trống để người dùng nhập trực tiếp — thay cho hộp thoại nhập nghĩa trước đây,
    /// vốn đã thành thừa khi mỗi nghĩa là một ô nhập.
    mutating func insertEmptyRow(source: String, at index: Int) {
        var rows = rowsBySource[source] ?? []
        let position = min(max(index, 0), rows.count)
        rows.insert(Row(text: ""), at: position)
        rowsBySource[source] = rows
    }

    mutating func appendEmptyRow(source: String) {
        var rows = rowsBySource[source] ?? []
        rows.append(Row(text: ""))
        rowsBySource[source] = rows
    }

    // MARK: - Tách chuỗi nghĩa

    /// Tách chuỗi nghĩa gộp thành từng nghĩa. Giữ nguyên hành vi cũ: `¦` coi như `/`, và chuỗi bắt
    /// đầu bằng `/` thì phần rỗng đầu tiên được giữ lại (đừng lặng lẽ đổi `/foo` thành `foo`).
    static func splitMeanings(_ translation: String) -> [String] {
        let clean = translation.replacingOccurrences(of: "¦", with: "/")
        let startsWithSeparator = clean.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
        let components = clean.components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var result: [String] = []
        for (index, component) in components.enumerated() {
            if index == 0 && startsWithSeparator {
                result.append(component)
            } else if !component.isEmpty {
                result.append(component)
            }
        }
        return result
    }
}
