import Foundation

/// Dịch lại tên chương đã lưu (`title_trans` ở `ChapterStore`) của một hoặc nhiều truyện — chỗ duy nhất làm việc này
/// (1.3.845). Nút "Dịch lại tên chương" (`BookActionRunner`, mọi màn) và các lượt tự dịch lại (đổi phồn → giản ở popup dịch,
/// lượt một lần lúc mở app — `ChapterTitleConvertMigration`) đều gọi vào đây.
///
/// - Phồn → giản là **bước chuyển trước khi dịch**: tên gốc được chuyển theo cấu hình của truyện
///   (`TranslationConfigStore.convertsTraditionalToSimplified(bookId:packageId:)`) rồi mới dịch — qua
///   `ChineseTextPipeline.chapterTitle` (có bộ rule tên chương, 1.3.846). Trước 1.3.845 `title_trans` luôn là bản
///   **không** chuyển nên truyện bật phồn → giản bỏ qua nó.
/// - Xong một truyện ⇒ `chapterTitlesDidRetranslate` (`userInfo["bookId"]`) trên main — mục lục Reader và màn đọc truyện
///   tranh nạp lại. Không toast (Services không gọi `ToastManager`); caller tự báo.
/// - Không kiểm từ điển đã nạp: caller kiểm `TranslationManager.isVietPhraseLoaded` trước (từ điển chưa nạp ⇒ "bản dịch"
///   chỉ là chữ Hán, ghi đè bản lưu đang đúng).
enum ChapterTitleRetranslator {
    struct Target: Sendable, Hashable {
        let bookId: String
        let packageId: String
    }

    /// Số tên đã ghi; `0` = truyện chưa có mục lục lưu (hoặc không tên nào để dịch).
    @discardableResult
    static func retranslate(_ target: Target) async -> Int {
        let bookId = target.bookId
        guard let stored = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId), !stored.isEmpty else { return 0 }
        let converts = TranslationConfigStore.shared.convertsTraditionalToSimplified(bookId: bookId, packageId: target.packageId)
        let options = ChineseTextPipeline.Options(converts: converts, translates: true, dictionaryBookId: bookId)
        TranslateUtils.clearChapterTitleCache(for: bookId)

        struct Item: Sendable {
            let index: Int
            let url: String
            let title: String
        }
        let items = stored.map { Item(index: $0.index, url: $0.url, title: $0.title) }
        let updates: [(index: Int, url: String, titleTrans: String)] = await Task.detached(priority: .userInitiated) {
            var list: [(index: Int, url: String, titleTrans: String)] = []
            list.reserveCapacity(items.count)
            for item in items {
                if Task.isCancelled { break }
                guard !item.title.isEmpty else { continue }
                let translated = ChineseTextPipeline.chapterTitle(item.title, options)
                list.append((index: item.index, url: item.url, titleTrans: translated))
            }
            return list
        }.value

        if !updates.isEmpty {
            do {
                try await ChapterStore.shared.updateTitleTranslations(bookId: bookId, updates: updates)
            } catch {
                AppLogger.shared.log("❌ [ChapterTitle] Không ghi được tên chương đã dịch lại: \(error.localizedDescription)")
                return 0
            }
        }
        AppLogger.shared.log("📚 [ChapterTitle] Dịch lại \(updates.count) tên chương (phồn→giản: \(converts ? "bật" : "tắt"))")
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("chapterTitlesDidRetranslate"),
                object: nil,
                userInfo: ["bookId": bookId]
            )
        }
        return updates.count
    }

    /// Lần lượt từng truyện (không song song — tránh dồn việc dịch lên CPU).
    static func retranslate(_ targets: [Target]) async {
        for target in targets {
            if Task.isCancelled { return }
            await retranslate(target)
        }
    }
}
