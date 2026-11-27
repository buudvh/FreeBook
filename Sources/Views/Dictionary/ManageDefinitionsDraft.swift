import Foundation

/// Bản nháp các nghĩa đang sửa trong màn "Quản lý nghĩa từ".
///
/// Mỗi nghĩa là một hàng có `id` riêng chứ không tra theo chuỗi nữa: nghĩa giờ sửa được tại chỗ nên
/// nội dung không còn là khoá ổn định, và hai nghĩa trùng chữ vẫn phải là hai hàng khác nhau để
/// nút đổi chỗ và nút xoá biết chính xác đang tác động vào hàng nào.
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

    /// Nhãn nguồn của từ điển Pronouns trong `[DictionaryMatchInfo]` — `ReaderView.dictionaryMatches(for:bookId:)` gắn
    /// đúng hằng này, thanh chip (`ReaderView+Suggestions`) và màn này nhận ra nhóm Pronoun bằng nó.
    static let pronounSource = "Xưng hô (Pronouns)"

    /// Năm nhóm từ điển sửa được ở màn này, theo thứ tự hiển thị — cũng là thứ tự chip nghĩa (`ReaderView+Suggestions`).
    /// Pronoun (anh Bửu, 2026-11-27) đứng sau VP Chung, chỉ có bản chung, lưu thẳng file Pronouns gốc. Nhóm còn lại trong
    /// `[DictionaryMatchInfo]` (Phiên âm) chỉ đọc nên không có mặt ở đây.
    static let editableSources = [
        "Names (Riêng)",
        "Names (Chung)",
        "VietPhrase (Riêng)",
        "VietPhrase (Chung)",
        pronounSource
    ]

    private var rowsBySource: [String: [Row]] = [:]

    init(matches: [DictionaryMatchInfo]) {
        for source in Self.editableSources {
            let translation = matches.first(where: { $0.source == source })?.translation ?? ""
            rowsBySource[source] = Self.splitMeanings(translation, source: source).map {
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

    /// Đổi chỗ hàng ở `index` với hàng liền kề theo `offset` (-1 về trước, +1 về sau). Ngoài dải thì bỏ qua.
    mutating func move(source: String, from index: Int, by offset: Int) {
        guard var rows = rowsBySource[source] else { return }
        let target = index + offset
        guard rows.indices.contains(index), rows.indices.contains(target) else { return }
        rows.swapAt(index, target)
        rowsBySource[source] = rows
    }

    /// Thêm một nghĩa trống ở cuối nhóm và trả `id` của nó để màn chọn luôn chip mới mà mở ô sửa.
    @discardableResult
    mutating func appendEmptyRow(source: String) -> UUID {
        var rows = rowsBySource[source] ?? []
        let row = Row(text: "")
        rows.append(row)
        rowsBySource[source] = rows
        return row.id
    }

    /// Gỡ hẳn một hàng khỏi bản nháp (không phải xoá mềm).
    mutating func removeRow(rowId: UUID, source: String) {
        rowsBySource[source]?.removeAll { $0.id == rowId }
    }

    /// Hàng người dùng vừa thêm mà chưa nhập gì: không có gì để hoàn tác nên gỡ hẳn thay vì xoá mềm.
    /// Hàng rỗng đọc từ đĩa (`preservesEmpty`) không tính — nó là một nghĩa thật.
    func isDiscardableBlank(rowId: UUID, source: String) -> Bool {
        guard let row = rows(for: source).first(where: { $0.id == rowId }) else { return false }
        return !row.preservesEmpty && row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Tách chuỗi nghĩa

    /// Như `splitMeanings(_:)`, thêm luật riêng nguồn: nghĩa Pronoun còn ngăn bằng `|` (file Pronouns cũ), coi như `/`.
    /// Bản nháp và phép so "đã sửa chưa" lúc lưu phải cùng gọi hàm này — tách khác nhau là mục không đụng tới vẫn bị ghi lại.
    static func splitMeanings(_ translation: String, source: String) -> [String] {
        guard source == pronounSource else { return splitMeanings(translation) }
        return splitMeanings(translation.replacingOccurrences(of: "|", with: "/"))
    }

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
