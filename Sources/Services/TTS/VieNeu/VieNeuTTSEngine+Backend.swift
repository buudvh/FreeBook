import Foundation

/// Tách từ `VieNeuTTSEngine.swift` (file đó chạm trần 400 dòng, R6) — nhánh vô điều kiện CFG.
extension VieNeuTTSEngine {
    /// Nhánh **vô điều kiện** của CFG: chạy `text_encoder` với đúng `[bos, eos]` và `null_style`.
    ///
    /// Nhận `backend: VieNeuInferenceBackend` (không còn `VieNeuONNXRuntime`) để `ctx` ra **đúng shape
    /// của bộ máy đang chạy**: ORT giữ `L` động (⇒ ctx `[1, 2, styleDim]`), Core ML đóng băng `L = 200`
    /// (⇒ ctx `[1, 200, styleDim]`). `VieNeuCoreMLRuntime.vectorEstimatorUnconditioned` tự mở rộng
    /// `nullMask` 1→200 nên ở đây chỉ cần trả `[1, 1]`.
    static func makeNullBranch(
        backend: VieNeuInferenceBackend,
        config: VieNeuConfig
    ) throws -> (context: [Float], shape: [Int64], mask: [UInt8]) {
        let context = try backend.textEncoder(
            ids: [config.bosID, config.eosID],
            style: config.constants.nullStyle,
            styleRows: config.nStyle,
            styleColumns: config.styleDim
        )
        return (context.values, context.shape, [1, 1])
    }
}
