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

    /// `computeUnits` cho Core ML — `.all` (ANE + GPU + CPU) theo plan §4.3.
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
        guard VieNeuBackendSelfTest.isPassed() else {
            AppLogger.shared.log("⚠️ [VieNeuBackend] Core ML đã biên dịch nhưng tự test chưa đạt — dùng ORT.")
            guard let ort else {
                throw VieNeuTTSEngine.EngineError.modelMissing(store.missingNames)
            }
            return BackendChoice(primary: ort, fallback: nil)
        }

        let coreML = VieNeuCoreMLRuntime(store: store, paddingID: config.padID, computeUnits: coreMLComputeUnits)
        AppLogger.shared.log("🎙️ [VieNeuBackend] Dùng Core ML làm primary, ORT làm fallback.")
        return BackendChoice(primary: coreML, fallback: ort)
    }
}
