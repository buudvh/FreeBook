import SwiftData
import SwiftUI
import UIKit

/// Theo dõi lượt kiểm tra nguồn của hai màn kiểm tra (Legado, tiện ích JS) để lượt **thu nhỏ** được (1.3.697).
///
/// Hai bộ chạy (`LegadoCorpusRunner`, `ExtensionCheckRunner`) vốn giữ lượt độc lập với màn. Từ 1.3.697 rời màn khi lượt
/// còn chạy (nút ⌄, vuốt xuống sheet, quay lại) **không** dừng lượt nữa — chỉ nút Dừng mới dừng. Vòng đời một bản ghi:
/// - Màn bắt đầu / gắn vào lượt ⇒ `track` (màn mở, hub không thấy); vòng thăm dò của màn gọi `update` mỗi giây.
/// - Màn đóng (`screenDidClose`): lượt còn chạy ⇒ thu nhỏ, lớp này tự thăm dò mỗi giây cho dòng "Kiểm tra nguồn" của
///   hub; lượt đã xong ⇒ bỏ (người dùng đã thấy kết quả).
/// - Xong/dừng khi đang thu nhỏ ⇒ toast (cũng vào Trung tâm thông báo), dòng hub giữ "bấm để xem".
/// - `reopen` (chạm dòng hub) trình bày lại màn ở chế độ gắn vào lượt bằng UIKit từ màn trên cùng của cửa sổ mức thường
///   (sheet có thanh kéo, như màn Thông báo của hub).
///
/// Màn đóng mà không nhận `onDisappear` (đang đẩy màn con thì sheet bị vuốt xuống) vẫn được bắt nhờ `ScreenLease` —
/// `@StateObject` của màn, giải phóng cùng màn. Tầng Views vì cần toast và trình bày màn.
@MainActor
final class MinimizedSourceCheckCoordinator: ObservableObject {
    static let shared = MinimizedSourceCheckCoordinator()

    /// Màn kiểm tra cần gì để dựng lại.
    enum Payload {
        case legado(packageIds: [String])
        case script(targets: [ExtensionCheckRunner.Target])
    }

    /// Danh tính một màn kiểm tra đang mở; giải phóng (màn bị gỡ khỏi cây view) ⇒ coi như màn đóng.
    final class ScreenLease: ObservableObject {
        let id = UUID()
        fileprivate var bound: (kind: MinimizedSourceCheck.Kind, runId: String)?

        deinit {
            guard let kind = bound?.kind else { return }
            let screenId = self.id
            Task { @MainActor in
                MinimizedSourceCheckCoordinator.shared.screenDidClose(kind, screenId: screenId)
            }
        }
    }

    /// Câu của màn mở lại khi bộ chạy đã sang lượt khác.
    static let replacedRunMessage = "Lượt kiểm tra này không còn — bộ kiểm tra đã chạy lượt khác sau nó."
    private static let pollInterval: UInt64 = 1_000_000_000
    /// Số lần thử trình bày lại (mỗi 0,25 s) khi màn trên cùng đang mở/đóng dở.
    private static let presentAttempts = 20

    /// Theo thứ tự bắt đầu theo dõi. Hub chỉ đọc bản đang thu nhỏ (`isMinimized`).
    @Published private(set) var entries: [MinimizedSourceCheck] = []
    private var payloads: [MinimizedSourceCheck.Kind: Payload] = [:]
    private var pollTask: Task<Void, Never>?

    private init() {}

    func entry(for kind: MinimizedSourceCheck.Kind) -> MinimizedSourceCheck? {
        entries.first { $0.kind == kind }
    }

    // MARK: - Màn kiểm tra báo

