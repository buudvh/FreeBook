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
/// - Mở app (`checkOnLaunch`, 1.3.748): một lượt đủ mọi kho mỗi lần khởi động, tính vào giãn cách; trả các tiện ích
///   đã cài đang có bản mới để `MainTabView` hiện toast. Công tắc `launchCheckEnabledKey` (thiếu khoá = bật).
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
    /// Công tắc "Báo cập nhật khi mở app" (ngăn kéo … tab Tiện Ích). Tắt ⇒ không kiểm lúc mở app, không toast; lượt tự
    /// kiểm khi vào "Tất cả tiện ích" vẫn chạy.
    nonisolated static let launchCheckEnabledKey = "extensionUpdateLaunchCheckEnabled"

    private(set) var isChecking = false
    private(set) var isAddingRepository = false
    /// Lượt kiểm tra gần nhất trong phiên; `nil` khi chưa chạy lượt nào.
    private(set) var lastOutcome: Outcome?

    var isBusy: Bool { isChecking || isAddingRepository }

    @ObservationIgnored private var lastSuccessfulCheckAt: Date?
    /// Lượt mở app chỉ chạy một lần mỗi tiến trình, kể cả khi `MainTabView` bị dựng lại.
    @ObservationIgnored private var didCheckOnLaunch = false

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

    /// Lượt mở app (1.3.748): tải lại mọi kho như ↻ rồi trả các tiện ích **đã cài** đang có bản mới (loại Legado —
    /// nguồn Legado không có `remoteVersion`), dùng gần nhất trước. Mất mạng ⇒ vẫn trả theo cache registry cũ. Rỗng khi
    /// công tắc tắt, đã chạy trong tiến trình này, chưa có kho hoặc đang có lượt khác chạy.
    func checkOnLaunch() async -> [Extension] {
        guard !didCheckOnLaunch, Self.isLaunchCheckEnabled else { return [] }
        didCheckOnLaunch = true
        let repos = library.repositories
        guard !repos.isEmpty, !isBusy else { return [] }
        isChecking = true
        await perform(repos, isFullPass: true)
        let pending = library.installed.filter { $0.hasUpdate && !LegadoSourcePolicy.isLegado($0) }
        AppLogger.shared.log("ℹ️ [ExtSync] Mở app: \(pending.count) tiện ích có bản mới")
        return pending.sorted(by: Self.noticeOrder)
    }

    /// Thiếu khoá = bật (`UserDefaults.bool` trả `false` cho khoá chưa ghi nên không dùng được).
    nonisolated static var isLaunchCheckEnabled: Bool {
        UserDefaults.standard.object(forKey: launchCheckEnabledKey) as? Bool ?? true
    }

    /// Câu toast cho danh sách của `checkOnLaunch`: một tiện ích ⇒ kèm phiên bản; nhiều ⇒ tối đa 3 tên.
    static func availableMessage(for pending: [Extension]) -> String {
        guard pending.count > 1 else {
            guard let ext = pending.first else { return "" }
            let versions = ext.remoteVersion.map { " (v\(ext.version) → v\($0))" } ?? ""
            return "Tiện ích \(ext.name) có bản mới\(versions)"
        }
        let names = pending.prefix(3).map(\.name).joined(separator: ", ")
        return "Có bản mới cho \(pending.count) tiện ích: \(names)" + (pending.count > 3 ? "…" : "")
    }

    /// Vừa dùng trước (`lastUsedAt` giảm, chưa dùng đứng sau), rồi A-Z.
    private static func noticeOrder(_ lhs: Extension, _ rhs: Extension) -> Bool {
        switch (lhs.lastUsedAt, rhs.lastUsedAt) {
        case let (l?, r?) where l != r: return l > r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func run(_ targets: [ExtensionRepositoryRecord], isFullPass: Bool) {
        guard !targets.isEmpty, !isBusy else { return }
        isChecking = true
        Task { await perform(targets, isFullPass: isFullPass) }
    }

    /// Lõi một lượt kiểm tra. Nơi gọi bật `isChecking` **đồng bộ** trước lần `await` đầu (chặn chạy trùng); hạ ở cuối —
    /// thân hàm không có nhánh thoát sớm.
    private func perform(_ targets: [ExtensionRepositoryRecord], isFullPass: Bool) async {
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
