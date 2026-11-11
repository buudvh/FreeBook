import Foundation

/// Dịch các khối chữ của một ảnh truyện tranh bằng VietPhrase (dịch ảnh, 1.3.826) — ngoài main.
///
/// - Dịch **từng khối** (một bong bóng = một chuỗi đưa vào dịch), nên `<START>` / `<END>` của rule dịch nhanh vẫn là đầu /
///   cuối câu thoại; name, rule riêng của truyện áp như nội dung truyện chữ (`TranslateUtils.translateContent` + `bookId`).
/// - Bỏ khối không có chữ Hán (số trang, chữ Latin) và khối dịch ra rỗng.
/// - Không lưu bản dịch: gọi lại mỗi lần hàng hiện hay từ điển đổi ⇒ sửa name là thấy ngay.
enum ComicPageTextTranslator {
    /// Một khối đã dịch. `id` = vị trí của khối trong mảng nhận chữ (ổn định giữa các lần dịch lại).
    struct Item: Identifiable, Hashable, Sendable {
        let id: Int
        let block: ComicTextBlock
        let translated: String
    }

    /// `nil` khi task gọi bị huỷ.
    static func translate(_ blocks: [ComicTextBlock], bookId: String, convertsTraditional: Bool) async -> [Item]? {
        let worker = Task.detached(priority: .userInitiated) { () -> [Item]? in
            var items: [Item] = []
            items.reserveCapacity(blocks.count)
            for (index, block) in blocks.enumerated() {
                if Task.isCancelled { return nil }
                guard TranslateUtils.containsChinese(block.text) else { continue }
                let translated = TranslateUtils.translateContent(
                    block.text,
                    bookId: bookId,
                    shouldConvertTraditionalToSimplified: convertsTraditional
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translated.isEmpty else { continue }
                items.append(Item(id: index, block: block, translated: translated))
            }
            return Task.isCancelled ? nil : items
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
