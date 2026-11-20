import Foundation

/// Nhập file vào ba **từ điển phiên âm** (NghiTTS, VieNeu-TTS, vtts — 1.3.1041) theo ba `DataImportMode` (popup chọn cách
/// nhập).
///
/// Đặt ngoài `Services/TTS/` có chủ ý: chỉ gọi API công khai của hai kho (`TextPreprocessor.replaceAllWords`,
/// `VieNeuJapaneseDictionary.replaceAll`) — gộp xong trên RAM rồi ghi **một lần**, không đổi gì trong kho.
///
/// Khoá so trùng = khoá **đúng như kho tra lúc đọc**:
/// - NghiTTS: bỏ khoảng trắng hai đầu + hạ chữ thường (như `TextPreprocessor.updateWord`). Đường nhập cũ ghi khoá
///   .plist / .json nguyên văn ⇒ khoá có chữ hoa là mục chết và "Gộp" sẽ tạo mục trùng.
/// - VieNeu: `VieNeuJapaneseDictionary.normalizedKey` (gấp dấu phụ, hạ chữ thường); mục khoá / cách đọc rỗng bị bỏ.
/// - vtts: `VttsPhoneticDictionary.normalizedKey` (hạ chữ thường, **giữ dấu**); mục rỗng bị bỏ.
enum PhoneticDictionaryImporter {
    enum Failure: LocalizedError {
        case empty

        var errorDescription: String? {
            switch self {
            case .empty: return "File không có mục từ điển hợp lệ nào."
            }
        }
    }

    /// Nhập vào từ điển NghiTTS. `fileWords` là bảng vừa đọc từ file (chưa chuẩn hoá khoá).
    static func importNghiTTS(_ fileWords: [String: String], mode: DataImportMode) async throws -> KeyedImportSummary {
        var incoming: [String: String] = [:]
        for (rawKey, rawValue) in fileWords {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            incoming[key] = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !incoming.isEmpty else { throw Failure.empty }

        let current = await TextPreprocessor.shared.getWordMap()
        let merged = KeyedImportMerger.merge(existing: current, imported: incoming, mode: mode)
        // Ghi cả bảng + xoá cache phiên âm cùng lượt (đường cũ ghi plist rồi `loadResources()` không xoá cache).
        try await TextPreprocessor.shared.replaceAllWords(merged.values)
        return merged.summary
    }

    /// Nhập vào từ điển VieNeu-TTS. `fileWords` là bảng vừa đọc từ file (chưa chuẩn hoá khoá).
    static func importVieNeu(_ fileWords: [String: String], mode: DataImportMode) async throws -> KeyedImportSummary {
        var incoming: [String: String] = [:]
        for (rawKey, rawValue) in fileWords {
            let key = VieNeuJapaneseDictionary.normalizedKey(rawKey)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            incoming[key] = value
        }
        guard !incoming.isEmpty else { throw Failure.empty }

        let current = await VieNeuJapaneseDictionary.shared.all()
        let merged = KeyedImportMerger.merge(existing: current, imported: incoming, mode: mode)
        try await VieNeuJapaneseDictionary.shared.replaceAll(merged.values)
        return merged.summary
    }

    /// Nhập vào từ điển vtts. `fileWords` là bảng vừa đọc từ file (chưa chuẩn hoá khoá).
    static func importVtts(_ fileWords: [String: String], mode: DataImportMode) async throws -> KeyedImportSummary {
        var incoming: [String: String] = [:]
        for (rawKey, rawValue) in fileWords {
            let key = VttsPhoneticDictionary.normalizedKey(rawKey)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            incoming[key] = value
        }
        guard !incoming.isEmpty else { throw Failure.empty }

        let current = await VttsPhoneticDictionary.shared.all()
        let merged = KeyedImportMerger.merge(existing: current, imported: incoming, mode: mode)
        try await VttsPhoneticDictionary.shared.replaceAll(merged.values)
        return merged.summary
    }
}
