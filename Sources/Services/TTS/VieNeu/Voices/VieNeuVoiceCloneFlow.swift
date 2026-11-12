import AVFoundation
import Foundation
import Observation

/// Trạng thái + luồng của **sheet nhân bản giọng VieNeu** (1.3.901, mockup anh Bửu duyệt). View chỉ vẽ; thu âm, chọn file,
/// nghe lại mẫu, tải gói và tạo giọng ở đây. Một thực thể mỗi lần mở sheet.
///
/// - **Mẫu**: thu âm (tự dừng ở 8 s, `VieNeuVoiceRecorder`) hoặc file (`DocumentPickerPresenter` ở View, URL đã chép vào
///   thư mục tạm). Đường Nano **giữ nguyên** (`VieNeuTTSService.enrollVoice`, mẫu đưa nguyên văn, không khử nhiễu) nên vẫn
///   đòi mẫu 3–30 giây; Turbo tự cắt im lặng + lấy 8 giây đầu (`VieNeuTurboReferencePreparer`).
/// - **Dùng cho** Nano / Turbo / Cả hai (mặc định model đang đọc). "Cả hai": tạo Nano trước rồi Turbo từ chính mẫu Nano
///   đã lưu (`createVoice(fromNanoVoiceId:)`) ⇒ hai bản liên kết qua `sourceNanoVoiceId`.
/// - **Lưu** (`VieNeuVoiceCloneFlow+Save`): tải gói thiếu (có %) → Nano → Turbo → chọn giọng vừa tạo + đọc thử câu mẫu.
@MainActor
@Observable
final class VieNeuVoiceCloneFlow {
    enum Source: String, CaseIterable, Identifiable {
        case record = "Thu âm"
        case file = "Chọn file"

        var id: String { rawValue }
    }

    enum Target: Hashable {
        case nano
        case turbo
        case both

        var includesNano: Bool { self != .turbo }
        var includesTurbo: Bool { self != .nano }
    }

    /// Một bước của lượt Lưu, để sheet vẽ danh sách bước.
    enum Step: Equatable {
        case downloading
        case nano
        case turbo
    }

    /// Tự dừng thu ở 8 giây — Turbo chỉ dùng 8 giây, Nano khuyên 3–8 giây.
    static let recordLimitSeconds = VieNeuVoiceCloner.recommendedSampleSeconds

    // MARK: Mẫu

    var source: Source = .record
    private(set) var isRecording = false
    private(set) var recordedSeconds: Double = 0
    private(set) var level: Float = -160
    private(set) var sampleURL: URL?
    private(set) var sampleSeconds: Double?
    private(set) var isProbing = false
    private(set) var isPlayingSample = false
    var name = ""

    // MARK: Dùng cho

    /// Đổi xong thì View gọi `refreshMissingBytes()` (không dùng `didSet` trong lớp `@Observable`).
    var target: Target
    var denoise = true
    private(set) var missingBytes: Int64 = 0

    // MARK: Lượt lưu (ghi ở `+Save`)

    var isSaving = false
    var step: Step?
    var completedSteps: Set<Step> = []
    /// Mọi đích tải của lượt lưu (cộng tiến độ) / đích do chính lượt lưu khởi tạo (huỷ được).
    var downloadTargets: [String] = []
    var ownedDownloadTargets: [String] = []
    var downloadTotal: Int64 = 0
    var nanoStage: VieNeuVoiceCloner.Stage?
    /// Dòng trạng thái / lỗi của lượt gần nhất (không phải giải thích).
    var statusMessage = ""
    var isError = false
    /// Tăng khi lưu xong — View đóng sheet.
    var finishToken = 0

    let recorder = VieNeuVoiceRecorder()
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var didSave = false

    /// Không đọc đĩa ở đây: SwiftUI dựng lại `init` của sheet mỗi lần màn cha vẽ lại (bỏ bản thừa) — View gọi
    /// `refreshMissingBytes()` ở `onAppear`.
    init(target: Target) {
        self.target = target
    }

    // MARK: - Trạng thái suy ra

    /// Có mẫu chưa lưu — sheet hỏi trước khi vuốt đóng.
    var hasUnsavedWork: Bool { sampleURL != nil || isRecording }

    /// Lý do chưa bấm Lưu được; `nil` = được. Dùng làm dòng trạng thái dưới nút khi thiếu.
    var saveBlockReason: String? {
        if isSaving { return "Đang lưu…" }
        if isProbing { return "Đang đọc file âm thanh…" }
        if isRecording { return "Đang thu âm." }
        guard let seconds = sampleSeconds, sampleURL != nil else { return "Chưa có mẫu giọng." }
        if target.includesTurbo, !VieNeuTurboRuntime.isAvailable {
            return "Bản build này chưa có audio.cpp nên chưa tạo được giọng Turbo — chọn Nano."
        }
        if target.includesNano {
            if seconds < VieNeuVoiceCloner.minimumSampleSeconds {
                return String(format: "Mẫu dài %.1f giây — giọng Nano cần ít nhất %.0f giây.", seconds, VieNeuVoiceCloner.minimumSampleSeconds)
            }
            if seconds > VieNeuVoiceCloner.maximumSampleSeconds {
                return String(format: "Mẫu dài %.0f giây — giọng Nano chỉ nhận tối đa %.0f giây. Chọn Turbo hoặc cắt bớt file.", seconds, VieNeuVoiceCloner.maximumSampleSeconds)
            }
        }
        let trimmedName = name.trimmed
        if trimmedName.isEmpty { return "Nhập tên giọng." }
        // Kiểm trùng tên **trước** khi tải / tạo: "Cả hai" mà trùng tên Turbo thì Nano tạo xong rồi Turbo mới lỗi.
        let directory = VieNeuVoiceDirectory.shared
        if target.includesNano, Self.contains(directory.nanoMine, name: trimmedName) {
            return "Đã có giọng Nano tên “\(trimmedName)”. Đặt tên khác."
        }
        if target.includesTurbo, Self.contains(directory.turboMine, name: trimmedName) {
            return "Đã có giọng Turbo tên “\(trimmedName)”. Đặt tên khác."
        }
        return nil
    }

