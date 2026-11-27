import Foundation

/// **Hàng đợi duy nhất** cho mọi lượt ghi từ điển gốc dùng chung: nhập từ thẻ (Cài đặt dịch thuật › Từ điển chung), nhập
/// từ danh sách Phiên âm / Pronouns, sửa / xoá một hàng của hai danh sách đó (và nhóm Pronoun của màn Quản lý nghĩa từ),
/// xoá cả từ điển ở thẻ, lượt chuẩn hoá `|` → `/` một lần của Pronouns.
///
/// Vì sao phải xếp hàng **cả phần nạp lại**: một lượt = đọc file gốc ⇒ đổi ⇒ ghi ⇒ nạp lại (`loadAllDictionaries` mất vài
/// giây). Actor thường cho lượt khác chen vào ở mỗi `await` (reentrancy) — trước đây một lượt sửa hàng chen giữa lúc nhập
/// đang nạp lại đọc bản RAM cũ rồi ghi đè file ⇒ mất mọi mục vừa nhập. `serialized` nối các lượt thành chuỗi: lượt sau
/// chờ lượt trước **xong hẳn** (kể cả nạp lại). Thêm nữa, mọi lượt đọc từ điển gốc **trên đĩa**
/// (`GlobalDictionaryImporter.baseEntries`), không đọc bản đã nạp trong RAM.
///
/// Sửa / xoá một hàng (chỉ PhienAm `ChinesePhienAmWords.txt` và Pronouns `Pronouns.dat`): đọc cả từ điển gốc, đổi, ghi lại
/// cả file (`GlobalDictionaryImporter.writeBase`: Pronouns dựng lại `.dat` — `.txt` không còn sau lần nạp đầu; PhienAm ghi
/// file text), nạp lại **riêng** từ điển đó, xoá cache dịch và báo đổi từ điển để Reader / TTS dịch lại.
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

    /// Đuôi chuỗi các lượt đã xếp hàng.
    private var tail: Task<Void, Never>?

    // MARK: - Đọc

    /// Mục hiện có (trên đĩa, sau mọi lượt ghi đang xếp hàng), sắp theo khoá.
    func entries(type: String) async throws -> [(key: String, value: String)] {
        try Self.checkEditable(type)
        return try await serialized {
            try GlobalDictionaryImporter.baseEntries(type: type).sorted { $0.key < $1.key }
        }
    }

    // MARK: - Ghi

    /// Nhập file theo `DataImportMode` (mọi loại: `vietphrase`, `names`, `pronouns`, `phienam`).
    func importFile(at url: URL, type: String, mode: DataImportMode) async throws -> GlobalDictionaryImporter.Outcome {
        try await serialized {
            try await GlobalDictionaryImporter.importFile(at: url, type: type, mode: mode)
        }
    }

    /// Xoá file gốc (`.txt` + `.dat`) của một từ điển chung (mọi loại).
    func deleteBase(type: String) async throws {
        try await serialized {
            try await GlobalDictionaryImporter.deleteBaseDictionary(type: type)
        }
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

    // MARK: - Chuẩn hoá một lần

    /// Kết quả `normalizePronounSeparators()`: số mục Pronouns đã đổi / tổng số mục (0 / 0 = chưa có từ điển).
    struct SeparatorNormalization: Sendable {
        let changed: Int
        let total: Int
    }

    /// Đổi mọi `|` trong **nghĩa** của Pronouns thành `/` (`PronounsSeparatorNormalization`). Chỉ đổi cú pháp: một ký tự
    /// đổi một ký tự — không cắt khoảng trắng, không gộp / bỏ nghĩa trùng, không đụng `¦`, khoá giữ nguyên. Không mục nào
    /// có `|` (hoặc chưa có từ điển) ⇒ không ghi gì. Có đổi ⇒ ghi lại + nạp lại y như sửa một hàng.
    func normalizePronounSeparators() async throws -> SeparatorNormalization {
        try await serialized {
            let entries = try GlobalDictionaryImporter.baseEntries(type: "pronouns")
            var changed = 0
            let normalized = entries.map { entry -> (key: String, value: String) in
                guard entry.value.contains("|") else { return entry }
                changed += 1
                return (key: entry.key, value: entry.value.replacingOccurrences(of: "|", with: "/"))
            }
            guard changed > 0 else { return SeparatorNormalization(changed: 0, total: entries.count) }
            try GlobalDictionaryImporter.writeBase(normalized, type: "pronouns")
            await Self.reloadAfterWrite(type: "pronouns")
            return SeparatorNormalization(changed: changed, total: entries.count)
        }
    }

    // MARK: - Phụ trợ

    /// Chạy `operation` sau khi mọi lượt xếp trước đã xong hẳn. `tail` đổi ngay (không `await` trước đó) nên thứ tự lượt
    /// đúng thứ tự gọi.
    private func serialized<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }

    private static func checkEditable(_ type: String) throws {
        guard type == "phienam" || type == "pronouns" else { throw EditError.unsupportedType(type) }
    }

    private func rewrite(
        type: String,
        change: @escaping @Sendable (inout [(key: String, value: String)]) -> Void
    ) async throws {
        try Self.checkEditable(type)
        try await serialized {
            var entries = try GlobalDictionaryImporter.baseEntries(type: type)
            change(&entries)
            try GlobalDictionaryImporter.writeBase(entries, type: type)
            await Self.reloadAfterWrite(type: type)
        }
    }

    /// Sau khi ghi lại cả file gốc: nạp lại **riêng** từ điển đó, xoá cache dịch, báo đổi từ điển (Reader / TTS dịch lại).
    private static func reloadAfterWrite(type: String) async {
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
