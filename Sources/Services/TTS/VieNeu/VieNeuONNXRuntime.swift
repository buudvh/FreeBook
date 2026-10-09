import Foundation

/// Tầng ONNX của engine VieNeu-TTS: gọi **cầu nối C** khai ở `VieNeuONNXBridge.h`.
///
/// ## Vì sao không dùng lớp ObjC (`OnnxRuntimeBindings`) như `ONNXPiperEngine`
/// `ctx_mask` của `duration_predictor.onnx` và `vector_estimator.onnx` khai `elem_type = 9 = BOOL` (đọc
/// trực tiếp protobuf của model; node duy nhất dùng nó là `Not`, mà `Not` của ONNX chỉ nhận bool nên
/// không có đường vá sang kiểu số). Nhưng `ORTTensorElementDataType` của wrapper ObjC **không có case
/// `Bool`** ở **mọi** bản còn dùng được — đã kiểm `ort_enums.h` tại ORT v1.16.0, v1.20.0, v1.24.2 (bản
/// gói SPM `from: 1.16.0` resolve tới) và cả `main` của gói SPM; chỉ `main` của **ORT core** mới có, và
/// nó chưa phát hành.
///
/// ## Vì sao phải qua file C trung gian
/// `import onnxruntime` **không** hoạt động: product SPM `onnxruntime` chỉ trỏ tới target ObjC
/// `OnnxRuntimeBindings`, còn binary target C là dependency **nội bộ** của target đó, và umbrella header
/// `onnxruntime.h` không `#import` header C API ⇒ module C không nằm trong tầm import của target app.
/// Nên phần C API nằm ở `VieNeuONNXBridge.m`, và Swift thấy nó qua bridging header (khai ở `project.yml`).
///
/// ## Shape của `ctx` là dữ liệu, không phải hằng số
/// `textEncoder` trả **cả shape thật** của tensor, và `durationPredictor`/`vectorEstimator` bắt buộc
/// nhận lại đúng shape đó. Bản đầu tự dựng `[1, L, dim]` với `dim = 512` đọc từ `config.json`, nên
/// `duration_predictor` báo `Got: 512 Expected: 256` — chiều thật của `ctx` là `style_dim` (256), còn
/// `dim` là một chiều khác của kiến trúc. Đây là lần thứ ba trong engine này cùng một loại lỗi: **đoán
/// thay vì hỏi model**.
///
/// Mọi mảng C trả về là `malloc` ⇒ Swift phải `free` sau khi copy.
final class VieNeuONNXRuntime {
    enum RuntimeError: LocalizedError {
        case failure(String)

        var errorDescription: String? {
            switch self {
            case .failure(let message): return "ONNX Runtime: \(message)"
            }
        }
    }

    /// Số chiều tối đa nhận từ `GetDimensions` — mọi tensor của pipeline đều ≤ 3 chiều.
    ///
    /// `internal` (không `private`) vì `VieNeuONNXRuntime+Clone` — file khác — cũng dùng để cấp buffer
    /// shape cho `codec_encoder`. Swift giới hạn `private` theo file.
    static let maximumRank = 8

    /// Handle ngữ cảnh ORT.
    ///
    /// `internal` (không `private`) vì `VieNeuONNXRuntime+Clone` — file khác — gọi thẳng cầu nối C cho 3
    /// graph clone. Cùng lý do và cùng khuôn với `VieNeuTTSEngine+Adaptive`: Swift giới hạn `private`
    /// theo file, nên tách file là phải hạ quyền truy cập của đúng những thành viên dùng chéo file.
    let handle: OpaquePointer

    /// Số luồng ORT và cờ spin **thật sự** dùng khi tạo ngữ cảnh này — để log `[VieNeuPerf]` báo đúng
    /// cấu hình đang chạy. Không đọc lại `UserDefaults`: engine là singleton không bao giờ nạp lại,
    /// nên đổi cài đặt chỉ có hiệu lực sau khi tắt hẳn app rồi mở lại.
    let threadCount: Int32
    let allowSpinning: Bool

