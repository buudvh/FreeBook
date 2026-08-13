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
                    let existingURLs: Set<String>
                    if !ChapterStoreConfiguration.enableSwiftDataTOCWrite {
                        let storeChaps = (try? await ChapterStore.shared.fetchOrderedTOC(bookId: book.bookId)) ?? []
                        existingURLs = Set(storeChaps.map(\.url))
                    } else {
                        existingURLs = Set(book.chapters.map(\.url))
                    }

                    let additionSnapshots = allChapters.enumerated().compactMap { index, item -> ChapterMetadataSnapshot? in
                        guard !existingURLs.contains(item.url) else { return nil }
                        return ChapterMetadataSnapshot(
                            title: item.name,
                            url: item.url,
                            index: index,
                            host: item.host
                        )
                    }

                    if additionSnapshots.isEmpty {
                        let totalCount = (try? await ChapterStore.shared.fetchCountAndChecksum(bookId: book.bookId))?.count ?? existingURLs.count
                        store.updateChapters(totalCount: totalCount, onlineChapters: [])
                        ToastManager.shared.show(message: "Mục lục đã mới nhất", type: .success)
                        onLocalTOCRefreshed?(totalCount)
                    } else {
                        let saveResult = try await ChapterContentRepository.shared.saveChapterList(
                            bookId: book.bookId,
                            createSnapshot: nil,
                            chapters: additionSnapshots,
                            mode: .upsertPage
                        )
                        let totalCount = saveResult.totalChapters
                        store.updateChapters(totalCount: totalCount, onlineChapters: [])
                        ToastManager.shared.show(message: "Đã thêm \(additionSnapshots.count) chương mới", type: .success)
                        onLocalTOCRefreshed?(totalCount)
                    }
                } else {
                    let oldCount = onlineChapters.count
                    onlineChapters = allChapters
                    store.updateChapters(totalCount: allChapters.count, onlineChapters: allChapters)
                    let added = max(0, allChapters.count - oldCount)
                    ToastManager.shared.show(message: added == 0 ? "Mục lục đã mới nhất" : "Đã thêm \(added) chương mới", type: .success)
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
