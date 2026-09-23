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

    /// Lưu hàng loạt danh sách mục trích xuất vào từ điển riêng của truyện (Name riêng hoặc VP riêng).
    public func saveExtractedEntries(
        _ names: [AIExtractedName],
        bookId: String,
        isName: Bool,
        isMerge: Bool
    ) async -> Int {
        let validItems = names.filter { $0.isSelected }
            .map { (
                orig: $0.original.trimmingCharacters(in: .whitespacesAndNewlines),
                mean: $0.suggestedMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
            )}
            .filter { !$0.orig.isEmpty && !$0.mean.isEmpty }

        guard !validItems.isEmpty else { return 0 }

        let newRecords = validItems.map { DictionaryTextRecord(key: $0.orig, value: $0.mean) }

        do {
            try await TranslationDictionaryWriter.shared.mutate(isName: isName, bookId: bookId) { existing in
                existing = DictionaryTextFileStore.mergedRecords(imported: newRecords, existing: existing, isMerge: isMerge)
            }
            return validItems.count
        } catch {
            AppLogger.shared.log("Lỗi lưu từ điển AI vào sách \(bookId): \(error.localizedDescription)")
            return 0
        }
    }

    /// Lưu hàng loạt danh sách tên riêng trích xuất vào từ điển truyện (mặc định gộp).
    public func saveExtractedNames(_ names: [AIExtractedName], bookId: String) async -> Int {
        await saveExtractedEntries(names, bookId: bookId, isName: true, isMerge: true)
    }
}