    /// Màn vừa bắt đầu / gắn vào lượt `progress.runId`: thay bản cũ cùng bộ chạy (kết quả cũ đã bị lượt mới thay).
    func track(
        _ kind: MinimizedSourceCheck.Kind,
        scopeTitle: String,
        progress: MinimizedSourceCheck.Progress,
        payload: Payload,
        screen: ScreenLease
    ) {
        screen.bound = (kind, progress.runId)
        entries.removeAll { $0.kind == kind }
        entries.append(MinimizedSourceCheck(kind: kind, scopeTitle: scopeTitle, progress: progress, openScreenId: screen.id))
        payloads[kind] = payload
    }

    /// Tiến độ mới từ vòng thăm dò của màn đang mở — để lúc màn đóng biết lượt còn chạy hay đã xong.
    func update(_ kind: MinimizedSourceCheck.Kind, progress: MinimizedSourceCheck.Progress) {
        guard let index = entries.firstIndex(where: { $0.kind == kind && $0.runId == progress.runId }),
              entries[index].progress != progress else { return }
        entries[index].progress = progress
    }

    /// Màn rời đi. `screenId == nil` (sheet đóng, không biết màn nào) ⇒ mọi màn đang mở của `kind`. Gọi lại nhiều lần
    /// vô hại: chỉ tác động bản ghi còn gắn đúng màn đó.
    func screenDidClose(_ kind: MinimizedSourceCheck.Kind, screenId: UUID?) {
        guard let index = entries.firstIndex(where: { $0.kind == kind }),
              let openId = entries[index].openScreenId,
              screenId == nil || screenId == openId else { return }
        guard entries[index].isRunning else {
            discard(kind)
            return
        }
        entries[index].openScreenId = nil
        let entry = entries[index]
        AppLogger.shared.log(
            "🧪 [SourceCheck] Thu nhỏ \(kind.rawValue) \(entry.runId): \(entry.progress.completed)/\(entry.progress.total)"
        )
        startPollingIfNeeded()
    }

    /// Thôi theo dõi: người dùng bấm Dừng, hoặc màn mở lại không còn gắn được vào lượt. `runId` khác `nil` ⇒ chỉ bỏ khi
    /// bản ghi đúng lượt đó (đã có màn khác bắt đầu lượt mới thì giữ).
    func discard(_ kind: MinimizedSourceCheck.Kind, runId: String? = nil) {
        guard let entry = entry(for: kind), runId == nil || entry.runId == runId else { return }
        entries.removeAll { $0.kind == kind }
        payloads[kind] = nil
    }

    // MARK: - Mở lại

