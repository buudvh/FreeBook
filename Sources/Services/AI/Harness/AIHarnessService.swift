import Foundation

/// Dịch vụ điều phối AI Agent Harness: xử lý câu hỏi, tool calls và chế độ Ask/Plan/Bypass.
public final class AIHarnessService: Sendable {
    public static let shared = AIHarnessService()

    private init() {}

    /// Thực thi một hành động thao tác dữ liệu đã được phê duyệt.
    public func executeAction(_ action: AIHarnessAction, bookId: String) async throws -> AIHarnessAction {
        var updated = action
        switch action.type {
        case .addCustomName:
            let original = action.payload["original"] ?? ""
            let meaning = action.payload["meaning"] ?? ""
            guard !original.isEmpty, !meaning.isEmpty else {
                throw NSError(domain: "AIHarness", code: 400, userInfo: [NSLocalizedDescriptionKey: "Thiếu dữ liệu tên riêng"])
            }
            try await TranslationManager.shared.saveCustomEntry(word: original, meaning: meaning, isName: true, bookId: bookId)
            updated.status = .executed

        case .addVietPhraseEntry:
            let original = action.payload["original"] ?? ""
            let meaning = action.payload["meaning"] ?? ""
            guard !original.isEmpty, !meaning.isEmpty else {
                throw NSError(domain: "AIHarness", code: 400, userInfo: [NSLocalizedDescriptionKey: "Thiếu dữ liệu VietPhrase"])
            }
            try await TranslationManager.shared.saveCustomEntry(word: original, meaning: meaning, isName: false, bookId: bookId)
            updated.status = .executed

        case .addJunkFilter:
            let pattern = action.payload["pattern"] ?? ""
            guard !pattern.isEmpty else {
                throw NSError(domain: "AIHarness", code: 400, userInfo: [NSLocalizedDescriptionKey: "Mẫu lọc rác không được để trống"])
            }
            await MainActor.run {
                JunkFilterManager.shared.addRule(pattern: pattern)
            }
            updated.status = .executed

        case .deleteCustomEntry:
            let original = action.payload["original"] ?? ""
            let isName = (action.payload["isName"] ?? "true") == "true"
            if !original.isEmpty {
                try await TranslationManager.shared.deleteCustomEntry(word: original, isName: isName, bookId: bookId)
            }
            updated.status = .executed
        }

        await MainActor.run {
            TranslationManager.shared.notifyDictionariesDidUpdate()
        }
        return updated
    }

    /// Kết quả `saveExtractedEntries` — số đếm cho toast theo đúng chế độ lưu.
    public struct ExtractedEntriesSaveResult: Sendable {
        /// Số mục đã ghi vào từ điển: "Thay thế toàn bộ" / "Gộp" = mọi mục hợp lệ; "Chỉ thêm key mới" = mục chưa có.
        public let saved: Int
        /// "Chỉ thêm key mới": số mục đã có trong từ điển đích, giữ nguyên nghĩa cũ (không ghi). Chế độ khác: 0.
        public let keptExisting: Int
    }

    /// Lưu hàng loạt danh sách mục trích xuất vào từ điển riêng của truyện (Name riêng hoặc VP riêng) theo `DataImportMode`
    /// (plan 2026-11-27-phan-loai-name L16, cùng luật với nhập file — `TranslationDictionaryWriter.importRecords`):
    /// - `.replaceAll`: từ điển riêng chỉ còn các mục đang chọn.
    /// - `.overwriteExisting` ("Gộp"): mục đã có lấy nghĩa mới, mục chưa có thêm vào (lên đầu file).
    /// - `.keepExisting` ("Chỉ thêm key mới"): chỉ thêm mục chưa có; mục đã có giữ nghĩa cũ.
    ///
    /// `nil` = không có mục hợp lệ (khoá / nghĩa rỗng) hoặc ghi lỗi (log ❌). `saved == 0` **không** phải lỗi: "Chỉ thêm
    /// key mới" mà mọi mục đã có.
    public func saveExtractedEntries(
        _ names: [AIExtractedName],
        bookId: String,
        isName: Bool,
        mode: DataImportMode
    ) async -> ExtractedEntriesSaveResult? {
        // Nghĩa chuẩn hoá trước (như `persist`) để "đã có" so đúng nghĩa đã lưu; khoá lặp chỉ giữ mục đầu (như `persist`).
        var seenKeys = Set<String>()
        let newRecords = names.filter { $0.isSelected }
            .map { DictionaryTextRecord(
                key: $0.original.trimmingCharacters(in: .whitespacesAndNewlines),
                value: DictionaryTextFileStore.normalizeMeaning($0.suggestedMeaning)
            )}
            .filter { !$0.key.isEmpty && !$0.value.isEmpty && seenKeys.insert($0.key).inserted }

        guard !newRecords.isEmpty else { return nil }

        do {
            let counts = try await TranslationDictionaryWriter.shared.importRecords(
                newRecords, isName: isName, bookId: bookId, mode: mode
            )
            guard mode == .keepExisting else {
                return ExtractedEntriesSaveResult(saved: newRecords.count, keptExisting: 0)
            }
            return ExtractedEntriesSaveResult(saved: counts.added, keptExisting: newRecords.count - counts.added)
        } catch {
            AppLogger.shared.log("❌ Lỗi lưu từ điển AI vào sách \(bookId): \(error.localizedDescription)")
            return nil
        }
    }

    /// Lưu hàng loạt danh sách tên riêng trích xuất vào từ điển truyện (mặc định gộp).
    public func saveExtractedNames(_ names: [AIExtractedName], bookId: String) async -> Int {
        await saveExtractedEntries(names, bookId: bookId, isName: true, mode: .overwriteExisting)?.saved ?? 0
    }
}
