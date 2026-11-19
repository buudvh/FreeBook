import Foundation

extension CachedChapter {
    /// Bản dịch đã cache còn dùng được không: cùng generation token của từ điển/rule, cùng công tắc dịch và
    /// cùng công tắc Phồn → Giản. Gom 4 bản copy của cùng một điều kiện trong `ReaderViewModel`
    /// (`requestChapter`, `runNavigationWorker` ×2, `+Translation.updateCachedTranslatedContent`).
    /// Chỗ chỉ kiểm riêng token (`memoryCommitTask` trong `requestChapter`) cố ý **không** dùng hàm này.
    func isTranslationFresh(token: Int, enabled: Bool, convertTraditional: Bool) -> Bool {
        translationToken == token
            && isTranslationEnabled == enabled
            && shouldConvertTraditionalToSimplified == convertTraditional
    }
}
