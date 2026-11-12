import Foundation

/// Chuẩn bị **mẫu giọng** cho nhân bản VieNeu Turbo: đọc → mono → cắt im lặng → tối đa 8 giây → khử nhiễu (tuỳ chọn)
/// → speaker embedding 192 số. Buffer kết quả đưa nguyên cho audio.cpp tạo mã tham chiếu
/// (`VieNeuTurboRuntime.encodeReference`), nên embedding và mã tham chiếu đi ra từ **cùng một** buffer — đúng
/// `prepare_reference` của upstream (`src/vieneu/_v3_turbo_engine/onnx_runtime_lite.py`):
///
/// ```text
/// _preclean_reference_audio:  sf.read → mean kênh → librosa.effects.trim(top_db=30) → sf.write (PCM_16, tần số gốc)
/// prepare_reference:          _load_mono → wav[: int(8.0 * sr)] → denoise (mặc định BẬT) → 44,1 kHz
///                             speaker_emb = speaker_encoder.embed(wav, sr)     # → 16 kHz, fbank Kaldi 80, trừ TB, ONNX
///                             ref_codes   = _encode_ref_wav(wav, sr)            # → 48 kHz, MOSS encoder (ở đây: audio.cpp)
/// ```
///
/// Khác upstream (đã biết, cố ý):
/// - Upstream ghi đoạn đã cắt ra WAV **PCM 16-bit** rồi đọc lại; ở đây giữ float (sai khác cỡ 1/32768, dưới ngưỡng nghe).
/// - Lấy lại tần số bằng `AVAudioConverter` thay cho soxr (như đường Nano, `VieNeuAudioResampler`).
/// - Chỉ đọc `maximumDecodeSeconds` giây đầu file — upstream đọc cả file. Chỉ khác khi tiếng nói bắt đầu sau giây 52.
/// - Tắt khử nhiễu ⇒ buffer giữ **tần số gốc** của file (upstream cũng vậy), không ép 44,1 kHz.
///
/// **Nặng và đồng bộ** — bên gọi chạy ngoài MainActor. Ngữ cảnh ORT (speaker_encoder + denoiser) mở trong hàm và
/// **nhả khi hàm trả về**, trước bước audio.cpp — để hai đỉnh bộ nhớ không chồng nhau.
enum VieNeuTurboReferencePreparer {
    enum Stage: Sendable {
        case decoding
        case trimming
        case loadingGraphs
        case denoising
        case embedding
    }

    struct Timings: Sendable {
        var decodeMs = 0.0
        var trimMs = 0.0
        var loadGraphsMs = 0.0
        var denoiseMs = 0.0
        var embeddingMs = 0.0
    }

    struct Prepared: Sendable {
        /// Mono, ≤ 8 giây — đưa thẳng cho audio.cpp (nó tự lên 48 kHz, tự cắt 8 s).
        let samples: [Float]
        let sampleRate: Double
        /// 192 số, **không** chuẩn hoá L2 — đúng `speaker.emb.txt` của giọng đóng gói.
        let speakerEmbedding: [Float]
        let isDenoised: Bool
        let sourceSampleRate: Double
        /// Độ dài phần đã đọc của file (≤ `maximumDecodeSeconds`).
        let decodedSeconds: Double
        let leadingTrimSeconds: Double
        let trailingTrimSeconds: Double
        /// Đoạn sau cắt im lặng + cắt 8 giây, **trước** khử nhiễu, ở tần số gốc — chỉ khi `keepsIntermediate` (màn thử
        /// chia sẻ để đối chứng với script Python).
        let trimmedSamples: [Float]?
        let timings: Timings

        var durationSeconds: Double { Double(samples.count) / max(1, sampleRate) }
    }

    enum PrepareError: LocalizedError {
        case silent
        case tooShort(Double)
        case badEmbedding(String)

        var errorDescription: String? {
            switch self {
            case .silent:
                return "Mẫu giọng toàn im lặng (không còn gì sau khi cắt khoảng lặng)."
            case .tooShort(let seconds):
                return String(
                    format: "Mẫu giọng chỉ còn %.1f giây sau khi cắt khoảng lặng, cần ít nhất %.0f giây.",
                    seconds, VieNeuTurboReferencePreparer.minimumSeconds
                )
            case .badEmbedding(let detail):
                return "Speaker embedding không hợp lệ: \(detail)"
            }
        }
    }

    /// `_MAX_REF_SECONDS` của Turbo upstream — audio.cpp cũng tự cắt ở đúng 8 giây (`kMaxReferenceSeconds`).
    static let maximumSeconds = 8.0
    /// Sàn sau khi cắt im lặng. Upstream không chặn; dưới ~2 giây mã tham chiếu quá ít khung để ra giọng dùng được.
    static let minimumSeconds = 2.0
    /// Chỉ giải mã chừng này giây đầu file (xem doc của type).
    static let maximumDecodeSeconds = 60.0

