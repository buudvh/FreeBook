import Foundation

/// Sửa thẳng **từ điển gốc** PhienAm (`ChinesePhienAmWords.txt`) và Pronouns (`Pronouns.dat`) từ hai màn danh sách mới
/// (thẻ PhienAm.txt / Pronouns.txt › Sửa). Mỗi lần lưu / xoá một mục: đọc cả từ điển gốc, đổi, ghi lại cả file
/// (`GlobalDictionaryImporter.writeBase`: Pronouns dựng lại `.dat` — bản `.txt` không còn sau lần nạp đầu; PhienAm ghi
/// file text), nạp lại **riêng** từ điển đó, xoá cache dịch và báo đổi từ điển để Reader / TTS dịch lại.
///
/// `actor` ⇒ các lượt ghi tuần tự, ngoài main thread. Chỉ hai loại `phienam` / `pronouns`.
actor GlobalDictionaryEditor {
    static let shared = GlobalDictionaryEditor()

    enum EditError: LocalizedError {
        case unsupportedType(String)
        case emptyField

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let type): return "Không sửa thẳng được từ điển \"\(type)\"."
            case .emptyField: return "Từ gốc và nghĩa không được để trống."
            }
        }
    }

    /// Mục hiện có, sắp theo khoá (danh sách dựng một lần).
    func entries(type: String) throws -> [(key: String, value: String)] {
        try checkType(type)
        return try GlobalDictionaryImporter.baseEntries(type: type).sorted { $0.key < $1.key }
    }

    /// Lưu một mục. `oldKey` khác `key` ⇒ đổi từ gốc (bỏ mục cũ); `key` đã có ⇒ đè nghĩa.
    func save(key rawKey: String, value rawValue: String, replacing oldKey: String?, type: String) async throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty, !key.contains("=") else { throw EditError.emptyField }
        try await rewrite(type: type) { entries in
            entries.removeAll { $0.key == key || (oldKey != nil && $0.key == oldKey) }
            entries.append((key: key, value: value))
        }
    }

    func delete(key: String, type: String) async throws {
        try await rewrite(type: type) { entries in
            entries.removeAll { $0.key == key }
        }
    }

    // MARK: - Phụ trợ

    private func checkType(_ type: String) throws {
        guard type == "phienam" || type == "pronouns" else { throw EditError.unsupportedType(type) }
    }

    private func rewrite(type: String, change: (inout [(key: String, value: String)]) -> Void) async throws {
        try checkType(type)
        var entries = try GlobalDictionaryImporter.baseEntries(type: type)
        change(&entries)
        try GlobalDictionaryImporter.writeBase(entries, type: type)
        let manager = TranslationManager.shared
        if type == "phienam" {
            await manager.reloadPhienAmMap()
        } else {
            await manager.reloadPronounsDictionary()
        }
        TranslateUtils.clearCache()
        manager.notifyDictionariesDidUpdate()
    }
}
