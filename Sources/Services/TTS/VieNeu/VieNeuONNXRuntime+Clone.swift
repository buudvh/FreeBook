import Foundation

/// Ba graph **clone giọng** của VieNeu-TTS v3 Nano: `speaker_encoder` / `codec_encoder` /
/// `reference_encoder`.
///
/// Tách khỏi `VieNeuONNXRuntime.swift` vì trần **400 dòng vật lý** của repo: thêm ba wrapper vào file
/// chính là đẩy nó lên 420. Đây là cùng khuôn đã dùng cho `VieNeuTTSEngine+Adaptive`,
/// `VieNeuTTSTestView+Sections` và `SeaG2P+Phonemize`.
///
/// **Hệ quả của việc tách file**: Swift giới hạn `private` theo file, nên ba thành viên của
/// `VieNeuONNXRuntime` dùng ở đây đã phải hạ xuống `internal` — `handle`, `consume` và `maximumRank`.
/// Đây là bẫy đã lặp lại nhiều lần trong repo; xem doc của từng thành viên đó.
///
/// ## Ba graph này **khác** bốn graph chính ở đâu
/// Chúng chỉ cần khi người dùng **tạo giọng mới**, và đi theo một ngữ cảnh ORT **riêng**
/// (`init(cloneOnlyModelStore:threadCount:)`) — nạp kèm 4 graph chính thì tốn thêm ~280 MB vô ích.
/// Ngữ cảnh đó **không** dùng được cho `textEncoder`/`durationPredictor`/`vectorEstimator`/`codecDecoder`.
///
/// Chữ ký graph **đã xác nhận bằng `onnxruntime` thật** (plan §5.2):
/// ```
/// speaker_encoder   in 'input'    [batch_size, sequence_length, 80]  float
///                  out 'output'   [batch_size, 192]                  float
/// codec_encoder     in 'wav'      [1, 1, N]                         float
///                  out 'mu'       [1, 24, T]                         float
/// reference_encoder in 'ref'      [1, 144, Tr]                      float
///                     'ref_mask'  [1, Tr]                            bool
///                  out 'style'    [1, 50, 256]                       float
/// ```
/// Tên input/output **không** hardcode ở đây: cầu nối C đọc chúng từ chính session lúc nạp
/// (`SessionGetInputName`/`SessionGetOutputName`), theo bài học "hỏi model, đừng đoán".
extension VieNeuONNXRuntime {
    /// Sức chứa buffer cho x-vector. Thật là **192** (§5.2); cấp dư để graph trả nhiều hơn dự kiến là lỗi
    /// rõ ràng chứ không phải cắt im lặng.
    private static var speakerEmbeddingCapacity: Int { 512 }

    /// Sức chứa buffer cho style token: `n_style × style_dim` = 50 × 256 = **12.800**.
    private static var styleTokenCapacity: Int { 12_800 }

