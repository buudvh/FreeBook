import Foundation

/// Thay đổi do **một** phiên engine tạo ra, áp lên trạng thái hiện hành theo từng khoá — hai phiên chạy song song
/// trên cùng sách (trang chi tiết tải thông tin và mục lục cùng lúc) không ghi đè mất biến của nhau.
struct LegadoBookStateDelta: Sendable {
    /// `nil` = không đổi.
    var tocUrl: String?
    var info: LegadoBookState.Info?
    /// Cờ đảo mục lục (`book.setReverseToc`); `nil` = không đổi.
    var reverseToc: Bool?
    /// Loại nội dung của sách do JS ghi (`book.type`, spec §13.6); `nil` = không đổi.
    var typeOverride: Int?
    /// Giá trị `nil` = xoá khoá.
    var variables: [String: String?] = [:]
    var ruleVariables: [String: String?] = [:]
    var chapterVariables: [String: [String: String?]] = [:]

    init(tocUrl: String? = nil, info: LegadoBookState.Info? = nil) {
        self.tocUrl = tocUrl
        self.info = info
    }

    var isEmpty: Bool {
        tocUrl == nil && info == nil && reverseToc == nil && typeOverride == nil && variables.isEmpty
            && ruleVariables.isEmpty && chapterVariables.isEmpty
    }

    /// Khác biệt từ `old` tới `new` (khoá mới/đổi ⇒ giá trị, khoá mất ⇒ `nil`).
    static func changes(from old: [String: String], to new: [String: String]) -> [String: String?] {
        var output: [String: String?] = [:]
        for (key, value) in new where old[key] != value {
            output.updateValue(value, forKey: key)
        }
        for key in old.keys where new[key] == nil {
            output.updateValue(nil, forKey: key)
        }
        return output
    }

    /// Ghi nhận biến của sách đã đổi trong phiên (so với bản chụp lúc mở phiên).
    mutating func recordBook(_ book: LegadoBookContext, initial: LegadoBookState) {
        guard book.hasChanges else { return }
        variables = Self.changes(from: initial.variables, to: book.variables)
        ruleVariables = Self.changes(from: initial.ruleVariables, to: book.ruleVariables)
    }

    /// Ghi nhận các thuộc tính "lưu bền" JS đã ghi lên `book` trong phiên (spec §13.5): `setReverseToc`, `book.type`.
    mutating func recordOverrides(_ book: LegadoBookContext) {
        if let reverse = book.reverseTocOverride { reverseToc = reverse }
        if let type = book.typeOverride { typeOverride = type }
    }

    /// Ghi nhận biến của một chương đã đổi trong phiên.
    mutating func recordChapter(url: String, initial: [String: String], current: [String: String]) {
        let changed = Self.changes(from: initial, to: current)
        guard !url.isEmpty, !changed.isEmpty else { return }
        chapterVariables[url, default: [:]].merge(changed) { _, new in new }
    }

    func applied(to state: LegadoBookState) -> LegadoBookState {
        var result = state
        if let tocUrl { result.tocUrl = tocUrl }
        if let info { result.info = info }
        if let reverseToc { result.reverseToc = reverseToc }
        if let typeOverride { result.typeOverride = typeOverride }
        Self.apply(variables, to: &result.variables)
        Self.apply(ruleVariables, to: &result.ruleVariables)
        for (url, values) in chapterVariables {
            var current = result.chapterVariables[url] ?? [:]
            Self.apply(values, to: &current)
            result.chapterVariables[url] = current.isEmpty ? nil : current
        }
        return result
    }

    private static func apply(_ changes: [String: String?], to target: inout [String: String]) {
        for (key, value) in changes {
            if let value {
                target[key] = value
            } else {
                target.removeValue(forKey: key)
            }
        }
    }
}
