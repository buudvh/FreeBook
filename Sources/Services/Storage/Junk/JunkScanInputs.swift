import Foundation

/// Trạng thái app mà luật rác cần, chụp trên MainActor **trước** khi quét ngoài main (`JunkScanner` là hàm thuần).
/// Màn Dung lượng và trang Dọn rác dùng cùng bản chụp này ⇒ nhóm đang bị chặn hiện 0, không hiện một con số mà lượt dọn
/// sẽ không xoá.
struct JunkScanInputs: Sendable {
    /// `VieNeuCoreMLAccelerator` đang tải / biên dịch / tự kiểm.
    var coreMLBusy = false
    /// `ModelDownloadCenter` còn lượt tải model TTS (kể cả lượt đang xếp hàng).
    var modelDownloadBusy = false
    /// `DownloadManager` còn tác vụ tải / xuất chưa tới trạng thái cuối.
    var bookTaskBusy = false
    /// `BackupCoordinator` đang sao lưu / khôi phục.
    var backupBusy = false
    /// `BookSourceChangeCoordinator` đang đổi nguồn / khôi phục lượt đổi nguồn.
    var sourceChangeRunning = false
    /// Mọi `Book.bookId` của thư viện; `nil` = không đọc được (hoặc không có container) ⇒ bỏ nhóm truyện đã xoá.
    var ownedBookIds: Set<String>? = nil

    /// Có lượt tải nào (model TTS, gói Core ML, truyện / phim) đang chạy.
    var anyDownloadBusy: Bool { coreMLBusy || modelDownloadBusy || bookTaskBusy }

    @MainActor
    static func capture(ownedBookIds: Set<String>?) -> JunkScanInputs {
        var inputs = JunkScanInputs()
        // Chỉ hỏi `VieNeuCoreMLAccelerator.shared` khi thư mục Core ML đã có: khởi tạo nó đọc đĩa trên main và tạo thư mục
        // VieNeu. Chưa có thư mục ⇒ không có gì của Core ML để dọn, cũng không có lượt chuẩn bị nào đang ghi.
        if FileManager.default.fileExists(atPath: JunkPaths.coreMLRoot.path) {
            inputs.coreMLBusy = VieNeuCoreMLAccelerator.shared.isBusy
        }
        inputs.modelDownloadBusy = ModelDownloadCenter.shared.isBusy
        inputs.bookTaskBusy = DownloadManager.shared.hasActiveTasks
        inputs.backupBusy = BackupCoordinator.shared.isBusy
        inputs.sourceChangeRunning = BookSourceChangeCoordinator.shared.isRunning
        inputs.ownedBookIds = ownedBookIds
        return inputs
    }

    /// Lý do các nhóm bị bỏ qua, cho dòng log `[JunkCleanup]`.
    var blockedSummary: String {
        var reasons: [String] = []
        if coreMLBusy { reasons.append("Core ML đang chuẩn bị") }
        if modelDownloadBusy { reasons.append("đang tải model TTS") }
        if bookTaskBusy { reasons.append("đang tải / xuất truyện") }
        if backupBusy { reasons.append("đang sao lưu / khôi phục") }
        if sourceChangeRunning { reasons.append("đang đổi nguồn") }
        if ownedBookIds == nil { reasons.append("không đọc được thư viện") }
        return reasons.isEmpty ? "không" : reasons.joined(separator: ", ")
    }
}
