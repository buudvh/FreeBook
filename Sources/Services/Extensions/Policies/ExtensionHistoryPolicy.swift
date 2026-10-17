import Foundation

/// Tiện ích có được **ghi mới** vào Lịch sử đọc/xem hay không (bật `Book.isHistory`).
///
/// Mặc định: tiện ích NSFW (`ExtensionNsfwClassifier`) không lưu lịch sử, còn lại có; người dùng đè bằng
/// `Extension.savesHistory` (màn Cấu hình tiện ích). Tắt chỉ chặn ghi mới — lịch sử cũ giữ nguyên; tiến độ đọc,
/// `lastReadDate`, chỉ số chương vẫn được lưu như thường.
///
/// Đọc bảng chụp có lock của `ExtensionLibraryRepository` nên gọi được từ thread/actor bất kỳ, không `await`.
enum ExtensionHistoryPolicy {
    /// Tra bản cài rồi catalog. `"local"`/rỗng/không tìm thấy tiện ích ⇒ `true` (giữ hành vi cũ).
    nonisolated static func recordsHistory(packageId: String) -> Bool {
        let key = packageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.lowercased() != "local" else { return true }
        guard let ext = ExtensionLibraryRepository.snapshot(packageId: key)
                ?? ExtensionLibraryRepository.catalogSnapshot(packageId: key) else { return true }
        return recordsHistory(for: ext)
    }

    /// `savesHistory` nếu người dùng đã chọn, không thì `!isNsfw`.
    nonisolated static func recordsHistory(for ext: Extension) -> Bool {
        ext.savesHistory ?? !ExtensionNsfwClassifier.isNsfw(ext)
    }
}
