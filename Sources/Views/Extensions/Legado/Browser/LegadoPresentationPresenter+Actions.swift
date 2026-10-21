import SwiftData
import SwiftUI
import UIKit

/// Sự kiện phụ của engine nguồn Legado: `java.searchBook` (spec §11.6) và `java.openUrl` (spec §14.5).
extension LegadoPresentationPresenter {
    /// Mở màn Tìm kiếm với từ khoá; `sourceKey` khác `nil` ⇒ chọn sẵn nguồn đó (tìm trong một nguồn), không thì mọi nguồn.
    func presentSearch(keyword: String, sourceKey: String?) {
        guard let container = modelContainer else { return }
        let installed = ExtensionLibraryRepository.shared.installed
        let selected = sourceKey.flatMap { key -> Extension? in
            let packageId = LegadoSourceIdentity.packageId(forSourceUrl: key)
            return installed.first { $0.packageId == packageId }
        }
        let host = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
        host.rootView = AnyView(
            NavigationStack {
                SearchView(activeExtensions: installed, selectedExtension: selected, initialSearchQuery: keyword)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Đóng") { [weak host] in host?.dismiss(animated: true) }
                        }
                    }
            }
            .modelContainer(container)
        )
        host.modalPresentationStyle = .pageSheet
        presentAuxiliary(host)
    }

    /// `legado://`/`yuedu://` ⇒ hỏi rồi nhập nguồn; `http(s)` ⇒ trình duyệt nhỏ của nguồn; scheme khác ⇒ hỏi rồi mới mở
    /// ứng dụng ngoài. Không bao giờ làm gì im lặng.
    func openURL(_ text: String, sourceKey: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            AppLogger.shared.log("❌ [LegadoPresenter] java.openUrl: địa chỉ không hợp lệ")
            return
        }
        if let parsed = LegadoSourceLink.parse(url) {
            switch parsed {
            case .success(.importSources(let source)):
                confirm(title: "Nhập nguồn từ liên kết?", message: "Tải và nhập nguồn Legado từ:\n\(source)",
                        actionTitle: "Nhập") { [weak self] in self?.importSources(from: source) }
            case .failure(let issue):
                inform(title: "Không mở được liên kết", message: issue.message)
            }
            return
        }
        if scheme == "http" || scheme == "https" {
            presentPlainBrowser(url: trimmed, sourceKey: sourceKey)
            return
        }
        confirm(title: "Mở bằng ứng dụng khác?", message: trimmed, actionTitle: "Mở") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Nội bộ

    private func presentPlainBrowser(url: String, sourceKey: String) {
        let packageId = LegadoSourceIdentity.packageId(forSourceUrl: sourceKey)
        let sourceName = ExtensionLibraryRepository.snapshot(packageId: packageId)?.name ?? ""
        let request = LegadoBrowserRequest(id: UUID(), sourceKey: sourceKey, sourceName: sourceName, url: url, title: "",
                                           html: nil, waitsForResult: false, userAgent: LegadoHTTPClient.webViewUserAgent,
                                           headers: [:], cookies: [])
        let host = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
        host.rootView = AnyView(LegadoBrowserSheet(request: request) { [weak host] _, _ in
            host?.dismiss(animated: true)
        })
        host.modalPresentationStyle = .overFullScreen
        presentAuxiliary(host)
    }

    private func importSources(from source: String) {
        AppLogger.shared.log("🔗 📚 [LegadoImport] Nhập từ java.openUrl (người dùng đã xác nhận)")
        Task { @MainActor [weak self] in
            let result = await LegadoSourceCoordinator.shared.importFromLink(source)
            switch result {
            case .success(let summary):
                self?.inform(title: "Đã nhập \(summary.importedCount) nguồn",
                             message: LegadoSourceTabState.importSummaryMessage(summary))
            case .failure(let error):
                self?.inform(title: "Lỗi nguồn Legado", message: error.localizedDescription)
            }
        }
    }

    private func confirm(title: String, message: String, actionTitle: String, action: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        alert.addAction(UIAlertAction(title: actionTitle, style: .default) { _ in action() })
        presentAuxiliary(alert)
    }

    private func inform(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Xong", style: .cancel))
        presentAuxiliary(alert)
    }
}
