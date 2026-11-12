import Foundation

/// Graph **khử nhiễu** `denoiser.onnx` (lõi resemble-enhance) cho đường nhân bản giọng VieNeu Turbo (1.3.890).
///
/// Chỉ có trên ngữ cảnh `init(turboCloneModelStore:threadCount:loadsDenoiser: true)`. Tách file vì trần 400 dòng, cùng
/// khuôn `VieNeuONNXRuntime+Clone` (dùng `handle` / `consume` đã hạ xuống `internal`).
///
/// Chữ ký graph (đọc bằng `onnxruntime` thật trên file của kho mirror, 42.661.414 byte):
/// ```
/// denoiser  in  'mag' 'cos' 'sin'                 [b, 841, t]  float
///           out 'sep_mag' 'sep_cos' 'sep_sin'     [b, 841, t]  float
/// ```
/// 841 = `n_fft / 2 + 1` với `n_fft` 1680. STFT / iSTFT quanh graph là việc của `VieNeuDenoiserSTFT`.
extension VieNeuONNXRuntime {
    /// Ba ma trận ra của graph, cùng bố cục với vào: **phẳng theo tần số** `bins × frames`.
    struct DenoisedSpectrum: Sendable {
        let magnitude: [Float]
        let cosine: [Float]
        let sine: [Float]
    }

    var hasDenoiser: Bool { VieNeuORTHasDenoiser(handle) == 1 }

    /// `denoiser(mag, cos, sin)` → `(sep_mag, sep_cos, sep_sin)`. Ba mảng vào là `[1, bins, frames]` phẳng theo hàng
    /// (hàng = bin tần số).
    func denoise(magnitude: [Float], cosine: [Float], sine: [Float], bins: Int, frames: Int) throws -> DenoisedSpectrum {
        let count = bins * frames
        guard bins > 0, frames > 0, magnitude.count == count, cosine.count == count, sine.count == count else {
            throw RuntimeError.failure("denoiser: phổ vào sai kích thước (\(bins)×\(frames))")
        }
        var message: UnsafeMutablePointer<CChar>?
        var outMagnitude = [Float](repeating: 0, count: count)
        var outCosine = [Float](repeating: 0, count: count)
        var outSine = [Float](repeating: 0, count: count)
        let status = magnitude.withUnsafeBufferPointer { magnitudeIn in
            cosine.withUnsafeBufferPointer { cosineIn in
                sine.withUnsafeBufferPointer { sineIn in
                    outMagnitude.withUnsafeMutableBufferPointer { magnitudeOut in
                        outCosine.withUnsafeMutableBufferPointer { cosineOut in
                            outSine.withUnsafeMutableBufferPointer { sineOut in
                                VieNeuORTRunDenoiser(
                                    handle,
                                    magnitudeIn.baseAddress, cosineIn.baseAddress, sineIn.baseAddress,
                                    Int32(bins), Int32(frames),
                                    magnitudeOut.baseAddress, cosineOut.baseAddress, sineOut.baseAddress,
                                    Int32(count), &message
                                )
                            }
                        }
                    }
                }
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "denoiser thất bại"))
        }
        if let message { VieNeuORTFreeErrorMessage(message) }
        return DenoisedSpectrum(magnitude: outMagnitude, cosine: outCosine, sine: outSine)
    }
}
