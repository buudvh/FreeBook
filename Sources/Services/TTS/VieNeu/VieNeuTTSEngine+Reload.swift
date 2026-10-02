import Foundation

/// Đường **nhả ngữ cảnh** của engine VieNeu, phục vụ nạp lại tại chỗ — dùng cho thí nghiệm
/// **CoreML EP** (1.3.466).
///
/// ## Vì sao phải có đường nhả
/// `prepareLocked` chỉ chạy **một lần** trong vòng đời engine (`guard runtime == nil`) và engine sống
/// suốt vòng đời app ⇒ đổi EP mà không nhả thì cấu hình mới **không bao giờ** có hiệu lực. Trước
/// 1.3.466 điều đó không thành vấn đề vì mọi thay đổi đều nói rõ "cần mở lại app"; nay màn Cài đặt gọi
/// `VieNeuTTSService.reloadEngine(useCoreML:)` nên phải có đường nhả thật.
///
/// ## Vì sao tách file
/// `VieNeuTTSEngine.swift` đang ở **đúng 400 dòng** (trần của `check_architecture.py`) ⇒ không thêm được
/// dòng nào. Hệ quả bắt buộc: bảy thành viên mà file này cần đọc/ghi — `runtime`, `config`, `catalog`,
/// `phonemizer`, `nullContext`, `nullContextShape`, `nullMask` — đã hạ từ `private` xuống `internal`,
/// đúng khuôn đã dùng cho `VieNeuTTSEngine+Adaptive` và `VieNeuONNXRuntime+Clone`.
///
/// ## An toàn luồng
/// `unload()` lấy **chính** `lock` mà `synthesize` giữ suốt lượt tổng hợp ⇒ nó **luôn** chờ lượt đang
/// chạy xong rồi mới nhả. Đây là điều kiện sống còn: `VieNeuORTDestroy` giải phóng tensor cache của
/// nhánh vô điều kiện, mà buffer nguồn của cache đó chính là ba mảng `null*` bên dưới.
extension VieNeuTTSEngine {
    /// Nhả ngữ cảnh ORT + cấu hình + phonemizer để `prepare()` dựng lại từ đầu (kèm cấu hình EP mới).
    ///
    /// **Không** dọn `mode` / `requestedMode` / bộ đếm thích nghi: đó là *cài đặt người dùng*, không phải
    /// trạng thái của ngữ cảnh — dọn chúng sẽ làm chế độ chất lượng người dùng chọn trôi về mặc định.
    /// Cố ý dọn `droppedScalarWarningShown` để cảnh báo "phoneme bị bỏ" của ngữ cảnh mới vẫn hiện được.
    func unload() {
        lock.lock()
        defer { lock.unlock() }
        // Thứ tự quan trọng: bỏ `runtime` **trước** khi xoá ba mảng `null*`, vì tensor cache của nhánh vô
        // điều kiện trỏ vào buffer của chúng — `VieNeuONNXRuntime.deinit` → `VieNeuORTDestroy` giải phóng
        // cache, và chỉ sau đó buffer nguồn mới được phép biến mất.
        runtime = nil
        config = nil
        catalog = nil
        phonemizer = nil
        nullContext = []
        nullContextShape = []
        nullMask = []
        droppedScalarWarningShown = false
        AppLogger.shared.log("🎙️ [VieNeu] Đã nhả ngữ cảnh ORT (chờ nạp lại)")
    }

    /// `true` khi ngữ cảnh **đang dùng** đã đăng ký được CoreML EP.
    ///
    /// Đây là **nguồn sự thật** cho UI và cho log — khác hẳn cờ `UserDefaults` (chỉ là *ý định* của người
    /// dùng). Đọc dưới `lock` để không đọc phải ngữ cảnh đang bị nhả giữa lúc nạp lại; trên thực tế chỉ
    /// được gọi khi màn Cài đặt đang mở, tức đã tạm dừng phát nên không có tranh chấp.
    var coreMLActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return runtime?.coreMLActive ?? false
    }
}
