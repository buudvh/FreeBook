import Combine
import Foundation

/// Projection reader cho màn debug server: gộp hai stream (trạng thái server và yêu cầu cài đang chờ)
/// thành state sẵn sàng render.
///
/// Gộp ở đây chứ không ở tầng Services vì hai nguồn thuộc hai concern khác nhau —
/// `ExtensionDebugServer` sở hữu vòng đời socket, `ExtensionDebugInstallGate` sở hữu cửa xác
/// nhận Phase 4 — và không nên biết về nhau chỉ để UI hiện trong cùng một màn.
@MainActor
final class ExtensionDebugServerReader: ObservableObject {
    @Published private(set) var status = ExtensionDebugServerStatus()
    @Published private(set) var pendingInstall: ExtensionDebugInstallGate.Request?

    private var statusTask: Task<Void, Never>?
    private var gateTask: Task<Void, Never>?

    /// Idempotent: `.task` của View gọi lại không tạo stream thứ hai.
    func attach() {
        if statusTask == nil {
            statusTask = Task { [weak self] in
                let stream = await ExtensionDebugServer.shared.statusStream()
                for await value in stream {
                    guard let self else { return }
                    self.status = value
                }
            }
        }
        if gateTask == nil {
            gateTask = Task { [weak self] in
                let stream = await ExtensionDebugInstallGate.shared.pendingStream()
                for await value in stream {
                    guard let self else { return }
                    self.pendingInstall = value
                }
            }
        }
    }

    func detach() {
        statusTask?.cancel()
        statusTask = nil
        gateTask?.cancel()
        gateTask = nil
    }
}
