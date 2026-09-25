import SwiftUI

/// Các thành phần UI và xử lý OAuth cho AISettingsView.
extension AISettingsView {
    @ViewBuilder
    internal var oauthAuthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tài khoản OpenAI (OAuth)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let email = config.activeProfile.accountEmail, !email.isEmpty {
                HStack {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(email)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if config.activeProfile.isOAuthLoggedIn {
                            Text("Đã đăng nhập • Phiên hoạt động")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button("Đổi tài khoản") {
                        showingOpenAIOAuthSheet = true
                    }
                    .font(.caption)
                }
                .padding(.vertical, 2)

                Button(role: .destructive, action: logoutOAuth) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Đăng xuất tài khoản")
                    }
                    .font(.caption)
                }
            } else {
                Button(action: { showingOpenAIOAuthSheet = true }) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.blue)
                        Text("Đăng nhập tài khoản OpenAI")
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Text("Đăng nhập OpenAI bằng PKCE trực tiếp để sử dụng tài khoản ChatGPT của bạn.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    internal func logoutOAuth() {
        var p = config.activeProfile
        p.apiKey = ""
        p.refreshToken = nil
        p.tokenExpiresAt = nil
        p.accountEmail = nil
        config.updateActiveProfile(p)
        AISettingsStore.shared.saveConfiguration(config)
        testResultMessage = "Đã đăng xuất tài khoản OAuth."
        isTestSuccess = true
    }
}