    /// Mở lại màn của lượt đang thu nhỏ. `delay` cho màn đang đóng kịp đóng hẳn (nút "Mở lượt đang chạy").
    func reopen(_ kind: MinimizedSourceCheck.Kind, delay: UInt64 = 0) {
        guard let entry = entry(for: kind), entry.isMinimized, let payload = payloads[kind] else { return }
        let controller = makeController(entry: entry, payload: payload)
        Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            self?.present(controller, kind: kind, runId: entry.runId, attempt: 0)
        }
    }

    private func present(_ controller: UIViewController, kind: MinimizedSourceCheck.Kind, runId: String, attempt: Int) {
        // Lượt đã bị bỏ/thay, hoặc đã mở lại bằng đường khác trong lúc chờ ⇒ thôi.
        guard let index = entries.firstIndex(where: { $0.kind == kind && $0.runId == runId }),
              entries[index].isMinimized else { return }
        if let top = LegadoPresentationPresenter.topViewController() {
            // Hub xám ngay; màn gắn vào lượt sẽ `track` lại với danh tính của nó.
            entries[index].openScreenId = UUID()
            top.present(controller, animated: true)
            return
        }
        guard attempt < Self.presentAttempts else {
            AppLogger.shared.log("❌ [SourceCheck] Không mở lại được màn kiểm tra (không có màn trên cùng)")
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self?.present(controller, kind: kind, runId: runId, attempt: attempt + 1)
        }
    }

    private func makeController(entry: MinimizedSourceCheck, payload: Payload) -> UIViewController {
        let hosting = UIHostingController(rootView: AnyView(EmptyView()))
        // Màn tự đóng qua closure này (nút ⌄): `dismiss` của environment không chắc tới được màn trình bày bằng UIKit.
        let close: () -> Void = { [weak hosting] in
            guard let hosting, !hosting.isBeingDismissed,
                  let presenting = hosting.presentingViewController,
                  presenting.presentedViewController === hosting else { return }
            presenting.dismiss(animated: true)
        }
        let screen: AnyView
        switch payload {
        case .legado(let packageIds):
            screen = AnyView(LegadoSourceCheckView(
                packageIds: packageIds, scopeTitle: entry.scopeTitle, isPresentedAsSheet: true,
                attachRunId: entry.runId, onClose: close
            ))
        case .script(let targets):
            screen = AnyView(ExtensionCheckView(
                targets: targets, scopeTitle: entry.scopeTitle, isPresentedAsSheet: true,
                attachRunId: entry.runId, onClose: close
            ))
        }
        // Trình bày bằng UIKit ⇒ không thừa hưởng `.tint` của `MainTabView`, gắn lại màu nhấn.
        let root = NavigationStack { screen }.appAccentTint()
        if let container = FloatingHubWindowManager.shared.modelContainer {
            hosting.rootView = AnyView(root.modelContainer(container))
        } else {
            hosting.rootView = AnyView(root)
        }
        hosting.modalPresentationStyle = .pageSheet
        hosting.sheetPresentationController?.prefersGrabberVisible = true
        return hosting
    }

    // MARK: - Thăm dò khi thu nhỏ

    /// Một vòng cho mọi lượt đang thu nhỏ mà còn chạy; hết lượt như vậy thì dừng. Đọc ngay rồi mới chờ.
    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while let self, self.entries.contains(where: { $0.isMinimized && $0.isRunning }) {
                await self.refreshMinimizedEntries()
                try? await Task.sleep(nanoseconds: MinimizedSourceCheckCoordinator.pollInterval)
            }
            self?.pollTask = nil
        }
    }

    private func refreshMinimizedEntries() async {
        for entry in entries where entry.isMinimized && entry.isRunning {
            let latest: MinimizedSourceCheck.Progress?
            switch entry.kind {
            case .legado:
                latest = await LegadoCorpusRunner.shared.status(includeSources: false).map { MinimizedSourceCheck.Progress($0) }
            case .script:
                latest = await ExtensionCheckRunner.shared.status().map { MinimizedSourceCheck.Progress($0) }
            }
            apply(latest, kind: entry.kind, runId: entry.runId)
        }
    }

    private func apply(_ latest: MinimizedSourceCheck.Progress?, kind: MinimizedSourceCheck.Kind, runId: String) {
        // Bản ghi có thể đã đổi trong lúc chờ bộ chạy (mở lại, bị thay).
        guard let index = entries.firstIndex(where: { $0.kind == kind && $0.runId == runId }),
              entries[index].isMinimized else { return }
        guard let latest, latest.runId == runId else {
            // Bộ chạy đã sang lượt khác (Debug server…) ⇒ kết quả lượt này không còn để xem.
            AppLogger.shared.log("🧪 [SourceCheck] Lượt \(kind.rawValue) \(runId) không còn ở bộ chạy, bỏ khỏi hub")
            discard(kind, runId: runId)
            return
        }
        guard entries[index].progress != latest else { return }
        entries[index].progress = latest
        if !entries[index].isRunning {
            announceEnd(of: entries[index])
        }
    }

    private func announceEnd(of entry: MinimizedSourceCheck) {
        let progress = entry.progress
        switch progress.phase {
        case .finished:
            ToastManager.shared.show(
                message: "\(entry.kind.title) xong · \(progress.passed) đạt, \(progress.failed) lỗi",
                type: .success
            )
        case .cancelled:
            ToastManager.shared.show(
                message: "\(entry.kind.title) đã dừng · \(progress.completed)/\(progress.total)",
                type: .info
            )
        case .running:
            break
        }
    }
}
