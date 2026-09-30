import Foundation

/// Fbank 80-mel kiểu **Kaldi** cho `speaker_encoder` của VieNeu-TTS v3 Nano — thuần Swift, **không** dùng
/// `Accelerate`/`vDSP`.
///
/// Cố ý tránh `Accelerate`: (1) `vDSP` là API Apple-only nên file này không biên dịch được ngoài macOS,
/// trong khi cổng kiểm chứng số cần biên dịch nó bằng `swiftc` ở nơi khác; (2) một FFT radix-2 tự viết
/// ở đây **kiểm chứng được** bằng cách đối chiếu với `numpy.fft` — `vDSP` thì không.
///
/// ## Chép đúng bản tham chiếu upstream
/// `pnnbao97/VieNeu-TTS`, `src/vieneu/_v3_turbo_engine/speaker/{fbank,audio_utils}.py`:
/// `sample_rate=16000`, `n_mels=80`, `dither=0`, `snip_edges=True`, `window_type="povey"`,
/// `remove_dc_offset=True`, `preemph_coeff=0.97`, `low_freq=20`, `high_freq=0` (⇒ Nyquist),
/// `use_energy=False`, `htk_mode=False`, `use_power=True`, `use_log_fbank=True` (log **tự nhiên**).
/// Sau cùng `extract_fbank(mean_norm=True)` ⇒ **trừ trung bình theo từng bin mel qua trục thời gian**.
///
/// ## Bẫy 1 — `mean_norm` là bắt buộc, không phải tuỳ chọn
/// Bỏ bước trừ trung bình ⇒ x-vector **lệch hẳn** mà không có lỗi nào. Vì mean-norm triệt tiêu mọi hằng số
/// cộng trong miền log, quy ước scale waveform (nhân `32768` hay không) **không** ảnh hưởng kết quả cuối —
/// nhưng **ma trận thô thì có**, nên cổng kiểm chứng so ở dạng **thô** (trước mean-norm) mới là phép thử chặt.
///
/// ## Bẫy 2 — thứ tự tiền xử lý từng frame
/// Kaldi làm đúng thứ tự: `remove_dc_offset` → `preemphasis` → **nhân cửa sổ sau cùng**. Đổi thứ tự
/// (ví dụ nhân cửa sổ trước preemphasis) vẫn ra số "trông hợp lệ" nhưng sai.
/// `preemph` dùng mẫu 0 của chính nó: `x[0] -= c * x[0]` (tương đương `pad(mode="replicate")` của torchaudio).
///
/// ## Bẫy 3 — `snip_edges=True`
/// `numFrames = 1 + (n - frameLength) / frameShift` khi `n >= frameLength`, **không** đệm đầu/cuối.
/// Đệm thêm frame ⇒ lệch số frame và lệch cả biên.
///
/// ## Bẫy 4 — `htk_mode=False` ⇒ **không** chuẩn hoá diện tích bộ lọc mel
/// Trọng số tam giác đạt đỉnh 1 tại tâm bin, **không** chia cho độ rộng dải mel (đó là kiểu Slaney/HTK).
enum VieNeuFbank {

    /// Ma trận log-mel đã tính, **row-major** theo `frames × bins` — đúng thứ tự phần tử mà
    /// `speaker_encoder` nhận ở input `[1, frames, 80]`.
    struct Features: Sendable {
        let frames: Int
        let bins: Int
        /// `frames * bins` phần tử, hàng `f` nằm ở `values[f * bins ..< (f + 1) * bins]`.
        let values: [Float]
    }

    enum FbankError: LocalizedError {
        case audioTooShort(samples: Int, frameLength: Int)

        var errorDescription: String? {
            switch self {
            case .audioTooShort(let samples, let frameLength):
                return "Audio quá ngắn để tính fbank (\(samples) mẫu, cần ≥ \(frameLength) mẫu cho một frame)."
            }
        }
    }

    // MARK: - Tham số (khớp `kaldi-native-fbank` mà upstream dùng)

    /// Mẫu mà `speaker_encoder` được huấn luyện. `VieNeuAudioResampler` phải hạ về đây trước khi gọi.
    static let targetSampleRate = 16000
    static let numMelBins = 80
    static let frameLengthMs = 25.0
    static let frameShiftMs = 10.0
    static let preemphasisCoefficient = 0.97
    static let lowFrequency = 20.0
    /// `0` nghĩa là Nyquist (`sampleRate / 2`) — đúng quy ước Kaldi.
    static let highFrequency = 0.0
    /// `std::numeric_limits<float>::epsilon()` = `FLT_EPSILON`, đúng hằng số Kaldi dùng làm sàn trước `log`.
    static let energyFloor = 1.1920928955078125e-07
    static let windowExponent = 0.85

