import Foundation
import CoreML

/// Chọn bộ máy suy luận VieNeu theo (a) toggle người dùng, (b) `coreMLReady`, (c) kết quả self-test đã
/// lưu, (d) ONNX có mặt. **Luôn dựng ORT làm fallback** (không unload) khi Core ML được chọn ⇒ hỗ trợ
/// "rớt từng đoạn về ORT" (plan §2 Q2) mà không đổi logic tổng hợp ở `VieNeuTTSEngine`.
enum VieNeuBackendFactory {
    /// Bộ máy được chọn. `fallback` luôn là ORT khi Core ML được bật, để `runChunk` rớt về ORT từng đoạn.
    struct BackendChoice {
        let primary: VieNeuInferenceBackend
        let fallback: VieNeuONNXRuntime?
    }

    /// `computeUnits` cho Core ML — **`.cpuAndGPU` (LOẠI ANE)**.
    ///
    /// Vì sao KHÔNG còn `.all`: self-test trên **máy thật** (dùng ANE) báo `vector_estimator-T234`
    /// `vel = −2 dB` (rác) ⇒ T234 rớt ORT; nhưng `verify_package` trên CI (macOS VM **không ANE**,
    /// chạy CPU) báo T234 đạt ≥30 dB cho **cùng gói** (sha y hệt). Khác biệt duy nhất là ANE ⇒ ANE
    /// cho kết quả sai với T234 ⇒ lệch âm sắc đoạn dài (ORT) vs đoạn ngắn (Core ML) = "lúc đọc đúng
    /// lúc đọc không đúng". Số đo tốc độ trước đây đến từ **CPU+fp16**, không từ ANE ⇒ bỏ ANE không
    /// mất tốc độ đã đo. (Nếu GPU cũng lỗi thì hạ tiếp `.cpuOnly`.)
    static let coreMLComputeUnits: MLComputeUnits = .cpuAndGPU

    /// Dựng lựa chọn bộ máy.
    ///
    /// - `useCoreML`: toggle người dùng (`VieNeuSynthesisPolicy.vieneuCoreMLEnabled`).
    /// - Trả `primary = ORT, fallback = nil` khi **không** bật Core ML (hoặc Core ML chưa sẵn sàng /
    ///   tự test chưa đạt) — lúc đó ORT vừa là primary vừa là fallback, không tốn RAM Core ML.
    static func make(
        store: VieNeuModelStore,
        config: VieNeuConfig,
        useCoreML: Bool,
        threadCount: Int32
    ) throws -> BackendChoice {
        // ORT chỉ dựng khi có ONNX (`isReady`): nó vừa là primary (khi không bật Core ML) vừa là fallback
        // cho từng chunk (khi bật Core ML). Không có ONNX ⇒ `ort = nil` (Core ML chạy một mình, không có
        // fallback). Nếu ONNX có mặt mà nạp thất bại thì lỗi gốc được ném lên (không bị che bằng "thiếu model").
        let ort: VieNeuONNXRuntime?
        if store.isReady {
            ort = try VieNeuONNXRuntime(modelStore: store, threadCount: threadCount)
        } else {
            ort = nil
        }

        guard useCoreML else {
            guard let ort else {
                throw VieNeuTTSEngine.EngineError.modelMissing(store.missingNames)
            }
            return BackendChoice(primary: ort, fallback: nil)
        }
        guard store.coreMLReady else {
            AppLogger.shared.log("⚠️ [VieNeuBackend] Yêu cầu Core ML nhưng chưa biên dịch xong (coreMLReady=false) — dùng ORT.")
            guard let ort else {
                throw VieNeuTTSEngine.EngineError.modelMissing(store.missingNames)
            }
            return BackendChoice(primary: ort, fallback: nil)
        }
        let capable = VieNeuBackendSelfTest.capableBuckets()
        guard !capable.isEmpty else {
            AppLogger.shared.log("⚠️ [VieNeuBackend] Core ML đã biên dịch nhưng không bucket nào tự test đạt — dùng ORT.")
            guard let ort else {
                throw VieNeuTTSEngine.EngineError.modelMissing(store.missingNames)
            }
            return BackendChoice(primary: ort, fallback: nil)
        }

        // Null branch của ORT (L=2) — dùng cho `vectorEstimatorUnconditioned` khi route sang ORT. Khác null
        // branch của Core ML (L=200). `ort` có thể nil khi chỉ tải Core ML (không có ONNX) ⇒ route không thể
        // thực hiện, nhưng lúc đó `capable` phải gồm mọi bucket (không bucket nào cần route) nên an toàn.
        let ortNull: VieNeuCoreMLRuntime.NullBranch?
        if let ort {
            let branch = try VieNeuTTSEngine.makeNullBranch(backend: ort, config: config)
            ortNull = VieNeuCoreMLRuntime.NullBranch(ctx: branch.context, shape: branch.shape, mask: branch.mask)
        } else {
            ortNull = nil
        }

        let coreML = VieNeuCoreMLRuntime(
            store: store, paddingID: config.padID, computeUnits: coreMLComputeUnits,
            ortFallback: ort, ortNull: ortNull, capableBuckets: capable
        )
        AppLogger.shared.log("🎙️ [VieNeuBackend] Dùng Core ML làm primary (\(capable.count)/\(VieNeuBucketSelector.bucketFrames.count) bucket), ORT làm fallback.")
        return BackendChoice(primary: coreML, fallback: ort)
    }
}
