import Foundation

/// **Gói nhân bản giọng VieNeu Turbo** (1.3.892): `speaker_encoder.onnx` + `denoiser.onnx` (~71 MB), tuỳ chọn — chỉ cần
/// khi tạo giọng Turbo mới, không cần để đọc. Tải từ `common/` của kho mirror (`VieNeuModelMirror`), cất chung
/// `VieNeuModelStore` (`Models/`) như `sea_g2p.bin`; `speaker_encoder.onnx` dùng chung với gói clone của Nano.
///
/// API cho UI (màn tạo giọng làm sau theo mockup, màn thử Turbo):
/// - `byteCount` — dung lượng khi tải đủ, để nhãn nút nói trước
/// - `isReady` / `missingNames` / `bytesOnDisk` — trạng thái trên đĩa
/// - `download()` — qua `ModelDownloadCenter` (đích `ModelDownloadCenter.Target.vieNeuTurboClone`): tiến độ sống qua
///   việc rời màn, kết quả ra toast ở `MainTabView` như các gói model khác
/// - `delete()` — giữ `speaker_encoder.onnx` khi gói clone Nano còn dùng
///
/// Xoá model Nano khi máy còn model Turbo **giữ** hai file này (`VieNeuModelStore.deleteAll`); xoá gói clone Nano khi gói
/// này còn **giữ** `speaker_encoder.onnx` (`deleteCloneGraphs`).
enum VieNeuTurboClonePack {
    static var byteCount: Int64 { VieNeuModelStore.turboCloneByteCount }

    static var downloadTarget: String { ModelDownloadCenter.Target.vieNeuTurboClone }

    static var isReady: Bool {
        (try? VieNeuModelStore())?.hasTurboCloneGraphs ?? false
    }

    static var missingNames: [String] {
        (try? VieNeuModelStore())?.missingTurboCloneGraphNames ?? VieNeuModelStore.turboCloneGraphNames
    }

    static var bytesOnDisk: Int64 {
        (try? VieNeuModelStore())?.turboCloneTotalBytes ?? 0
    }

    @MainActor
    static func download() {
        ModelDownloadCenter.shared.startVieNeuTurboClonePack()
    }

    @MainActor
    static var isDownloading: Bool {
        ModelDownloadCenter.shared.isRunning(id: downloadTarget)
    }

    static func delete() throws {
        try VieNeuModelStore().deleteTurboCloneGraphs()
        AppLogger.shared.log("🎙️ [VieNeuTurboClone] Đã xoá gói nhân bản giọng Turbo")
    }
}
