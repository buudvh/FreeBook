import Foundation

/// Một giọng VieNeu **chưa có bản ở model kia** — nguồn của "Tạo bản Turbo" / "Tạo bản Nano" (1.3.937,
/// `VieNeuVoiceCopyRunner`). Bản sao bất biến, dựng ở `VieNeuVoiceDirectory` ngoài main.
///
/// - Có mẫu gốc dùng được (`sampleURL`) ⇒ nhân bản từ mẫu: giọng Nano tự tạo còn file mẫu; giọng Turbo tự tạo còn
///   `sample.wav` dài ít nhất `VieNeuVoiceCloner.minimumSampleSeconds` (Nano cần ≥ 3 s, mẫu Turbo có thể chỉ 1 s).
/// - Không có ⇒ cho chính giọng này đọc đoạn mẫu (`VieNeuVoiceSampleSpeaker`) rồi nhân bản từ tiếng máy đọc.
struct VieNeuVoiceCopySource: Identifiable, Hashable, Sendable {
    /// Giọng nguồn — cũng là giọng đọc đoạn mẫu khi không có mẫu gốc.
    let selection: VieNeuVoiceSelection
    let name: String
    /// Giọng nhân bản của người dùng (không phải giọng có sẵn).
    let isCustom: Bool
    /// Giọng Nano tự tạo: id bản ghi ở `VieNeuCustomVoiceStore` (liên kết `sourceNanoVoiceId` của bản Turbo).
    let nanoRecordId: String?
    let sampleURL: URL?
    let sampleSeconds: Double?

    var id: String { selection.key }
    var model: VieNeuModelChoice { selection.model }
    /// Model của bản sẽ tạo.
    var target: VieNeuModelChoice { selection.model == .nano ? .turbo : .nano }
    var hasSample: Bool { sampleURL != nil }
}
