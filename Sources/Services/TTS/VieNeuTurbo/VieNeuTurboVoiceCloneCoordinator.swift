import Foundation
import Observation

/// Chủ **luồng tạo giọng VieNeu Turbo** từ một mẫu âm thanh (1.3.892): kiểm điều kiện → chuẩn bị mẫu + speaker embedding
/// (ORT, `VieNeuTurboReferencePreparer`) → mã tham chiếu (audio.cpp, `VieNeuTurboRuntime.encodeReference`) → ghi giọng
/// (`VieNeuTurboCustomVoiceStore`) → làm mới `VieNeuTurboCustomVoiceRepository`.
///
/// API cho sheet nhân bản giọng (`VieNeuVoiceCloneFlow`, nút "Tạo bản Turbo") và màn thử Turbo:
/// - `createVoice(fromFile:name:denoise:keepsSample:)` — file âm thanh bất kỳ iOS đọc được; `keepsSample` giữ **đoạn đã
///   cắt** (≤ 8 giây, WAV) chứ không chép cả file
/// - `createVoice(fromNanoVoiceId:name:denoise:)` — dùng lại mẫu gốc của một giọng Nano tự tạo
/// - `isRunning`, `stage` — để vẽ tiến trình; `Stage` không mang chữ hiển thị (chữ là việc của View)
///
/// Thứ tự giữ đỉnh bộ nhớ thấp: ngữ cảnh ORT (denoiser + speaker_encoder) nhả **trước** khi audio.cpp chạy encoder;
/// audio.cpp xong thì dựng lại session hoặc nhả model (xem `VieNeuTurboRuntime+Encode`).
@MainActor
@Observable
final class VieNeuTurboVoiceCloneCoordinator {
    static let shared = VieNeuTurboVoiceCloneCoordinator()

    enum Stage: Sendable {
        case decoding
        case trimming
        case loadingGraphs
        case denoising
        case embedding
        case encoding
        case saving
    }

