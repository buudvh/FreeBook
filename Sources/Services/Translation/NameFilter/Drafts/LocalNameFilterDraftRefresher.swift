import Foundation

/// **Gói tạm tự cập nhật** theo danh sách đuôi + "Không phải name" (plan 2026-11-27-nghia-ten-tay-huyen mục 6, anh Bửu
/// duyệt): mỗi lần trang đầu "Lọc name local" hiện ra (mở sheet, quay lại từ màn danh sách, bấm ‹ ở màn duyệt) sheet gọi
/// `refresh` ngoài main cho các gói của truyện đang mở — gói của truyện khác cập nhật khi mở sheet ở truyện đó.
///
/// Với từng gói:
/// - bỏ name nằm trong "Không phải name" (khớp nguyên cụm như bộ lọc). Xoá cụm khỏi danh sách thì name đã bỏ **không**
///   quay lại. Gói hết name ⇒ xoá gói.
/// - name ghép lại được (`LocalNameFilterMeaningComposer.canRecompose` — không phải người / họ tộc) mà nghĩa đang có **bằng**
///   nghĩa máy ghép đã nhớ (`autoMeanings`) ⇒ ghép lại bằng đúng bộ ghép nghĩa của bộ lọc với danh sách đuôi hiện tại +
///   công tắc "Ưu tiên tên Latin" của truyện; cập nhật nghĩa, `autoMeanings`, cờ `isGuessedMeaning`. Nghĩa đã tự sửa (khác
///   nghĩa máy) ⇒ giữ nguyên. Gói cũ chưa có `autoMeanings` ⇒ không ghép lại.
/// - Bật Latin mà không nạp được mô hình ⇒ lần này không ghép lại (tránh ghi đè nghĩa Latin bằng nghĩa Hán-Việt).
///
/// Đọc – sửa – ghi trong một lần giữ khoá của store (`LocalNameFilterDraftStore.update`); không đổi gì ⇒ không ghi.
/// `savedAt` giữ nguyên (thứ tự gói không đổi).
enum LocalNameFilterDraftRefresher {
    /// Các danh sách / công tắc chụp trên main lúc trang đầu hiện ra.
    struct Inputs: Sendable {
        let bookId: String
        let blockedTerms: Set<String>
        let suffixes: [LocalNameFilter.Suffix]
        let prefersLatinNames: Bool
    }

    /// Gói sau cập nhật (ghi gần nhất trước). Gọi ngoài main.
    static func refresh(_ inputs: Inputs) async -> [LocalNameFilterDraft] {
        let drafts = LocalNameFilterDraftStore.load(bookId: inputs.bookId)
        guard !drafts.isEmpty else { return [] }
        let composer = await makeComposer(for: drafts, inputs: inputs)
        if Task.isCancelled { return drafts }
        var removed = 0
        var recomposed = 0
        let result = LocalNameFilterDraftStore.update(bookId: inputs.bookId) { current in
            var changed = false
            var updated: [LocalNameFilterDraft] = []
            for draft in current {
                var draft = draft
                let before = draft
                let kept = draft.names.filter {
                    !inputs.blockedTerms.contains($0.original.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                removed += draft.names.count - kept.count
                draft.names = kept
                if let composer {
                    recomposed += recompose(&draft, with: composer)
                }
                if draft != before { changed = true }
                if !draft.names.isEmpty { updated.append(draft) }
            }
            return changed ? updated : nil
        }
        if removed > 0 || recomposed > 0 {
            AppLogger.shared.log("🔎 [LọcName] Cập nhật gói tạm: bỏ \(removed) name thuộc \"Không phải name\", "
                + "ghép lại \(recomposed) nghĩa theo danh sách đuôi")
        }
        return result
    }

    /// Bộ ghép nghĩa khi có gói cần ghép lại; `nil` = không ghép lại lần này (gói cũ, VietPhrase chưa nạp, thiếu mô hình
    /// Latin).
    private static func makeComposer(
        for drafts: [LocalNameFilterDraft],
        inputs: Inputs
    ) async -> LocalNameFilterMeaningComposer? {
        let needsMeaning = drafts.contains { draft in
            guard let auto = draft.autoMeanings else { return false }
            return auto.values.contains { LocalNameFilterMeaningComposer.canRecompose($0.kind) }
        }
        guard needsMeaning else { return nil }
        var latinModel: LocalNameFilterLatinModel?
        if inputs.prefersLatinNames {
            do {
                latinModel = try await LocalNameFilterLatinModelGate.shared.model()
            } catch {
                if !(error is CancellationError) {
                    AppLogger.shared.log("❌ [LọcName] Gói tạm không ghép lại nghĩa: thiếu mô hình đoán tên Latin — "
                        + error.localizedDescription)
                }
                return nil
            }
        }
        return LocalNameFilterMeaningComposer(bookId: inputs.bookId, suffixes: inputs.suffixes, latinModel: latinModel)
    }

    /// Ghép lại nghĩa các name còn do máy ghép trong một gói. Trả số name đổi nghĩa / cờ đoán.
    private static func recompose(_ draft: inout LocalNameFilterDraft, with composer: LocalNameFilterMeaningComposer) -> Int {
        guard var autoMeanings = draft.autoMeanings else { return 0 }
        var count = 0
        for index in draft.names.indices {
            let key = draft.names[index].original
            guard let auto = autoMeanings[key], draft.names[index].suggestedMeaning == auto.meaning,
                  let rebuilt = composer.meaning(term: key, kind: auto.kind) else { continue }
            guard rebuilt.meaning != auto.meaning || rebuilt.isGuessed != draft.names[index].isGuessedMeaning else {
                continue
            }
            draft.names[index].suggestedMeaning = rebuilt.meaning
            draft.names[index].isGuessedMeaning = rebuilt.isGuessed
            autoMeanings[key] = LocalNameFilterDraft.AutoMeaning(meaning: rebuilt.meaning, kind: auto.kind)
            count += 1
        }
        draft.autoMeanings = autoMeanings
        return count
    }
}
