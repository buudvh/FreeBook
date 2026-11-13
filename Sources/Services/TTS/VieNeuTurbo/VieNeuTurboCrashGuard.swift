import Foundation
#if canImport(AudioCpp)
import AudioCpp
#endif

/// Chống **sập lặp lại** khi bật "Tăng tốc codec bằng AMX" (1.3.925) + ghi lý do audio.cpp dừng tiến trình.
///
/// Vì sao: 1.3.924 bật công tắc làm app chết ngay lượt Turbo đầu tiên trên iPhone, log không có dòng nào, và công tắc
/// vẫn bật ⇒ lần đọc Turbo sau chết tiếp. Hai file nhỏ ở `Library/Caches` (còn lại sau khi tiến trình chết):
/// - **Dấu "đang thử AMX"** (`vieneu-turbo-amx-pending.txt`, chứa mã của tiến trình): ghi trước lượt Turbo **đầu tiên**
///   có codec AMX của mỗi lần mở app, xoá khi lượt đó kết thúc (xong hay ném lỗi — tức là không chết). Mở app sau mà dấu
///   còn và là của tiến trình khác ⇒ lần trước chết giữa lượt đó.
/// - **Câu báo của ggml** (`audiocpp-abort.txt`): bản vá `capi_abort_file` cho `GGML_ASSERT` / exception chưa bắt ghi câu
///   báo vào đây trước khi `abort()`. Không bắt được truy cập bộ nhớ sai (cần file `.ips` của iOS).
/// `recoverIfNeeded()` thấy một trong hai ⇒ ghi `❌` vào log; nếu công tắc đang bật thì tự tắt + bật cờ
/// `codecAMXAutoDisabledKey` (Cài đặt hiện một dòng giải thích). Bị giết khi đang đọc (vuốt tắt app) đúng lượt đầu thì
/// cũng bị tính là chết — chấp nhận, vì chỉ canh lượt đầu tiên mỗi lần mở app.
///
/// Gọi: `VieNeuTurboRuntime.createSessionLocked` (hàng đợi runtime, trước mọi lượt đầu) và `VieNeuTTSSettingsView`
/// (main, để công tắc hiện đúng ngay sau khi mở lại app). Khoá `lock` giữ hai nơi không cùng ghi.
enum VieNeuTurboCrashGuard {
    /// Mã riêng của tiến trình này — phân biệt dấu của lượt đang chạy với dấu sót lại từ tiến trình đã chết.
    private static let processToken = UUID().uuidString
    private static let lock = NSLock()

    private static var cachesURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static var pendingMarkerURL: URL { cachesURL.appendingPathComponent("vieneu-turbo-amx-pending.txt") }
    static var abortNoteURL: URL { cachesURL.appendingPathComponent("audiocpp-abort.txt") }

    /// Đặt file nhận câu báo của ggml (bản vá `capi_abort_file`). Gọi trên hàng đợi runtime; gọi lại nhiều lần vô hại.
    static func installAbortNote() {
        #if canImport(AudioCpp)
        try? FileManager.default.createDirectory(at: cachesURL, withIntermediateDirectories: true)
        let status = audiocpp_set_abort_file(abortNoteURL.path)
        if status != AUDIOCPP_OK {
            AppLogger.shared.log("❌ [VieNeuTurbo] Không đặt được file ghi lý do dừng của audio.cpp: \(String(cString: audiocpp_last_error()))")
        }
        #endif
    }

    /// Trước lượt Turbo đầu tiên có codec AMX của tiến trình này.
    static func beginGuardedRun() {
        try? Data(processToken.utf8).write(to: pendingMarkerURL, options: .atomic)
    }

    /// Lượt đó đã kết thúc (xong hoặc ném lỗi) — tiến trình không chết.
    static func endGuardedRun() {
        try? FileManager.default.removeItem(at: pendingMarkerURL)
    }

    /// Lần trước chết giữa lượt AMX / audio.cpp có ghi câu báo ⇒ log, và tự tắt công tắc nếu đang bật.
    /// Trả `true` khi vừa tự tắt.
    @discardableResult
    static func recoverIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let fileManager = FileManager.default
        let marker = try? String(contentsOf: pendingMarkerURL, encoding: .utf8)
        let diedDuringAMX = marker != nil && marker != processToken
        let abortNote = ((try? String(contentsOf: abortNoteURL, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard diedDuringAMX || !abortNote.isEmpty else { return false }
        if diedDuringAMX { try? fileManager.removeItem(at: pendingMarkerURL) }
        try? fileManager.removeItem(at: abortNoteURL)

        var reason = diedDuringAMX ? "app dừng giữa lượt Turbo đầu tiên có AMX" : "audio.cpp dừng tiến trình"
        if !abortNote.isEmpty { reason += " — audio.cpp báo: \(abortNote.prefix(600))" }
        guard VieNeuTurboAcceleration.isCodecAMXEnabled else {
            AppLogger.shared.log("❌ [VieNeuTurbo] Lần trước \(reason)")
            return false
        }
        UserDefaults.standard.set(false, forKey: VieNeuTurboAcceleration.codecAMXKey)
        UserDefaults.standard.set(true, forKey: VieNeuTurboAcceleration.codecAMXAutoDisabledKey)
        AppLogger.shared.log("❌ [VieNeuTurbo] Lần trước \(reason) ⇒ đã tự tắt \"Tăng tốc bằng AMX\"")
        return true
    }
}
