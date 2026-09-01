import Foundation

/// Túi biến của một lượt bóc tách — tương ứng `RuleData` + `Book.variable` + `BookChapter.variable`
/// của Legado (`AnalyzeRule.put/get`, `:836-864`).
///
/// Thứ tự tra của Legado là chương → truyện → phiên → nguồn. Bản này gộp còn **ba** mức:
/// `chapter` (chỉ trong lượt hiện tại và được ghi kèm chương), `book` (persist theo truyện),
/// `session` (chỉ trong lượt). Mức `source` bị bỏ vì nó là cache toàn cục của Legado, không có nơi
/// tương ứng trong FreeBook và gần như chỉ dùng cho đăng nhập — vốn đã ngoài phạm vi.
public final class LegadoVariableBag: @unchecked Sendable {
    private let lock = NSLock()
    private var chapterVariables: [String: String]
    private var bookVariables: [String: String]
    private var sessionVariables: [String: String] = [:]

    /// Giá trị đọc-chỉ để rule tra `bookName` / `title` (`AnalyzeRule.get`, `:851-858`).
    public var bookName: String?
    public var chapterTitle: String?

    /// Có biến nào được ghi trong lượt này ⇒ caller cần lưu lại.
    public private(set) var isDirty = false

    public init(book: [String: String] = [:], chapter: [String: String] = [:]) {
        bookVariables = book
        chapterVariables = chapter
    }

    public func put(_ key: String, _ value: String) {
        lock.lock()
        defer { lock.unlock() }
        // Legado ghi vào mức sâu nhất đang có; ở đây luôn ghi mức truyện để giá trị sống qua các lần
        // fetch khác nhau (tìm kiếm → mục lục → nội dung), đúng nhu cầu thực tế của nguồn.
        bookVariables[key] = value
        sessionVariables[key] = value
        isDirty = true
    }

    public func putChapterScoped(_ key: String, _ value: String) {
        lock.lock()
        chapterVariables[key] = value
        isDirty = true
        lock.unlock()
    }

    public func get(_ key: String) -> String {
        if key == "bookName", let bookName, !bookName.isEmpty { return bookName }
        if key == "title", let chapterTitle, !chapterTitle.isEmpty { return chapterTitle }
        lock.lock()
        defer { lock.unlock() }
        if let value = chapterVariables[key], !value.isEmpty { return value }
        if let value = bookVariables[key], !value.isEmpty { return value }
        if let value = sessionVariables[key], !value.isEmpty { return value }
        return ""
    }

    public var bookSnapshot: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return bookVariables
    }

    public var chapterSnapshot: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return chapterVariables
    }

    public func markClean() {
        lock.lock()
        isDirty = false
        lock.unlock()
    }
}
