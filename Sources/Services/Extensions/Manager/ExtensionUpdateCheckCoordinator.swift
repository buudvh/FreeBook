import Foundation
import Observation

/// Kiểm tra cập nhật tiện ích + thêm kho — chủ **duy nhất** của mọi lượt tải registry kho (1.3.673).
///
/// "Kiểm tra cập nhật" = tải lại registry của từng kho (1 request/kho) rồi lưu cache qua
/// `ExtensionTransactionCoordinator.saveRegistry`; `ExtensionLibraryRepository` tính lại `remoteVersion` nên `hasUpdate`
/// và banner "Cập nhật tất cả" tự đổi theo. Chỉ kiểm tra, **không** tự cài bản mới.
///
/// - Tự chạy mỗi lần vào "Tất cả tiện ích" (`checkOnEntry`), giãn cách `autoCheckInterval` sau một lượt tải được ít
///   nhất một kho. Mốc giữ trong RAM: mở lại app là kiểm tra ngay lần đầu vào. Lượt hỏng hết (mất mạng) không tính ⇒
///   lần vào sau tự thử lại. Thay cửa 6 tiếng của `RepositoryRefreshPolicy` (1.3.330–1.3.672).
/// - Nút ↻ / "Thử lại" (`checkNow`) bỏ qua giãn cách.
/// - `isBusy` chặn chạy trùng giữa kiểm tra, thêm kho và xoá kho (trang Danh sách kho đọc cùng cờ). Trước đây thêm kho
///   trong lúc làm mới hạ cờ chung `isRefreshingAll` giữa chừng ⇒ mở lại nút xoá kho, cho lượt làm mới thứ hai chạy.
/// - Các kho được tải song song, mỗi request tối đa `registryTimeout` giây.
/// - Không toast (`SERVICE_TOAST_COUPLING`): View đọc `isChecking` / `lastOutcome` để vẽ dòng trạng thái.
@MainActor
@Observable
final class ExtensionUpdateCheckCoordinator {
    static let shared = ExtensionUpdateCheckCoordinator()

    /// Kết quả một lượt kiểm tra. Kho hỏng = lỗi tải, registry rỗng (giữ cache cũ) hoặc lưu cache lỗi.
    struct Outcome: Equatable {
        let finishedAt: Date
        let repositoryCount: Int
        let failedCount: Int
    }

    static let autoCheckInterval: TimeInterval = 5 * 60
    nonisolated static let registryTimeout: TimeInterval = 20
    static let defaultRepositoryName = "Kho mặc định (buudvh)"
    static let defaultRepositoryUrl = "https://raw.githubusercontent.com/buudvh/leech_story_ext/main/plugin.json"

    private(set) var isChecking = false
    private(set) var isAddingRepository = false
    /// Lượt kiểm tra gần nhất trong phiên; `nil` khi chưa chạy lượt nào.
    private(set) var lastOutcome: Outcome?

    var isBusy: Bool { isChecking || isAddingRepository }

    @ObservationIgnored private var lastSuccessfulCheckAt: Date?

    private var library: ExtensionLibraryRepository { .shared }

    private init() {}

    // MARK: - Kiểm tra cập nhật

    /// Lượt tự động khi vào "Tất cả tiện ích". Chưa tới hạn ⇒ vẫn tải riêng các kho **chưa có cache registry** (vừa
    /// migrate từ SwiftData, hoặc lưu cache lỗi lúc thêm): thiếu cache thì tab không có mục chưa cài và không biết bản
    /// cập nhật.
    func checkOnEntry(now: Date = Date()) {
        let isDue = lastSuccessfulCheckAt.map { now.timeIntervalSince($0) >= Self.autoCheckInterval } ?? true
        let repos = library.repositories
        run(isDue ? repos : repos.filter { library.registries[$0.url] == nil }, isFullPass: isDue)
    }

    /// Nút ↻ / "Thử lại": mọi kho, bỏ qua giãn cách.
    func checkNow() {
        run(library.repositories, isFullPass: true)
    }

