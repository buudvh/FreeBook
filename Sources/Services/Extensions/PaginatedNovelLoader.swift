import Foundation
import Combine

/// Nguồn dữ liệu dùng chung cho danh sách truyện có phân trang cuộn (load more),
/// sử dụng bởi `CategoryNovelsListView` (genres) và `DiscoveryCategoryTabView` (discovery).
/// Gói gọn việc gọi `executeCustomScript`, lọc/dedupe, state và auto-retry load-more.
@MainActor
final class PaginatedNovelLoader: ObservableObject {
    @Published private(set) var novels: [ExtensionItemResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var canLoadMore = false

    private let localPath: String
    private let downloadUrl: String
    private let scriptFileName: String
    private let input: String
    private let configJson: String

    private var currentPage = 1
    private var nextPageUrl: String?
    private var retryCount = 0

    init(
        localPath: String,
        downloadUrl: String = "",
        scriptFileName: String,
        input: String,
        configJson: String = "{}"
    ) {
        self.localPath = localPath
        self.downloadUrl = downloadUrl
        self.scriptFileName = scriptFileName
        self.input = input
        self.configJson = configJson
    }

    func loadInitial() async {
        await load(page: 1)
    }

    func loadMore() async {
        guard !isLoadingMore, !isLoading else { return }
        await load(page: currentPage + 1)
    }

    func reload() async {
        await load(page: 1)
    }

    private func load(page: Int) async {
        if page == 1 {
            isLoading = true
            errorMessage = ""
            retryCount = 0
        } else {
            isLoadingMore = true
        }

        do {
            let (results, nextPage) = try await ExtensionManager.shared.executeCustomScript(
                localPath: localPath,
                downloadUrl: downloadUrl,
                scriptFileName: scriptFileName,
                input: input,
                page: page,
                pageUrl: page == 1 ? nil : nextPageUrl,
                configJson: configJson
            )

            let unique = filterAndDeduplicate(results)
            if page == 1 {
                novels = unique
            } else {
                let newUnique = unique.filter { item in
                    !novels.contains(where: { normalizeLink($0.link) == normalizeLink(item.link) })
                }
                novels.append(contentsOf: newUnique)
            }

            nextPageUrl = nextPage
            currentPage = page
            canLoadMore = results.count >= 10 && (nextPage != nil || input.contains("{0}"))
            isLoading = false
            isLoadingMore = false
            retryCount = 0
        } catch {
            AppLogger.shared.log("❌ [PaginatedNovelLoader] load page \(page) error: \(error.localizedDescription)")
            if page == 1 {
                errorMessage = error.localizedDescription
                isLoading = false
                canLoadMore = false
            } else {
                isLoadingMore = false
                if retryCount < 3 {
                    retryCount += 1
                    AppLogger.shared.log("🔄 Tự động tải lại trang \(page) (Lần thử \(retryCount))...")
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await load(page: page)
                    }
                }
            }
        }
    }
}