    static func prepare(
        sampleURL: URL,
        denoise: Bool,
        modelStore: VieNeuModelStore,
        threadCount: Int32,
        keepsIntermediate: Bool = false,
        onStage: (@Sendable (Stage) -> Void)? = nil
    ) throws -> Prepared {
        var timings = Timings()
        var mark = ProcessInfo.processInfo.systemUptime
        func lap() -> Double {
            let now = ProcessInfo.processInfo.systemUptime
            defer { mark = now }
            return (now - mark) * 1_000
        }

        onStage?(.decoding)
        let decoded = try VieNeuAudioResampler.loadMono(url: sampleURL, maxSeconds: maximumDecodeSeconds)
        let sourceRate = decoded.sampleRate
        timings.decodeMs = lap()

        onStage?(.trimming)
        let kept = VieNeuSilenceTrimmer.nonSilentRange(of: decoded.samples)
        guard !kept.isEmpty else { throw PrepareError.silent }
        let limit = Int((maximumSeconds * sourceRate).rounded(.down)) // `int(max_seconds * sr)` của upstream
        let trimmed = Array(decoded.samples[kept].prefix(limit))
        let trimmedSeconds = Double(trimmed.count) / sourceRate
        guard trimmedSeconds >= minimumSeconds else { throw PrepareError.tooShort(trimmedSeconds) }
        timings.trimMs = lap()

        onStage?(.loadingGraphs)
        let runtime = try VieNeuONNXRuntime(
            turboCloneModelStore: modelStore,
            threadCount: threadCount,
            loadsDenoiser: denoise
        )
        timings.loadGraphsMs = lap()

        var samples = trimmed
        var sampleRate = sourceRate
        if denoise {
            onStage?(.denoising)
            let output = try VieNeuReferenceDenoiser.denoise(trimmed, sampleRate: sourceRate, runtime: runtime)
            samples = output.samples
            sampleRate = VieNeuReferenceDenoiser.sampleRate
            timings.denoiseMs = lap()
        }

        onStage?(.embedding)
        let embedding = try speakerEmbedding(samples: samples, sampleRate: sampleRate, runtime: runtime)
        timings.embeddingMs = lap()

        return Prepared(
            samples: samples,
            sampleRate: sampleRate,
            speakerEmbedding: embedding,
            isDenoised: denoise,
            sourceSampleRate: sourceRate,
            decodedSeconds: decoded.duration,
            leadingTrimSeconds: Double(kept.lowerBound) / sourceRate,
            trailingTrimSeconds: Double(decoded.samples.count - kept.upperBound) / sourceRate,
            trimmedSamples: keepsIntermediate ? trimmed : nil,
            timings: timings
        )
    }

    /// `speaker_encoder.embed(wav, sr)` của upstream: lên/xuống 16 kHz → fbank Kaldi 80 mel (25/10 ms, povey,
    /// snip_edges, preemph 0,97, dither 0 — `VieNeuFbank`) → trừ trung bình mỗi bin → `speaker_encoder` → 192 số.
    /// Cùng đường với nhân bản Nano (`VieNeuVoiceCloner`), chỉ khác buffer vào.
    static func speakerEmbedding(samples: [Float], sampleRate: Double, runtime: VieNeuONNXRuntime) throws -> [Float] {
        let pcm16 = try VieNeuAudioResampler.resample(
            samples,
            from: sampleRate,
            to: Double(VieNeuFbank.targetSampleRate)
        )
        let features = try VieNeuFbank.melSpectrogram(samples: pcm16, sampleRate: VieNeuFbank.targetSampleRate)
        let normalized = VieNeuFbank.meanNormalized(features)
        let embedding = try runtime.speakerEncoder(fbank: normalized, frames: features.frames, melBins: features.bins)
        guard embedding.count == VieNeuVoiceCatalog.speakerEmbeddingCount else {
            throw PrepareError.badEmbedding(
                "speaker_encoder trả \(embedding.count) số, cần \(VieNeuVoiceCatalog.speakerEmbeddingCount)"
            )
        }
        guard embedding.allSatisfy({ $0.isFinite }) else { throw PrepareError.badEmbedding("có NaN/Inf") }
        // `_speaker_anchor` của upstream từ chối embedding toàn 0 — chặn sớm thay vì để lượt đọc lỗi.
        guard embedding.contains(where: { $0 != 0 }) else { throw PrepareError.badEmbedding("toàn số 0") }
        return embedding
    }
}
