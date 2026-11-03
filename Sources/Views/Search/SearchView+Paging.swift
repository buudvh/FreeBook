import SwiftUI

/// "Tìm trong một nguồn": trang 1 (tách khỏi `performSearch`) và tải thêm trang khi cuộn gần cuối danh sách.
///
/// Trang kế đi theo token mà nguồn trả (`SourceRuntime.searchPage`); luật dừng, lọc trùng và chống kết quả về muộn ở
/// `SearchPagingState`. Lỗi ở trang sau: tự thử lại, hết lượt thì chân danh sách hiện "Thử lại" (log `❌` một lần).
extension SearchView {
    static func singleSourceFoundMessage(count: Int, sourceName: String) -> String {
        "Tìm thấy \(count) truyện trên nguồn \(sourceName)."
    }

    /// Lượt tìm mới / xoá ô tìm: huỷ lượt tải thêm đang chạy, bỏ kết quả về muộn của lượt cũ.
    func resetSearchPaging() {
        searchPaging.reset()
    }

    /// Trang 1 của nguồn đang chọn — gọi từ `performSearch` sau khi đã `resetSearchPaging()`.
    func startSingleSourceSearch(ext: Extension, query: String) {
        searchStatusMessage = "Đang tìm trên nguồn \(ext.name)..."
        ExtensionTransactionCoordinator.shared.markUsed(packageId: ext.packageId) // chỉ tìm MỘT nguồn mới tính "đã dùng"

        searchTask = Task {
            do {
                let firstPage = try await SourceRuntime.shared.searchPage(
                    localPath: ext.localPath,
                    downloadUrl: ext.downloadUrl,
                    query: query,
                    page: 1,
                    pageToken: nil,
                    configJson: ext.configJson
                )
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    let cleanResults = filterAndDeduplicate(firstPage.results)
                    self.searchResults = cleanResults.map { ExtensionItemResultWithExt(result: $0, ext: ext) }
                    self.searchPaging.didLoadFirstPage(ext: ext, query: query, shownCount: cleanResults.count,
                                                       nextToken: firstPage.nextPage)
                    self.isSearching = false
                    self.searchStatusMessage = Self.singleSourceFoundMessage(count: cleanResults.count, sourceName: ext.name)
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.isSearching = false
                    self.searchStatusMessage = "Lỗi khi tìm kiếm: \(error.localizedDescription)"
                    self.attachStatusErrorLink(error, fallbacks: [ext.sourceUrl], host: nil, retry: .search, packageId: ext.packageId)
                }
            }
        }
    }

    /// Sentinel cuối danh sách / một trong vài mục cuối hiện ra ⇒ tải trang kế. Gọi trùng lúc đang tải thì bỏ qua.
    func loadMoreSearchResults() {
        guard !searchAllSources, !isSearching, !searchPaging.isLoadingMore, searchPaging.canLoadMore,
              searchPaging.failedMessage == nil,
              let ext = searchPaging.ext, let token = searchPaging.nextToken else { return }
        let searchId = searchPaging.searchId
        let query = searchPaging.query
        let page = searchPaging.pagesLoaded + 1
        searchPaging.isLoadingMore = true
        searchPaging.loadTask = Task { @MainActor in
            await loadSearchPage(ext: ext, query: query, page: page, token: token, searchId: searchId)
        }
    }

    /// Thử lại **trong cùng** task (huỷ / lượt mới chặn được cả lúc đang chờ thử lại).
    @MainActor
    private func loadSearchPage(ext: Extension, query: String, page: Int, token: String, searchId: Int) async {
        var retryCount = 0
        while true {
            do {
                let response = try await SourceRuntime.shared.searchPage(
                    localPath: ext.localPath,
                    downloadUrl: ext.downloadUrl,
                    query: query,
                    page: page,
                    pageToken: token,
                    configJson: ext.configJson
                )
                guard isCurrentSearchPaging(searchId) else { return }
                appendSearchPage(response.results, nextPage: response.nextPage, usedToken: token, ext: ext)
                return
            } catch {
                guard isCurrentSearchPaging(searchId) else { return }
                // Lượt tải bị huỷ không phải lỗi: không `❌`, không thử lại.
                if error is CancellationError {
                    searchPaging.isLoadingMore = false
                    return
                }
                guard retryCount < SearchPagingState.maxRetries else {
                    AppLogger.shared.log("❌ [SearchView] Tải thêm trang tìm kiếm \(page) của nguồn \(ext.name) lỗi: \(error.localizedDescription)")
                    searchPaging.fail(message: error.localizedDescription)
                    return
                }
                retryCount += 1
                AppLogger.shared.log("🔄 Tự động tải lại trang tìm kiếm \(page) (Lần thử \(retryCount))...")
                do {
                    try await Task.sleep(nanoseconds: SearchPagingState.retryDelayNanoseconds)
                } catch {
                    return // bị huỷ lúc chờ ⇒ lượt mới đã `reset()`
                }
                guard isCurrentSearchPaging(searchId) else { return }
            }
        }
    }

    /// Nút "Thử lại" ở chân danh sách: tải lại trang kế vừa lỗi.
    func retryLoadMoreSearchResults() {
        searchPaging.clearFailure()
        loadMoreSearchResults()
    }

    /// Chân danh sách của "tìm trong một nguồn" (`shownCount` = số mục đang hiện sau lọc đổi nguồn).
    func singleSourceFooterPhase(shownCount: Int, noun: String) -> LoadMoreFooter.Phase? {
        guard !isSearching, shownCount > 0 else { return nil }
        if let message = searchPaging.failedMessage { return .failed(message) }
        if searchPaging.canLoadMore { return .loading }
        return .finished("\(shownCount) \(noun)")
    }

    private func isCurrentSearchPaging(_ searchId: Int) -> Bool {
        !Task.isCancelled && searchPaging.searchId == searchId
    }

    /// Nối các link **mới** (lọc trùng với mọi kết quả đang có) và cập nhật câu "Tìm thấy…".
    private func appendSearchPage(_ results: [ExtensionItemResult], nextPage: String?, usedToken: String, ext: Extension) {
        let previousMessage = Self.singleSourceFoundMessage(count: searchResults.count, sourceName: ext.name)
        let existingKeys = Set(searchResults.map { normalizeLink($0.result.link) })
        let newResults = filterAndDeduplicate(results).filter { !existingKeys.contains(normalizeLink($0.link)) }
        searchResults.append(contentsOf: newResults.map { ExtensionItemResultWithExt(result: $0, ext: ext) })
        searchPaging.didLoadPage(usedToken: usedToken, addedCount: newResults.count, nextToken: nextPage)
        // Chỉ thay câu đếm của chính lượt này — không đè câu lỗi đổi nguồn đang hiện.
        if searchStatusMessage == previousMessage {
            searchStatusMessage = Self.singleSourceFoundMessage(count: searchResults.count, sourceName: ext.name)
        }
    }
}
