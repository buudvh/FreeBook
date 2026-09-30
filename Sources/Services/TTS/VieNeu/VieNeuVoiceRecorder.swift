import AVFoundation
import Foundation

/// Thu âm audio mẫu để nhân bản giọng.
///
/// Ba việc **bắt buộc**, mỗi việc ứng với một bẫy thật — không việc nào là "cho chắc":
///
/// 1. **Xin quyền micro** (`AVAudioApplication.requestRecordPermission`). App chưa từng xin quyền này, và
///    thiếu `NSMicrophoneUsageDescription` trong `Info.plist` thì iOS **kill app** ngay khi phiên âm thanh
///    chạm tới input — không phải chỉ trả `false` rồi thôi.
/// 2. **Đổi `AVAudioSession` sang `.playAndRecord` rồi khôi phục `.playback` + `.spokenAudio`**:
///    `TTSAudioSessionController.configureAudioSession()` đặt `.playback`, mà `.playback` **không thu
///    được**. Quên khôi phục thì TTS đọc truyện mất tiếng ở **mọi lượt sau** — một lỗi hoàn toàn khác
///    chỗ với nguyên nhân, và chỉ lộ ra ở lần bấm Phát kế tiếp.
/// 3. **Dừng TTS trước khi thu.** Chung một phiên âm thanh, và loa đang phát sẽ lọt thẳng vào bản thu.
///    Việc dừng do **bên gọi** làm (`TTSManager.shared.stop()`), không nằm ở đây — lớp này không phụ
///    thuộc `TTSManager`.
///
/// Định dạng đầu ra là `.m4a` (AAC) trong thư mục tạm; bên gọi chuyển nó cho `VieNeuCustomVoiceStore`
/// để copy vào `CustomVoices/samples/`.
@MainActor
final class VieNeuVoiceRecorder {
    enum RecorderError: LocalizedError {
        case permissionDenied
        case sessionUnavailable(String)
        case cannotStart(String)
        case emptyRecording

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Chưa được cấp quyền micro. Mở Cài đặt ▸ Quyền riêng tư ▸ Micro để bật cho ứng dụng."
            case .sessionUnavailable(let reason):
                return "Không đổi được phiên âm thanh sang chế độ thu: \(reason)"
            case .cannotStart(let reason):
                return "Không bắt đầu thu được: \(reason)"
            case .emptyRecording:
                return "Bản thu không có dữ liệu."
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private var destinationURL: URL?

    var isRecording: Bool { recorder?.isRecording ?? false }

    /// Số giây đã thu. `0` khi chưa thu.
    var elapsed: TimeInterval { recorder?.currentTime ?? 0 }

    /// Mức tín hiệu gần nhất (dB, thường −160…0) — UI dùng để vẽ thanh nhịp cho người dùng biết mic có
    /// thu được gì không. Thu **im lặng** là kiểu hỏng hay gặp nhất khi thu âm.
    func refreshLevel() -> Float {
        guard let recorder, recorder.isRecording else { return -160 }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }

    /// Hỏi quyền micro. Trả `true` nếu đã được cấp.
    static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    /// Bắt đầu thu. Bên gọi **phải** đã dừng TTS trước (xem doc của type).
    func start() throws {
        guard recorder == nil else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            // `.defaultToSpeaker` để không bị định tuyến vào tai nghe nhỏ khi không cắm gì; `.allowBluetooth`
            // để dùng được tai nghe bluetooth có micro.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            throw RecorderError.sessionUnavailable(error.localizedDescription)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vieneu-sample-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let newRecorder: AVAudioRecorder
        do {
            newRecorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            restorePlaybackSession()
            throw RecorderError.cannotStart(error.localizedDescription)
        }
        // Bật đo mức tín hiệu — `refreshLevel()` cần nó, và mặc định là tắt.
        newRecorder.isMeteringEnabled = true
        guard newRecorder.record() else {
            restorePlaybackSession()
            throw RecorderError.cannotStart("AVAudioRecorder.record() trả về false")
        }
        recorder = newRecorder
        destinationURL = url
    }

    /// Dừng thu, khôi phục phiên âm thanh về `.playback`, và trả về file vừa thu (`nil` nếu rỗng).
    @discardableResult
    func stop() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        self.recorder = nil
        restorePlaybackSession()

        let url = destinationURL
        destinationURL = nil
        guard let url else { return nil }
        let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        guard size > 0 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    /// Xoá bản thu tạm (khi người dùng nghe lại thấy không ổn và thu lại).
    func discard() {
        if let url = stop() { try? FileManager.default.removeItem(at: url) }
    }

    /// Trả phiên âm thanh về đúng cấu hình chuẩn của app (`.playback` + `.spokenAudio`).
    ///
    /// Gọi thẳng `TTSAudioSessionController` thay vì tự `setCategory` để **chỉ có một nguồn sự thật** cho
    /// cấu hình phiên âm thanh của TTS — tự đặt lại ở đây là mở đường cho hai chỗ lệch nhau.
    private func restorePlaybackSession() {
        _ = TTSAudioSessionController().configureAudioSession()
    }
}
