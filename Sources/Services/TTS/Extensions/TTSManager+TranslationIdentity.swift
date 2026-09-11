import Foundation

extension TTSManager {
    internal func makeNextChapterKey(for chapter: TTSChapterInfo) -> TTSPreparedNextChapterKey {
        let key = "showChapterTitle_\(playingBookId)"
        let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true
        let extFingerprint: String?
        if tool == "system" || tool == "nghitts" || tool == "google" {
            extFingerprint = nil
        } else {
            extFingerprint = ExtensionManager.shared.getTTSRuntimeFingerprint(
                localPath: extensionLocalPath, configJson: extensionConfigJson)
        }
        return TTSPreparedNextChapterKey(
            bookId: playingBookId, chapterIndex: chapter.index, chapterUrl: chapter.url,
            chapterHost: chapter.host, chapterTitle: chapter.title,
            tool: tool, selectedVoice: selectedVoice, googlePitch: tool == "google" ? pitch : nil,
            chunkLength: chunkLength, includeChapterTitle: showTitle,
            removeDuplicatedTitle: readRemoveDuplicatedTitle(for: playingBookId),
            isTranslationEnabled: sessionTranslationEnabled,
            shouldConvertTraditionalToSimplified: sessionShouldConvertTraditionalToSimplified,
            translationToken: TranslateUtils.translationGenerationToken(for: playingBookId),
            extensionLocalPath: extensionLocalPath, extensionConfigJson: extensionConfigJson,
            extensionFingerprint: extFingerprint)
    }
}
