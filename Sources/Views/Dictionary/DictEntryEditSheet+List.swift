import SwiftUI

/// Chế độ danh sách của màn Sửa từ (`DictEntryEditListMode`): kiểm luật + trùng khoá qua store của danh sách, lưu trả lỗi
/// thì giữ sheet, hàng phụ riêng của danh sách. Mọi thành viên ở đây trả về giá trị trung tính khi `listMode == nil`
/// (từ điển VP / Name / Pronouns / name AI), nên màn đó chạy y như trước.
extension DictEntryEditSheet {

    // MARK: - Trạng thái suy ra

    /// Danh sách, khoá gốc rỗng = thêm mục mới (tiêu đề "Thêm từ", nút "Thêm", ô gõ chữ gốc mở sẵn); thêm từ một cụm nguồn
    /// (`DictEntryEditListMode.addsFromSource`) cũng là thêm mới.
    var isAddingListEntry: Bool {
        guard let listMode else { return false }
        return trimmedOriginalKey.isEmpty || listMode.addsFromSource
    }

    /// Ô nghĩa, dải chip, aa…AA — chỉ "Không phải name" tắt.
    var showsMeaningRows: Bool { listMode?.showsMeaning ?? true }

    /// Khoá bị thay khi lưu (xem `DictEntryEditListMode`): cập nhật / đổi chữ gốc ⇒ khoá đang sửa; chọn một phần hoặc
    /// đang thêm mới ⇒ `nil`.
    var listReplacingKey: String? {
        guard !isAddingListEntry else { return nil }
        switch saveAction {
        case .update?, .rename?: return trimmedOriginalKey
        case .addNew?, nil: return nil
        }
    }

    private var trimmedMeaning: String { meaning.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Lỗi luật chặn nút lưu (cả khi chưa hiện — vd nghĩa còn trống). `nil` ở chế độ từ điển.
    var listValidationError: String? {
        guard let listMode, saveAction != nil else { return nil }
        if let error = listMode.keyError(saveTargetKey, listReplacingKey) { return error }
        return showsMeaningRows ? listMode.meaningError(trimmedMeaning) : nil
    }

    /// Lỗi **hiện** đỏ: như form cũ, ô còn trống thì không tô đỏ — khoá rỗng không có `saveAction`, nghĩa rỗng thì bỏ qua.
    private var visibleListErrors: [String] {
        guard let listMode, saveAction != nil else { return [] }
        var errors: [String] = []
        if let keyError = listMode.keyError(saveTargetKey, listReplacingKey) {
            errors.append(keyError)
        } else if showsMeaningRows, !trimmedMeaning.isEmpty, let meaningError = listMode.meaningError(trimmedMeaning) {
            errors.append(meaningError)
        }
        if let listSaveError, !errors.contains(listSaveError) { errors.append(listSaveError) }
        return errors
    }

    // MARK: - Hàng

    @ViewBuilder
    var listExtraRowsView: some View {
        if let extraRows = listMode?.extraRows {
            extraRows(saveTargetKey, trimmedMeaning)
        }
    }

    @ViewBuilder
    var listErrorNoticeView: some View {
        ForEach(visibleListErrors, id: \.self) { error in
            noticeLine(error, systemImage: "exclamationmark.circle.fill", color: .red)
        }
    }

    // MARK: - Lưu

    /// Lưu qua store của danh sách; lỗi ⇒ hiện đỏ, giữ sheet để sửa tiếp.
    func saveToList() {
        guard let listMode, saveAction != nil, !isLoadingMeaning, listValidationError == nil else { return }
        let key = saveTargetKey
        if showsMeaningRows, trimmedMeaning.isEmpty { return }
        let value = showsMeaningRows ? trimmedMeaning : ""
        // Nơi mở cần hỏi lại trước (`DictEntryEditListMode.interceptSave`) ⇒ nó tự lưu + đóng sheet khi người dùng đồng ý.
        if listMode.interceptSave?(key, value, listReplacingKey) == true { return }
        if let error = listMode.save(key, value, listReplacingKey) {
            listSaveError = error
            return
        }
        dismiss()
    }
}
