import Foundation

/// Tầng ONNX của ZeroTTS: gọi **cầu nối C** khai ở `ZeroTTSONNXBridge.h`.
///
/// Mọi mảng C trả về đều là `malloc` ⇒ Swift phải `free` sau khi copy; riêng các hàm ở đây ghi vào buffer
/// do Swift cấp nên không có `malloc` nào để quên.
///
/// **Một ngữ cảnh = một lượt sinh tại một thời điểm.** Trạng thái `packed_kv`/`full_valid` nằm trong ngữ
/// cảnh C và bị ghi tại chỗ mỗi frame, nên hai lượt sinh chồng nhau sẽ phá nhau. `ZeroTTSEngine` bọc trọn
/// lượt tổng hợp bằng `NSLock` — cùng cách `VieNeuTTSEngine` làm.
final class ZeroTTSONNXRuntime {
    enum RuntimeError: LocalizedError {
        case failure(String)

        var errorDescription: String? {
            switch self {
            case .failure(let message): return "ONNX Runtime (ZeroTTS): \(message)"
            }
        }
    }

    /// Số chiều tối đa nhận từ cầu nối. `cross_kv`/`packed_kv` là 6 chiều.
    static let maximumRank = 8

    let handle: OpaquePointer
    /// Shape **đọc từ graph** lúc nạp. Trường nào model khai là chiều động thì bằng `0`.
    let shapes: ZeroTTSORTShapes

    init(modelDirectory: URL, threadCount: Int32) throws {
        var message: UnsafeMutablePointer<CChar>?
        var shapes = ZeroTTSORTShapes()
        guard let handle = ZeroTTSORTCreate(modelDirectory.path, threadCount, &shapes, &message) else {
            throw RuntimeError.failure(Self.consume(message, fallback: "không tạo được ngữ cảnh ORT"))
        }
        self.handle = handle
        self.shapes = shapes
    }

    deinit {
        ZeroTTSORTDestroy(handle)
    }

    // MARK: - Bốn bước của pipeline