    static func frameLength(sampleRate: Int) -> Int {
        Int((frameLengthMs * Double(sampleRate) / 1000.0).rounded())
    }

    static func frameShift(sampleRate: Int) -> Int {
        Int((frameShiftMs * Double(sampleRate) / 1000.0).rounded())
    }

    /// Kích thước FFT: luỹ thừa 2 nhỏ nhất ≥ `frameLength` (`round_to_power_of_two=True`).
    static func paddedLength(sampleRate: Int) -> Int {
        var size = 1
        while size < frameLength(sampleRate: sampleRate) { size <<= 1 }
        return size
    }

    // MARK: - Cửa sổ

    /// Cửa sổ Povey: `(0.5 - 0.5·cos(2πi/(N-1)))^0.85` — như Hamming nhưng **về 0 ở hai biên**.
    static func poveyWindow(length: Int) -> [Double] {
        let a = 2.0 * Double.pi / Double(length - 1)
        return (0 ..< length).map { index in
            Foundation.pow(0.5 - 0.5 * Foundation.cos(a * Double(index)), windowExponent)
        }
    }

    // MARK: - Bộ lọc mel

    /// Thang mel Kaldi: `1127 · ln(1 + f/700)`.
    static func melScale(_ frequency: Double) -> Double {
        1127.0 * Foundation.log(1.0 + frequency / 700.0)
    }

    /// Ma trận bộ lọc tam giác, **row-major** `numBins × numFFTBins`, đỉnh bằng 1, không chuẩn hoá diện tích.
    static func melFilterBank(sampleRate: Int, numBins: Int, paddedLength: Int) -> [Double] {
        let numFFTBins = paddedLength / 2
        var high = highFrequency
        if high <= 0.0 { high += 0.5 * Double(sampleRate) }
        let melLow = melScale(lowFrequency)
        let melHigh = melScale(high)
        let melDelta = (melHigh - melLow) / Double(numBins + 1)
        let fftBinWidth = Double(sampleRate) / Double(paddedLength)

        // Mel của từng bin FFT tính một lần, dùng lại cho cả 80 bộ lọc.
        var binMels = [Double](repeating: 0, count: numFFTBins)
        for index in 0 ..< numFFTBins {
            binMels[index] = melScale(fftBinWidth * Double(index))
        }

        var filters = [Double](repeating: 0, count: numBins * numFFTBins)
        for bin in 0 ..< numBins {
            let left = melLow + Double(bin) * melDelta
            let center = melLow + Double(bin + 1) * melDelta
            let right = melLow + Double(bin + 2) * melDelta
            let rowStart = bin * numFFTBins
            for index in 0 ..< numFFTBins {
                let mel = binMels[index]
                guard mel > left, mel < right else { continue }
                let weight = mel <= center
                    ? (mel - left) / (center - left)
                    : (right - mel) / (right - center)
                filters[rowStart + index] = weight
            }
        }
        return filters
    }

    // MARK: - FFT

    /// FFT radix-2 tại chỗ, độ dài `n` là luỹ thừa 2. Bảng twiddle **tính trực tiếp bằng `cos`/`sin`**
    /// (không nhân dồn) để tránh trôi số — nhân dồn tích luỹ sai số đủ để trượt cổng `< 1e-4`.
    ///
    /// Trả về `(real, imag)`. `imag[0]` luôn 0 vì đầu vào thực.
    static func fft(real inputReal: [Double], imag inputImag: [Double]) -> (real: [Double], imag: [Double]) {
        let n = inputReal.count
        var real = inputReal
        var imag = inputImag

        // Đảo bit: đưa mẫu về đúng vị trí của nó trong cây butterfly.
        var j = 0
        for i in 0 ..< n {
            if i < j {
                real.swapAt(i, j)
                imag.swapAt(i, j)
            }
            var mask = n >> 1
            while mask >= 1, j >= mask {
                j -= mask
                mask >>= 1
            }
            j += mask
        }

        // Bảng twiddle cho nửa vòng tròn đơn vị.
        var twiddleReal = [Double](repeating: 0, count: n / 2)
        var twiddleImag = [Double](repeating: 0, count: n / 2)
        for k in 0 ..< (n / 2) {
            let angle = -2.0 * Double.pi * Double(k) / Double(n)
            twiddleReal[k] = Foundation.cos(angle)
            twiddleImag[k] = Foundation.sin(angle)
        }

        var length = 2
        while length <= n {
            let half = length / 2
            let stride = n / length
            var start = 0
            while start < n {
                for k in 0 ..< half {
                    let twiddle = k * stride
                    let wr = twiddleReal[twiddle]
                    let wi = twiddleImag[twiddle]
                    let evenIndex = start + k
                    let oddIndex = start + k + half
                    let oddReal = real[oddIndex]
                    let oddImag = imag[oddIndex]
                    let vr = oddReal * wr - oddImag * wi
                    let vi = oddReal * wi + oddImag * wr
                    real[oddIndex] = real[evenIndex] - vr
                    imag[oddIndex] = imag[evenIndex] - vi
                    real[evenIndex] += vr
                    imag[evenIndex] += vi
                }
                start += length
            }
            length <<= 1
        }
        return (real, imag)
    }

