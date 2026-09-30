import Foundation

/// Nhân bản giọng: từ **một file audio mẫu** ra đúng hai mảng số của một giọng VieNeu-TTS v3 Nano.
///
/// Chép **nguyên văn** `OnnxV3NanoEngine.prepare_reference()` của upstream (`v3nano.py:194-223`):
///
/// ```text
/// wav, sr = load_mono(ref_audio)                 # mono
/// wav     = wav[: int(30.0 * sr)]                # _MAX_REF_SECONDS
/// spk     = speaker_encoder.embed(wav, sr)       # -> (192,)
///
/// m24 = resample(wav, sr -> 24000)
/// m24 = m24[: int(24000 * 5.0)]                  # _REF_SECONDS
/// mu  = codec_encoder(wav = m24[None, None])     # -> [1, 24, T]
/// z   = (mu - latent_mean) / latent_std * latent_scale
/// z   = group_latent(z)                          # -> [1, 144, T/6]
/// z   = z[:, :, : min(int(5.0 * 15.625), 140)]   # -> [1, 144, 78]
/// style = reference_encoder(ref = z, ref_mask = ones(1, 78))[0]   # -> (50, 256)
/// ```
///
/// và bên trong `speaker_encoder.embed`:
///
/// ```text
/// feat = extract_speaker_fbank(mono, sample_rate = sr)   # resample -> 16 kHz, (T, 80)
/// feat = feat - feat.mean(axis = 0)                      # MEAN NORM
/// graph(feat[None]) -> (1, 192)
/// ```
///
/// ## Bốn chi tiết mà bản mô tả đầu tiên làm thiếu (plan §0) — thiếu cái nào cũng **im lặng** mà sai
/// 1. `mean_norm` — fbank phải **trừ trung bình theo từng bin** trước khi vào `speaker_encoder`.
/// 2. `snip_edges = True` — không đệm đầu/cuối (đã nằm trong `VieNeuFbank`).
/// 3. `codec_encoder` ra **24 kênh**, `group = 6` gộp **sau** ⇒ 144 kênh mới là input của
///    `reference_encoder`.
/// 4. Chuẩn hoá latent `(mu - mean) / std * scale` — `mean`/`std` shape `(24,)`, `scale = 0,25`.
///
/// ## Bộ nhớ
/// Mỗi lượt gọi mở một ngữ cảnh ORT **chỉ 3 graph clone** (`~91 MB`) rồi nhả khi xong, thay vì dùng
/// ngữ cảnh 4 graph chính của engine (`+~280 MB` nữa). Đổi lại, mỗi lượt tạo giọng phải đọc lại 3 graph
/// từ đĩa (~2–4 s) — chấp nhận được vì đây là thao tác một lần, và UI có thanh tiến trình.
enum VieNeuVoiceCloner {
    /// Kết quả nhân bản — **đúng hai mảng số** của một giọng preset, không hơn.
    struct Enrollment: Sendable {
        /// 192 phần tử (x-vector).
        let speakerEmbedding: [Float]
        /// 50 × 256 = 12.800 phần tử, đã làm phẳng theo hàng.
        let style: [Float]
        let sampleSeconds: Double
        let fbankFrames: Int
        let codecChannels: Int
        let codecFrames: Int
        /// Số frame **sau khi gộp nhóm và cắt** — đưa vào `reference_encoder`.
        let styleFrames: Int
    }

    enum CloneError: LocalizedError {
        case missingLatentConstants
        case audioTooShort(Double)
        case audioTooLong(Double)
        case unexpectedShape(String)
        case badEmbedding(String)
        case nonFiniteValues(String)

        var errorDescription: String? {
            switch self {
            case .missingLatentConstants:
                return "Gói model thiếu `latent_mean`/`latent_std`/`latent_scale` trong `constants.npz` nên không nhân bản giọng được. Tải lại model VieNeu."
            case .audioTooShort(let seconds):
                return String(format: "Audio mẫu chỉ %.1f giây, cần ít nhất %.0f giây.", seconds, VieNeuVoiceCloner.minimumSampleSeconds)
            case .audioTooLong(let seconds):
                return String(format: "Audio mẫu dài %.0f giây, chỉ dùng được tối đa %.0f giây.", seconds, VieNeuVoiceCloner.maximumSampleSeconds)
            case .unexpectedShape(let detail):
                return "Graph trả shape không mong đợi: \(detail)"
            case .badEmbedding(let detail):
                return "Kết quả nhân bản không đúng kích thước: \(detail)"
            case .nonFiniteValues(let label):
                return "Kết quả nhân bản có giá trị không hợp lệ (NaN/Inf) ở \(label)."
            }
        }
    }

