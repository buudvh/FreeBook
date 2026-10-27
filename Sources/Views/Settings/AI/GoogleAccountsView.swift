import SwiftUI

/// Màn **Tài khoản Google** (1.3.616) — danh sách tài khoản của **một provider** Chế độ AI.
///
/// Thứ tự dòng **chính là** thứ tự xoay vòng khi Google giới hạn số câu trả lời AI: bị giới hạn thì app tráo sang tài
/// khoản kế tiếp (`GoogleAccountRotation`), hết tài khoản mới chuyển Gemini Web rồi mới chờ. Kéo ≡ để đổi thứ tự.
///
/// Chỉ có **một** kho cookie Google trong app (iOS không có `WKWebsiteDataStore(forIdentifier:)`) ⇒ chạm một dòng là tráo
/// cookie sang tài khoản đó, và cả app — kể cả Gemini Web lẫn trình duyệt bypass — chuyển theo.
public struct GoogleAccountsView: View {
    @State internal var config: AIConfiguration = AISettingsStore.shared.loadConfiguration()
    @State internal var accounts: [GoogleAccount] = []
    @State internal var currentAccountId: String?
    @State internal var busyAccountId: String?
    @State internal var errorMessage: String?
    @State internal var draftLabel: String = ""
    @State internal var showingNameAlert = false
    /// `nil` = hộp tên đang dùng để **thêm** tài khoản mới; khác `nil` = đổi tên tài khoản này.
    @State internal var renamingAccount: GoogleAccount?

    public init() {}

    /// Provider đang hiển thị: provider đang chọn nếu nó là Chế độ AI, không thì provider Chế độ AI đầu tiên.
    internal var displayProfile: AIProviderProfile? {
        if config.activeProfile.isGoogleAIMode { return config.activeProfile }
        return config.profiles.first(where: { $0.isGoogleAIMode })
    }

    public var body: some View {
        Form {
            Section(header: Text("Thứ Tự Xoay Vòng Khi Bị Giới Hạn"), footer: Text(rotationFooter)) {
                if let displayProfile {
                    Text("Provider: \(displayProfile.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if accounts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Chưa có tài khoản nào.")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Bấm \"Thêm tài khoản Google\" bên dưới để đăng nhập tài khoản đầu tiên.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(accounts) { account in
                        accountRow(account)
                    }
                    .onMove(perform: moveAccounts)
                }
            }

            Section {
                Button(action: startAddAccount) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Thêm tài khoản Google")
                    }
                    .font(.subheadline)
                }
                .disabled(busyAccountId != nil || displayProfile == nil)
            } footer: {
                Text("Thêm tài khoản = lưu phiên tài khoản đang đăng nhập vào provider này → xoá cookie Google → mở trang đăng nhập; đăng nhập xong thì lưu thành tài khoản mới. Huỷ giữa chừng thì phiên cũ được khôi phục.")
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
                Text("Cả app chỉ có một tài khoản Google tại một thời điểm (giới hạn của iOS): chạm một tài khoản là tráo phiên cho cả Chế độ AI, Gemini Web và trình duyệt bypass. Giao thức web không chính thức — Google đổi là có thể hỏng.")
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
            reloadAccounts()
        }
        .alert(renamingAccount == nil ? "Thêm tài khoản Google" : "Đổi tên tài khoản", isPresented: $showingNameAlert) {
            TextField("Tên tài khoản", text: $draftLabel)
            Button("Huỷ", role: .cancel) { renamingAccount = nil }
            Button("Tiếp tục") { confirmName() }
        } message: {
            Text(renamingAccount == nil
                 ? "Đặt tên để phân biệt các tài khoản (ví dụ \"acc chính\", \"acc phụ\")."
                 : "Tên chỉ để hiển thị trong app.")
        }
    }

    internal var rotationFooter: String {
        guard accounts.count > 1 else {
            return "Chỉ có một tài khoản: bị Google giới hạn thì app chờ 1 → 2 → 4 → 8 phút rồi quét tiếp. Thêm tài khoản thứ hai để app tự chuyển khi bị giới hạn."
        }
        return "Bị Google giới hạn số câu trả lời AI ⇒ tự chuyển sang tài khoản kế tiếp theo thứ tự này. Hết tất cả ⇒ chuyển Gemini Web (nếu có), rồi chờ 1 → 2 → 4 → 8 phút."
    }

    @ViewBuilder
    private func accountRow(_ account: GoogleAccount) -> some View {
        Button {
            useAccount(account)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(account.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        if account.id == currentAccountId {
                            Text("Đang dùng")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }
                    Text("Đã lưu phiên · \(account.cookies.count) cookie")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if busyAccountId == account.id {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busyAccountId != nil)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteAccount(account)
            } label: {
                Label("Xoá", systemImage: "trash")
            }
            Button {
                startRename(account)
            } label: {
                Label("Đổi tên", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}
