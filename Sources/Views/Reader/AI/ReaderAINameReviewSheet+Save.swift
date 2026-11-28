import SwiftUI

/// Nút Lưu của màn duyệt name (`ReaderAINameReviewSheet`, dùng chung luồng AI và Lọc name local) — plan
/// `Docs/Plans/2026-11-27-phan-loai-name.md` mục L16 (anh Bửu: "Bấm lưu sẽ hiển thị màn popup vào hoạt động giống nhập
/// name/vp từ file. Tất nhiên chỉ có name mới thì nhập thẳng như hiện tại. Làm cho cả AI nhé"), mockup
/// https://claude.ai/artifact/9qgrqxGZpkiCQHQdK4vgbx khung "Bấm Lưu → chọn cách nhập".
///
/// - "Đã có" = khoá có trong **file đích của truyện** (`Names.txt` / `VietPhrase.txt` riêng, đọc ngoài main lúc bấm Lưu),
///   **không** theo cờ `hasInBookNames` / `hasInBookVP` — hai cờ đó tính cả Name / VP Chung lẫn từ điển gốc, còn ba chế độ
///   chỉ ghi file riêng của truyện. Không name nào đã có ⇒ lưu thẳng bằng "Gộp" (không có gì để đè), như trước.
/// - Có name đã có ⇒ popup `DataImportModePopup` đủ ba `DataImportMode` ("Gộp" chọn sẵn — "Thay thế toàn bộ" phá dữ liệu),
///   dòng dưới tiêu đề "N name mới · M đã có trong Name riêng", lời giải thích theo ngữ cảnh lưu (không nói "file"), nút
///   "Lưu". Ba chế độ ghi cùng luật nhập file (`AIHarnessService.saveExtractedEntries` ⇒
///   `TranslationDictionaryWriter.importRecords`).
/// - Lưu **mọi** mục đang chọn, kể cả mục đang bị ô tìm / chip loại của thẻ ẩn; hàng gạch (luồng AI) không bao giờ lưu.
extension ReaderAINameReviewSheet {
    /// Tên đích trong popup: "Name riêng" / "VP riêng".
    static func saveTargetLabel(isName: Bool) -> String {
        isName ? "Name riêng" : "VP riêng"
    }

    /// Lời giải thích ba chế độ theo ngữ cảnh lưu (thay lời "file" mặc định của `DataImportMode.explanation`).
    static func saveModeExplanations(isName: Bool) -> [DataImportMode: String] {
        [
            .replaceAll: "Xoá \(saveTargetLabel(isName: isName)) cũ của truyện, chỉ giữ các name đang chọn.",
            .overwriteExisting: "Name đã có thì lấy nghĩa mới đè lên; chưa có thì thêm vào.",
            .keepExisting: "Chỉ thêm name chưa có; name đã có giữ nguyên nghĩa cũ."
        ]
    }

    var savePopupTitle: String {
        "Lưu vào \(Self.saveTargetLabel(isName: pendingIsName))"
    }

    var savePopupMessage: String {
        "\(pendingNewCount) name mới · \(pendingExistingCount) đã có trong \(Self.saveTargetLabel(isName: pendingIsName))"
    }

    /// Các dòng `khoá=nghĩa` Lưu sẽ ghi — cùng bộ lọc với `AIHarnessService.saveExtractedEntries`: mục đang chọn, không gạch,
    /// khoá đã trim và nghĩa đã chuẩn hoá đều không rỗng, khoá lặp chỉ giữ mục đầu. **Một** nguồn cho phép đếm "đã có" lúc
    /// Lưu và cho nút ▼ › "Xuất file" (`+Export`: số mục ở dòng phụ + nội dung file).
    var recordsToSave: [DictionaryTextRecord] {
        var seenKeys = Set<String>()
        var records: [DictionaryTextRecord] = []
        for item in names where item.isSelected && !isStruck(item) {
            let key = item.original.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = DictionaryTextFileStore.normalizeMeaning(item.suggestedMeaning)
            guard !key.isEmpty, !value.isEmpty, seenKeys.insert(key).inserted else { continue }
            records.append(DictionaryTextRecord(key: key, value: value))
        }
        return records
    }

    /// Khoá sẽ được ghi (`recordsToSave`).
    private var keysToSave: Set<String> {
        Set(recordsToSave.map(\.key))
    }

    /// Bước 1: đọc file đích của truyện (ngoài main) ⇒ không name nào đã có thì lưu thẳng ("Gộp"), có thì mở popup.
    func requestSave(isName: Bool) {
        guard !isCheckingSaveTarget else { return }
        let keys = keysToSave
        // Không khoá hợp lệ: giao luôn như trước — nơi gọi báo "thất bại" (service trả `nil`).
        guard !keys.isEmpty else {
            executeSave(isName: isName, mode: .overwriteExisting)
            return
        }
        isCheckingSaveTarget = true
        let bid = bookId
        Task { @MainActor in
            let existingKeys = await Task.detached(priority: .userInitiated) {
                let sets = AIBookDataInspector.shared.fetchBookDictionarySets(bookId: bid)
                return isName ? sets.names : sets.vps
            }.value
            isCheckingSaveTarget = false
            let existingCount = keys.intersection(existingKeys).count
            guard existingCount > 0 else {
                executeSave(isName: isName, mode: .overwriteExisting)
                return
            }
            pendingIsName = isName
            pendingNewCount = keys.count - existingCount
            pendingExistingCount = existingCount
            showingSavePopup = true
        }
    }

    /// Bước 2: chốt cách lưu. Sheet đóng ngay sau khi giao việc cho `onSave` — màn gọi (luồng AI) thay nội dung tin nhắn
    /// bằng bản tóm tắt nên danh sách ở đây thành dữ liệu cũ. Popup gọi bước này **sau khi** đóng hẳn.
    func executeSave(isName: Bool, mode: DataImportMode) {
        // Hàng gạch không bao giờ được lưu (ô chọn đã khoá; lọc thêm cho chắc).
        let chosen = names.filter { $0.isSelected && !isStruck($0) }
        guard !chosen.isEmpty else { return }
        onSave(chosen, isName, mode)
        dismiss()
    }

    /// Toast sau khi lưu xong — dùng chung luồng AI (`ReaderAIFullScreenView.saveNamesToDictionary`) và Lọc name local
    /// (`LocalNameFilterSheet.save`). `targetName` giữ chữ của toast cũ ("Name riêng" / "VietPhrase riêng"). "Chỉ thêm key
    /// mới" mà mọi mục đã có ⇒ báo thường, không phải lỗi.
    static func savedToast(
        _ result: AIHarnessService.ExtractedEntriesSaveResult,
        targetName: String
    ) -> (message: String, type: ToastType) {
        guard result.saved > 0 else {
            return ("Không có mục mới · \(result.keptExisting) mục đã có trong \(targetName) giữ nguyên nghĩa cũ", .info)
        }
        let kept = result.keptExisting > 0 ? " · giữ nguyên \(result.keptExisting) mục đã có" : ""
        return ("Đã lưu \(result.saved) mục vào \(targetName) của truyện\(kept)", .success)
    }
}
