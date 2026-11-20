import SwiftUI

/// Danh sách giọng của sheet chọn giọng **vtts Việt–Anh** (2026-11-20, mockup anh Bửu duyệt): 2 hàng `VttsVoice.allCases`
/// — tên, dòng phụ `detail`, badge Nhẹ, ▶ thử giọng (`TTSVoicePreviewPlayer`, đường `VttsTTSService`). **Không** có tải /
/// xoá: dữ liệu đóng sẵn trong app. Chạm hàng = chọn giọng qua `TTSManager.selectVttsVoice` — trình đọc là vtts thì đổi
/// giọng trình đọc, không thì chỉ lưu cho giọng dự phòng (mở từ màn Giọng dự phòng).
struct VttsVoicePickerList: View {
    /// Chữ ô tìm (chưa chuẩn hoá).
    let query: String

    @ObservedObject private var ttsManager = TTSManager.shared
    /// Giọng đang chọn. `@State` vì chọn cho giọng dự phòng chỉ ghi `UserDefaults` (không quan sát được) ⇒ dấu ✓ phải tự
    /// đổi; đọc lại mỗi lần danh sách hiện (bài học 1.3.456).
    @State private var selected = VttsVoice.resolve(TTSManager.storedVttsVoice)

    var body: some View {
        let normalized = VoiceNameSearch.normalize(query)
        let voices = VttsVoice.allCases.filter { VoiceNameSearch.matches($0.displayName, normalizedQuery: normalized) }
        List {
            Group {
                if voices.isEmpty {
                    TTSVoiceNoMatchSection(query: query)
                } else {
                    Section("Có sẵn trong app") {
                        ForEach(voices) { voice in row(voice) }
                    }
                }
            }
            .glassSheetRows()
        }
        .onAppear { selected = ttsManager.vttsDisplayedVoice() }
    }

    private func row(_ voice: VttsVoice) -> some View {
        let key = "vtts:\(voice.rawValue)"
        return TTSVoiceListRow(
            name: voice.displayName,
            detail: voice.detail,
            isReady: true,
            isSelected: selected == voice,
            primary: TTSVoicePreviewPlayer.shared.isActive(key) ? .stop : .play,
            badge: .light,
            onPrimary: { TTSVoicePreviewToggle.toggle(key: key, request: .vtts(voiceId: voice.rawValue)) },
            onSelect: { select(voice) }
        )
    }

    private func select(_ voice: VttsVoice) {
        guard selected != voice else { return }
        selected = voice
        ttsManager.selectVttsVoice(voice)
    }
}
