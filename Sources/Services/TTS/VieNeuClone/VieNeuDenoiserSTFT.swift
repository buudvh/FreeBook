import Accelerate
import Foundation

/// STFT / iSTFT quanh graph khử nhiễu `denoiser.onnx` — chép `_stft` / `_istft` của upstream
/// (`src/vieneu/_v3_turbo_engine/onnx_denoiser.py`, `pnnbao97/VieNeu-TTS`):
///
/// ```text
/// N_FFT = 1680, HOP = 420, cửa sổ Hann **tuần hoàn** 0,5 − 0,5·cos(2πn/N)
/// _stft : đệm reflect N/2 hai đầu → khung × cửa sổ → rfft → (f, t), BỎ khung cuối
/// _istft: lặp khung cuối → irfft × cửa sổ → cộng chồng → chia Σw² (sàn 1e-11) → bỏ N/2 hai đầu → đệm/cắt về out_len
/// ```
///
/// ## Vì sao DFT bằng nhân ma trận
/// 1680 = 2⁴·3·5·7. FFT radix-2 của app (`VieNeuFbank.fft`) cần độ dài lũy thừa 2; `vDSP_DFT_zrop` chỉ nhận
/// `f·2ⁿ` với `f ∈ {1, 3, 5, 15}` — thừa số 7 làm cả hai không dùng được. Bluestein (đệm lên FFT 4096) làm được nhưng
/// thêm một lớp phức tạp khó kiểm khi không chạy được trên máy. Ở đây DFT là **phép nhân ma trận** với bảng cos / sin
/// tính trước (841 × 1680): một lượt `vDSP_mmul` cho phần thực, một cho phần ảo. Với 8 giây mẫu (~841 khung) mỗi chiều
/// là ~2,4 GFLOP — Accelerate chạy trong vài chục ms trên iPhone, và đây là việc một lần khi tạo giọng.
///
/// Đã đối chiếu bằng numpy (cùng thuật toán, float32) với `_stft` / `_istft` gốc trên tín hiệu ngẫu nhiên 3 giây:
/// sai lệch phổ ≤ 1,5e-5 (biên độ tới ~26), sai lệch iSTFT ≤ 5e-7.
///
/// Bố cục ma trận phổ: **phẳng theo tần số** `bins × frames` (hàng = bin) — đúng `(f, t)` mà graph nhận `[1, 841, t]`.
enum VieNeuDenoiserSTFT {
    static let fftLength = 1680
    static let hopLength = 420
    /// `n_fft / 2 + 1`.
    static let binCount = fftLength / 2 + 1

    /// Phổ phức tách thực / ảo, phẳng theo tần số.
    struct Spectrum {
        let real: [Float]
        let imaginary: [Float]
        let frames: Int
    }

    /// Bảng DFT `binCount × fftLength`: `cos(2πkn/N)` và `−sin(2πkn/N)` (phần ảo của rfft mang dấu trừ). Tính chỉ số
    /// `k·n mod N` bằng số nguyên trước khi nhân 2π/N để góc không trôi khi `k·n` lớn.
    struct Tables {
        let cosine: [Float]
        let negativeSine: [Float]
        let window: [Float]

