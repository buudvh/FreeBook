import SwiftUI

extension TTSSettingsView {
    internal var numberPreprocessingSection: some View {
        Section(header: Text("Tiền Xử Lý Số Rời Rạc (VD: 10 1000)")) {
            Picker("Chế độ ngắt số", selection: Binding(
                get: { TTSNumberSeparatorMode.current },
                set: { TTSNumberSeparatorMode.current = $0 }
            )) {
                ForEach(TTSNumberSeparatorMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Text("Tự động chèn dấu ngắt giữa các cụm số như '10 1000' hoặc '10-1000' để tránh TTS đọc ghép thành một số liền.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