    private func run(_ targets: [ExtensionRepositoryRecord], isFullPass: Bool) {
        guard !targets.isEmpty, !isBusy else { return }
        isChecking = true

        Task {
            let startedAt = Date()
            let fetched = await Self.fetchRegistries(targets.map(\.url))
            var failedCount = 0
            for repo in targets {
                switch fetched[repo.url] {
                case .success(let items)?:
                    // Registry rỗng: `saveRegistry` giữ cache cũ — không tính là đã cập nhật được kho.
                    guard !items.isEmpty else {
                        AppLogger.shared.log("⚠️ [RepoRefresh] Registry rỗng, giữ cache cũ của kho \(repo.name)")
                        failedCount += 1
                        continue
                    }
                    if case .failure(let err) = ExtensionTransactionCoordinator.shared.saveRegistry(url: repo.url, items: items) {
                        AppLogger.shared.log("⚠️ [RepoRefresh] Lưu registry thất bại cho kho \(repo.name): \(err.localizedDescription)")
                        failedCount += 1
                    }
                case .failure(let error)?:
                    AppLogger.shared.log("⚠️ [RepoRefresh] Fetch registry failed for repo \(repo.name): \(error.localizedDescription)")
                    failedCount += 1
                case nil:
                    failedCount += 1
                }
            }

            // Chỉ lượt đủ mọi kho mới tính giãn cách; lượt trắng (mất mạng) không được chặn lần vào kế tiếp.
            if isFullPass && failedCount < targets.count {
                lastSuccessfulCheckAt = Date()
            }
            lastOutcome = Outcome(finishedAt: Date(), repositoryCount: targets.count, failedCount: failedCount)
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(startedAt))
            AppLogger.shared.log("ℹ️ [ExtSync] Kiểm tra cập nhật: \(targets.count - failedCount)/\(targets.count) kho (1 request/kho) trong \(elapsed)s")
            isChecking = false
        }
    }

    nonisolated private static func fetchRegistries(_ urls: [String]) async -> [String: Result<[ExtensionRegistryItem], Error>] {
        await withTaskGroup(of: (String, Result<[ExtensionRegistryItem], Error>).self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let items = try await ExtensionManager.shared.fetchRegistry(from: url, timeout: Self.registryTimeout)
                        return (url, .success(items))
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }
            var results: [String: Result<[ExtensionRegistryItem], Error>] = [:]
            for await (url, result) in group {
                results[url] = result
            }
            return results
        }
    }

    // MARK: - Thêm kho

    /// Tải registry trước, được mới lưu kho + cache. Trả câu báo cho màn gọi hiện (rỗng khi URL rỗng).
    func addRepository(name: String, url: String) async -> String {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else { return "" }
        if library.repositories.contains(where: { $0.url == trimmedUrl }) {
            return "Kho tiện ích này đã được nhập trước đó!"
        }
        guard !isBusy else { return "Đang cập nhật kho, hãy thử lại sau ít giây." }

        isAddingRepository = true
        defer { isAddingRepository = false }

        let items: [ExtensionRegistryItem]
        do {
            items = try await ExtensionManager.shared.fetchRegistry(from: trimmedUrl, timeout: Self.registryTimeout)
        } catch {
            return "Lỗi khi tải kho truyện: \(error.localizedDescription)"
        }

        let repoName = name.isEmpty ? "Kho Tiện Ích Mới" : name
        let coordinator = ExtensionTransactionCoordinator.shared
        if case .failure(let error) = coordinator.addRepository(url: trimmedUrl, name: repoName) {
            return "Lỗi khi lưu kho truyện: \(error.localizedDescription)"
        }
        switch coordinator.saveRegistry(url: trimmedUrl, items: items) {
        case .success:
            return "Đã nhập thành công kho '\(repoName)' với \(items.count) nguồn truyện."
        case .failure(let error):
            return "Lỗi lưu danh mục kho '\(repoName)': \(error.localizedDescription)"
        }
    }

    func addDefaultRepository() async -> String {
        await addRepository(name: Self.defaultRepositoryName, url: Self.defaultRepositoryUrl)
    }
}
