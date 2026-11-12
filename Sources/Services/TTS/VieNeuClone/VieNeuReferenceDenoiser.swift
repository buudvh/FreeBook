import Foundation

/// Khử nhiễu mẫu giọng trước khi nhân bản cho VieNeu Turbo — chép `OnnxDenoiser.denoise` của upstream
/// (`src/vieneu/_v3_turbo_engine/onnx_denoiser.py`). Upstream ghi lý do: mẫu có nhiễu đẩy speaker embedding ra ngoài
/// phân bố huấn luyện (dữ liệu huấn luyện đã khử nhiễu), dễ làm model "nói mãi không dừng" lúc đọc.
///
/// ```text
/// wav = soxr.resample(wav, sr, 44100)          # ở đây: AVAudioConverter (VieNeuAudioResampler), không trùng bit với soxr
/// length  = len(wav)
/// abs_max = max(max|wav|, 1e-7);  w = wav / abs_max
/// w = pad(w, (0, 441))                          # npad của resemble-enhance
/// x = w / (max|w| + 1e-7)                       # _forward chuẩn hoá LẦN HAI — giữ đúng như upstream
/// mag, cos, sin = |stft(x)|, cos∠, sin∠
/// sep_mag, sep_cos, sep_sin = denoiser(mag, cos, sin)
/// o = istft(sep_mag · (sep_cos + i·sep_sin), out_len = len(x))
/// return o[:length] · abs_max                   # mono 44,1 kHz
/// ```
/// Upstream chạy một khối (≤ ~30 s) — mẫu ở đây ≤ 8 giây.
enum VieNeuReferenceDenoiser {
    static let sampleRate = 44_100.0
    /// `npad = 441` của `inference_chunk` (resemble-enhance).
    static let trailingPad = 441

    struct Output {
        /// Mono 44,1 kHz, cùng độ dài với mẫu sau khi lấy lại tần số.
        let samples: [Float]
        let stftFrames: Int
    }

    static func denoise(_ samples: [Float], sampleRate sourceRate: Double, runtime: VieNeuONNXRuntime) throws -> Output {
        let resampled = try VieNeuAudioResampler.resample(samples, from: sourceRate, to: Self.sampleRate)
        let length = resampled.count
        guard length > VieNeuDenoiserSTFT.fftLength / 2 else {
            throw VieNeuONNXRuntime.RuntimeError.failure("denoiser: mẫu quá ngắn (\(length) mẫu ở 44,1 kHz)")
        }
        let absMax = max(peak(of: resampled), 1e-7)
        var padded = resampled.map { $0 / absMax }
        padded.append(contentsOf: [Float](repeating: 0, count: trailingPad))
        let secondPeak = peak(of: padded) + 1e-7
        let normalized = padded.map { $0 / secondPeak }

        let tables = VieNeuDenoiserSTFT.Tables()
        let spectrum = VieNeuDenoiserSTFT.forward(normalized, tables: tables)
        let polar = VieNeuDenoiserSTFT.polar(spectrum)
        let separated = try runtime.denoise(
            magnitude: polar.magnitude,
            cosine: polar.cosine,
            sine: polar.sine,
            bins: VieNeuDenoiserSTFT.binCount,
            frames: spectrum.frames
        )
        let restored = VieNeuDenoiserSTFT.inverse(
            magnitude: separated.magnitude,
            cosine: separated.cosine,
            sine: separated.sine,
            frames: spectrum.frames,
            outputLength: normalized.count,
            tables: tables
        )
        let output = restored.prefix(length).map { $0 * absMax }
        guard output.allSatisfy({ $0.isFinite }) else {
            throw VieNeuONNXRuntime.RuntimeError.failure("denoiser trả giá trị không hợp lệ (NaN/Inf)")
        }
        return Output(samples: output, stftFrames: spectrum.frames)
    }

    private static func peak(of samples: [Float]) -> Float {
        samples.reduce(Float(0)) { max($0, abs($1)) }
    }
}