    /// Bước của quá trình nhân bản — để UI hiện tiến trình thật thay vì một vòng xoay vô định.
    ///
    /// Nhãn tiếng Việt nằm ở tầng View, **không** ở đây: `Sources/Services/**` không được biết chữ nào
    /// hiển thị cho người dùng.
    enum Stage: Sendable {
        case decoding
        case features
        case loadingGraphs
        case speaker
        case codec
        case style
    }

    /// `_REF_SECONDS` của upstream — style token lấy từ **5 giây đầu**.
    static let refSeconds = 5.0
    /// `_MAX_REF_SECONDS` của upstream — x-vector chỉ thấy tối đa 30 giây.
    static let maximumSampleSeconds = 30.0
    /// Sàn độ dài audio mẫu. Dưới ngưỡng này cả fbank lẫn phần cắt 5 giây đều quá ngắn để ra giọng dùng được.
    static let minimumSampleSeconds = 3.0
    /// Độ dài **khuyến nghị** — UI thu âm cắt ở đây (plan §3.1 "3–8 s"). Dài hơn vẫn nhận: upstream chỉ
    /// dùng 5 giây đầu cho style và 30 giây đầu cho x-vector.
    static let recommendedSampleSeconds = 8.0

    /// Nhân bản một audio mẫu. **Nặng và đồng bộ** — bên gọi phải chạy trong `Task.detached`.
    ///
    /// `onStage` có default `nil` nên call site cũ không phải sửa; nó chỉ **báo bước**, không mang dữ liệu
    /// người dùng, và phải `@Sendable` vì được gọi từ trong `Task.detached`.
    static func enroll(
        sampleURL: URL,
        modelStore: VieNeuModelStore,
        threadCount: Int32,
        onStage: (@Sendable (Stage) -> Void)? = nil
    ) throws -> Enrollment {
        let config = try VieNeuConfig.load(modelStore: modelStore)
        guard let latentMean = config.constants.latentMean,
              let latentStd = config.constants.latentStd,
              let latentScale = config.constants.latentScale else {
            throw CloneError.missingLatentConstants
        }

        onStage?(.decoding)
        let decoded = try VieNeuAudioResampler.loadMono(url: sampleURL)
        guard decoded.duration >= minimumSampleSeconds else {
            throw CloneError.audioTooShort(decoded.duration)
        }
        guard decoded.duration <= maximumSampleSeconds else {
            throw CloneError.audioTooLong(decoded.duration)
        }

        // Cắt ≤ 30 s **trước** mọi bước — đúng `wav = wav[: int(max_seconds * sr)]` của upstream.
        let limited = Array(decoded.samples.prefix(Int(maximumSampleSeconds * decoded.sampleRate)))

        // 1. x-vector: 16 kHz → fbank 80-mel Kaldi → trừ trung bình theo bin → speaker_encoder
        let pcm16 = try VieNeuAudioResampler.resample(
            limited,
            from: decoded.sampleRate,
            to: Double(VieNeuFbank.targetSampleRate)
        )
        onStage?(.features)
        let features = try VieNeuFbank.melSpectrogram(
            samples: pcm16,
            sampleRate: VieNeuFbank.targetSampleRate
        )
        let normalized = VieNeuFbank.meanNormalized(features)

        // 2. latent: 24 kHz → cắt 5 giây đầu → codec_encoder
        let pcm24 = try VieNeuAudioResampler.resample(
            limited,
            from: decoded.sampleRate,
            to: Double(config.sampleRate)
        )
        let refSampleCount = min(pcm24.count, Int(Double(config.sampleRate) * refSeconds))
        guard refSampleCount > 0 else { throw CloneError.audioTooShort(decoded.duration) }

        // Đây là bước **lâu nhất** trong 3 lượt ORT: đọc 3 graph (~91 MB) từ đĩa rồi dựng session.
        onStage?(.loadingGraphs)
        let runtime = try VieNeuONNXRuntime(cloneOnlyModelStore: modelStore, threadCount: threadCount)

        onStage?(.speaker)
        let speaker = try runtime.speakerEncoder(
            fbank: normalized,
            frames: features.frames,
            melBins: features.bins
        )

        onStage?(.codec)
        let codec = try runtime.codecEncoder(pcm: Array(pcm24.prefix(refSampleCount)))
        guard codec.shape.count == 3 else {
            throw CloneError.unexpectedShape("codec_encoder trả rank \(codec.shape.count), cần 3")
        }
        let channels = Int(codec.shape[1])
        let codecFrames = Int(codec.shape[2])
        guard channels == config.latentDim else {
            throw CloneError.unexpectedShape("codec_encoder trả \(channels) kênh, cần \(config.latentDim)")
        }
        guard codecFrames > 0, codec.values.count == channels * codecFrames else {
            throw CloneError.unexpectedShape("codec_encoder trả \(codec.values.count) phần tử cho \(channels)×\(codecFrames)")
        }
        guard latentMean.count == channels, latentStd.count == channels else {
            throw CloneError.unexpectedShape("latent_mean/std có \(latentMean.count)/\(latentStd.count) phần tử, cần \(channels)")
        }

        // 3. z = (mu - latent_mean) / latent_std * latent_scale — broadcast theo kênh, đúng upstream.
        var latent = codec.values
        for channel in 0..<channels {
            let mean = latentMean[channel]
            let deviation = latentStd[channel]
            guard deviation != 0 else {
                throw CloneError.unexpectedShape("latent_std[\(channel)] = 0")
            }
            let base = channel * codecFrames
            for frame in 0..<codecFrames {
                latent[base + frame] = (latent[base + frame] - mean) / deviation * latentScale
            }
        }

        // 4. Gộp nhóm rồi cắt theo frame (cắt **sau** khi gộp — xem doc của `groupLatent`).
        let grouped = groupLatent(latent, channels: channels, frames: codecFrames, group: config.group)
        let targetFrames = config.referenceFrameCount(refSeconds: refSeconds)
        let styleFrames = min(grouped.frames, max(1, targetFrames))
        let cropped = cropFrames(
            grouped.values,
            channels: grouped.channels,
            frames: grouped.frames,
            to: styleFrames
        )

        onStage?(.style)
        let style = try runtime.referenceEncoder(
            latent: cropped,
            channels: grouped.channels,
            frames: styleFrames
        )

        // 5. Hậu điều kiện (plan §3.8): sai kích thước hoặc có NaN/Inf thì **ném**, không lưu giọng hỏng.
        guard speaker.count == VieNeuVoiceCatalog.speakerEmbeddingCount else {
            throw CloneError.badEmbedding(
                "speaker_encoder trả \(speaker.count) phần tử, cần \(VieNeuVoiceCatalog.speakerEmbeddingCount)"
            )
        }
        guard style.count == VieNeuVoiceCatalog.styleCount else {
            throw CloneError.badEmbedding(
                "reference_encoder trả \(style.count) phần tử, cần \(VieNeuVoiceCatalog.styleCount)"
            )
        }
        try requireFinite(speaker, label: "x-vector")
        try requireFinite(style, label: "style")

        return Enrollment(
            speakerEmbedding: speaker,
            style: style,
            sampleSeconds: decoded.duration,
            fbankFrames: features.frames,
            codecChannels: channels,
            codecFrames: codecFrames,
            styleFrames: styleFrames
        )
    }

