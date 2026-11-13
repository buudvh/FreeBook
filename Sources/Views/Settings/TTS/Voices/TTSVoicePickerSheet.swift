import SwiftUI

/// **Sheet chọn giọng** của Siri / NghiTTS / Google / tiện ích TTS — cùng vỏ với `VieNeuVoicePickerSheet`: tiêu đề "Giọng
/// đọc" + nút "?" (giải thích theo trình đọc), ô "Tìm theo tên giọng" (`VoiceNameSearch`: bỏ dấu, "đ" = "d"), danh sách
/// kính. Mỗi trình đọc một danh sách riêng (`SiriVoicePickerList`, `NghiVoicePickerList`, `GoogleVoicePickerList`,
/// `ExtensionVoicePickerList`) — mỗi cái tự giữ `List` và hộp thoại của nó.
///
/// Thử giọng qua `TTSVoicePreviewPlayer`; sheet đóng thì dừng câu thử (`finishSession`).
struct TTSVoicePickerSheet: View {
    let engine: TTSVoiceEngine

    @State private var query = ""

    private var preview: TTSVoicePreviewPlayer { .shared }

    var body: some View {
        NavigationStack {
            content
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm theo tên giọng")
                .pageTitle("Giọng đọc", help: engine.helpText)
        }
        .onDisappear { preview.finishSession() }
        .onChange(of: preview.failureToken) { _, _ in
            ToastManager.shared.show(message: preview.failureMessage, type: .error)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch engine {
        case .siri:
            SiriVoicePickerList(query: query)
        case .nghi:
            NghiVoicePickerList(query: query)
        case .google:
            GoogleVoicePickerList(query: query)
        case .ext(let packageId):
            ExtensionVoicePickerList(packageId: packageId, query: query)
        }
    }
}

extension View {
    /// Trình bày sheet chọn giọng chung (kính, vuốt xuống đóng) cho trình đọc `engine` — `nil` ⇒ đóng.
    func ttsVoicePickerSheet(engine: Binding<TTSVoiceEngine?>, onDismiss: (() -> Void)? = nil) -> some View {
        sheet(item: engine, onDismiss: onDismiss) { engine in
            Group {
                TTSVoicePickerSheet(engine: engine)
                    .presentationDragIndicator(.visible)
            }
            .appGlassSheet()
        }
    }
}
