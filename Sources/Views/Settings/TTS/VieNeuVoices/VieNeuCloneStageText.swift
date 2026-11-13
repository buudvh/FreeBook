import Foundation

/// Chữ **bước đang chạy** của lượt nhân bản giọng VieNeu — sheet nhân bản (`VieNeuVoiceCloneSheet`) và nút "Tạo bản
/// Turbo" (`VieNeuTurboCopyRow`) dùng chung. Nhãn tiếng Việt ở tầng View, **không** ở Service (`VieNeuVoiceCloner.Stage`,
/// `VieNeuTurboVoiceCloneCoordinator.Stage` chỉ là trạng thái).
enum VieNeuCloneStageText {
    /// Bước của lượt nhân bản **Nano**; `nil` khi chưa có bước nào (bên gọi tự hiện câu chờ chung).
    static func nano(_ stage: VieNeuVoiceCloner.Stage?) -> String? {
        switch stage {
        case .some(.decoding): return "Đang đọc file audio mẫu…"
        case .some(.features): return "Đang trích fbank 80-mel…"
        case .some(.loadingGraphs): return "Đang nạp 3 graph nhân bản (~91 MB)…"
        case .some(.speaker): return "Đang tạo x-vector (192 số)…"
        case .some(.codec): return "Đang mã hoá latent 24 kHz…"
        case .some(.style): return "Đang tạo style (50×256)…"
        case .none: return nil
        }
    }

    /// Bước của lượt nhân bản **Turbo** (`VieNeuTurboVoiceCloneCoordinator.stage`).
    static func turbo(_ stage: VieNeuTurboVoiceCloneCoordinator.Stage?) -> String {
        switch stage {
        case .decoding: return "Đang đọc file âm thanh…"
        case .trimming: return "Đang cắt khoảng lặng…"
        case .loadingGraphs: return "Đang nạp speaker_encoder / denoiser…"
        case .denoising: return "Đang khử nhiễu…"
        case .embedding: return "Đang tính speaker embedding…"
        case .encoding: return "Đang mã hoá giọng bằng audio.cpp…"
        case .saving: return "Đang lưu giọng…"
        case nil: return "Đang chuẩn bị…"
        }
    }
}
