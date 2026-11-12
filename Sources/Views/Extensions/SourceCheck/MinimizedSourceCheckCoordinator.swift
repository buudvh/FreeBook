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
/// - Chạm dòng hub ⇒ màn gắn vào lượt hiện **ngay trong sheet hub** (trang con, `embeddedPage` / `embeddedScreen`,
///   1.3.872). `reopen` (nút "Mở lượt đang chạy" của màn kiểm tra) vẫn trình bày lại màn bằng UIKit từ màn trên cùng của
///   cửa sổ mức thường (sheet có thanh kéo).
///
/// Báo "màn đóng" **không** trông vào một mình `onDisappear` (1.3.702: máy thật đóng sheet mà lượt không thu nhỏ): nút ⌄
/// báo trước khi đóng; mọi sheet có thể chứa màn kiểm tra gọi `screenDidClose(_, screenId: nil)` ở `onDismiss` (sheet
/// mở lại từ hub: `SheetDismissRelay`); `onDisappear` và `ScreenLease` (`@StateObject` giải phóng cùng màn) là lối dự
/// phòng. Tầng Views vì cần toast và trình bày màn.
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

    /// Vuốt xuống sheet mở lại (UIKit) ⇒ thu nhỏ lần nữa. `presentationController.delegate` là tham chiếu yếu nên lớp
    /// điều phối giữ relay (`sheetRelays`).
    @MainActor
    final class SheetDismissRelay: NSObject, UIAdaptivePresentationControllerDelegate {
        let kind: MinimizedSourceCheck.Kind

        init(kind: MinimizedSourceCheck.Kind) {
            self.kind = kind
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            MinimizedSourceCheckCoordinator.shared.screenDidClose(kind, screenId: nil)
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
    private var sheetRelays: [MinimizedSourceCheck.Kind: SheetDismissRelay] = [:]
    private var pollTask: Task<Void, Never>?

    private init() {}

    func entry(for kind: MinimizedSourceCheck.Kind) -> MinimizedSourceCheck? {
        entries.first { $0.kind == kind }
    }

    /// Bộ chạy `kind` có lượt **đang chạy ở nền** (đã thu nhỏ) ⇒ khoá các lối mở lượt mới (1.3.704,
    /// `SourceCheckBusyReader`). Màn kiểm tra còn mở thì đã che mọi lối vào nên không cần tính — và không đổi trạng thái
    /// của `NavigationLink` đang đẩy chính màn đó.
    func isBusy(_ kind: MinimizedSourceCheck.Kind) -> Bool {
        entries.contains { $0.kind == kind && $0.isMinimized && $0.isRunning }
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
        AppLogger.shared.log("🧪 [SourceCheck] Theo dõi \(kind.rawValue) \(progress.runId), màn \(screen.id.uuidString.prefix(8))")
    }

    /// Tiến độ mới từ vòng thăm dò của màn đang mở — để lúc màn đóng biết lượt còn chạy hay đã xong. Lượt đã thu nhỏ thì
    /// lớp này tự thăm dò (màn đóng mà task của nó chưa dừng không được cướp mốc "xong" ⇒ mất toast).
    func update(_ kind: MinimizedSourceCheck.Kind, progress: MinimizedSourceCheck.Progress) {
        guard let index = entries.firstIndex(where: { $0.kind == kind && $0.runId == progress.runId }),
              !entries[index].isMinimized,
              entries[index].progress != progress else { return }
        entries[index].progress = progress
    }

    /// Màn rời đi. `screenId == nil` (nút ⌄, `onDismiss` của sheet chứa màn) ⇒ màn đang mở của `kind`, không cần biết
    /// màn nào. Gọi lại nhiều lần vô hại: chỉ tác động bản ghi còn gắn màn.
    func screenDidClose(_ kind: MinimizedSourceCheck.Kind, screenId: UUID?) {
        guard let index = entries.firstIndex(where: { $0.kind == kind }) else {
            if screenId == nil {
                AppLogger.shared.log("🧪 [SourceCheck] Đóng màn \(kind.rawValue): không có lượt đang theo dõi")
            }
            return
        }
        guard let openId = entries[index].openScreenId else { return }
        guard screenId == nil || screenId == openId else {
            AppLogger.shared.log(
                "🧪 [SourceCheck] Đóng màn \(kind.rawValue) bỏ qua: màn \(screenId.map { String($0.uuidString.prefix(8)) } ?? "-") "
                    + "không phải màn đang gắn \(String(openId.uuidString.prefix(8)))"
            )
            return
        }
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

    // MARK: - Trang con trong sheet hub (1.3.872)

    /// Ảnh chụp một lượt đang thu nhỏ để dựng màn kiểm tra **ngay trong sheet hub** (trang con "Kiểm tra nguồn", như trang
    /// "Tác vụ AI") thay cho sheet riêng của `reopen`. Chụp lúc chạm dòng hub: màn gắn vào lượt xong thì bản ghi thôi "thu
    /// nhỏ" (hub không thấy nữa) nên không tra lại mỗi lượt vẽ.
    struct EmbeddedPage: Equatable {
        let kind: MinimizedSourceCheck.Kind
        let runId: String
        fileprivate let scopeTitle: String
        fileprivate let payload: Payload

        static func == (lhs: EmbeddedPage, rhs: EmbeddedPage) -> Bool {
            lhs.kind == rhs.kind && lhs.runId == rhs.runId
        }
    }

    /// Lượt `kind` đang thu nhỏ ⇒ trang con để mở trong sheet hub; không có ⇒ `nil`.
    func embeddedPage(_ kind: MinimizedSourceCheck.Kind) -> EmbeddedPage? {
        guard let entry = entry(for: kind), entry.isMinimized, let payload = payloads[kind] else { return nil }
        return EmbeddedPage(kind: kind, runId: entry.runId, scopeTitle: entry.scopeTitle, payload: payload)
    }

    /// Màn kiểm tra gắn vào lượt của `page`, tiêu đề giữa (trang con có nút ‹ — `SourceCheckHeaderButtons` thôi vẽ ⌄).
    /// Màn tự `track` khi gắn xong và `screenDidClose` khi rời; `onClose` là đường đóng của chính màn (⌄, "Mở lượt đang
    /// chạy").
    func embeddedScreen(_ page: EmbeddedPage, onClose: @escaping () -> Void) -> AnyView {
        switch page.payload {
        case .legado(let packageIds):
            return AnyView(LegadoSourceCheckView(
                packageIds: packageIds, scopeTitle: page.scopeTitle, attachRunId: page.runId, onClose: onClose
            ))
        case .script(let targets):
            return AnyView(ExtensionCheckView(
                targets: targets, scopeTitle: page.scopeTitle, attachRunId: page.runId, onClose: onClose
            ))
        }
    }

    private func present(_ controller: UIViewController, kind: MinimizedSourceCheck.Kind, runId: String, attempt: Int) {
        // Lượt đã bị bỏ/thay, hoặc đã mở lại bằng đường khác trong lúc chờ ⇒ thôi.
        guard let index = entries.firstIndex(where: { $0.kind == kind && $0.runId == runId }),
              entries[index].isMinimized else { return }
        if let top = LegadoPresentationPresenter.topViewController() {
            // Hub xám ngay; màn gắn vào lượt sẽ `track` lại với danh tính của nó.
            entries[index].openScreenId = UUID()
            let relay = SheetDismissRelay(kind: kind)
            sheetRelays[kind] = relay
            top.present(controller, animated: true) {
                // Gán **sau** khi trình bày: `presentationController` chỉ có từ lúc trình bày (luật 26).
                controller.presentationController?.delegate = relay
            }
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
        // Nền kính như mọi sheet (1.3.873): hosting trong suốt, kính vẽ ở gốc SwiftUI.
        let root = NavigationStack { screen }.appAccentTint().appGlassUIKitSheet()
        hosting.view.backgroundColor = .clear
        if let container = FloatingHubWindowManager.shared.modelContainer {
            hosting.rootView = AnyView(root.modelContainer(container))
        } else {
            hosting.rootView = AnyView(root)
        }
        hosting.modalPresentationStyle = .pageSheet
        hosting.sheetPresentationController?.prefersGrabberVisible = true
        hosting.sheetPresentationController?.preferredCornerRadius = 16
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
