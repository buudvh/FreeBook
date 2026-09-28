import Foundation

/// Tầng ONNX của engine VieNeu-TTS: gọi **cầu nối C** khai ở `VieNeuONNXBridge.h`.
///
/// ## Vì sao không dùng lớp ObjC (`OnnxRuntimeBindings`) như `ONNXPiperEngine`
/// `ctx_mask` của `duration_predictor.onnx` và `vector_estimator.onnx` khai `elem_type = 9 = BOOL` (đọc
/// trực tiếp protobuf của model; node duy nhất dùng nó là `Not`, mà `Not` của ONNX chỉ nhận bool nên
/// không có đường vá sang kiểu số). Nhưng `ORTTensorElementDataType` của wrapper ObjC **không có case
/// `Bool`** ở **mọi** bản còn dùng được — đã kiểm `ort_enums.h` tại ORT v1.16.0, v1.20.0, v1.24.2 (bản
/// gói SPM `from: 1.16.0` resolve tới) và cả `main` của gói SPM; chỉ `main` của **ORT core** mới có, và
/// nó chưa phát hành. Hàm map `PublicToCAPITensorElementType` dùng bảng tra + throw nên
/// `ORTTensorElementDataType(rawValue: 9)` cũng không lọt, và `ORTValue` không có init nào nhận con trỏ
/// C `OrtValue*`.
///
/// ## Vì sao phải qua file C trung gian
/// `import onnxruntime` **không** hoạt động: product SPM `onnxruntime` chỉ trỏ tới target ObjC
/// `OnnxRuntimeBindings`, còn binary target C là dependency **nội bộ** của target đó, và umbrella header
/// `onnxruntime.h` không `#import` header C API ⇒ module C không nằm trong tầm import của target app.
/// Nên phần C API nằm ở `VieNeuONNXBridge.m` (C thuần, mọi kiểu chắc chắn theo header), và Swift chỉ
/// gọi bốn hàm typed đúng bằng bốn bước pipeline. Bridging header khai ở `project.yml`.
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

    private let handle: OpaquePointer

    init(modelStore: VieNeuModelStore, threadCount: Int32) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard let handle = VieNeuORTCreate(modelStore.modelsURL.path, threadCount, &message) else {
            throw RuntimeError.failure(Self.consume(message, fallback: "không tạo được ngữ cảnh ORT"))
        }
        self.handle = handle
    }

    deinit {
        VieNeuORTDestroy(handle)
    }

    // MARK: - Bốn bước của pipeline

    /// `text_encoder(ids, style)` → `ctx` phẳng theo hàng, shape `[1, length, dim]`.
    func textEncoder(ids: [Int64], style: [Float], styleRows: Int, styleColumns: Int, dim: Int) throws -> [Float] {
        var count: Int32 = 0
        var message: UnsafeMutablePointer<CChar>?
        let pointer = ids.withUnsafeBufferPointer { idsBuffer in
            style.withUnsafeBufferPointer { styleBuffer in
                VieNeuORTRunTextEncoder(
                    handle,
                    idsBuffer.baseAddress, Int32(ids.count),
                    styleBuffer.baseAddress, Int32(styleRows), Int32(styleColumns),
                    &count, &message
                )
            }
        }
        return try Self.take(pointer, count: count, message: message)
    }

    /// `duration_predictor(ctx, ctx_mask, spk)` → `log_s`.
    func durationPredictor(
        context: [Float],
        length: Int,
        mask: [UInt8],
        speaker: [Float],
        dim: Int
    ) throws -> Float {
        var value: Float = 0
        var message: UnsafeMutablePointer<CChar>?
        let status = context.withUnsafeBufferPointer { contextBuffer in
            mask.withUnsafeBufferPointer { maskBuffer in
                speaker.withUnsafeBufferPointer { speakerBuffer in
                    VieNeuORTRunDurationPredictor(
                        handle,
                        contextBuffer.baseAddress, Int32(length), Int32(dim),
                        maskBuffer.baseAddress,
                        speakerBuffer.baseAddress, Int32(speaker.count),
                        &value, &message
                    )
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
    func vectorEstimator(
        latent: [Float],
        time: Float,
        context: [Float],
        length: Int,
        mask: [UInt8],
        speaker: [Float],
        style: [Float],
        styleRows: Int,
        styleColumns: Int,
        latentChannels: Int,
        frames: Int,
        dim: Int
    ) throws -> [Float] {
        var count: Int32 = 0
        var message: UnsafeMutablePointer<CChar>?
        let pointer = latent.withUnsafeBufferPointer { latentBuffer in
            context.withUnsafeBufferPointer { contextBuffer in
                mask.withUnsafeBufferPointer { maskBuffer in
                    speaker.withUnsafeBufferPointer { speakerBuffer in
                        style.withUnsafeBufferPointer { styleBuffer in
                            VieNeuORTRunVectorEstimator(
                                handle,
                                latentBuffer.baseAddress, Int32(latentChannels), Int32(frames),
                                time,
                                contextBuffer.baseAddress, Int32(length), Int32(dim),
                                maskBuffer.baseAddress,
                                speakerBuffer.baseAddress, Int32(speaker.count),
                                styleBuffer.baseAddress, Int32(styleRows), Int32(styleColumns),
                                &count, &message
                            )
                        }
                    }
                }
            }
        }
        return try Self.take(pointer, count: count, message: message)
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
    private static func consume(_ message: UnsafeMutablePointer<CChar>?, fallback: String) -> String {
        guard let message else { return fallback }
        let text = String(cString: message)
        VieNeuORTFreeErrorMessage(message)
        return text
    }
}
