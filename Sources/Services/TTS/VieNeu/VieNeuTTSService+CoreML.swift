import Foundation

/// Phần mở rộng bật/tắt **Core ML** làm backend chính của VieNeu-TTS (thử nghiệm, mặc định TẮT).
///
/// Tách khỏi `VieNeuTTSService.swift` để giữ file gốc ≤ 400 dòng (quy tắc `NEW_FILE_TOO_LARGE`, plan §5.4).
/// Mọi logic nặng (tải → biên dịch → tự test) nằm ở `enableCoreML()`; tầng View (`Model VieNeu`)
/// gọi nó rồi tự toast — Service TUYỆT ĐỐI KHÔNG gọi `ToastManager.shared` (`SERVICE_TOAST_COUPLING`).
///
/// Truy cập `store` qua `modelStore` (computed property `internal`) và `engine` (đã nới lên `internal`)
/// để extension ở file riêng vẫn dùng được mà không phá đóng gói của hai stored property `private`.
extension VieNeuTTSService {

    /// Bật/tắt **Core ML** làm bộ máy chính (thử nghiệm, mặc định **TẮT** — plan §2 Q1).
    ///
    /// Ghi thẳng `vieneuCoreMLEnabled` (`UserDefaults.bool` ⇒ thiếu khoá = `false`), rồi báo engine đổi
    /// backend (Core ML primary + ORT fallback, hoặc chỉ ORT). **Không** tự tải/biên dịch ở đây — việc nặng
    /// nằm ở `enableCoreML()` và được màn `Model VieNeu` gọi từ `Toggle`. Tầng View mới được toast
    /// (`SERVICE_TOAST_COUPLING`: Services không gọi `ToastManager.shared`), nên service chỉ báo engine,
    /// không hiện thông báo.
    var useCoreML: Bool {
        get { UserDefaults.standard.bool(forKey: VieNeuSynthesisPolicy.coreMLEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: VieNeuSynthesisPolicy.coreMLEnabledKey)
            engine.setRequestedCoreML(newValue)
            Task { @MainActor in TTSManager.shared.invalidateVieNeuBackend() }
        }
    }

    /// Tải → biên dịch → tự test Core ML. Trả `(passed, detail)`: `detail` là SNR dB (thành công) hoặc
    /// mô tả lỗi (thất bại). **Không** toast, **không** đổi khoá `useCoreML` — màn `Model VieNeu` lo phần
    /// đó (tầng View mới được toast). Khi thất bại, xoá kết quả tự test để `VieNeuBackendFactory` không
    /// chọn Core ML làm primary.
    ///
    /// Tiến độ chi tiết chỉ log (màn `Model VieNeu` tự poll trạng thái đĩa qua `TimelineView`), nên hàm
    /// này không cần callback UI — đúng tinh thần "không block UI" của plan §3.
    func enableCoreML() async -> (passed: Bool, detail: String) {
        do {
            let client = VieNeuModelClient(store: modelStore)
            _ = try await client.prefetchCoreML { message, fraction in
                AppLogger.shared.log("🎙️ [VieNeuCoreML] \(message) \(Int(fraction * 100))%")
            }
            try VieNeuCoreMLCompiler.compileAll(store: modelStore) { message, fraction in
                AppLogger.shared.log("🎙️ [VieNeuCoreML] \(message) \(Int(fraction * 100))%")
            }
            let config = try VieNeuConfig.load(modelStore: modelStore)
            let report = VieNeuBackendSelfTest.run(store: modelStore, config: config)
            let capable = report.buckets.filter { $0.passed }.map { $0.frames }
            guard !capable.isEmpty else {
                VieNeuBackendSelfTest.reset()
                // Kèm **lý do thật** (note của bucket đầu tiên rớt): SNR `-1` một mình là mã lỗi,
                // không đủ để chẩn đoán — xem bẫy 2026-10-03.
                let reason = report.firstFailure.map { "T\($0.frames): \($0.note)" } ?? "không rõ nguyên nhân"
                return (false, "Tự test không đạt (SNR thấp nhất \(String(format: "%.1f", report.minSnrDb)) dB) — \(reason)")
            }
            // Đạt nghĩa mới = ít nhất 1 bucket chạy được Core ML; bucket hỏng tự route sang ORT từng graph.
            let total = VieNeuBucketSelector.bucketFrames.count
            let detail = capable.count == total
                ? "Tự test đạt cả \(total)/\(total) bucket (SNR \(String(format: "%.0f", report.minSnrDb)) dB)"
                : "Tự test đạt \(capable.count)/\(total) bucket (\(capable.sorted().map { "T\($0)" }.joined(separator: ",")) chạy Core ML, còn lại dùng ORT)"
            return (true, detail)
        } catch {
            VieNeuBackendSelfTest.reset()
            AppLogger.shared.log("⚠️ [VieNeuCoreML] Bật thất bại: \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }
}
