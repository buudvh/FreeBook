import SwiftUI

/// Nhận liên kết `legado://…` mở app từ ngoài (spec §12.2, `CFBundleURLTypes` trong `project.yml`): hỏi "Nhập nguồn từ
/// liên kết?" (Huỷ / Nhập) ⇒ nhập như "Nhập nguồn từ URL" qua `LegadoSourceCoordinator.importFromLink` ⇒ alert tổng kết
/// giống tab "Nguồn Legado". Không bao giờ nhập im lặng; `src` chỉ nhận http/https (`LegadoSourceLink`).
///
/// Gắn **một lần** ở view gốc (`AppLaunchRootView`). Liên kết đến khi app còn ở màn chờ từ điển (`isReady == false`) được
/// giữ lại tới khi cổng mở rồi mới hỏi.
struct LegadoLinkImportModifier: ViewModifier {
    let isReady: Bool

    private enum LinkAlert: Identifiable {
        case confirm(url: String)
        case result(title: String, message: String)

        var id: String {
            switch self {
            case .confirm(let url): return "confirm:" + url
            case .result(let title, _): return "result:" + title
            }
        }
    }

    @State private var pendingURL: String?
    @State private var alert: LinkAlert?
    @State private var isImporting = false

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in handle(url) }
            .onChange(of: isReady) { _, ready in
                guard ready, let pending = pendingURL else { return }
                pendingURL = nil
                alert = .confirm(url: pending)
            }
            .alert(
                Text(alertTitle),
                isPresented: Binding(
                    get: { alert != nil },
                    set: { if !$0 { alert = nil } }
                ),
                presenting: alert
            ) { item in
                switch item {
                case .confirm(let url):
                    Button("Huỷ", role: .cancel) {}
                    Button("Nhập") { startImport(url) }
                case .result:
                    Button("Xong", role: .cancel) {}
                }
            } message: { item in
                switch item {
                case .confirm(let url):
                    Text("Tải và nhập nguồn Legado từ:\n\(url)")
                case .result(_, let message):
                    Text(message)
                }
            }
    }

    private var alertTitle: String {
        switch alert {
        case .confirm: return "Nhập nguồn từ liên kết?"
        case .result(let title, _): return title
        case .none: return ""
        }
    }

    private func handle(_ url: URL) {
        guard let parsed = LegadoSourceLink.parse(url) else { return }
        switch parsed {
        case .failure(let issue):
            alert = .result(title: "Không mở được liên kết", message: issue.message)
        case .success(.importSources(let source)):
            if isReady {
                alert = .confirm(url: source)
            } else {
                pendingURL = source
            }
        }
    }

    private func startImport(_ source: String) {
        guard !isImporting else { return }
        isImporting = true
        AppLogger.shared.log("🔗 📚 [LegadoImport] Nhập từ liên kết (người dùng đã xác nhận)")
        Task { @MainActor in
            let result = await LegadoSourceCoordinator.shared.importFromLink(source)
            isImporting = false
            switch result {
            case .success(let summary):
                alert = .result(
                    title: "Đã nhập \(summary.importedCount) nguồn",
                    message: LegadoSourceTabState.importSummaryMessage(summary)
                )
            case .failure(let error):
                alert = .result(title: "Lỗi nguồn Legado", message: error.localizedDescription)
            }
        }
    }
}

extension View {
    /// Nhận liên kết `legado://…` — xem `LegadoLinkImportModifier`.
    func legadoLinkImportHandler(isReady: Bool) -> some View {
        modifier(LegadoLinkImportModifier(isReady: isReady))
    }
}
