import SwiftData
import SwiftUI

/// Màn bật/tắt debug server và cửa xác nhận cài bản nháp (Phase 4).
///
/// Bật là lắng nghe: không QR, không token, không bước xác nhận kết nối. Người dùng chỉ cần chuỗi
/// `ws://ip:port` hiện ở đây.
///
/// Công tắc là `@AppStorage` nên **rời màn hình này không tắt server**, và app mở lại sẽ tự bật lại
/// (xem `MainTabView`).
///
/// Từ 1.3.349 có thêm công tắc "Không cần bấm xác nhận", **mặc định bật**: `draft.install` và
/// `draft.rollback` chạy luôn. Khi nó bật thì `installSection` không bao giờ xuất hiện, vì
/// `ExtensionDebugInstallGate` trả `.approved` mà không đặt `pending`.
struct ExtensionDebugServerView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var reader = ExtensionDebugServerReader()
    @AppStorage(ExtensionDebugServerLauncher.enabledKey) private var isServerEnabled = false
    @AppStorage(ExtensionDebugInstallGate.autoApproveDefaultsKey) private var autoApproveInstall = true
    @State private var isBusy = false

    var body: some View {
        Form {
            stateSection
            autoApproveSection
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
            Toggle("Bật server", isOn: $isServerEnabled)
                .disabled(isBusy)
                .onChange(of: isServerEnabled) { _, enabled in
                    apply(enabled: enabled)
                }

            HStack {
                Text("Trạng thái")
                Spacer()
                Text(reader.status.phaseLabel)
                    .foregroundStyle(reader.status.phase == .failed ? .red : .secondary)
            }

            if let endpoint = reader.status.websocketEndpoint {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Địa chỉ kết nối")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(endpoint)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = endpoint
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if let client = reader.status.clientName {
                HStack {
                    Text("Client")
                    Spacer()
                    Text(client).foregroundStyle(.secondary)
                }
            }

            if let message = reader.status.failureMessage {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Server")
        } footer: {
            Text("Máy tính cùng Wi-Fi nối thẳng vào địa chỉ trên — không cần ghép nối. Cổng được ghi nhớ nên lần sau mở lại đúng địa chỉ này nếu cổng còn rảnh. Rời màn hình này không tắt server; nhưng khi iOS treo app ở nền thì server ngừng nhận tới lúc bạn mở lại app.")
        }
    }

    /// Section riêng, **không** nhồi vào `stateSection`: hai `Section` cạnh nhau trong một computed
    /// property `some View` không có `@ViewBuilder` thì Swift không suy được kiểu trả về.
    private var autoApproveSection: some View {
        Section {
            Toggle("Không cần bấm xác nhận", isOn: $autoApproveInstall)
        } header: {
            Text("Cài từ debug")
        } footer: {
            Text("Bật (mặc định): `draft.install` và `draft.rollback` chạy ngay, không hỏi gì — tiện khi sửa extension liên tục. Nhớ rằng server **không có ghép nối**, nên trong lúc nó bật, máy nào tới được địa chỉ trên cũng ghi được extension vào thư viện. Tắt công tắc này để mỗi lần cài lại phải bấm và thấy trước danh sách file sẽ đổi. Dù bật hay tắt, mọi lần cài đều được ghi vào app_logs.txt.")
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
                Label(approveLabel(for: pending.kind), systemImage: "checkmark.seal")
            }
            Button(role: .destructive, action: { decideInstall(id: pending.id, approved: false) }) {
                Label("Không", systemImage: "xmark.seal")
            }
        } header: {
            Text(pending.kind == .installNew ? "Yêu cầu thêm extension mới" : "Yêu cầu ghi đè extension")
        } footer: {
            Text(installFooter(for: pending.kind))
        }
    }

    private func approveLabel(for kind: ExtensionDebugInstallGate.Kind) -> String {
        switch kind {
        case .install: return "Đồng ý ghi đè"
        case .installNew: return "Đồng ý cài mới"
        case .rollback: return "Đồng ý rollback"
        }
    }

    /// Chuỗi trả về là `String` runtime nên `Text` **không** hiểu markdown ở đây (khác các `Text("…")`
    /// literal trong `safetySection`) — vì vậy viết phẳng, không `**` hay backtick.
    private func installFooter(for kind: ExtensionDebugInstallGate.Kind) -> String {
        switch kind {
        case .installNew:
            return "Extension này chưa có trên máy: app sẽ tạo thư mục mới trong extensions/ và thêm một bản ghi vào thư viện. Chỉ đồng ý nếu bạn biết máy nào đang gửi."
        case .install, .rollback:
            return "Bản đang cài được sao lưu trước khi thay, và thay theo kiểu nguyên tử. Có thể rollback sau đó."
        }
    }

    private var safetySection: some View {
        Section("Giới hạn đã biết") {
            Text("• Không có ghép nối: khi server đang bật, **bất kỳ** máy nào trong cùng Wi-Fi nối được và chạy được script của extension. Chỉ bật khi đang ở mạng bạn tin.")
            Text("• Kết nối là `ws` chưa có TLS.")
            Text("• Trace đã bỏ header, cookie, body và nội dung chương; giá trị query trong URL hiện dưới dạng “…”.")
            Text("• Bản nháp sống trong `extension-drafts/` và bị xoá sạch khi tắt server hoặc mở lại app.")
            Text("• Cài bản nháp lên extension **đã có** chỉ thay file; metadata trong thư viện không đổi.")
            Text("• Extension **chưa có** trên máy thì cài mới được: app tạo thư mục và thêm bản ghi thư viện — vẫn phải bấm đồng ý ở đây.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func apply(enabled: Bool) {
        isBusy = true
        let container = modelContext.container
        Task {
            if enabled {
                await ExtensionDebugServer.shared.start(container: container)
            } else {
                await ExtensionDebugServer.shared.stop()
            }
            isBusy = false
        }
    }

    private func decideInstall(id: UUID, approved: Bool) {
        Task { await ExtensionDebugServer.shared.decideInstall(id: id, approved: approved) }
    }
}
