import SwiftUI

/// Màn **Tài khoản Google** (1.3.614) — mỗi dòng là một profile Chế độ AI của Google, tức một tài khoản Google.
///
/// Thứ tự dòng **chính là** thứ tự xoay vòng khi Google giới hạn số câu trả lời AI: bị giới hạn thì app tráo sang dòng kế
/// tiếp (`GoogleAccountRotation`), hết tài khoản thì mới chuyển Gemini Web rồi mới chờ. Kéo ≡ để đổi thứ tự.
///
/// Chỉ có **một** kho cookie Google trong app (iOS không có `WKWebsiteDataStore(forIdentifier:)`) ⇒ thêm tài khoản là
/// tráo cookie, và cả app — kể cả Gemini Web lẫn trình duyệt bypass — chuyển theo tài khoản đang dùng.
public struct GoogleAccountsView: View {
    @State internal var config: AIConfiguration = AISettingsStore.shared.loadConfiguration()
    /// Profile đã có snapshot phiên trong Keychain.
    @State internal var snapshotProfileIds: Set<String> = []
    @State internal var busyProfileId: String?
    @State internal var errorMessage: String?

    public init() {}

    internal var accounts: [AIProviderProfile] {
        config.profiles.filter { $0.isGoogleAIMode }
    }

    public var body: some View {
        Form {
            Section(header: Text("Thứ Tự Xoay Vòng Khi Bị Giới Hạn"), footer: Text(rotationFooter)) {
                if accounts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Chưa có tài khoản nào.")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Thêm một tài khoản bên dưới — app tạo profile \"Chế độ AI của Google\" tương ứng.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(accounts) { profile in
                        accountRow(profile)
                    }
                    .onMove(perform: moveAccounts)
                }
            }

            Section {
                Button(action: addAccount) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Thêm tài khoản Google")
                    }
                    .font(.subheadline)
                }
                .disabled(busyProfileId != nil)
            } footer: {
                Text("Thêm tài khoản = lưu phiên tài khoản đang đăng nhập vào profile hiện tại → xoá cookie Google → mở trang đăng nhập; đăng nhập xong thì lưu phiên vào profile mới. Huỷ giữa chừng thì phiên cũ được khôi phục.")
            }

            if let errorMessage {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }

            Section {
                Text("Trình duyệt bypass và Gemini Web cũng chuyển sang tài khoản đang dùng — cả app chỉ có một tài khoản Google tại một thời điểm. Giao thức web không chính thức: Google đổi là có thể hỏng.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Tài khoản Google")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: AISettingsStore.didChangeNotification)) { _ in
            config = AISettingsStore.shared.loadConfiguration()
            refreshSnapshotFlags()
        }
    }

    internal var rotationFooter: String {
        guard accounts.count > 1 else {
            return "Chỉ có một tài khoản: bị Google giới hạn thì app chờ 1 → 2 → 4 → 8 phút rồi quét tiếp. Thêm tài khoản thứ hai để app tự chuyển khi bị giới hạn."
        }
        return "Bị Google giới hạn số câu trả lời AI ⇒ tự chuyển sang tài khoản kế tiếp theo thứ tự này và ghi vào Cài đặt. Hết tất cả ⇒ chờ 1 → 2 → 4 → 8 phút."
    }

    @ViewBuilder
    private func accountRow(_ profile: AIProviderProfile) -> some View {
        let hasSession = snapshotProfileIds.contains(profile.id)
        Button {
            login(profile)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        if profile.id == config.activeProfileId {
                            Text("Đang dùng")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }
                    if hasSession {
                        Text("Chế độ AI · đã lưu phiên")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Chưa gắn phiên — bấm để đăng nhập")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Spacer()
                if busyProfileId == profile.id {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busyProfileId != nil)
    }
}
