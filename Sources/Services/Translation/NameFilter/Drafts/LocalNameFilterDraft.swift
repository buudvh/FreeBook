import Foundation

/// Một **gói name tạm** của "Lọc name local" (plan 2026-11-27 mục E2): danh sách đang duyệt được giữ lại khi người dùng
/// đóng màn duyệt mà chưa bấm Lưu (kể cả sau "Dừng"), hoặc khi app vào nền lúc đang duyệt. Mở lại ⇒ màn duyệt đúng trạng
/// thái đã giữ. Lưu ở `LocalNameFilterDraftStore` (mỗi truyện một file, tối đa 5 gói).
///
/// `names` giữ nguyên `AIExtractedName` của màn duyệt: chữ Hán, nghĩa (kể cả nghĩa đã sửa), nhãn loại, số lần, đang chọn,
/// cờ NE / VP — mở lại vẫn tra lại cờ NE / VP (từ điển có thể đã đổi), giữ trạng thái chọn.
///
/// Gói **tự cập nhật** theo danh sách đuôi + "Không phải name" (plan 2026-11-27-nghia-ten-tay-huyen mục 6,
/// `LocalNameFilterDraftRefresher`): `autoMeanings` nhớ nghĩa máy ghép để phân biệt với nghĩa người dùng đã tự sửa.
struct LocalNameFilterDraft: Codable, Sendable, Identifiable, Equatable {
    /// Nghĩa máy ghép của một name + loại của nó lúc lọc (loại quyết định có ghép lại được không — người / họ tộc thì không).
    struct AutoMeaning: Codable, Sendable, Equatable {
        var meaning: String
        let kind: LocalNameFilter.Kind
        /// Ghi đè công tắc **"Nới đoán tên Latin"** cho riêng name này (màn Sửa từ của màn duyệt, 2026-11-28 — mockup N6);
        /// `nil` = theo công tắc của truyện. Trường tuỳ chọn ⇒ gói tạm cũ (chưa có trường) đọc được. Mọi lần ghép lại phải
        /// giữ giá trị này (init không có mặc định để chỗ dựng nào cũng phải chọn).
        var loosensLatin: Bool?

        init(meaning: String, kind: LocalNameFilter.Kind, loosensLatin: Bool?) {
            self.meaning = meaning
            self.kind = kind
            self.loosensLatin = loosensLatin
        }
    }

    /// Cố định suốt đời gói: mở lại rồi đóng chưa Lưu ⇒ ghi đè đúng gói này, không tạo gói mới.
    let id: UUID
    /// Lúc lọc xong (giờ hiện ở hàng của sheet thiết lập) — không đổi khi gói được ghi lại.
    let filteredAt: Date
    /// Lần ghi gần nhất — gói ghi lâu nhất bị bỏ khi quá `LocalNameFilterDraftStore.maxDraftsPerBook`.
    var savedAt: Date
    /// Mô tả phạm vi đã đọc: "chương 1–50" (chương liền nhau) hoặc "193 chương" (`scopeLabel(chapterNumbers:)`).
    let scopeLabel: String
    /// Số chương đã đọc trong lượt lọc.
    let chapterCount: Int
    var names: [AIExtractedName]
    /// Chữ Hán ⇒ nghĩa máy ghép (lúc lọc, hoặc lần tự cập nhật trước). Nghĩa đang có khác nghĩa máy ghép ⇒ người dùng đã tự
    /// sửa ⇒ giữ nguyên. `nil` = gói của bản trước (chưa có trường này) ⇒ không ghép lại nghĩa, chỉ bỏ name "Không phải name".
    var autoMeanings: [String: AutoMeaning]?
    /// Dấu danh sách đuôi + công tắc Latin / nới của lần ghép nghĩa gần nhất (`LocalNameFilterMeaningComposer.signature`): trùng
    /// dấu hiện tại ⇒ bộ cập nhật gói không ghép lại. `nil` ⇒ chưa biết ⇒ ghép lại một lần rồi ghi dấu.
    var meaningSignature: String? = nil

    var selectedCount: Int {
        names.reduce(0) { $0 + ($1.isSelected ? 1 : 0) }
    }

    /// Phạm vi đã đọc theo **số chương hiển thị** (`AINameScanChapter.number`), đúng thứ tự đọc: một chương ⇒ "chương 7";
    /// liền nhau ⇒ "chương 1–50"; có chỗ hở (chỉ chương đã tải mới được đọc) ⇒ "193 chương". Rỗng ⇒ "0 chương".
    static func scopeLabel(chapterNumbers: [Int]) -> String {
        guard let first = chapterNumbers.first, let last = chapterNumbers.last else { return "0 chương" }
        if chapterNumbers.count == 1 { return "chương \(first)" }
        let isContiguous = last >= first && last - first + 1 == chapterNumbers.count
        return isContiguous ? "chương \(first)–\(last)" : "\(chapterNumbers.count) chương"
    }
}
