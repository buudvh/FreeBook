import SwiftUI

/// Sheet toàn cục dùng chung giữa Widget TTS và mọi màn hình.
/// Bọc TTSSettingsView trong NavigationStack để NavigationLink
/// bên trong hoạt động đúng như khi điều hướng từ Settings tab.
struct TTSSettingsSheet: View {
    @ObservedObject private var ttsManager = TTSManager.shared

    var body: some View {
        NavigationStack {
            TTSSettingsView(isPresentedAsSheet: true)
        }
    }
}
