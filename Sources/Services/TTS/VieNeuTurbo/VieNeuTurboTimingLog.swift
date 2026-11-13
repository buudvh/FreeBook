import Foundation
#if canImport(AudioCpp)
import AudioCpp
#endif

/// Bộ đếm giờ **có sẵn** của audio.cpp cho từng lượt `audiocpp_session_run` của Turbo — để dòng log
/// `[VieNeuTurbo] Đoạn` tách được thời gian nạp prompt / backbone / bộ giải mã âm học / codec (báo cáo tối ưu Turbo).
///
/// audio.cpp tự đo các phần này (`timing_log_scalar`) nhưng chỉ ghi khi log của nó bật; bản vá
/// `Scripts/ci/audiocpp_patches/capi_log_file.py` thêm hàm C `audiocpp_set_log_file` để bật. Mỗi lượt:
/// `beginRun()` đóng file cũ, xoá, mở file mới ⇒ file chỉ chứa log của lượt này; `finishRun()` đọc, cộng dồn rồi tắt log.
/// Chỉ chạy khi log của app đang bật (`AppLogger.isLoggingEnabled`) — tắt log thì audio.cpp không ghi gì.
///
/// **Chỉ gọi trên hàng đợi của `VieNeuTurboRuntime`**: trạng thái log của audio.cpp là toàn tiến trình, và
/// `audiocpp_last_error()` là thread-local.
enum VieNeuTurboTimingLog {
    /// Tổng các bộ đếm của một lượt (một đoạn của trình đọc). ms là thời gian tường.
    struct Timings: Sendable {
        /// `talker.prefill_ms` — nạp prompt (chữ + giọng mẫu) qua 12 lớp backbone.
        var prefillMs = 0.0
        /// `talker.cached_step_ms` — 1 lượt backbone mỗi khung.
        var stepMs = 0.0
        /// `talker.code_predictor_ms` — 16 bước bộ giải mã âm học mỗi khung.
        var acousticMs = 0.0
        /// `speech_decoder_ms` — codec MOSS giải mã cả đoạn (kể cả lượt sinh lại nếu có).
        var codecMs = 0.0
        /// Số lần sinh mã (`talker.total_ms`): 1 + lượt sinh lại vì chạm trần khung / nghi nói lan.
        var generateCalls = 0
        /// Codec có chạy qua BLAS ở lượt này không (`moss.audio_tokenizer.decode.blas_active`, ghi mỗi lượt giải mã,
        /// 0 cả khi công tắc tắt); `nil` = không có dòng nào (lượt hỏng trước khi giải mã).
        var codecBLASActive: Bool?
    }

    static let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("audiocpp-turbo-timing.log")

    /// Bật log của audio.cpp vào file sạch cho lượt sắp chạy. `false` ⇒ lượt này không đo (log app tắt / lỗi mở file).
    static func beginRun() -> Bool {
        #if canImport(AudioCpp)
        _ = audiocpp_set_log_file(nil)
        guard AppLogger.shared.isLoggingEnabled else { return false }
        try? FileManager.default.removeItem(at: fileURL)
        let status = audiocpp_set_log_file(fileURL.path)
        guard status == AUDIOCPP_OK else {
            let detail = String(cString: audiocpp_last_error())
            AppLogger.shared.log("❌ [VieNeuTurbo] Không bật được bộ đếm giờ của audio.cpp: \(detail)")
            return false
        }
        return true
        #else
        return false
        #endif
    }

    /// Tắt log của audio.cpp (đóng file) rồi đọc tổng của lượt vừa chạy. Gọi cả khi lượt hỏng (để đóng file).
    static func finishRun() -> Timings? {
        #if canImport(AudioCpp)
        _ = audiocpp_set_log_file(nil)
        #endif
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return parse(text)
    }

    /// Dòng dạng `[TIMING ts=20261113-125232] vieneu_v3_turbo.talker.prefill_ms 301.5` ⇒ cộng dồn theo tên.
    static func parse(_ text: String) -> Timings {
        var timings = Timings()
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("[TIMING"), let close = line.firstIndex(of: "]") else { continue }
            let parts = line[line.index(after: close)...].split(separator: " ")
            guard parts.count >= 2, let value = Double(parts[1]) else { continue }
            switch parts[0] {
            case "vieneu_v3_turbo.talker.prefill_ms": timings.prefillMs += value
            case "vieneu_v3_turbo.talker.cached_step_ms": timings.stepMs += value
            case "vieneu_v3_turbo.talker.code_predictor_ms": timings.acousticMs += value
            case "vieneu_v3_turbo.speech_decoder_ms": timings.codecMs += value
            case "vieneu_v3_turbo.talker.total_ms": timings.generateCalls += 1
            case "moss.audio_tokenizer.decode.blas_active":
                // Nhiều lượt giải mã trong một lượt chạy (sinh lại) ⇒ "có BLAS" khi mọi lượt đều chạy BLAS.
                timings.codecBLASActive = (timings.codecBLASActive ?? true) && value >= 1
            default: break
            }
        }
        return timings
    }
}
