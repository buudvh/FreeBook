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
    /// Link "Mở link lỗi" của `errorMessage` (lỗi trang 1) — gán/xoá cùng chỗ với chữ lỗi; `nil` ⇒ màn ẩn nút.
    @Published private(set) var errorLink: SourceErrorLink?
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

    /// URL mục có chỗ cắm số trang: `{0}` của tiện ích JS, hoặc `{{page}}` / `{{page-1}}` / `{{(page-1)*20}}` của nguồn
    /// Legado (biểu thức `{{…}}` có nhắc tới `page`).
    nonisolated static func hasPagePlaceholder(_ input: String) -> Bool {
        input.contains("{0}") || input.range(of: #"\{\{[^}]*page"#, options: .regularExpression) != nil
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
            errorLink = nil
            retryCount = 0
        } else {
            isLoadingMore = true
        }

        do {
            // Danh sách đang hiện cho người dùng ⇒ nguồn Legado được mở trình duyệt / hỏi mã xác minh khi trang bắt xác minh.
            let (path, download, script, itemInput, config) = (localPath, downloadUrl, scriptFileName, input, configJson)
            let pageUrl = page == 1 ? nil : nextPageUrl
            let (results, nextPage) = try await SourceRuntime.userInitiated {
                try await SourceRuntime.shared.executeCustomScript(
                    localPath: path,
                    downloadUrl: download,
                    scriptFileName: script,
                    input: itemInput,
                    page: page,
                    pageUrl: pageUrl,
                    configJson: config
                )
            }

            let unique = filterAndDeduplicate(results)
            var addedCount = unique.count
            if page == 1 {
                novels = unique
            } else {
                // Dựng lại tập khoá **mỗi trang**, không giữ thành biến state: `reload()` gán thẳng
                // `novels = unique`, một `Set` sống qua lần đó sẽ nuốt im lặng mọi kết quả trùng khoá cũ.
                // O(tổng mục) mỗi trang thay cho O(mục mới × tổng mục) của `contains(where:)`.
                let existingKeys = Set(novels.map { normalizeLink($0.link) })
                let newUnique = unique.filter { !existingKeys.contains(normalizeLink($0.link)) }
                novels.append(contentsOf: newUnique)
                addedCount = newUnique.count
            }

            nextPageUrl = nextPage
            currentPage = page
            if scriptFileName == SourceRuntime.legadoExploreScriptName {
                // Mục khám phá Legado: chỉ tin `nextPage` của runtime (đã xét chỗ cắm trang), và dừng khi trang không thêm
                // mục mới — trang web bỏ qua số trang sẽ trả lại đúng trang cũ, không được tải mãi.
                canLoadMore = nextPage != nil && addedCount > 0
            } else {
                canLoadMore = results.count >= 10 && (nextPage != nil || Self.hasPagePlaceholder(input))
            }
            isLoading = false
            isLoadingMore = false
            retryCount = 0
        } catch is CancellationError {
            // Lượt tải bị huỷ (rời màn, đổi nguồn) không phải lỗi: không ghi `❌`, không hiện thông báo, không tự thử lại.
            isLoading = false
            isLoadingMore = false
        } catch {
            AppLogger.shared.log("❌ [PaginatedNovelLoader] load page \(page) error: \(error.localizedDescription)")
            if page == 1 {
                errorMessage = error.localizedDescription
                // URL mục (`input`) có thể là mẫu `{0}` / từ khoá trần ⇒ `SourceErrorLink` tự loại, dùng `source` nguồn.
                let sourceUrl = ExtensionHostResolver.sourceUrl(localPath: localPath)
                errorLink = SourceErrorLink.resolve(from: error, fallbacks: [input, sourceUrl], host: sourceUrl)
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
