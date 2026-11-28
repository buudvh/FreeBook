import Foundation

/// Gói name tạm của màn duyệt (plan 2026-11-27 mục E2, mockup LAC khung 5): danh sách đang duyệt (trạng thái chọn, nghĩa
/// đã sửa, cờ NE / VP) được giữ thành một `LocalNameFilterDraft` khi
/// - sheet đóng lúc đang duyệt mà chưa bấm Lưu (kể cả lượt đã "Dừng") — `keepDraftOnClose`, sheet hiện toast;
/// - app vào nền lúc đang duyệt — `persistDraftForBackground` (bị tắt app thì không mất), không toast.
/// Một màn duyệt chỉ có **một** gói (`ReviewContext.draftId`): ghi lần nữa là ghi đè gói đó, không tạo gói mới. Bấm Lưu
/// ⇒ `beginSave` đánh dấu để lần đóng ngay sau đó không giữ gói; lưu xong mới xoá gói (`LocalNameFilterSheet.save`).
///
/// Ghi đồng bộ trên main: file một truyện tối đa 5 gói (vài trăm KB với truyện dài) — tránh việc mở lại sheet ngay sau khi
/// đóng mà gói chưa kịp ghi.
extension LocalNameFilterSession {
    /// Màn duyệt đang mở thuộc truyện / gói nào, kèm thông tin hiện ở hàng gói của sheet thiết lập.
    struct ReviewContext {
        let bookId: String
        let draftId: UUID
        let filteredAt: Date
        let scopeLabel: String
        let chapterCount: Int
        /// Nghĩa máy ghép của từng name (`LocalNameFilterDraft.autoMeanings`) — đi theo gói để gói tự cập nhật theo danh
        /// sách đuôi (`LocalNameFilterDraftRefresher`); thêm đuôi ở màn duyệt ghép lại thì cập nhật theo
        /// (`makeReviewSuffixContext`). `nil` = mở từ gói của bản trước.
        var autoMeanings: [String: LocalNameFilterDraft.AutoMeaning]?
        /// Dấu danh sách đuôi + công tắc Latin / nới mà `autoMeanings` ứng với (`LocalNameFilterDraft.meaningSignature`).
        var meaningSignature: String?
    }

    /// Ngữ cảnh đuôi của màn duyệt sắp mở: nghĩa máy ghép đổi (thêm đuôi từ màn Sửa từ) ⇒ ghi vào `reviewContext` để gói
    /// tạm mang bản mới.
    func makeReviewSuffixContext(
        bookId: String,
        autoMeanings: [String: LocalNameFilterDraft.AutoMeaning]?
    ) -> LocalNameFilterReviewSuffixContext {
        // Gắn với **đúng** màn duyệt đang mở: lượt ghép lại xong muộn (sau ‹ rồi mở gói khác) không được ghi vào gói khác.
        let draftId = reviewContext?.draftId
        return LocalNameFilterReviewSuffixContext(bookId: bookId, autoMeanings: autoMeanings) { [weak self] updated in
            guard let self, self.reviewContext?.draftId == draftId else { return }
            self.reviewContext?.autoMeanings = updated
            // Ghép lại theo danh sách đuôi vừa đổi ⇒ gói ứng với danh sách hiện tại.
            self.reviewContext?.meaningSignature = LocalNameFilterMeaningComposer.signature(
                suffixes: LocalNameFilterSuffixStore.shared.allSuffixes(bookId: bookId),
                prefersLatinNames: LocalNameFilterLatinPreferenceStore.shared.prefersLatin(bookId: bookId),
                prefixes: LocalNameFilterPrefixStore.shared.allPrefixes(bookId: bookId),
                loosensLatin: LocalNameFilterLatinPreferenceStore.loosensLatin(bookId: bookId)
            )
        }
    }

    /// Nghĩa máy ghép lúc lọc xong: chữ Hán ⇒ nghĩa + loại (trùng chữ ⇒ giữ hàng đầu).
    static func autoMeanings(of names: [LocalNameFilter.Name]) -> [String: LocalNameFilterDraft.AutoMeaning] {
        var result: [String: LocalNameFilterDraft.AutoMeaning] = [:]
        for name in names where result[name.term] == nil {
            // Lúc lọc mọi name theo công tắc "Nới" của truyện ⇒ chưa có ghi đè riêng.
            result[name.term] = LocalNameFilterDraft.AutoMeaning(meaning: name.meaning, kind: name.kind, loosensLatin: nil)
        }
        return result
    }

