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

    /// `computeUnits` cho Core ML — `.all` (ANE + GPU + CPU).
    ///
    /// ⚠️ **1.3.497 từng đổi sang `.cpuAndGPU` để "loại ANE"** (giả thuyết ANE làm hỏng T234) — **SAI**:
    /// log `app_logs (71).txt` cho thấy T234 vẫn `vel=-2dB` dưới **cả** GPU/CPU, còn T64/T96 **TỤT**
    /// 50 → 42/41 dB (ANE chính xác hơn GPU). Revert về `.all` ở 1.3.498. Xem `Docs/CodeGraph/CHANGELOG.md`.
    static let coreMLComputeUnits: MLComputeUnits = .all

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