    var canSave: Bool { saveBlockReason == nil }

    static func contains(_ entries: [VieNeuVoiceEntry], name: String) -> Bool {
        entries.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func refreshMissingBytes() {
        missingBytes = VieNeuClonePackages.missingBytes(nano: target.includesNano, turbo: target.includesTurbo)
    }

    // MARK: - Thu âm

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    /// Gọi mỗi 0,1 s từ View khi đang thu: cập nhật đồng hồ / mức âm, tự dừng ở 8 giây.
    func tick() {
        guard isRecording else { return }
        recordedSeconds = recorder.elapsed
        level = recorder.refreshLevel()
        if recordedSeconds >= Self.recordLimitSeconds { stopRecording() }
    }

    /// Mức âm 0…1 (−60…0 dB) cho thanh mức.
    var levelFraction: Double {
        (max(-60, min(0, Double(level))) + 60) / 60
    }

    private func startRecording() {
        statusMessage = ""
        Task {
            guard await VieNeuVoiceRecorder.requestPermission() else {
                showError(VieNeuVoiceRecorder.RecorderError.permissionDenied.errorDescription ?? "Chưa được cấp quyền micro.")
                return
            }
            // Loa đang phát sẽ lọt vào bản thu. Chỉ tạm dừng khi truyện thật sự đang phát — Cài đặt TTS đã dừng sẵn, gọi
            // `stop()` là mất phiên đọc tiếp lúc đóng Cài đặt.
            if TTSManager.shared.isPlaying { TTSManager.shared.pause() }
            VieNeuVoicePreviewPlayer.shared.stop()
            stopSample()
            discardSample()
            do {
                try recorder.start()
                isRecording = true
                recordedSeconds = 0
                isError = false
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        level = -160
        if let url = recorder.stop() {
            sampleURL = url
            sampleSeconds = recordedSeconds
        } else {
            showError(VieNeuVoiceRecorder.RecorderError.emptyRecording.errorDescription ?? "Bản thu không có dữ liệu.")
        }
    }

    // MARK: - File

    /// URL từ `DocumentPickerPresenter` (`asCopy`) — đã nằm trong thư mục tạm của app. Đọc độ dài ngoài main.
    func acceptPickedFile(_ url: URL) {
        stopSample()
        discardSample()
        isProbing = true
        statusMessage = ""
        Task {
            let seconds = await Task.detached(priority: .userInitiated) { () -> Double? in
                guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
                return Double(file.length) / file.fileFormat.sampleRate
            }.value
            isProbing = false
            guard let seconds, seconds > 0 else {
                Self.removeIfTemporary(url)
                showError("Không đọc được file âm thanh này.")
                return
            }
            sampleURL = url
            sampleSeconds = seconds
        }
    }

    // MARK: - Nghe lại mẫu

    func toggleSamplePlayback() {
        if isPlayingSample {
            stopSample()
            return
        }
        guard let sampleURL else { return }
        VieNeuVoicePreviewPlayer.shared.stop()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: sampleURL)
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            isPlayingSample = true
            // Không cần delegate: đặt hẹn tắt cờ theo độ dài mẫu.
            let duration = newPlayer.duration
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((duration + 0.2) * 1_000_000_000))
                guard let self, self.player === newPlayer else { return }
                self.stopSample()
            }
        } catch {
            showError("Phát mẫu thất bại: \(error.localizedDescription)")
        }
    }

    func stopSample() {
        player?.stop()
        player = nil
        isPlayingSample = false
    }

    // MARK: - Dọn

    /// Sheet đóng: dừng thu / phát, huỷ lượt Lưu dở; chưa lưu thì xoá mẫu tạm.
    ///
    /// Đang lưu mà bỏ: `enrollVoice` / `createVoice(fromFile:)` có thể **còn đọc** file mẫu (ORT / audio.cpp không dừng giữa
    /// chừng) ⇒ chỉ xoá mẫu tạm sau khi lượt lưu dở kết thúc hẳn.
    func cleanUp() {
        stopSample()
        if isRecording {
            isRecording = false
            _ = recorder.stop()
        }
        if isSaving, let running = saveTask {
            let sample = didSave ? nil : sampleURL
            cancelSave()
            sampleURL = nil
            sampleSeconds = nil
            if let sample {
                Task {
                    await running.value
                    Self.removeIfTemporary(sample)
                }
            }
            return
        }
        if !didSave { discardSample() }
    }

    func markSaved() {
        didSave = true
    }

    func discardSample() {
        if let sampleURL { Self.removeIfTemporary(sampleURL) }
        sampleURL = nil
        sampleSeconds = nil
    }

    func showError(_ message: String) {
        isError = true
        statusMessage = message
    }

    /// Chỉ xoá file trong thư mục tạm của app — URL ngoài sandbox là file gốc của người dùng.
    static func removeIfTemporary(_ url: URL) {
        guard url.path.hasPrefix(FileManager.default.temporaryDirectory.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