    /// Màn duyệt báo danh sách đang duyệt mỗi lần đổi (chọn / bỏ chọn, sửa, bỏ mục, cờ NE / VP tra lại).
    /// Ô tích lúc **vào** màn duyệt từ một gói tạm (anh Bửu 2026-11-28: "mỗi lần vào danh sách duyệt hãy bỏ tick và chỉ tick
    /// lại các name chưa có trong vp/name riêng chung"): tích mọi name rồi để `decorateExtractedNames` bỏ tích + gắn lại
    /// badge NE / VP cho name đã có trong Name hoặc VP (riêng truyện, Chung, gốc) — cùng luật với lúc vừa lọc xong, nên
    /// name anh đã lưu sau lần lọc đó tự bỏ tích, name chưa có tự được tích lại dù lần trước anh đã bỏ tích. Chạy ngoài
    /// main (đọc file từ điển riêng của truyện).
    static func resettingSelection(_ names: [AIExtractedName], bookId: String) async -> [AIExtractedName] {
        let ticked = names.map { item -> AIExtractedName in
            var copy = item
            copy.isSelected = true
            return copy
        }
        return await Task.detached(priority: .userInitiated) {
            AIBookDataInspector.shared.decorateExtractedNames(names: ticked, bookId: bookId)
        }.value
    }

    func updateReviewNames(_ names: [AIExtractedName]) {
        guard phase == .review else { return }
        latestReviewNames = names
    }

    /// App vào nền lúc đang duyệt mà chưa bấm Lưu ⇒ ghi gói ngay.
    func persistDraftForBackground() {
        guard !savePending, let context = reviewContext, let draft = currentDraft(), !draft.names.isEmpty else { return }
        LocalNameFilterDraftStore.upsert(draft, bookId: context.bookId)
        AppLogger.shared.log("🔎 [LọcName] App vào nền lúc đang duyệt ⇒ giữ gói tạm \(draft.names.count) name")
    }

    /// Sheet đóng: đang duyệt mà chưa bấm Lưu ⇒ ghi gói, trả số name đã giữ (sheet hiện toast). Danh sách đã bỏ hết ⇒
    /// xoá gói của màn này (nếu từng ghi), trả `nil`.
    func keepDraftOnClose() -> Int? {
        guard !savePending, let context = reviewContext, let draft = currentDraft() else { return nil }
        guard !draft.names.isEmpty else {
            LocalNameFilterDraftStore.delete(id: context.draftId, bookId: context.bookId)
            return nil
        }
        LocalNameFilterDraftStore.upsert(draft, bookId: context.bookId)
        AppLogger.shared.log("🔎 [LọcName] Đóng màn duyệt chưa lưu ⇒ giữ gói tạm \(draft.names.count) name")
        return draft.names.count
    }

    /// Bấm Lưu ở màn duyệt (gọi **trước** khi màn duyệt đóng sheet): lần đóng ngay sau đó không giữ gói. Trả truyện + gói
    /// hiện tại để nơi lưu xoá gói khi lưu xong, hoặc ghi lại gói khi lưu lỗi (danh sách không mất).
    func beginSave() -> (bookId: String, draft: LocalNameFilterDraft)? {
        savePending = true
        guard let context = reviewContext, let draft = currentDraft() else { return nil }
        return (context.bookId, draft)
    }

    /// Gói của màn duyệt đang mở, `savedAt` = bây giờ; `nil` khi không ở màn duyệt.
    private func currentDraft() -> LocalNameFilterDraft? {
        guard phase == .review, let context = reviewContext else { return nil }
        return LocalNameFilterDraft(
            id: context.draftId,
            filteredAt: context.filteredAt,
            savedAt: Date(),
            scopeLabel: context.scopeLabel,
            chapterCount: context.chapterCount,
            names: latestReviewNames,
            autoMeanings: context.autoMeanings,
            meaningSignature: context.meaningSignature
        )
    }
}