        init() {
            let length = VieNeuDenoiserSTFT.fftLength
            let bins = VieNeuDenoiserSTFT.binCount
            var cosine = [Float](repeating: 0, count: bins * length)
            var negativeSine = [Float](repeating: 0, count: bins * length)
            let step = 2 * Double.pi / Double(length)
            for bin in 0..<bins {
                let row = bin * length
                for sample in 0..<length {
                    let angle = Double((bin * sample) % length) * step
                    cosine[row + sample] = Float(cos(angle))
                    negativeSine[row + sample] = Float(-sin(angle))
                }
            }
            self.cosine = cosine
            self.negativeSine = negativeSine
            self.window = (0..<length).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(length))) }
        }
    }

    // MARK: - STFT

    /// `torch.stft(center=True, pad_mode="reflect", window=hann_periodic)` rồi bỏ khung cuối, như upstream.
    /// Cần ít nhất `fftLength / 2 + 1` mẫu (đệm reflect đòi vậy).
    static func forward(_ signal: [Float], tables: Tables) -> Spectrum {
        let length = fftLength
        let pad = length / 2
        guard signal.count > pad else { return Spectrum(real: [], imaginary: [], frames: 0) }
        let padded = reflectPadded(signal, pad: pad)
        let frames = (padded.count - length) / hopLength // = 1 + (…)/hop khung, bỏ khung cuối
        guard frames > 0 else { return Spectrum(real: [], imaginary: [], frames: 0) }

        // Ma trận khung **chuyển vị** `fftLength × frames` để `vDSP_mmul` ra thẳng `bins × frames`.
        var framesT = [Float](repeating: 0, count: length * frames)
        for frame in 0..<frames {
            let start = frame * hopLength
            for sample in 0..<length {
                framesT[sample * frames + frame] = padded[start + sample] * tables.window[sample]
            }
        }
        var real = [Float](repeating: 0, count: binCount * frames)
        var imaginary = [Float](repeating: 0, count: binCount * frames)
        multiply(tables.cosine, rows: binCount, inner: length, by: framesT, columns: frames, into: &real)
        multiply(tables.negativeSine, rows: binCount, inner: length, by: framesT, columns: frames, into: &imaginary)
        return Spectrum(real: real, imaginary: imaginary, frames: frames)
    }

    /// `np.abs` / `cos(np.angle)` / `sin(np.angle)` của phổ. Bin biên độ 0 (đoạn đệm 441 mẫu 0, im lặng số) cho
    /// `angle = 0` như numpy ⇒ cos 1, sin 0 — **không** chia cho 0 (NaN sẽ lan khắp UNet).
    static func polar(_ spectrum: Spectrum) -> (magnitude: [Float], cosine: [Float], sine: [Float]) {
        let count = spectrum.real.count
        var magnitude = [Float](repeating: 0, count: count)
        var cosine = [Float](repeating: 1, count: count)
        var sine = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let re = spectrum.real[index]
            let im = spectrum.imaginary[index]
            let value = (re * re + im * im).squareRoot()
            magnitude[index] = value
            if value > 0 {
                cosine[index] = re / value
                sine[index] = im / value
            }
        }
        return (magnitude, cosine, sine)
    }

    // MARK: - iSTFT

    /// `_istft(spec, out_len)` của upstream, với `spec = mag · (cos + i·sin)`.
    static func inverse(
        magnitude: [Float],
        cosine: [Float],
        sine: [Float],
        frames: Int,
        outputLength: Int,
        tables: Tables
    ) -> [Float] {
        let length = fftLength
        let bins = binCount
        guard frames > 0, magnitude.count == bins * frames else { return [Float](repeating: 0, count: outputLength) }
        // Lặp khung cuối (upstream `concatenate([spec, spec[:, -1:]])`) và nhân sẵn trọng số irfft: bin 0 và bin N/2
        // ×1/N, còn lại ×2/N. Phần ảo của bin 0 / N/2 tự rơi vì hàng −sin của chúng toàn 0 — đúng như `irfft` bỏ qua.
        let extended = frames + 1
        var realT = [Float](repeating: 0, count: extended * bins)
        var imaginaryT = [Float](repeating: 0, count: extended * bins)
        for bin in 0..<bins {
            let weight: Float = (bin == 0 || bin == bins - 1) ? 1 / Float(length) : 2 / Float(length)
            let row = bin * frames
            for frame in 0..<extended {
                let source = row + min(frame, frames - 1)
                let value = magnitude[source] * weight
                realT[frame * bins + bin] = value * cosine[source]
                imaginaryT[frame * bins + bin] = value * sine[source]
            }
        }
        // Khung thời gian `extended × fftLength` = Reᵀ·cos + Imᵀ·(−sin).
        var realPart = [Float](repeating: 0, count: extended * length)
        var imaginaryPart = [Float](repeating: 0, count: extended * length)
        multiply(realT, rows: extended, inner: bins, by: tables.cosine, columns: length, into: &realPart)
        multiply(imaginaryT, rows: extended, inner: bins, by: tables.negativeSine, columns: length, into: &imaginaryPart)
        let timeFrames = vDSP.add(realPart, imaginaryPart)

        // Cộng chồng có cửa sổ, chia Σw².
        let signalLength = length + hopLength * (extended - 1)
        var output = [Float](repeating: 0, count: signalLength)
        var windowSum = [Float](repeating: 0, count: signalLength)
        for frame in 0..<extended {
            let start = frame * hopLength
            let base = frame * length
            for sample in 0..<length {
                let weight = tables.window[sample]
                output[start + sample] += timeFrames[base + sample] * weight
                windowSum[start + sample] += weight * weight
            }
        }
        let pad = length / 2
        var result = [Float](repeating: 0, count: outputLength)
        let available = max(0, signalLength - 2 * pad)
        for index in 0..<min(outputLength, available) {
            result[index] = output[pad + index] / max(windowSum[pad + index], 1e-11)
        }
        return result
    }

    // MARK: - Nội bộ

    /// `np.pad(x, (pad, pad), mode="reflect")` — phản xạ **không** lặp mẫu biên. Cần `x.count > pad`.
    static func reflectPadded(_ signal: [Float], pad: Int) -> [Float] {
        let count = signal.count
        var padded = [Float](repeating: 0, count: count + 2 * pad)
        for index in 0..<pad {
            padded[index] = signal[pad - index]
            padded[pad + count + index] = signal[count - 2 - index]
        }
        for index in 0..<count {
            padded[pad + index] = signal[index]
        }
        return padded
    }

    /// `C (rows × columns) = A (rows × inner) · B (inner × columns)`, cả ba phẳng theo hàng.
    private static func multiply(
        _ left: [Float],
        rows: Int,
        inner: Int,
        by right: [Float],
        columns: Int,
        into output: inout [Float]
    ) {
        vDSP_mmul(left, 1, right, 1, &output, 1, vDSP_Length(rows), vDSP_Length(columns), vDSP_Length(inner))
    }
}