    // MARK: - Tính fbank

    /// `samples` là waveform mono float trong `[-1, 1]`. Trả về log-mel **thô** (chưa trừ trung bình).
    ///
    /// Toàn bộ phép tính chạy ở `Double` rồi mới hạ về `Float`, khớp độ chính xác của bản tham chiếu numpy
    /// (cũng tính bằng `float64` rồi `astype(float32)` ở bước cuối).
    static func melSpectrogram(samples: [Float], sampleRate: Int) throws -> Features {
        let length = frameLength(sampleRate: sampleRate)
        let shift = frameShift(sampleRate: sampleRate)
        let padded = paddedLength(sampleRate: sampleRate)
        let bins = numMelBins

        // snip_edges = True: không đệm, chỉ lấy frame nào nằm trọn trong tín hiệu.
        guard samples.count >= length else {
            throw FbankError.audioTooShort(samples: samples.count, frameLength: length)
        }
        let frames = 1 + (samples.count - length) / shift

        let window = poveyWindow(length: length)
        let filters = melFilterBank(sampleRate: sampleRate, numBins: bins, paddedLength: padded)
        let numFFTBins = padded / 2

        var output = [Float](repeating: 0, count: frames * bins)
        var frame = [Double](repeating: 0, count: padded)
        var real = [Double](repeating: 0, count: padded)
        var imag = [Double](repeating: 0, count: padded)

        for frameIndex in 0 ..< frames {
            let start = frameIndex * shift

            // 1. remove_dc_offset
            var mean = 0.0
            for index in 0 ..< length { mean += Double(samples[start + index]) }
            mean /= Double(length)

            // 2. preemphasis (mẫu 0 dùng chính nó: `x[0] -= c·x[0]`) + 3. nhân cửa sổ Povey.
            // Lưu ý: cửa sổ Povey **bằng 0 ở cả hai biên** (`(0.5-0.5·cos 0)^0.85 = 0`), nên số hạng
            // preemphasis ở mẫu 0 bị nhân với 0 ⇒ không ảnh hưởng kết quả. Vẫn viết cho đúng công thức
            // Kaldi để nếu sau này đổi `window_type` thì không âm thầm sai.
            var previous = Double(samples[start]) - mean
            frame[0] = (previous - preemphasisCoefficient * previous) * window[0]
            for index in 1 ..< length {
                let current = Double(samples[start + index]) - mean
                frame[index] = (current - preemphasisCoefficient * previous) * window[index]
                previous = current
            }
            for index in length ..< padded { frame[index] = 0 }

            // 4. FFT → phổ công suất (use_power = True)
            for index in 0 ..< padded {
                real[index] = frame[index]
                imag[index] = 0
            }
            let spectrum = fft(real: real, imag: imag)

            // 5. Năng lượng mel: tích vô hướng phổ công suất với từng bộ lọc.
            for bin in 0 ..< bins {
                let rowStart = bin * numFFTBins
                var energy = 0.0
                for index in 0 ..< numFFTBins {
                    let weight = filters[rowStart + index]
                    if weight == 0 { continue }
                    let re = spectrum.real[index]
                    let im = spectrum.imag[index]
                    energy += (re * re + im * im) * weight
                }
                // 6. Sàn `FLT_EPSILON` rồi log tự nhiên — đúng `ApplyFloor` + `ApplyLog` của Kaldi.
                output[frameIndex * bins + bin] = Float(Foundation.log(max(energy, energyFloor)))
            }
        }
        return Features(frames: frames, bins: bins, values: output)
    }

    /// Bước `extract_fbank(mean_norm=True)` của upstream: trừ trung bình **theo từng bin** qua thời gian.
    ///
    /// Không phải tuỳ chọn: bỏ bước này thì x-vector lệch hẳn mà không báo lỗi (xem doc của type).
    static func meanNormalized(_ features: Features) -> [Float] {
        guard features.frames > 0 else { return features.values }
        var means = [Double](repeating: 0, count: features.bins)
        for frame in 0 ..< features.frames {
            let base = frame * features.bins
            for bin in 0 ..< features.bins { means[bin] += Double(features.values[base + bin]) }
        }
        for bin in 0 ..< features.bins { means[bin] /= Double(features.frames) }

        var result = features.values
        for frame in 0 ..< features.frames {
            let base = frame * features.bins
            for bin in 0 ..< features.bins {
                result[base + bin] = Float(Double(result[base + bin]) - means[bin])
            }
        }
        return result
    }
}
