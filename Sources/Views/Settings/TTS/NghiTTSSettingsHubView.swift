import SwiftUI
import AVFoundation

/// Hub **"Cài đặt NghiTTS"** — một chỗ cho mọi thứ thuộc engine NghiTTS.
///
/// Thiết kế theo khuôn `VieNeuTTSTestView`: **phần thử giọng nằm ngay trong màn** (không còn nav riêng) cộng
/// các lối vào quản lý. Trước lượt này tab Cài đặt có **3 nav rời** (`TTSSettingsSection.swift:14-28`) và
/// phần thử giọng nằm sau thêm một nav nữa trong "Cấu hình NghiTTS" — vào được nhưng phải nhớ đường.
///
/// ## Vì sao phải tách `+Sections`
/// `NghiTTSTextToolView` cũ bọc **cả một `Form`**, mà `Form` **không lồng được trong `Form`** — nhúng
/// nguyên view vào đây sẽ ra UI sai. Nội dung được chuyển thành các `Section` rời, đúng khuôn
/// `VieNeuTTSTestView+Sections`.
///
/// Dùng lại **đúng** `TTSManager.shared.nghiTTSService` chứ không tạo service riêng: một service mới nghĩa
/// là một `ORTSession` thứ hai nằm trong RAM và một đường tổng hợp không đi qua `PiperSynthesisCoordinator`
/// — trái với bất biến "chỉ một operation tổng hợp tại một thời điểm".
struct NghiTTSSettingsHubView: View {
    @State var text = "Xin chào, đây là bản thử giọng đọc."
    @State var speed: Double = 1.0
    @State var selectedVoice = ""
    @State var isSynthesizing = false
    @State var statusMessage = ""
    @State var isError = false
    @State var player: AVAudioPlayer?
    @State var synthesisTask: Task<Void, Never>?

    /// `ModelStore.init` có thể throw (không dựng được thư mục model); khi đó coi như chưa có giọng.
    let voices: [String] = (try? ModelStore())?.getLocalVoiceIDs() ?? []

    var isBlockedByPlayback: Bool {
        TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget
    }

    var canPlay: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedVoice.isEmpty
            && !isSynthesizing
            && !isBlockedByPlayback
    }

    var body: some View {
        Form {
            managementSection
            textSection
            voiceSection
            speedSection
            playSection
            resultSection
        }
        .tint(.white)
        .navigationTitle("Cài đặt NghiTTS")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadStoredSettings)
        .onDisappear(perform: stopSample)
    }
}