    enum CloneError: LocalizedError {
        case alreadyRunning
        case runtimeUnavailable
        case modelMissing
        case clonePackMissing([String])
        case readerBusy
        case nanoVoiceNotFound
        case nanoSampleMissing(String)
        case storeUnavailable

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "Đang tạo một giọng Turbo khác — chờ lượt đó xong."
            case .runtimeUnavailable: return "Bản build này chưa có audio.cpp nên chưa tạo được giọng Turbo."
            case .modelMissing: return "Chưa tải model VieNeu Turbo."
            case .clonePackMissing(let names):
                return "Chưa tải gói nhân bản giọng Turbo (thiếu \(names.joined(separator: ", ")))."
            case .readerBusy:
                return "Trình đọc đang đọc truyện bằng VieNeu Turbo — dừng đọc rồi tạo giọng (hai việc dùng chung model)."
            case .nanoVoiceNotFound: return "Không tìm thấy giọng Nano đã chọn."
            case .nanoSampleMissing(let name): return "Giọng Nano “\(name)” không còn lưu mẫu âm thanh gốc."
            case .storeUnavailable: return "Không dựng được thư mục VieNeu (Application Support không ghi được)."
            }
        }
    }

    /// Kết quả một lượt — `record` để UI chọn giọng ngay; phần còn lại cho màn thử báo số đo.
    struct Outcome: Sendable {
        let record: VieNeuTurboCustomVoiceStore.Record
        let prepared: VieNeuTurboReferencePreparer.Prepared
        let encoding: VieNeuTurboRuntime.ReferenceEncoding
        let totalMs: Double
        let memoryStart: String
        let memoryAfterPreparation: String
    }

    private(set) var isRunning = false
    private(set) var stage: Stage?

    private init() {}

    /// Điều kiện ngoài việc đang chạy: audio.cpp có trong bản build, đủ model Turbo, đủ gói nhân bản.
    static func readinessError(denoise: Bool) -> CloneError? {
        guard VieNeuTurboRuntime.isAvailable else { return .runtimeUnavailable }
        guard let turboStore = try? VieNeuTurboModelStore(), turboStore.hasModel else { return .modelMissing }
        guard let nanoStore = try? VieNeuModelStore() else { return .storeUnavailable }
        let missing = requiredGraphNames(denoise: denoise).filter { !nanoStore.exists($0) }
        return missing.isEmpty ? nil : .clonePackMissing(missing)
    }

    /// Gói nhân bản Turbo (`VieNeuModelStore.turboCloneGraphNames`); tắt khử nhiễu thì chỉ cần `speaker_encoder.onnx`.
    static func requiredGraphNames(denoise: Bool) -> [String] {
        denoise ? VieNeuModelStore.turboCloneGraphNames : ["speaker_encoder.onnx"]
    }

    /// Trình đọc truyện đang phát bằng Turbo ⇒ không tạo giọng: lượt mã hoá chiếm hàng đợi runtime vài giây và chồng
    /// thêm vài trăm MB lên model đang đọc.
    static var isReaderUsingTurbo: Bool {
        let tts = TTSManager.shared
        return tts.tool == "vieneu" && VieNeuModelChoice.current == .turbo && tts.isPlaying
    }

    // MARK: - Tạo giọng

    @discardableResult
    func createVoice(
        fromFile sampleURL: URL,
        name: String,
        denoise: Bool = true,
        keepsSample: Bool = true,
        keepsIntermediate: Bool = false
    ) async throws -> Outcome {
        try await run(
            sampleURL: sampleURL,
            name: name,
            denoise: denoise,
            keepsSample: keepsSample,
            keepsIntermediate: keepsIntermediate,
            sourceNanoVoiceId: nil
        )
    }

    /// Bản Turbo của một giọng Nano tự tạo, từ chính mẫu gốc Nano đã lưu (`VieNeu/CustomVoices/samples/`). Không chép
    /// lại mẫu (đã có ở kho Nano). `name` rỗng ⇒ lấy tên giọng Nano.
    @discardableResult
    func createVoice(fromNanoVoiceId nanoVoiceId: String, name: String? = nil, denoise: Bool = true) async throws -> Outcome {
        guard let nanoModelStore = try? VieNeuModelStore() else { throw CloneError.storeUnavailable }
        let nanoStore = VieNeuCustomVoiceStore(rootURL: nanoModelStore.rootURL)
        guard let record = try nanoStore.record(id: nanoVoiceId) else { throw CloneError.nanoVoiceNotFound }
        guard let sampleURL = nanoStore.sampleURL(for: record) else { throw CloneError.nanoSampleMissing(record.name) }
        let chosenName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try await run(
            sampleURL: sampleURL,
            name: chosenName.isEmpty ? record.name : chosenName,
            denoise: denoise,
            keepsSample: false,
            keepsIntermediate: false,
            sourceNanoVoiceId: record.id
        )
    }

    // MARK: - Nội bộ

    private func run(
        sampleURL: URL,
        name: String,
        denoise: Bool,
        keepsSample: Bool,
        keepsIntermediate: Bool,
        sourceNanoVoiceId: String?
    ) async throws -> Outcome {
        guard !isRunning else { throw CloneError.alreadyRunning }
        if let error = Self.readinessError(denoise: denoise) { throw error }
        guard !Self.isReaderUsingTurbo else { throw CloneError.readerBusy }
        guard let turboStore = try? VieNeuTurboModelStore(), let nanoStore = try? VieNeuModelStore(),
              let store = VieNeuTurboCustomVoiceRepository.shared.store else { throw CloneError.storeUnavailable }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw VieNeuTurboCustomVoiceStore.StoreError.emptyName }
        if VieNeuTurboCustomVoiceRepository.shared.voices.contains(where: {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            throw VieNeuTurboCustomVoiceStore.StoreError.duplicateName(trimmedName)
        }

        isRunning = true
        defer {
            isRunning = false
            stage = nil
        }
        let started = ProcessInfo.processInfo.systemUptime
        let memoryStart = ProcessMemoryProbe.snapshot().summary
        let id = store.makeVoiceId()
        AppLogger.shared.log(
            "🎙️ [VieNeuTurboClone] Bắt đầu tạo giọng \(id) (khử nhiễu: \(denoise ? "bật" : "tắt")) — \(memoryStart)"
        )
        do {
            let staging = try store.makeStagingDirectory(id: id)
            let threads = VieNeuSynthesisPolicy.effectiveThreadCount(from: .standard)
            let stageHandler: @Sendable (VieNeuTurboReferencePreparer.Stage) -> Void = { stage in
                Task { @MainActor in VieNeuTurboVoiceCloneCoordinator.shared.applyPreparerStage(stage) }
            }
            let prepared = try await Task.detached(priority: .userInitiated) {
                try VieNeuTurboReferencePreparer.prepare(
                    sampleURL: sampleURL,
                    denoise: denoise,
                    modelStore: nanoStore,
                    threadCount: threads,
                    keepsIntermediate: keepsIntermediate || keepsSample,
                    onStage: stageHandler
                )
            }.value
            let memoryAfterPreparation = ProcessMemoryProbe.snapshot().summary

            stage = .encoding
            let embeddingURL = staging.appendingPathComponent(VieNeuTurboModelStore.speakerEmbeddingFileName)
            try Data(Self.speakerEmbeddingText(prepared.speakerEmbedding).utf8).write(to: embeddingURL, options: .atomic)
            let encoding = try await VieNeuTurboRuntime.shared.encodeReference(
                samples: prepared.samples,
                sampleRate: prepared.sampleRate,
                speakerEmbeddingURL: embeddingURL,
                modelURL: turboStore.modelURL,
                threads: VieNeuTurboTTSService.threadCount
            )

            stage = .saving
            try Data(encoding.referenceCodesText.utf8).write(
                to: staging.appendingPathComponent(VieNeuTurboModelStore.referenceCodesFileName),
                options: .atomic
            )
            var sampleFileName: String?
            if keepsSample, let trimmed = prepared.trimmedSamples {
                sampleFileName = try store.writeSample(trimmed, sampleRate: prepared.sourceSampleRate, intoStagingOf: id)
            }
            let record = VieNeuTurboCustomVoiceStore.Record(
                id: id,
                name: trimmedName,
                createdAt: Date(),
                frames: encoding.frames,
                isDenoised: prepared.isDenoised,
                sampleSeconds: prepared.durationSeconds,
                sampleFileName: sampleFileName,
                sourceNanoVoiceId: sourceNanoVoiceId
            )
            try store.commit(record)
            VieNeuTurboCustomVoiceRepository.shared.reload()

            let totalMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            AppLogger.shared.log(
                "🎙️ [VieNeuTurboClone] Xong giọng \(id): \(encoding.frames) khung, mẫu \(String(format: "%.2f", prepared.durationSeconds)) s, " +
                "tổng \(String(format: "%.0f", totalMs)) ms — \(ProcessMemoryProbe.snapshot().summary)"
            )
            return Outcome(
                record: record,
                prepared: prepared,
                encoding: encoding,
                totalMs: totalMs,
                memoryStart: memoryStart,
                memoryAfterPreparation: memoryAfterPreparation
            )
        } catch {
            store.discardStaging(id: id)
            AppLogger.shared.log("❌ [VieNeuTurboClone] Tạo giọng \(id) lỗi: \(error.localizedDescription)")
            throw error
        }
    }

    private func applyPreparerStage(_ preparerStage: VieNeuTurboReferencePreparer.Stage) {
        guard isRunning, stage != .encoding, stage != .saving else { return }
        switch preparerStage {
        case .decoding: stage = .decoding
        case .trimming: stage = .trimming
        case .loadingGraphs: stage = .loadingGraphs
        case .denoising: stage = .denoising
        case .embedding: stage = .embedding
        }
    }

    /// `speaker.emb.txt` như giọng đóng gói: một dòng, 192 số `%.8f` cách nhau dấu phẩy, không chuẩn hoá L2.
    static func speakerEmbeddingText(_ embedding: [Float]) -> String {
        embedding.map { String(format: "%.8f", Double($0)) }.joined(separator: ",")
    }
}