    /// `speaker_encoder(input)` → x-vector.
    ///
    /// `fbank` là ma trận **row-major `frames × melBins` đã trừ trung bình theo bin** (`mean_norm`) —
    /// đúng thứ tự phần tử của input `[1, frames, melBins]`. Số phần tử output **đọc từ shape graph**,
    /// không hardcode `192`.
    func speakerEncoder(fbank: [Float], frames: Int, melBins: Int) throws -> [Float] {
        var message: UnsafeMutablePointer<CChar>?
        var count: Int32 = 0
        let capacity = Self.speakerEmbeddingCapacity
        var output = [Float](repeating: 0, count: capacity)
        let status = output.withUnsafeMutableBufferPointer { outBuffer in
            fbank.withUnsafeBufferPointer { fbankBuffer in
                VieNeuORTRunSpeakerEncoder(
                    handle,
                    fbankBuffer.baseAddress, Int32(frames), Int32(melBins),
                    outBuffer.baseAddress, Int32(capacity),
                    &count, &message
                )
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "speaker_encoder thất bại"))
        }
        if let message { VieNeuORTFreeErrorMessage(message) }
        return Self.trim(output, to: count)
    }

    /// `codec_encoder(wav)` → latent **chưa gộp nhóm** kèm **shape thật**.
    ///
    /// Số kênh (24) và số frame **không** suy được từ công thức ⇒ shape phải đọc từ graph. Sức chứa
    /// buffer lấy từ một chặn trên rộng (hop ≥ 128 mẫu, ≤ 32 kênh); graph trả nhiều hơn thì phía C báo
    /// lỗi rõ chứ **không** ghi tràn.
    func codecEncoder(pcm: [Float]) throws -> (values: [Float], shape: [Int64]) {
        var message: UnsafeMutablePointer<CChar>?
        var count: Int32 = 0
        var rank: Int32 = 0
        var shape = [Int64](repeating: 0, count: Self.maximumRank)
        let capacity = Self.codecLatentCapacity(sampleCount: pcm.count)
        var output = [Float](repeating: 0, count: capacity)
        let status = output.withUnsafeMutableBufferPointer { outBuffer in
            pcm.withUnsafeBufferPointer { pcmBuffer in
                shape.withUnsafeMutableBufferPointer { shapeBuffer in
                    VieNeuORTRunCodecEncoder(
                        handle,
                        pcmBuffer.baseAddress, Int32(pcm.count),
                        outBuffer.baseAddress, Int32(capacity),
                        shapeBuffer.baseAddress, Int32(Self.maximumRank), &rank,
                        &count, &message
                    )
                }
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "codec_encoder thất bại"))
        }
        if let message { VieNeuORTFreeErrorMessage(message) }
        return (Self.trim(output, to: count), Array(shape.prefix(Int(max(0, rank)))))
    }

    /// `reference_encoder(ref, ref_mask)` → style token.
    ///
    /// `latent` là latent **đã gộp nhóm** (`channels` = `latentDim × group` = 144) và `frames` là số frame
    /// **sau khi cắt**. `ref_mask` toàn `true` do phía C tự dựng — đúng `np.ones((1, T), bool)` của
    /// upstream, nên không có tham số nào để truyền.
    func referenceEncoder(latent: [Float], channels: Int, frames: Int) throws -> [Float] {
        var message: UnsafeMutablePointer<CChar>?
        var count: Int32 = 0
        let capacity = Self.styleTokenCapacity
        var output = [Float](repeating: 0, count: capacity)
        let status = output.withUnsafeMutableBufferPointer { outBuffer in
            latent.withUnsafeBufferPointer { latentBuffer in
                VieNeuORTRunReferenceEncoder(
                    handle,
                    latentBuffer.baseAddress, Int32(channels), Int32(frames),
                    outBuffer.baseAddress, Int32(capacity),
                    &count, &message
                )
            }
        }
        guard status == 0 else {
            throw RuntimeError.failure(Self.consume(message, fallback: "reference_encoder thất bại"))
        }
        if let message { VieNeuORTFreeErrorMessage(message) }
        return Self.trim(output, to: count)
    }

    /// Cắt buffer cấp dư về đúng số phần tử graph đã ghi. `count` âm (không xảy ra khi `status == 0`)
    /// được coi là 0 để không cắt quá đà.
    private static func trim(_ values: [Float], to count: Int32) -> [Float] {
        let used = min(values.count, Int(max(0, count)))
        return used == values.count ? values : Array(values.prefix(used))
    }

    /// Chặn trên số phần tử latent của `codec_encoder`.
    ///
    /// Đo được (§5.3): 24 kHz × 5 s = 120.000 mẫu → **468** frame (hop ≈ 256) và **24** kênh. Chặn trên ở
    /// đây dùng hop **128** và 32 kênh — rộng gấp đôi cả hai chiều, đủ để một bản model đổi hop hoặc số
    /// kênh vẫn không làm tràn buffer.
    private static func codecLatentCapacity(sampleCount: Int) -> Int {
        let frames = max(1, sampleCount / 128 + 16)
        return frames * 32
    }
}
