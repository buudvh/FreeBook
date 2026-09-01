import SwiftData
import SwiftUI

/// Màn bật/tắt debug server (Phase 2) và cửa xác nhận cài bản nháp (Phase 4).
///
/// Server **mặc định tắt** và chỉ bật bằng thao tác ở đây; `MainTabView` tắt nó khi app rời foreground.
/// Màn này là chỗ duy nhất người dùng thấy token/QR, thấy client đang xin kết nối, và thấy danh sách file
/// sẽ đổi trước khi đồng ý cho ghi đè extension.
struct ExtensionDebugServerView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var reader = ExtensionDebugServerReader()
    @State private var isBusy = false

    private var serviceName: String {
        "FreeBook " + (UIDevice.current.name.split(separator: " ").last.map(String.init) ?? "Debug")
    }

    var body: some View {
        Form {
            stateSection
            if reader.status.phase == .waitingForClient, let uri = reader.status.pairingURI {
                pairingSection(uri: uri)
            }
            if reader.status.phase == .waitingForApproval {
                approvalSection
            }
            if let pending = reader.pendingInstall {
                installSection(pending: pending)
            }
            safetySection
        }
        .navigationTitle("Debug Server (LAN)")
        .task { reader.attach() }
    }

    private var stateSection: some View {
        Section {
            HStack {
                Text("Trạng thái")
                Spacer()
                Text(reader.status.phaseLabel)
                    .foregroundStyle(reader.status.phase == .failed ? .red : .secondary)
            }
            if let port = reader.status.port {
                HStack {
                    Text("Cổng")
                    Spacer()
                    Text("\(port)").foregroundStyle(.secondary).monospaced()
                }
            }
            if let service = reader.status.serviceName {
                HStack {
                    Text("Bonjour")
                    Spacer()
                    Text("\(service) · _freebook-extdebug._tcp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let message = reader.status.failureMessage {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            if let client = reader.status.pairedClientName {
                HStack {
                    Text("Client")
                    Spacer()
                    Text(client).foregroundStyle(.secondary)
                }
            }

            if reader.status.isRunning {
                Button(role: .destructive, action: stopServer) {
                    Label("Tắt server", systemImage: "stop.circle")
                }
                .disabled(isBusy)
            } else {
                Button(action: startServer) {
                    Label("Bật server", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(isBusy)
            }
        } header: {
            Text("Server")
        } footer: {
            Text("Chỉ chạy khi app ở foreground; vào nền là tự tắt. Cổng ngẫu nhiên, tối đa một client.")
        }
    }

    private func pairingSection(uri: String) -> some View {
        Section {
            VStack(alignment: .center, spacing: 10) {
                ExtensionDebugPairingQRView(content: uri)
                if let countdown = reader.pairingCountdownText {
                    Text(countdown).font(.caption).foregroundStyle(.secondary)
                }
                Text(uri)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        } header: {
            Text("Ghép nối")
        } footer: {
            Text("Quét QR hoặc dán chuỗi trên vào lệnh “FreeBook: Pair with App” của VS Code. Token dùng một lần và hết hạn sau 3 phút.")
        }
    }

    private var approvalSection: some View {
        Section {
            Text(reader.status.pendingClientName ?? "Một client")
                .fontWeight(.semibold)
            Button(action: { decidePairing(approved: true) }) {
                Label("Cho phép kết nối", systemImage: "checkmark.circle")
            }
            Button(role: .destructive, action: { decidePairing(approved: false) }) {
                Label("Từ chối", systemImage: "xmark.circle")
            }
        } header: {
            Text("Client đang xin kết nối")
        } footer: {
            Text("Token đúng chỉ mở cửa xin phép — phải bấm ở đây thì client mới vào được.")
        }
    }

    private func installSection(pending: ExtensionDebugInstallGate.Request) -> some View {
        Section {
            Text(pending.summary).fontWeight(.semibold)
            if pending.changes.isEmpty {
                Text("Không có file nào khác nhau").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(pending.changes, id: \.self) { line in
                    Text(line).font(.system(size: 11, design: .monospaced))
                }
            }
            Button(action: { decideInstall(id: pending.id, approved: true) }) {
                Label(pending.kind == .install ? "Đồng ý ghi đè" : "Đồng ý rollback", systemImage: "checkmark.seal")
            }
            Button(role: .destructive, action: { decideInstall(id: pending.id, approved: false) }) {
                Label("Không", systemImage: "xmark.seal")
            }
        } header: {
            Text("Yêu cầu ghi đè extension")
        } footer: {
            Text("Bản đang cài được sao lưu trước khi thay, và thay theo kiểu nguyên tử. Có thể rollback sau đó.")
        }
    }

    private var safetySection: some View {
        Section("Giới hạn đã biết") {
            Text("• Chỉ dùng bản Dev/Ad Hoc trên LAN tin cậy: kết nối là `ws` chưa có TLS.")
            Text("• Trace đã bỏ header, cookie, body và nội dung chương; giá trị query trong URL hiện dưới dạng “…”.")
            Text("• Bản nháp sống trong `extension-drafts/` và bị xoá sạch khi tắt server hoặc mở lại app.")
            Text("• Cài bản nháp chỉ thay file; metadata trong thư viện không đổi.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func startServer() {
        isBusy = true
        let container = modelContext.container
        let name = serviceName
        Task {
            await ExtensionDebugServer.shared.start(container: container, serviceName: name)
            isBusy = false
        }
    }

    private func stopServer() {
        isBusy = true
        Task {
            await ExtensionDebugServer.shared.stop()
            isBusy = false
        }
    }

    private func decidePairing(approved: Bool) {
        Task {
            if approved {
                await ExtensionDebugServer.shared.approvePairing()
            } else {
                await ExtensionDebugServer.shared.rejectPairing()
            }
        }
    }

    private func decideInstall(id: UUID, approved: Bool) {
        Task { await ExtensionDebugServer.shared.decideInstall(id: id, approved: approved) }
    }
}
