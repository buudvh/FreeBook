import Combine
import Foundation

/// Nguồn của mục **"Thông báo"** trên nút hub nổi (`FloatingHubPresentationReader`): số thông báo chưa đọc
/// và có tác vụ nền nào đang chạy. Trước 1.3.524 lớp này là presentation reader của widget thông báo nổi
/// riêng; logic giữ nguyên, chỉ đổi tên theo chủ mới.
///
/// ## Vì sao phải có lớp đọc riêng
/// Hub là một `UIWindow` sống suốt phiên. Nếu cửa sổ đó observe thẳng `NotificationInboxManager`,
/// `NewChapterInboxManager`, `BackupCoordinator`, `ModelDownloadCenter`, `DownloadManager` và
/// `BookImportProgressCenter` thì **mỗi nhịp tiến độ** của một lượt khôi phục, tải model hay tải truyện đều
/// kéo cả cây view của hub vẽ lại — trong khi thứ duy nhất hub quan tâm chỉ đổi vài lần mỗi lượt. Lớp này
/// gộp sáu nguồn thành **một** snapshot và chỉ phát khi giá trị **thật sự** đổi (cùng khuôn
/// `VisibleBrowserPresentationReader`, `TTSPlayStateReader`).
///
/// ## Quy tắc có mục (người dùng chốt 2026-10-07)
/// Có mục khi **có thông báo chưa đọc** *hoặc* **đang có tác vụ chạy** (sao lưu / khôi phục / tải model /
/// tải, xuất, nhập truyện — ba việc sau thêm ở 1.3.557).
/// Vế thứ hai có lý do rõ ràng: màn Thông báo là **nơi duy nhất** xem được thanh tiến độ, nên nếu mục chỉ
/// có theo số chưa đọc thì một lượt khôi phục dài chạy nền sẽ không có lối vào nào.
@MainActor
final class NotificationInboxPresenceReader: ObservableObject {
    struct Snapshot: Equatable {
        var unreadCount = 0
        var hasRunningTask = false

        var shouldShowWidget: Bool { unreadCount > 0 || hasRunningTask }
    }

    @Published private(set) var snapshot = Snapshot()

    private var cancellables = Set<AnyCancellable>()

    init() {
        snapshot = Self.makeSnapshot()

        let inbox = NotificationInboxManager.shared
        let chapters = NewChapterInboxManager.shared
        let backup = BackupCoordinator.shared
        let downloads = ModelDownloadCenter.shared

        inbox.$records
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        chapters.$records
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        backup.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        downloads.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // `$tasks` phát ~10 lần/giây mỗi tác vụ đang chạy: rút về đúng một bit "còn tác vụ chưa xong" rồi
        // `removeDuplicates` trước khi sink, để `refresh()` chỉ chạy lúc chuyển trạng thái. Vẫn `receive(on:)`
        // vì `@Published` phát ở willSet — `makeSnapshot()` đọc đồng bộ thì còn thấy giá trị cũ.
        DownloadManager.shared.$tasks
            .map { tasks in tasks.contains(where: \.isActive) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        BookImportProgressCenter.shared.$entry
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        let updated = Self.makeSnapshot()
        guard updated != snapshot else { return }
        snapshot = updated
    }

    private static func makeSnapshot() -> Snapshot {
        Snapshot(
            unreadCount: NotificationInboxManager.shared.unreadCount
                + NewChapterInboxManager.shared.totalNewBooks,
            hasRunningTask: BackupCoordinator.shared.progress.isActive
                || ModelDownloadCenter.shared.isBusy
                || DownloadManager.shared.hasActiveTasks
                || BookImportProgressCenter.shared.isRunning
        )
    }
}
