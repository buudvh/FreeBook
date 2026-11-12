import Foundation
import Observation

/// Mục **"Tạo giọng Turbo từ file"** của màn thử VieNeu Turbo (1.3.893): chạy `VieNeuTurboVoiceCloneCoordinator` trên một
/// file chọn từ Files, báo thời gian từng bước + số khung + RAM, giữ file trung gian để chia sẻ đối chiếu với script
/// Python (`Scripts/vieneu_turbo_clone_reference.py`), rồi cho đọc thử bằng giọng vừa tạo (chọn giọng đó ở màn thử và
/// gọi "Đọc thử một lần" của `VieNeuTurboLab`).
///
/// Không phải giao diện người dùng cuối — màn tạo / chọn giọng thật làm sau theo mockup, gọi thẳng coordinator +
/// `VieNeuTurboCustomVoiceRepository`.
@MainActor
@Observable
final class VieNeuTurboCloneTrial {
    /// Khử nhiễu mẫu trước khi nhân bản (mặc định bật, như upstream). View gọi `refreshReadiness()` khi đổi (tắt chỉ cần
    /// `speaker_encoder.onnx`) — không dùng `didSet` trên thuộc tính của lớp `@Observable`.
    var denoise = true
    var name = ""
    var isPickingFile = false

    private(set) var sampleURL: URL?
    /// Lý do chưa tạo được (thiếu audio.cpp / model / gói nhân bản) — `nil` khi đủ.
    private(set) var readinessMessage: String?
    private(set) var statusMessage = ""
    private(set) var isError = false
    private(set) var report = ""
    private(set) var createdVoiceId: String?
    /// Đoạn sau cắt im lặng + 8 giây (tần số gốc) và buffer đưa audio.cpp (44,1 kHz khi khử nhiễu) — WAV 16-bit.
    private(set) var trimmedAudioURL: URL?
    private(set) var processedAudioURL: URL?

    var coordinator: VieNeuTurboVoiceCloneCoordinator { .shared }
    var isRunning: Bool { coordinator.isRunning }

    var createdVoiceFiles: (referenceCodes: URL, speakerEmbedding: URL)? {
        createdVoiceId.flatMap { VieNeuTurboCustomVoiceRepository.shared.voiceFiles(id: $0) }
    }

    /// Gọi khi vào màn (`VieNeuTurboLab.refreshStatus`), khi lượt tải gói xong và khi đổi công tắc khử nhiễu.
    func refreshReadiness() {
        readinessMessage = VieNeuTurboVoiceCloneCoordinator.readinessError(denoise: denoise)?.localizedDescription
    }

