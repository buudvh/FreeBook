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

    /// Lưu hàng loạt danh sách tên riêng trích xuất vào từ điển truyện.
    public func saveExtractedNames(_ names: [AIExtractedName], bookId: String) async -> Int {
        var savedCount = 0
        for item in names where item.isSelected {
            let orig = item.original.trimmingCharacters(in: .whitespacesAndNewlines)
            let mean = item.suggestedMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !orig.isEmpty, !mean.isEmpty else { continue }
            do {
                try await TranslationManager.shared.saveCustomEntry(word: orig, meaning: mean, isName: true, bookId: bookId)
                savedCount += 1
            } catch {
                AppLogger.shared.log("Không thể lưu tên riêng \(orig): \(error.localizedDescription)")
            }
        }
        if savedCount > 0 {
            await MainActor.run {
                TranslationManager.shared.notifyDictionariesDidUpdate()
            }
        }
        return savedCount
    }
}