    /// `text_encoder(text_ids, txt_lengths)` → `text_valid`, `soa_embed`, `cross_kv`.
    ///
    /// `crossKv` trả về phải được giữ **nguyên** suốt utterance: mọi `prefix_step` nhận lại đúng buffer
    /// này. `crossKvShape` là shape thật của graph (`(layers, 2, batch, heads, L, headDim)`) — bên gọi
    /// **không** được tự dựng lại.
    func textEncoder(ids: [Int64], batch: Int, length: Int,
                     soaCapacity: Int, crossKvCapacity: Int) throws
        -> (textValid: [UInt8], soa: [Float], crossKv: [Float], crossKvShape: [Int64]) {
        var message: UnsafeMutablePointer<CChar>?
        var crossKvCount: Int32 = 0
        var crossKvRank: Int32 = 0
        var crossKvShape = [Int64](repeating: 0, count: Self.maximumRank)
        var textValid = [UInt8](repeating: 0, count: max(0, batch * length))
        var soa = [Float](repeating: 0, count: max(0, soaCapacity))
        var crossKv = [Float](repeating: 0, count: max(0, crossKvCapacity))
        // Đọc `.count` **trước** khi vào `withUnsafeMutableBufferPointer`: đọc `soa.count` bên trong
        // closure của chính `soa` là truy cập chồng lấn — Swift báo `overlapping accesses to 'soa', but
        // modification requires exclusive access`, và đó là **lỗi biên dịch**, không phải cảnh báo.
        let soaCount = soa.count
        let crossKvLength = crossKv.count

        let status = textValid.withUnsafeMutableBufferPointer { textValidBuffer in
            soa.withUnsafeMutableBufferPointer { soaBuffer in
                crossKv.withUnsafeMutableBufferPointer { crossKvBuffer in
                    crossKvShape.withUnsafeMutableBufferPointer { shapeBuffer in
                        ids.withUnsafeBufferPointer { idsBuffer in
                            ZeroTTSORTRunTextEncoder(
                                handle,
                                idsBuffer.baseAddress, Int32(batch), Int32(length),
                                textValidBuffer.baseAddress,
                                soaBuffer.baseAddress, Int32(soaCount),
                                crossKvBuffer.baseAddress, Int32(crossKvLength), &crossKvCount,
                                shapeBuffer.baseAddress, Int32(Self.maximumRank), &crossKvRank,
                                &message
                            )
                        }
                    }
                }
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "text_encoder thất bại"))
        }
        if let message { ZeroTTSORTFreeErrorMessage(message) }
        return (textValid,
                soa,
                Array(crossKv.prefix(Int(max(0, crossKvCount)))),
                Array(crossKvShape.prefix(Int(max(0, crossKvRank)))))
    }

    /// Cấp phát lại KV cho một utterance mới.
    func beginSequence(batch: Int, voiceCount: Int, maxFrames: Int,
                       layers: Int, heads: Int, headDim: Int) throws {
        var message: UnsafeMutablePointer<CChar>?
        let status = ZeroTTSORTBeginSequence(handle, Int32(batch), Int32(voiceCount), Int32(maxFrames),
                                             Int32(layers), Int32(heads), Int32(headDim), &message)
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "cấp phát KV cache thất bại"))
        }
        if let message { ZeroTTSORTFreeErrorMessage(message) }
    }

    /// Cold start của `prefix_step`: nạp khối `[voice ‖ soa]`. Trả `hidden` ở vị trí cuối, `(batch, dModel)`.
    func prefixInit(externalEmbed: [Float], soa: [Float],
                    crossKv: [Float], crossKvShape: [Int64], textValid: [UInt8],
                    batch: Int, dModel: Int) throws -> [Float] {
        var message: UnsafeMutablePointer<CChar>?
        var hidden = [Float](repeating: 0, count: max(0, batch * dModel))
        let status = hidden.withUnsafeMutableBufferPointer { hiddenBuffer in
            externalEmbed.withUnsafeBufferPointer { externalBuffer in
                soa.withUnsafeBufferPointer { soaBuffer in
                    crossKv.withUnsafeBufferPointer { crossKvBuffer in
                        crossKvShape.withUnsafeBufferPointer { shapeBuffer in
                            textValid.withUnsafeBufferPointer { validBuffer in
                                ZeroTTSORTRunPrefixInit(
                                    handle,
                                    externalBuffer.baseAddress,
                                    soaBuffer.baseAddress,
                                    crossKvBuffer.baseAddress, Int32(crossKv.count),
                                    shapeBuffer.baseAddress, Int32(crossKvShape.count),
                                    validBuffer.baseAddress, Int32(textValid.count),
                                    hiddenBuffer.baseAddress,
                                    &message
                                )
                            }
                        }
                    }
                }
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "prefix_step (cold start) thất bại"))
        }
        if let message { ZeroTTSORTFreeErrorMessage(message) }
        return hidden
    }

    /// Một frame của `prefix_step`. `frameCodes` là `(batch, codebooks)` vừa lấy từ `localFrameDecode`.
    func prefixFrame(frameCodes: [Int64], frameIndex: Int, voiceCount: Int,
                     crossKv: [Float], crossKvShape: [Int64], textValid: [UInt8],
                     batch: Int, dModel: Int) throws -> [Float] {
        var message: UnsafeMutablePointer<CChar>?
        var hidden = [Float](repeating: 0, count: max(0, batch * dModel))
        let status = hidden.withUnsafeMutableBufferPointer { hiddenBuffer in
            frameCodes.withUnsafeBufferPointer { codesBuffer in
                crossKv.withUnsafeBufferPointer { crossKvBuffer in
                    crossKvShape.withUnsafeBufferPointer { shapeBuffer in
                        textValid.withUnsafeBufferPointer { validBuffer in
                            ZeroTTSORTRunPrefixFrame(
                                handle,
                                codesBuffer.baseAddress,
                                Int32(frameIndex), Int32(voiceCount),
                                crossKvBuffer.baseAddress, Int32(crossKv.count),
                                shapeBuffer.baseAddress, Int32(crossKvShape.count),
                                validBuffer.baseAddress, Int32(textValid.count),
                                hiddenBuffer.baseAddress,
                                &message
                            )
                        }
                    }
                }
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "prefix_step (frame) thất bại"))
        }
        if let message { ZeroTTSORTFreeErrorMessage(message) }
        return hidden
    }

    /// Một frame audio: `is_eoa` + `codes` (`codebooks` phần tử).
    ///
    /// `seenMask` bị **sửa tại chỗ** trong hàm này (đánh dấu code vừa lấy cho từng codebook), nên nó là
    /// `inout` và phải là mảng **của riêng lượt sinh** — dùng chung giữa hai lượt sẽ mang lịch sử phạt
    /// lặp của lượt trước sang lượt sau.
    func localFrameDecode(hidden: [Float], batch: Int, dModel: Int, forbidEoa: Bool,
                          sampling: ZeroTTSConfig.Sampling, seenMask: inout [UInt8],
                          ctrlRandomU: Float, audioRandomU: [Float],
                          codebooks: Int) throws -> (isEoa: Bool, codes: [Int64]) {
        var message: UnsafeMutablePointer<CChar>?
        var ctrlRandom = ctrlRandomU
        var isEoa: UInt8 = 0
        var codes = [Int64](repeating: 0, count: max(0, codebooks))
        var codeCount: Int32 = 0
        // Đọc trước khi vào closure: truy cập `seenMask.count`/`codes.count` bên trong
        // `withUnsafeMutableBufferPointer` của chính chúng là vi phạm exclusivity (lỗi biên dịch).
        let seenCount = seenMask.count
        let codesLength = codes.count

        let status = seenMask.withUnsafeMutableBufferPointer { seenBuffer in
            hidden.withUnsafeBufferPointer { hiddenBuffer in
                audioRandomU.withUnsafeBufferPointer { randomBuffer in
                    codes.withUnsafeMutableBufferPointer { codesBuffer in
                        ZeroTTSORTRunLocalFrameDecode(
                            handle,
                            hiddenBuffer.baseAddress, Int32(batch), Int32(dModel),
                            forbidEoa ? 1 : 0,
                            sampling.textTemperature, Int64(sampling.textTopK),
                            sampling.audioTemperature, Int64(sampling.audioTopK),
                            sampling.audioTopP, sampling.audioRepetitionPenalty, sampling.cfgScale,
                            seenBuffer.baseAddress, Int32(seenCount),
                            &ctrlRandom,
                            randomBuffer.baseAddress, Int32(audioRandomU.count),
                            &isEoa,
                            codesBuffer.baseAddress, Int32(codesLength), &codeCount,
                            &message
                        )
                    }
                }
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "local_frame_decode thất bại"))
        }
        if let message { ZeroTTSORTFreeErrorMessage(message) }
        return (isEoa != 0, Array(codes.prefix(Int(max(0, codeCount)))))
    }

    /// `decode_full(codes)` → PCM mono float32. `codesKT` là `(codebooks, frames)` int32; cầu nối tự
    /// chuyển vị sang `(1, T, K)` mà graph codec đòi.
    func codecDecode(codesKT: [Int32], codebooks: Int, frames: Int, pcmCapacity: Int) throws -> [Float] {
        var message: UnsafeMutablePointer<CChar>?
        var count: Int32 = 0
        var pcm = [Float](repeating: 0, count: max(0, pcmCapacity))
        // Cùng lý do như `textEncoder`: `pcm.count` phải đọc trước closure của chính nó.
        let pcmCount = pcm.count
        let status = pcm.withUnsafeMutableBufferPointer { pcmBuffer in
            codesKT.withUnsafeBufferPointer { codesBuffer in
                ZeroTTSORTRunCodecDecodeFull(
                    handle,
                    codesBuffer.baseAddress, Int32(codebooks), Int32(frames),
                    pcmBuffer.baseAddress, Int32(pcmCount), &count,
                    &message
                )
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "codec decode thất bại"))
        }
        if let message { ZeroTTSORTFreeErrorMessage(message) }
        return Array(pcm.prefix(Int(max(0, count))))
    }

    /// Đọc chuỗi lỗi C rồi giải phóng nó — bên gọi **không** được dùng `message` sau hàm này.
    private static func consume(_ message: UnsafeMutablePointer<CChar>?, fallback: String) -> String {
        guard let message else { return fallback }
        let text = String(cString: message)
        ZeroTTSORTFreeErrorMessage(message)
        return text
    }
}
