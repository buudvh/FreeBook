import SwiftUI

struct TelegramBackupSettingsView: View {
    @State private var token = ""
    @State private var chatID = TelegramConfiguration.chatID
    @State private var hasStoredToken = TelegramTokenStore.hasToken
    @State private var isChecking = false

    var body: some View {
        Form {
            Section {
                SecureField(hasStoredToken ? "Bot Token đã lưu (để trống nếu giữ nguyên)" : "Bot Token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Chat ID, ví dụ -100… hoặc @channel", text: $chatID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    saveAndCheck()
                } label: {
                    if isChecking {
                        HStack { ProgressView(); Text("Đang kiểm tra…") }
                    } else {
                        Label("Lưu và kiểm tra kết nối", systemImage: "checkmark.shield")
                    }
                }
                .disabled(isChecking || chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || (!hasStoredToken && token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            } header: {
                Text("Telegram Bot")
            } footer: {
                Text("Bot phải có quyền gửi tài liệu vào chat. Nút kiểm tra chỉ gọi getMe và getChat, không gửi tin nhắn. Bot Token được giữ trong Keychain và không nằm trong backup.")
            }

            if hasStoredToken || !TelegramConfiguration.chatID.isEmpty {
                Section {
                    Button("Xoá cấu hình Telegram", role: .destructive) {
                        TelegramConfiguration.clear()
                        token = ""
                        chatID = ""
                        hasStoredToken = false
                        ToastManager.shared.show(message: "Đã xoá cấu hình Telegram", type: .success)
                    }
                }
            }
        }
        .navigationTitle("Telegram")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveAndCheck() {
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TelegramTokenStore.save(token)
            token = ""
            hasStoredToken = TelegramTokenStore.hasToken
        }
        TelegramConfiguration.chatID = chatID
        isChecking = true
        Task {
            do {
                let message = try await TelegramBotClient.shared.validateConfiguration()
                ToastManager.shared.show(message: message, type: .success)
            } catch {
                ToastManager.shared.show(message: error.localizedDescription, type: .error)
            }
            isChecking = false
        }
    }
}
