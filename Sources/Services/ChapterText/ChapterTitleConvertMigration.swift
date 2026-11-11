import Foundation
import SwiftData

/// Lượt **một lần** sau khi lên 1.3.845: trước bản này `title_trans` luôn được dịch **không** chuyển phồn → giản (và mọi
/// danh sách bỏ qua nó khi truyện bật phồn → giản). Luật mới dùng `title_trans` cả khi bật ⇒ truyện đang bật phồn → giản
/// phải dịch lại tên chương cho đúng (`ChapterTitleRetranslator`), kẻo hiện bản không chuyển.
///
/// Chạy nền từ `MainTabView`: hoãn 20 s (không tranh CPU lúc mở app), chờ từ điển nạp xong (tối đa ~2 phút, chưa xong thì
/// để lần mở sau), lần lượt từng truyện. Xong mới ghi cờ ⇒ app tắt giữa chừng thì lần mở sau chạy lại (dịch lại thừa vô hại).
/// Đọc `Book` bằng `ModelContext` riêng, không ghi SwiftData.
enum ChapterTitleConvertMigration {
    static let doneKey = "chapterTitleTransConvertMigrationV1"

    static func runIfNeeded(container: ModelContainer) async {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        try? await Task.sleep(nanoseconds: 20_000_000_000)
        for _ in 0..<24 {
            if Task.isCancelled { return }
            if await MainActor.run(body: { TranslationManager.shared.isVietPhraseLoaded }) { break }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        guard await MainActor.run(body: { TranslationManager.shared.isVietPhraseLoaded }), !Task.isCancelled else { return }

        let context = ModelContext(container)
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let store = TranslationConfigStore.shared
        let targets = books
            .map { ChapterTitleRetranslator.Target(bookId: $0.bookId, packageId: $0.extensionPackageId) }
            .filter { store.convertsTraditionalToSimplified(bookId: $0.bookId, packageId: $0.packageId) }
        if !targets.isEmpty {
            AppLogger.shared.log("📚 [ChapterTitle] Dịch lại tên chương một lần cho \(targets.count) truyện đang bật phồn→giản (luật 1.3.845)")
            await ChapterTitleRetranslator.retranslate(targets)
        }
        guard !Task.isCancelled else { return }
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}
