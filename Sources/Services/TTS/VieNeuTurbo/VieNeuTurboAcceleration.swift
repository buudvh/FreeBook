import Foundation

/// **Tăng tốc bằng AMX** của VieNeu Turbo — **luôn bật** từ 1.3.928 (bỏ công tắc thử nghiệm của 1.3.924–1.3.927, anh
/// Bửu chốt "Bật, bỏ công tắc" sau khi đo 1.3.927: RTF 0,400 → 0,250 cùng mức nhiệt; báo cáo tối ưu Turbo mục 14).
///
/// Session audio.cpp được dựng với hai session option:
/// - `vieneu_v3_turbo.codec_blas=true` (bản vá `Scripts/ci/audiocpp_patches/vieneu_codec_blas.py`): codec MOSS giải mã
///   cả đoạn qua `ggml_backend_sched` [BLAS, CPU] — phép nhân ma trận (kể cả Q·Kᵀ của attention) chạy Accelerate, tức
///   AMX của A13 trở lên. Đo trên máy: codec nhanh 3,3×; tiếng trùng mã, WAV ~98 dB so với đường CPU.
/// - `vieneu_v3_turbo.prefill_blas=true` (bản vá `vieneu_prefill_blas.py`): bước nạp prompt qua Accelerate, nhanh 1,9×,
///   gần bản fp32 gốc hơn đường q8 (không lượng tử activation).
/// - `vieneu_v3_turbo.threadpool_poll=0` (1.3.929, bản vá `vieneu_threadpool.py`): giữ một pool luồng ggml suốt session
///   thay vì tạo + huỷ luồng ở mỗi lượt tính (~210 lần mỗi giây tiếng). Tiếng trùng từng byte; đo CI: RTF −4%, CPU −3%.
///   Pool tạo ở lượt tổng hợp đầu (luồng mang QoS người gọi), người gọi đổi QoS ⇒ audio.cpp tạo pool mới.
///   Đi chung cờ với AMX nên lối tự tắt khi sập tắt cả ba.
/// Bản build không có ggml-blas hoặc dựng scheduler lỗi ⇒ audio.cpp tự lùi về đường CPU cũ (log `amx=lùi:…`).
///
/// **Tự tắt khi sập**: `VieNeuTurboCrashGuard` thấy lần trước app chết giữa lượt AMX đầu tiên (hoặc audio.cpp ghi câu
/// báo dừng) ⇒ ghi số build đang chạy vào `disabledBuildKey` ⇒ AMX tắt cho **tới khi cài bản build khác** (bản sửa).
/// Không còn công tắc nên đây là lối thoát duy nhất khỏi vòng sập. Khoá cũ của công tắc (`vieneuTurboCodecAMX`,
/// `vieneuTurboCodecAMXAutoDisabled`) bỏ qua.
///
/// Đọc lúc chạy (UserDefaults, an toàn ngoài main): `VieNeuTurboRuntime.prepareLocked` so với cờ của session đang có,
/// lệch ⇒ dựng lại session (không nạp lại model).
enum VieNeuTurboAcceleration {
    /// Số build (`CFBundleVersion`) mà AMX đã bị tự tắt vì sập. Trùng build đang chạy ⇒ AMX tắt.
    static let disabledBuildKey = "vieneuTurboAMXDisabledBuild"

    /// Session option của bản vá `vieneu_codec_blas` — phải khớp tên trong bản vá (audio.cpp từ chối khoá lạ).
    static let codecBLASOption = "vieneu_v3_turbo.codec_blas"

    /// Session option của bản vá `vieneu_prefill_blas` (1.3.927): bước nạp prompt qua Accelerate.
    static let prefillBLASOption = "vieneu_v3_turbo.prefill_blas"

    /// Session option của bản vá `vieneu_threadpool` (1.3.929): pool luồng ggml giữ suốt session.
    static let threadpoolPollOption = "vieneu_v3_turbo.threadpool_poll"

    /// `poll` của pool: 0 = luồng ngủ ngay khi rảnh. poll 10 / 50 nhanh thêm ~2% trên CI nhưng luồng quay chờ đốt CPU
    /// và tranh lõi với Accelerate (nóng máy) — muốn đổi thì đo nhiệt trên máy trước.
    static let threadpoolPoll = "0"

    /// Số build đang chạy (bản build tay không có ⇒ "unknown").
    static var currentBuild: String {
        AppVersionInfo.buildNumber ?? "unknown"
    }

    /// AMX dùng được: chưa bị tự tắt ở chính bản build đang chạy.
    static var isAMXEnabled: Bool {
        UserDefaults.standard.string(forKey: disabledBuildKey) != currentBuild
    }

    /// Tắt AMX tới khi cài bản build khác (`VieNeuTurboCrashGuard`).
    static func disableForCurrentBuild() {
        UserDefaults.standard.set(currentBuild, forKey: disabledBuildKey)
    }
}
