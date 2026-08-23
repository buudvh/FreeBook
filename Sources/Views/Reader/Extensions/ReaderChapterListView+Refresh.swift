import SwiftUI

extension ReaderChapterListView {
    internal func refreshChapters() {
        guard let ext else {
            errorMessage = "Không tìm thấy tiện ích bóc tách!"
            ToastManager.shared.show(message: errorMessage, type: .error)
            return
        }
        let url = localBook?.detailUrl ?? bookDetailUrl ?? ""
        guard !url.isEmpty else {
            errorMessage = "Đường dẫn truyện không hợp lệ!"
            ToastManager.shared.show(message: errorMessage, type: .error)
            return
        }

        isUpdating = true
        errorMessage = ""
        Task {
            do {
                var allChapters: [ChapterResult] = []
                if ExtensionManager.shared.hasScript(localPath: ext.localPath, scriptKey: "page") {
                    let pages = try await ExtensionManager.shared.page(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: url,
                        host: localBook?.host,
                        configJson: ext.configJson
                    )
                    for pageURL in pages {
                        allChapters.append(contentsOf: try await ExtensionManager.shared.toc(
                            localPath: ext.localPath,
                            downloadUrl: ext.downloadUrl,
                            url: pageURL,
                            host: localBook?.host,
                            configJson: ext.configJson
                        ))
                    }
                } else {
                    allChapters = try await ExtensionManager.shared.toc(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: url,
                        host: localBook?.host,
                        configJson: ext.configJson
                    )
                }

                if let book = localBook {
                    let fullTOCSnapshots = allChapters.enumerated().map { index, item in
                        ChapterMetadataSnapshot(
                            title: item.name,
                            url: item.url,
                            index: index,
                            host: item.host
                        )
                    }

                    // Không tự diff ở đây nữa: `saveChapterList` → `ChapterTOCDiff` đã làm việc đó ngay trên
                    // dữ liệu vừa `fetchOrderedTOC` bên trong engine. Trước đây tầng này còn fetch toàn bộ mục lục
                    // lần nữa và dựng 2×N chuỗi identity chỉ để biết "có gì đổi không".
                    let readerOldIndex = currentChapterIndex
                    let readerOldRow = try? await ChapterStore.shared.fetchRange(bookId: book.bookId, startIndex: readerOldIndex, count: 1)
                    let readerOldUrl = readerOldIndex >= 0 ? (readerOldRow?.first?.url ?? "") : ""

                    let ttsIsActive = TTSManager.shared.playingBookId == book.bookId && TTSManager.shared.playingChapterIndex >= 0 && (TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget || !TTSManager.shared.playingChapterUrl.isEmpty)
                    let ttsOldIndex = ttsIsActive ? TTSManager.shared.playingChapterIndex : nil
                    let ttsOldUrl = ttsIsActive ? TTSManager.shared.playingChapterUrl : ""

                    let protectedTTS: ProtectedTTSChapter? = ttsIsActive ? ProtectedTTSChapter(bookId: book.bookId, index: ttsOldIndex!, url: ttsOldUrl) : nil

                    let saveResult = try await ChapterContentRepository.shared.saveChapterList(
                        bookId: book.bookId,
                        createSnapshot: nil,
                        chapters: fullTOCSnapshots,
                        mode: .replaceFullTOC,
                        protectedTTSChapter: protectedTTS
                    )
                    let totalCount = saveResult.totalChapters

                    // Engine không ghi hàng nào ⇒ mục lục y nguyên (giữ đúng luồng và câu thông báo cũ).
                    if saveResult.inserted == 0, saveResult.updated == 0, saveResult.deleted == 0 {
                        store.updateChapters(totalCount: totalCount, onlineChapters: [])
                        ToastManager.shared.show(message: "Mục lục đã mới nhất", type: .success)
                        let result = LocalTOCRefreshResult(
                            totalCount: totalCount,
                            readerOldIndex: readerOldIndex,
                            readerNewIndex: readerOldIndex,
                            ttsOldIndex: ttsOldIndex,
                            ttsNewIndex: ttsOldIndex,
                            isTOCUnchanged: true
                        )
                        onLocalTOCRefreshed?(result)
                        isUpdating = false
                        return
                    }

                    store.updateChapters(totalCount: totalCount, onlineChapters: [])

                    let normReaderOldUrl = readerOldUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                    let readerNewIndex = fullTOCSnapshots.firstIndex(where: { $0.url.trimmingCharacters(in: .whitespacesAndNewlines) == normReaderOldUrl }) ?? min(readerOldIndex, max(0, totalCount - 1))
                    let isReaderRemoved = !normReaderOldUrl.isEmpty && !fullTOCSnapshots.contains(where: { $0.url.trimmingCharacters(in: .whitespacesAndNewlines) == normReaderOldUrl })

                    let normTTSOldUrl = ttsOldUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ttsNewIndex = !normTTSOldUrl.isEmpty ? fullTOCSnapshots.firstIndex(where: { $0.url.trimmingCharacters(in: .whitespacesAndNewlines) == normTTSOldUrl }) : nil
                    let isTTSRemoved = !normTTSOldUrl.isEmpty && ttsNewIndex == nil

                    let result = LocalTOCRefreshResult(
                        totalCount: totalCount,
                        readerOldIndex: readerOldIndex,
                        readerNewIndex: readerNewIndex,
                        ttsOldIndex: ttsOldIndex,
                        ttsNewIndex: ttsNewIndex,
                        isTOCUnchanged: false,
                        isReaderChapterRemoved: isReaderRemoved,
                        isTTSChapterRemoved: isTTSRemoved
                    )

                    // `inserted` chính là số hàng mới engine vừa ghi ⇒ không cần đếm lại mục lục cũ để trừ.
                    let addedChapters = saveResult.inserted
                    let toastMessage = addedChapters > 0 ? "Đã thêm \(addedChapters) chương mới" : "Đã cập nhật mục lục"
                    ToastManager.shared.show(message: toastMessage, type: .success)
                    onLocalTOCRefreshed?(result)
                } else {
                    let oldCount = onlineChapters.count
                    onlineChapters = allChapters
                    store.updateChapters(totalCount: allChapters.count, onlineChapters: allChapters)
                    let added = max(0, allChapters.count - oldCount)
                    let result = LocalTOCRefreshResult(
                        totalCount: allChapters.count,
                        readerOldIndex: currentChapterIndex,
                        readerNewIndex: currentChapterIndex,
                        isTOCUnchanged: added == 0
                    )
                    ToastManager.shared.show(message: added == 0 ? "Mục lục đã mới nhất" : "Đã thêm \(added) chương mới", type: .success)
                    onLocalTOCRefreshed?(result)
                }
                isUpdating = false
            } catch {
                errorMessage = "Lỗi cập nhật: \(error.localizedDescription)"
                isUpdating = false
                ToastManager.shared.show(message: errorMessage, type: .error)
            }
        }
    }
}
