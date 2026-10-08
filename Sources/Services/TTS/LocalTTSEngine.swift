import Foundation

/// Giao diện chung cho các engine TTS **local** — Piper (`PiperTTSService`) và VieNeu
/// (`VieNeuTTSService`).
///
/// Mục đích: `TTSManager` chọn engine bằng một **computed property** (`localEngine`) thay vì thêm nhánh
/// `if tool == …` ở từng call site. Nhờ vậy `TTSManager.swift` — file đang **4026/3470** dòng, luật
/// ratchet-down cấm thêm dòng — không phải mọc thêm nhánh nào.
///
/// **Tính chất an toàn**: `localEngine` trả `nghiTTSService` cho **mọi** tool trừ `vieneu`, nên đường
/// NghiTTS đi y hệt code cũ. Đây là thứ phải giữ bằng mọi giá khi sửa tiếp.
///
/// Chữ ký ở đây lấy **nguyên** từ `PiperTTSService` (đã có `boundaryKind`), và `VieNeuTTSService` được
/// thêm tham số đó cho khớp — VieNeu **bỏ qua** nó vì nó tự phân loại ranh giới theo **dấu câu**
/// (`Chunk.Gap`), chứ không theo `boundaryKind` của tầng gọi.
protocol LocalTTSEngine: AnyObject {
    /// Chuỗi mô tả engine để hiện lên UI.
    var engineStatus: String { get }

    /// Nạp model cho một giọng. Idempotent.
    func prepare(voice: String) async throws

    func synthesize(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind,
        priority: SynthesisPriority,
        requestID: UUID,
        synthesisKey: String?
    ) async throws -> Data

    func synthesizeWithDuration(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind,
        priority: SynthesisPriority,
        requestID: UUID,
        synthesisKey: String?
    ) async throws -> (data: Data, pcmDuration: Double, queueWaitMs: Double, synthesisMs: Double)
}

extension LocalTTSEngine {
    /// Overload **không có `requestID`** cho các call site cũ.
    ///
    /// Swift **cấm** default argument trong protocol requirement, nên gọi `synthesizeWithDuration(…)`
    /// thiếu `requestID` qua `any LocalTTSEngine` sẽ lỗi "missing argument for parameter 'requestID'" —
    /// dù hai service cụ thể đều có `requestID: UUID = UUID()`.
    ///
    /// Cách chữa ở đây là thêm overload thay vì sửa call site: `TTSManager.swift` đang **4026/3470** dòng
    /// (luật ratchet-down), nên mọi dòng thêm vào đó đều phải cân nhắc. Overload giữ call site nguyên vẹn.
    func synthesizeWithDuration(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind,
        priority: SynthesisPriority,
        synthesisKey: String?
    ) async throws -> (data: Data, pcmDuration: Double, queueWaitMs: Double, synthesisMs: Double) {
        try await synthesizeWithDuration(
            text: text,
            voice: voice,
            speed: speed,
            boundaryKind: boundaryKind,
            priority: priority,
            requestID: UUID(),
            synthesisKey: synthesisKey
        )
    }
}
