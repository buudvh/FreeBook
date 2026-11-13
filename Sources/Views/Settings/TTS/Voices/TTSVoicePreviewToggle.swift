import Foundation

/// Nút ▶ / ■ của sheet chọn giọng chung: giọng đang thử ⇒ dừng; còn lại ⇒ thử. Bị chặn vì truyện đang phát thì báo bằng
/// toast — cùng câu với sheet VieNeu (Service không gọi toast).
enum TTSVoicePreviewToggle {
    @MainActor
    static func toggle(key: String, request: TTSVoicePreviewPlayer.Request) {
        let preview = TTSVoicePreviewPlayer.shared
        if preview.isActive(key) {
            preview.stop()
            return
        }
        if preview.play(request, key: key) == .blockedByReader {
            ToastManager.shared.show(message: "Đang phát truyện. Dừng phát rồi thử giọng.", type: .info)
        }
    }
}