    // MARK: - Xử lý mảng

    /// `[1, C, T] → [1, C·group, ceil(T/group)]`, đệm `T` cho tròn nhóm. **Chép đúng**
    /// `_group_latent` của upstream (`v3nano.py:185-192`).
    ///
    /// ⚠️ Bố cục phần tử **không** phải "ghép `group` kênh liền nhau". numpy làm
    /// `reshape(B, C, T/g, g).transpose(0, 1, 3, 2).reshape(B, C·g, T/g)`, tức
    /// `out[c·g + j][b] = z[c][b·g + j]`.
    ///
    /// Viết theo cách "hiển nhiên" — gộp `group` kênh **kề nhau** — ra **đúng shape nhưng sai số**:
    /// `reference_encoder` vẫn trả `(50, 256)` hợp lệ, không có lỗi nào báo, chỉ có giọng bị méo. Đây là
    /// đúng loại lỗi im lặng mà plan §6 rủi ro #1 cảnh báo.
    static func groupLatent(
        _ values: [Float],
        channels: Int,
        frames: Int,
        group: Int
    ) -> (values: [Float], channels: Int, frames: Int) {
        guard group > 0, channels > 0, frames > 0 else { return (values, channels, frames) }
        let blocks = (frames + group - 1) / group
        var output = [Float](repeating: 0, count: channels * group * blocks)
        for channel in 0..<channels {
            let sourceBase = channel * frames
            for block in 0..<blocks {
                for slot in 0..<group {
                    let sourceFrame = block * group + slot
                    // Frame đệm của numpy giữ 0, và mảng Swift đã khởi tạo 0 ⇒ chỉ cần bỏ qua.
                    guard sourceFrame < frames else { continue }
                    output[(channel * group + slot) * blocks + block] = values[sourceBase + sourceFrame]
                }
            }
        }
        return (output, channels * group, blocks)
    }

    /// `z[:, :, :target]` — mảng vào là row-major `channels × frames`.
    static func cropFrames(_ values: [Float], channels: Int, frames: Int, to target: Int) -> [Float] {
        guard target < frames else { return values }
        var output = [Float](repeating: 0, count: channels * target)
        for channel in 0..<channels {
            let sourceBase = channel * frames
            let targetBase = channel * target
            for frame in 0..<target {
                output[targetBase + frame] = values[sourceBase + frame]
            }
        }
        return output
    }

    private static func requireFinite(_ values: [Float], label: String) throws {
        guard values.allSatisfy({ $0.isFinite }) else {
            throw CloneError.nonFiniteValues(label)
        }
    }
}
