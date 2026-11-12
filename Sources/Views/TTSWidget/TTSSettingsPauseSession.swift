import Foundation

/// Phiên "đang mở Cài đặt TTS" (1.3.896): mở màn thì tạm dừng đọc, **chỉ khi màn đóng thật** mới đọc tiếp với cấu
/// hình mới.
///
/// Trước đây `TTSSettingsView.onDisappear` gọi thẳng `resumeAfterSettings()`. Nhưng `onDisappear` chạy cả khi một trang
/// con được đẩy lên trên (Cài đặt VieNeu, NghiTTS, từ điển…) hoặc khi chuyển sang tab khác, nên TTS tự đọc lại dù sheet
/// / trang Cài đặt TTS vẫn đang mở. Lần hiện lại sau đó còn gọi `prepareForSettings()` lần hai, ghi đè ảnh chụp cấu
/// hình lúc mở ⇒ đóng màn thì không thấy thay đổi đã làm trước khi vào trang con.
///
/// Giờ một cờ chung, gọi bao nhiêu lần cũng như một (idempotent):
/// - `begin()` ở `onAppear` của `TTSSettingsView`: lần đầu mới dừng + chụp cấu hình; hiện lại sau trang con / đổi tab
///   thì bỏ qua.
/// - `finish()` ở mọi lối **đóng thật**:
///   - `TTSSettingsView.onDisappear` khi `isPresented == false` (bị gỡ khỏi stack / sheet đóng);
///   - `onDismiss` của sheet (`TTSSettingsSheetHost`), phòng khi sheet đóng lúc đang ở trang con;
///   - `onAppear` của `TTSSettingsHubView` và trang gốc Cài đặt, phòng khi bị pop thẳng về gốc.
///
/// Màn Cài đặt TTS đẩy ở tab Cài đặt mà người dùng sang tab khác, bật đọc **truyện / chương khác** rồi mới quay lại đóng
/// ⇒ `finish()` không đọc tiếp kiểu "quay về đoạn đã lưu" (sẽ nhảy về vị trí của phiên cũ), chỉ khép phiên.
@MainActor
enum TTSSettingsPauseSession {
    private static var isPending = false
    private static var pendingBookId = ""
    private static var pendingChapterIndex = -1

    static func begin(caller: String = "TTSSettingsView") {
        guard !isPending else { return }
        let manager = TTSManager.shared
        isPending = true
        pendingBookId = manager.playingBookId
        pendingChapterIndex = manager.playingChapterIndex
        AppLogger.shared.log("[TTSSettings] Mở cài đặt (\(caller)): tạm dừng, đang đọc=\(manager.isPlaying)")
        manager.prepareForSettings()
    }

    static func finish(caller: String) {
        guard isPending else { return }
        isPending = false
        let manager = TTSManager.shared
        if manager.playingBookId != pendingBookId || manager.playingChapterIndex != pendingChapterIndex {
            AppLogger.shared.log("[TTSSettings] Đóng cài đặt (\(caller)): TTS đã sang truyện/chương khác ⇒ không đọc tiếp đoạn cũ")
            return
        }
        // Tự lưu cấu hình tiện ích TTS (nếu có thay đổi) trước khi đọc tiếp — như `onDisappear` cũ.
        if TTSManager.isExtensionTool(manager.tool),
           let ext = ExtensionLibraryRepository.shared.catalog.first(where: { $0.packageId == manager.tool }),
           manager.extensionConfigJson != ext.configJson {
            manager.extensionConfigJson = ext.configJson
        }
        AppLogger.shared.log("[TTSSettings] Đóng cài đặt (\(caller)): đọc tiếp với cấu hình mới")
        manager.resumeAfterSettings()
    }
}
