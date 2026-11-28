import Foundation

/// Danh sách hiệu lực của một truyện + thêm / sửa / xoá theo **phạm vi** R (Riêng truyện) | C (Chung) — 2026-11-28, plan
/// "Tiền tố hậu tố riêng truyện" mục B4–B6 (mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M3–M6).
///
/// Mục Chung là lớp bản gốc + sửa đổi của chính store này (`entries()`, `save` / `delete` không có `bookId`); mục Riêng ở
/// `bookStore` (`LocalNameFilterBookAffixStore`). Cùng chữ ở hai phạm vi được phép — bản Riêng thắng ở danh sách hiệu
/// lực; trùng chữ **trong cùng phạm vi** là lỗi.
extension LocalNameFilterAffixListStore {
    /// Phạm vi của một mục.
    enum Scope: String, Sendable, CaseIterable {
        /// Riêng truyện (R) — chỉ truyện đang mở.
        case book
        /// Chung (C) — mọi truyện.
        case common
    }

    /// Một mục đang sửa: chữ Hán + phạm vi hiện tại.
    struct ScopedKey: Equatable, Sendable {
        let key: String
        let scope: Scope
    }

    /// Danh sách hiệu lực của truyện, đúng dạng bộ lọc dùng: mục Riêng (mới thêm đứng đầu) rồi mục Chung **không trùng chữ**
    /// với mục Riêng nào — mỗi chữ đúng một mục, bản Riêng thắng (mọi chỗ tiêu thụ đều lấy mục đầu theo khoá, nên không được
    /// để sót bản Chung cùng chữ: 语 Riêng loại Thuật ngữ mà còn 语 Chung loại Nhân danh thì sẽ rơi vào cả hai bảng của
    /// `LocalNameFilterSetup`). `bookId` rỗng ⇒ chỉ Chung.
    func effective(bookId: String) -> [LocalNameFilter.Suffix] {
        let book = bookStore.affixes(bookId: bookId)
        let common = entries().map(\.suffix)
        guard !book.isEmpty else { return common }
        let bookKeys = Set(book.map(\.key))
        return book + common.filter { !bookKeys.contains($0.key) }
    }

    /// Luật khoá + trùng khoá ở phạm vi đích. `original` = mục đang sửa (`nil` khi thêm mới). Cùng luật đổi phạm vi với
    /// `save(...scope:bookId:original:)`: C → R kiểm trùng trong danh sách riêng như thêm mới; R → C **không** báo trùng khi
    /// Chung đã có chữ đó (sẽ ghi đè mục Chung).
    func keyError(_ key: String, scope: Scope, bookId: String, original: ScopedKey?) -> String? {
        let replacing = replacingKey(for: key, scope: scope, original: original)
        switch scope {
        case .common: return keyError(key, replacing: replacing)
        case .book: return bookStore.keyError(key, bookId: bookId, replacing: replacing)
        }
    }

    /// Thêm / sửa một mục ở phạm vi `scope`. `original` = mục đang sửa (`nil` khi thêm mới):
    /// - cùng phạm vi ⇒ như `save` của phạm vi đó (đổi chữ = thay mục cũ);
    /// - **C → R** (anh Bửu chốt 2026-11-28, mockup bản 3) ⇒ **tạo bản riêng** cho truyện `bookId`; mục Chung giữ nguyên cho
    ///   truyện khác (ở truyện này bản riêng che nó). Truyện đã có mục riêng cùng chữ ⇒ lỗi trùng;
    /// - **R → C** ⇒ ghi lên danh sách Chung (Chung đã có chữ đó ⇒ **ghi đè** nghĩa / loại / vị trí của mục Chung) rồi xoá
    ///   bản riêng `original.key` của truyện.
    ///
    /// `nil` = đã lưu; chuỗi = lỗi. Kiểm / ghi đích lỗi ⇒ không đổi gì. R → C ghi Chung xong mà xoá bản riêng lỗi ⇒ trả lỗi,
    /// mục có ở cả hai phạm vi (không mất dữ liệu).
    @discardableResult
    func save(
        key rawKey: String,
        meaning: String,
        kind: LocalNameFilter.SuffixKind,
        position: LocalNameFilter.MeaningPosition,
        scope: Scope,
        bookId: String,
        original: ScopedKey?
    ) -> String? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacing = replacingKey(for: key, scope: scope, original: original)
        let saveError: String?
        switch scope {
        case .common:
            saveError = save(key: key, meaning: meaning, kind: kind, position: position, replacing: replacing)
        case .book:
            saveError = bookStore.save(bookId: bookId, key: key, meaning: meaning, kind: kind, position: position,
                                       replacing: replacing)
        }
        if let saveError { return saveError }
        // Chỉ R → C bỏ bản cũ; C → R giữ mục Chung cho truyện khác.
        guard let original, original.scope == .book, scope == .common else { return nil }
        return bookStore.delete(bookId: bookId, key: original.key)
    }

    /// Khoá "đang sửa" truyền cho `keyError` / `save` của phạm vi đích: cùng phạm vi ⇒ khoá cũ; R → C mà Chung đã có chữ
    /// `key` ⇒ chính `key` (ghi đè, không báo trùng); thêm mới / C → R ⇒ `nil` (kiểm trùng như thêm mới).
    private func replacingKey(for rawKey: String, scope: Scope, original: ScopedKey?) -> String? {
        guard let original else { return nil }
        if original.scope == scope { return original.key }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if original.scope == .book, scope == .common, entries().contains(where: { $0.key == key }) { return key }
        return nil
    }

    /// Xoá một mục ở phạm vi `scope`: Chung ⇒ `delete(key:)` (mục gốc đánh dấu đã xoá, mọi truyện); Riêng ⇒ chỉ truyện
    /// `bookId`. `nil` = xong; chuỗi = lỗi.
    @discardableResult
    func delete(key: String, scope: Scope, bookId: String) -> String? {
        switch scope {
        case .common: return delete(key: key)
        case .book: return bookStore.delete(bookId: bookId, key: key)
        }
    }
}
