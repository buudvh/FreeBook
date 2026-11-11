import Foundation

/// Dịch các khối chữ của một ảnh truyện tranh (dịch ảnh, 1.3.826) — ngoài main.
///
/// - Bộ dịch QT: dịch **từng khối** (một bong bóng = một chuỗi đưa vào dịch) qua `ChineseTextPipeline.content` (phồn → giản
///   rồi VietPhrase), nên `<START>` / `<END>` của rule dịch nhanh vẫn là đầu / cuối câu thoại; name, rule riêng của truyện áp
///   như nội dung truyện chữ (`dictionaryBookId` = truyện).
/// - Bộ dịch là **tiện ích dịch** (`extensionRequest` khác `nil`): mọi khối của ảnh đi **một** lượt
///   `ChineseTextExtensionTranslator.translateWithFallback(kind: .content)` (runner gom lô theo `max_line` / `max_length`,
///   cache RAM theo dòng ⇒ trình xem phóng to dịch lại cùng ảnh không gọi tiện ích lần hai); khối lỗi lùi QT, runner ghi
///   log ❌. Khối là một dòng (`ComicTextBlockGrouper` ghép dòng không chèn `\n`) nên tiện ích nhận nguyên câu thoại.
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
    static func translate(
        _ blocks: [ComicTextBlock],
        bookId: String,
        convertsTraditional: Bool,
        extensionRequest: ChineseTextExtensionTranslator.Request?
    ) async -> [Item]? {
        let options = ChineseTextPipeline.Options(
            converts: convertsTraditional, translates: true, dictionaryBookId: bookId.isEmpty ? nil : bookId
        )
        let worker = Task.detached(priority: .userInitiated) { () -> [Item]? in
            let indexed = blocks.enumerated().filter { TranslateUtils.containsChinese($0.element.text) }
            guard !indexed.isEmpty else { return [] }
            let texts: [String]
            if let extensionRequest {
                // Chỉ ném `CancellationError` ⇒ `nil` = huỷ.
                guard let result = try? await ChineseTextExtensionTranslator.translateWithFallback(
                    indexed.map { $0.element.text }, kind: .content, request: extensionRequest
                ) else { return nil }
                texts = result.texts
            } else {
                var output: [String] = []
                output.reserveCapacity(indexed.count)
                for entry in indexed {
                    if Task.isCancelled { return nil }
                    output.append(ChineseTextPipeline.content(entry.element.text, options))
                }
                texts = output
            }
            var items: [Item] = []
            items.reserveCapacity(indexed.count)
            for (entry, translated) in zip(indexed, texts) {
                let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                items.append(Item(id: entry.offset, block: entry.element, translated: trimmed))
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
