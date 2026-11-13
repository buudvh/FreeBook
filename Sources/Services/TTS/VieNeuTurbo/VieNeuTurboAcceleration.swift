import Foundation

/// Công tắc thử nghiệm **"Tăng tốc codec bằng AMX"** của VieNeu Turbo (1.3.924, báo cáo tối ưu Turbo P1).
///
/// Bật ⇒ session audio.cpp được dựng với session option `vieneu_v3_turbo.codec_blas=true` (bản vá
/// `Scripts/ci/audiocpp_patches/vieneu_codec_blas.py`): codec MOSS giải mã cả đoạn qua `ggml_backend_sched` [BLAS, CPU],
/// phép nhân ma trận chạy trên Accelerate — tức bộ tăng tốc AMX của chip A13 trở lên. Đo trên CI (P0a): codec chiếm
/// 37–51% thời gian một đoạn Turbo và đang chạy fp32 NEON. Tiếng gần như y hệt (chỉ đổi thứ tự cộng fp32; job parity
/// chặn dưới 90 dB). Bản build không có ggml-blas hoặc dựng scheduler lỗi ⇒ audio.cpp tự lùi về đường CPU cũ.
///
/// Đọc lúc chạy (UserDefaults, an toàn ngoài main): `VieNeuTurboRuntime.prepareLocked` so với cờ của session đang có,
/// lệch ⇒ dựng lại session (không nạp lại model) ⇒ gạt công tắc có hiệu lực từ đoạn tổng hợp kế tiếp.
enum VieNeuTurboAcceleration {
    /// Khoá `UserDefaults` / `@AppStorage` (không dấu chấm). Thiếu khoá = tắt (thử nghiệm, mặc định tắt).
    static let codecAMXKey = "vieneuTurboCodecAMX"

    /// `true` khi `VieNeuTurboCrashGuard` vừa tự tắt công tắc vì lần trước app dừng giữa lượt AMX (1.3.925) — Cài đặt
    /// hiện một dòng giải thích; anh bật lại công tắc thì xoá cờ.
    static let codecAMXAutoDisabledKey = "vieneuTurboCodecAMXAutoDisabled"

    /// Session option của bản vá `vieneu_codec_blas` — phải khớp tên trong bản vá (audio.cpp từ chối khoá lạ).
    static let codecBLASOption = "vieneu_v3_turbo.codec_blas"

    static var isCodecAMXEnabled: Bool {
        UserDefaults.standard.bool(forKey: codecAMXKey)
    }
}