    /// URL từ `DocumentPickerPresenter` (`asCopy`) — đã nằm trong thư mục tạm của app.
    func acceptPickedFile(_ url: URL) {
        sampleURL = url
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = url.deletingPathExtension().lastPathComponent
        }
        statusMessage = ""
        isError = false
    }

    func canRun(labIsBusy: Bool) -> Bool {
        sampleURL != nil && !isRunning && !labIsBusy && readinessMessage == nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func run(lab: VieNeuTurboLab) {
        guard let sampleURL, canRun(labIsBusy: lab.isBusy) else { return }
        lab.stopSample()
        statusMessage = ""
        isError = false
        report = ""
        let denoise = self.denoise
        let name = self.name
        Task { [weak self] in
            do {
                let outcome = try await VieNeuTurboVoiceCloneCoordinator.shared.createVoice(
                    fromFile: sampleURL,
                    name: name,
                    denoise: denoise,
                    keepsSample: true,
                    keepsIntermediate: true
                )
                guard let self else { return }
                createdVoiceId = outcome.record.id
                writeIntermediateAudio(outcome.prepared)
                report = Self.reportText(outcome, sampleName: sampleURL.lastPathComponent)
                statusMessage = "Đã tạo giọng “\(outcome.record.name)” (\(outcome.record.id)) — \(outcome.encoding.frames) khung."
                lab.refreshStatus()
            } catch {
                guard let self else { return }
                isError = true
                statusMessage = "Tạo giọng thất bại: \(error.localizedDescription)"
            }
        }
    }

    /// Chọn giọng vừa tạo ở màn thử rồi đọc thử câu mẫu (dùng chung "Đọc thử một lần").
    func readWithCreatedVoice(lab: VieNeuTurboLab) {
        guard let createdVoiceId, VieNeuTurboCustomVoiceRepository.shared.voice(id: createdVoiceId) != nil else { return }
        lab.selectedVoiceId = createdVoiceId
        lab.readSampleOnce() // tự chặn khi chưa chạy được (`canRunTurbo`)
    }

    /// Thân file `.txt` chia sẻ (đầu file do `VieNeuTurboReportFile` thêm).
    func reportFileText() -> String {
        [statusMessage, report].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    // MARK: - Nội bộ

    private func writeIntermediateAudio(_ prepared: VieNeuTurboReferencePreparer.Prepared) {
        let fileManager = FileManager.default
        for url in [trimmedAudioURL, processedAudioURL].compactMap({ $0 }) {
            try? fileManager.removeItem(at: url)
        }
        let stamp = Int(Date().timeIntervalSince1970)
        trimmedAudioURL = prepared.trimmedSamples.flatMap {
            Self.writeWAV($0, sampleRate: prepared.sourceSampleRate, name: "vieneu-turbo-clone-\(stamp)-trimmed.wav")
        }
        let processedName = prepared.isDenoised ? "denoised" : "processed"
        processedAudioURL = Self.writeWAV(
            prepared.samples,
            sampleRate: prepared.sampleRate,
            name: "vieneu-turbo-clone-\(stamp)-\(processedName).wav"
        )
    }

    private static func writeWAV(_ samples: [Float], sampleRate: Double, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let data = WAVEncoder.encodePCM16(samples: samples, sampleRate: Int(sampleRate.rounded()), channels: 1)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    private static func reportText(_ outcome: VieNeuTurboVoiceCloneCoordinator.Outcome, sampleName: String) -> String {
        let prepared = outcome.prepared
        let timings = prepared.timings
        let encoding = outcome.encoding
        let ms = { (value: Double) in String(format: "%.0f ms", value) }
        let seconds = { (value: Double) in String(format: "%.2f s", value) }
        let modelLoad = encoding.modelLoadMs.map { "nạp model \(ms($0))" } ?? "model nạp sẵn"
        let cleanup = encoding.sessionRebuildMs.map { "dựng lại session \(ms($0))" } ?? "nhả model"
        return """
        mẫu           \(sampleName) · đọc \(seconds(prepared.decodedSeconds)) · \(Int(prepared.sourceSampleRate)) Hz
        cắt im lặng   đầu \(seconds(prepared.leadingTrimSeconds)) · cuối \(seconds(prepared.trailingTrimSeconds)) → dùng \(seconds(prepared.durationSeconds))
        khử nhiễu     \(prepared.isDenoised ? "bật" : "tắt") · buffer \(Int(prepared.sampleRate)) Hz
        giọng         \(outcome.record.id) · \(encoding.frames) khung × \(encoding.codeGroups) mã
        đọc file      \(ms(timings.decodeMs))
        cắt           \(ms(timings.trimMs))
        nạp graph     \(ms(timings.loadGraphsMs))
        khử nhiễu     \(prepared.isDenoised ? ms(timings.denoiseMs) : "-")
        embedding     \(ms(timings.embeddingMs))
        mã hoá        \(ms(encoding.encodeMs)) (audio.cpp · \(modelLoad) · \(cleanup))
        tổng          \(ms(outcome.totalMs))
        RAM đầu lượt  \(outcome.memoryStart)
        RAM sau ORT   \(outcome.memoryAfterPreparation)
        RAM trước mã  \(encoding.memoryBefore)
        RAM sau mã    \(encoding.memoryAfterEncode)
        RAM sau dọn   \(encoding.memoryAfterCleanup)
        nhiệt         \(VieNeuTurboSoakStats.thermalName(ProcessInfo.processInfo.thermalState))
        thư viện      \(VieNeuTurboRuntime.versionDescription)
        """
    }
}