    init(modelStore: VieNeuModelStore, threadCount: Int32, allowSpinning: Bool = false) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard let handle = VieNeuORTCreate(modelStore.modelsURL.path, threadCount, allowSpinning ? 1 : 0, &message) else {
            throw RuntimeError.failure(Self.consume(message, fallback: "không tạo được ngữ cảnh ORT"))
        }
        self.handle = handle
        self.threadCount = threadCount
        self.allowSpinning = allowSpinning
    }

    /// Ngữ cảnh **chỉ 3 graph clone** — dùng cho luồng tạo giọng.
    ///
    /// Cố ý **không** dùng `init(modelStore:threadCount:)`: ngữ cảnh đó nạp thêm 4 graph chính (~280 MB)
    /// mà luồng tạo giọng không cần, còn chia sẻ ngữ cảnh của `VieNeuTTSEngine` thì không được — engine
    /// giữ nó ở mức `private` và plan C2 cấm sửa file đó. Nhờ vậy đỉnh bộ nhớ lúc tạo giọng chỉ +~91 MB
    /// thay vì +~371 MB, và **nhả hết** khi xong (`deinit`).
    ///
    /// Ngữ cảnh này **không** dùng được cho `textEncoder`/`durationPredictor`/… (session 4 bước là `NULL`).
    init(cloneOnlyModelStore modelStore: VieNeuModelStore, threadCount: Int32, allowSpinning: Bool = false) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard let handle = VieNeuORTCreateCloneOnly(modelStore.modelsURL.path, threadCount, allowSpinning ? 1 : 0, &message) else {
            throw RuntimeError.failure(Self.consume(message, fallback: "không nạp được gói graph clone"))
        }
        self.handle = handle
        self.threadCount = threadCount
        self.allowSpinning = allowSpinning
    }

    deinit {
        VieNeuORTDestroy(handle)
    }

    // MARK: - Bốn bước của pipeline

    /// `text_encoder(ids, style)` → `ctx` kèm **shape thật** để hai bước sau dùng lại.
    func textEncoder(
        ids: [Int64],
        style: [Float],
        styleRows: Int,
        styleColumns: Int
    ) throws -> (values: [Float], shape: [Int64]) {
        var count: Int32 = 0
        var rank: Int32 = 0
        var shape = [Int64](repeating: 0, count: Self.maximumRank)
        var message: UnsafeMutablePointer<CChar>?
        let pointer = ids.withUnsafeBufferPointer { idsBuffer in
            style.withUnsafeBufferPointer { styleBuffer in
                shape.withUnsafeMutableBufferPointer { shapeBuffer in
                    VieNeuORTRunTextEncoder(
                        handle,
                        idsBuffer.baseAddress, Int32(ids.count),
                        styleBuffer.baseAddress, Int32(styleRows), Int32(styleColumns),
                        &count,
                        shapeBuffer.baseAddress, Int32(Self.maximumRank), &rank,
                        &message
                    )
                }
            }
        }
        let values = try Self.take(pointer, count: count, message: message)
        return (values, Array(shape.prefix(Int(max(0, rank)))))
    }

    /// `duration_predictor(ctx, ctx_mask, spk)` → `log_s`.
    func durationPredictor(
        context: [Float],
        contextShape: [Int64],
        mask: [UInt8],
        speaker: [Float]
    ) throws -> Float {
        var value: Float = 0
        var message: UnsafeMutablePointer<CChar>?
        let status = context.withUnsafeBufferPointer { contextBuffer in
            contextShape.withUnsafeBufferPointer { shapeBuffer in
                mask.withUnsafeBufferPointer { maskBuffer in
                    speaker.withUnsafeBufferPointer { speakerBuffer in
                        VieNeuORTRunDurationPredictor(
                            handle,
                            contextBuffer.baseAddress, shapeBuffer.baseAddress, Int32(contextShape.count),
                            maskBuffer.baseAddress,
                            speakerBuffer.baseAddress, Int32(speaker.count),
                            &value, &message
                        )
                    }
                }
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "duration_predictor thất bại"))
        }
        if let message { VieNeuORTFreeErrorMessage(message) }
        return value
    }

    /// `vector_estimator(x, t, ctx, ctx_mask, spk, style)` → velocity cùng shape với `x`.
    ///
    /// Ghi thẳng vào buffer do Swift cấp (`withUnsafeMutableBufferPointer`) ⇒ bỏ `malloc` ở phía C và bỏ
    /// một tầng `memcpy` so với hợp đồng `float*` cũ. Số phần tử đã biết trước (`latentChannels × frames`)
    /// vì velocity **cùng shape** với `x`.
    func vectorEstimator(
        latent: [Float],
        time: Float,
        context: [Float],
        contextShape: [Int64],
        mask: [UInt8],
        speaker: [Float],
        style: [Float],
        styleRows: Int,
        styleColumns: Int,
        latentChannels: Int,
        frames: Int
    ) throws -> [Float] {
        var message: UnsafeMutablePointer<CChar>?
        var count: Int32 = 0
        let capacity = max(0, latentChannels * frames)
        var output = [Float](repeating: 0, count: capacity)
        let status = output.withUnsafeMutableBufferPointer { outBuffer in
            latent.withUnsafeBufferPointer { latentBuffer in
                context.withUnsafeBufferPointer { contextBuffer in
                    contextShape.withUnsafeBufferPointer { shapeBuffer in
                        mask.withUnsafeBufferPointer { maskBuffer in
                            speaker.withUnsafeBufferPointer { speakerBuffer in
                                style.withUnsafeBufferPointer { styleBuffer in
                                    VieNeuORTRunVectorEstimatorInto(
                                        handle,
                                        latentBuffer.baseAddress, Int32(latentChannels), Int32(frames),
                                        time,
                                        contextBuffer.baseAddress, shapeBuffer.baseAddress, Int32(contextShape.count),
                                        maskBuffer.baseAddress,
                                        speakerBuffer.baseAddress, Int32(speaker.count),
                                        styleBuffer.baseAddress, Int32(styleRows), Int32(styleColumns),
                                        outBuffer.baseAddress, Int32(capacity),
                                        &count, &message
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "vector_estimator thất bại"))
        }
        if let message { VieNeuORTFreeErrorMessage(message) }
        if count < capacity { output.removeLast(capacity - Int(max(0, count))) }
        return output
    }

    /// Nhánh **vô điều kiện** của CFG — dùng tensor cache cho `ctx`/`ctx_mask`/`spk`/`style`.
    ///
    /// Bốn tensor đó là loop-invariant (đến từ `null_spk`/`null_style`, không phụ thuộc giọng hay văn bản)
    /// nên dựng một lần cho cả 8 bước Euler. **Buffer truyền vào phải sống tới `resetVectorCache()`** —
    /// đây là bất biến của `CreateTensorWithDataAsOrtValue` (không copy), nên engine có trách nhiệm gọi
    /// `resetVectorCache()` ngay khi thay `nullContext`/`nullMask`/`nullSpeaker`/`nullStyle`.
    func vectorEstimatorUnconditioned(
        latent: [Float],
        time: Float,
        nullContext: [Float],
        nullContextShape: [Int64],
        nullMask: [UInt8],
        nullSpeaker: [Float],
        nullStyle: [Float],
        styleRows: Int,
        styleColumns: Int,
        latentChannels: Int,
        frames: Int
    ) throws -> [Float] {
        var message: UnsafeMutablePointer<CChar>?
        var count: Int32 = 0
        let capacity = max(0, latentChannels * frames)
        var output = [Float](repeating: 0, count: capacity)
        var elementCount: Int64 = 1
        for dimension in nullContextShape { elementCount *= dimension }
        let status = output.withUnsafeMutableBufferPointer { outBuffer in
            latent.withUnsafeBufferPointer { latentBuffer in
                nullContext.withUnsafeBufferPointer { contextBuffer in
                    nullContextShape.withUnsafeBufferPointer { shapeBuffer in
                        nullMask.withUnsafeBufferPointer { maskBuffer in
                            nullSpeaker.withUnsafeBufferPointer { speakerBuffer in
                                nullStyle.withUnsafeBufferPointer { styleBuffer in
                                    VieNeuORTRunVectorEstimatorUnconditionedInto(
                                        handle,
                                        latentBuffer.baseAddress, Int32(latentChannels), Int32(frames),
                                        time,
                                        contextBuffer.baseAddress, elementCount,
                                        shapeBuffer.baseAddress, Int32(nullContextShape.count),
                                        maskBuffer.baseAddress, Int32(nullMask.count),
                                        speakerBuffer.baseAddress, Int32(nullSpeaker.count),
                                        styleBuffer.baseAddress, Int32(styleRows), Int32(styleColumns),
                                        outBuffer.baseAddress, Int32(capacity),
                                        &count, &message
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "vector_estimator (null) thất bại"))
        }
        if let message { VieNeuORTFreeErrorMessage(message) }
        if count < capacity { output.removeLast(capacity - Int(max(0, count))) }
        return output
    }

    /// Huỷ tensor cache nhánh vô điều kiện — **bắt buộc** trước khi thay các mảng null của engine.
    func resetVectorCache() {
        VieNeuORTResetVectorCache(handle)
    }

    /// Số `OrtValue` tạo/giải phóng và số byte output đã copy tích luỹ. Chỉ dùng để ghi log chẩn đoán.
    /// Trả **tuple 3 phần tử** để bên gọi gán thẳng vào `Timing` mà không cần biến trung gian.
    var churnSnapshot: (Int64, Int64, Int64) {
        var creates: Int64 = 0
        var releases: Int64 = 0
        var bytes: Int64 = 0
        VieNeuORTChurnSnapshot(handle, &creates, &releases, &bytes)
        return (creates, releases, bytes)
    }

    /// Đưa bộ đếm churn về 0 — gọi đầu mỗi lượt tổng hợp.
    func resetChurnCounters() {
        VieNeuORTResetChurnCounters(handle)
    }

    /// `codec_decoder(x)` → PCM float32. Số mẫu đọc từ shape thật ở phía C.
    func codecDecoder(latent: [Float], latentChannels: Int, frames: Int) throws -> [Float] {
        var count: Int32 = 0
        var message: UnsafeMutablePointer<CChar>?
        let pointer = latent.withUnsafeBufferPointer { latentBuffer in
            VieNeuORTRunCodecDecoder(
                handle,
                latentBuffer.baseAddress, Int32(latentChannels), Int32(frames),
                &count, &message
            )
        }
        return try Self.take(pointer, count: count, message: message)
    }


    // MARK: - Chuyển kết quả C sang Swift

    /// Copy mảng `malloc` của C sang Swift rồi `free`. `count` là số phần tử do phía C ghi ra.
    private static func take(
        _ pointer: UnsafeMutablePointer<Float>?,
        count: Int32,
        message: UnsafeMutablePointer<CChar>?
    ) throws -> [Float] {
        guard let pointer else {
            throw RuntimeError.failure(consume(message, fallback: "graph trả về con trỏ rỗng"))
        }
        let values = Array(UnsafeBufferPointer(start: pointer, count: Int(max(0, count))))
        free(pointer)
        if let message { VieNeuORTFreeErrorMessage(message) }
        return values
    }

    /// Đọc chuỗi lỗi C rồi giải phóng nó — bên gọi **không** được dùng `message` sau hàm này.
    ///
    /// `internal` (không `private`) vì `VieNeuONNXRuntime+Clone` cũng dùng — cùng lý do như `handle`.
    static func consume(_ message: UnsafeMutablePointer<CChar>?, fallback: String) -> String {
        guard let message else { return fallback }
        let text = String(cString: message)
        VieNeuORTFreeErrorMessage(message)
        return text
    }
}
