import Foundation

/// Dọn dẹp bản sao lưu **trong máy** — tách khỏi `BackupCoordinator.swift` vì file gốc đã sát trần
/// 400 dòng của `check_architecture.py`, cùng lý do đã tách `BackupCoordinator+AutoDrive.swift`.
///
/// Khác `+AutoDrive`, extension này **không** cần mở thêm cửa nội bộ: hai hàm ở đây chỉ đọc
/// `isBusy`/`localBackups` rồi gọi `refreshLocal()`, không ghi `isBusy`/`progress`.
extension BackupCoordinator {

    /// Xoá toàn bộ bản sao lưu **trong máy**. Chỉ đụng `backups/` cục bộ — bản trên Google Drive và
    /// Telegram thuộc kênh khác, có đường xoá riêng (`deleteFromDrive`).
    ///
    /// Chặn khi `isBusy`: đang tạo hoặc khôi phục mà xoá file bên dưới thì worker sẽ hỏng giữa chừng.
    public func deleteAllLocal() {
        guard !isBusy else { return }
        guard !localBackups.isEmpty else { return }
        do {
            let deleted = try LocalBackupStore.deleteAll()
            refreshLocal()
            lastMessage = "Đã xoá \(deleted) bản sao lưu trong máy"
        } catch {
            // Một phần có thể đã bị xoá: làm mới danh sách trước khi báo lỗi để UI khớp thực tế.
            refreshLocal()
            lastError = "Dọn dẹp chưa xong: \(error.localizedDescription)"
        }
    }

    /// Xoá bản trong máy **sau khi** upload đã thành công.
    ///
    /// Chỉ được gọi ở nhánh thành công — upload lỗi mà xoá local là mất luôn bản duy nhất. "Thành công"
    /// là do đích tự xác nhận: `GoogleDriveUploader` ném lỗi nếu hết byte mà Drive chưa đóng phiên, còn
    /// `TelegramBackupUploader` có SHA-256 từng part và toàn file.
    ///
    /// Trả về hậu tố để ghép vào `lastMessage`: xoá được thì nói ngắn, không xoá được thì phải nói rõ
    /// để người dùng không tưởng là đã dọn xong.
    ///
    /// **Hệ quả có chủ ý**: bản local biến mất ngay nên đường bấm tay là một archive → một đích. Muốn
    /// một bản lên cả Drive lẫn Telegram thì đi đường tự động (`+AutoDrive` export một lần rồi gửi
    /// tuần tự nhiều đích).
    func removeLocalCopyAfterUpload(_ item: LocalBackupStore.Item) -> String {
        do {
            try LocalBackupStore.delete(item)
            refreshLocal()
            return " và xoá bản trong máy"
        } catch {
            refreshLocal()
            return " (chưa xoá được bản trong máy)"
        }
    }
}
