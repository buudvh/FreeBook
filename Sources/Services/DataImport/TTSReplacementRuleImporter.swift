import Foundation

/// Nhập file JSON quy tắc **thay thế ký tự TTS** (tầng chung hoặc tầng riêng của truyện) theo ba `DataImportMode`.
///
/// Khoá so trùng = `TTSReplacementRule.matchKey` (mẫu hạ chữ thường, giữ dấu) — luật 1.3.978: mọi phép so mẫu của luật
/// thay thế đi qua đó. Luật trùng khoá bị đè giữ **`id` và vị trí cũ**, lấy mẫu / chuỗi thay / công tắc của bản trong
/// file. `id` trùng với luật khác (file xuất ra rồi nhập lại sau khi đã sửa) ⇒ cấp `id` mới.
///
/// Đặt ngoài `Services/TTS/` có chủ ý: gộp xong rồi ghi qua đúng một đường công khai của manager
/// (`importRules(fromJSONString:mode: .overwrite, bookId:)`) — đường duy nhất ghi được cả tầng riêng của truyện.
/// `TTSReplacementManager.ImportMode` (hai chế độ) chỉ còn cho "Khôi phục mặc định".
enum TTSReplacementRuleImporter {
    enum Failure: LocalizedError {
        case invalidJSON(String)
        case empty
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .invalidJSON(let reason): return "File JSON không đúng định dạng quy tắc thay thế TTS: \(reason)"
            case .empty: return "File không có quy tắc nào."
            case .saveFailed: return "Không ghi được quy tắc thay thế."
            }
        }
    }

    /// `bookId` rỗng / `nil` ⇒ tầng chung.
    @MainActor
    static func importRules(
        from data: Data,
        mode: DataImportMode,
        bookId: String?,
        manager: TTSReplacementManager = .shared
    ) throws -> KeyedImportSummary {
        let imported: [TTSReplacementRule]
        do {
            imported = try JSONDecoder().decode([TTSReplacementRule].self, from: data)
        } catch {
            throw Failure.invalidJSON(error.localizedDescription)
        }
        guard !imported.isEmpty else { throw Failure.empty }

        let isBookLayer = !(bookId ?? "").isEmpty
        let current = isBookLayer ? manager.rules(bookId: bookId) : manager.rules
        let merged = KeyedImportMerger.merge(
            existing: current,
            imported: imported,
            mode: mode,
            key: { $0.matchKey },
            isSameContent: { $0.pattern == $1.pattern && $0.replacement == $1.replacement && $0.isEnabled == $1.isEnabled },
            overwrite: { existing, incoming in
                var updated = incoming
                updated.id = existing.id
                return updated
            }
        )
        let rules = KeyedImportMerger.uniquingIDs(merged.elements, id: \TTSReplacementRule.id, makeID: { UUID() })

        let encoded = try JSONEncoder().encode(rules)
        guard let json = String(data: encoded, encoding: .utf8),
              manager.importRules(fromJSONString: json, mode: .overwrite, bookId: bookId) else {
            throw Failure.saveFailed
        }
        return merged.summary
    }
}
