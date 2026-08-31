import Foundation

/// Hợp đồng của một engine TTS **chạy trên máy** (nhánh `tool == "nghitts"`).
///
/// Tồn tại để `TTSManager` và hai bộ prefetch (`TTSChapterPrefetcher`,
/// `TTSNextChapterPrefixCache`) không còn phụ thuộc vào kiểu cụ thể `PiperTTSService`:
/// nhánh `nghitts` giờ có hai engine (`nghiEngineKind` = `piper` hoặc `vieneu`) và mọi
/// policy on-device (watermark prefetch, trim cache, next-chapter prefix, energy log)
/// được thừa hưởng nguyên vẹn thay vì phải nhân bản cho một `tool` value mới.
///
/// Đúng 5 thành viên dưới đây là toàn bộ những gì tầng trên thật sự gọi — cố ý giữ hẹp
/// để đường Piper không phải đổi thân hàm nào. Chi tiết riêng của từng engine
/// (`ONNXPiperEngine`, ONNX Runtime session, model store) phải nằm **trong** service
/// tương ứng, không rò qua protocol này.
///
/// `Sendable` vì `TTSManager.scheduleNghiWarmUp` bắt service vào `Task.detached`.
protocol LocalTTSSynthesizing: AnyObject, Sendable {
    /// Giọng đang nạp — chỉ dùng để hiển thị/log.
    var currentModel: String? { get }

    /// Một dòng mô tả engine cho màn Cài đặt.
    var engineStatus: String { get }

    /// Nạp trước model/từ điển để lần tổng hợp đầu không phải trả giá khởi động.
    /// Được gọi từ warm-up nền; không được throw vì lý do "chưa tải model".
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

/// Tham số mặc định **phải** nằm ở đây, không phải ở kiểu cụ thể: giá trị mặc định khai
/// trong `PiperTTSService` không đi qua witness table, nên khi biến đổi sang
/// `any LocalTTSSynthesizing` thì các call site bỏ bớt `requestID` sẽ không biên dịch được.
extension LocalTTSSynthesizing {
    func synthesizeWithDuration(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind = .paragraphEnd,
        priority: SynthesisPriority = .demand,
        synthesisKey: String? = nil
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

    func synthesize(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind = .paragraphEnd,
        priority: SynthesisPriority = .demand,
        synthesisKey: String? = nil
    ) async throws -> Data {
        try await synthesize(
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
