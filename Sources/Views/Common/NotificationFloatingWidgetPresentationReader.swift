import Combine
import Foundation

/// Ảnh chụp trạng thái mà widget thông báo nổi cần để quyết định **có hiện hay không**: số thông báo chưa
/// đọc và có tác vụ nền nào đang chạy.
///
/// ## Vì sao phải có lớp đọc riêng
/// Widget là một `UIWindow` sống suốt phiên. Nếu cửa sổ đó observe thẳng `NotificationInboxManager`,
/// `NewChapterInboxManager`, `BackupCoordinator` và `ModelDownloadCenter` thì **mỗi nhịp tiến độ** của một
/// lượt khôi phục hay tải model đều kéo cả cây view của widget vẽ lại — trong khi thứ duy nhất widget quan
/// tâm chỉ đổi vài lần mỗi lượt. Lớp này gộp bốn nguồn thành **một** snapshot và chỉ phát khi giá trị
/// **thật sự** đổi (cùng khuôn `VisibleBrowserPresentationReader`, `TTSPlayStateReader`).
///
/// ## Quy tắc hiện nút (người dùng chốt 2026-10-07)
/// Hiện khi **có thông báo chưa đọc** *hoặc* **đang có tác vụ chạy** (sao lưu / khôi phục / tải model).
/// Vế thứ hai có lý do rõ ràng: màn Thông báo là **nơi duy nhất** xem được thanh tiến độ, nên nếu nút chỉ
/// hiện theo số chưa đọc thì một lượt khôi phục dài chạy nền sẽ không có lối vào nào.
@MainActor
final class NotificationFloatingWidgetPresentationReader: ObservableObject {
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
        )
    }
}
