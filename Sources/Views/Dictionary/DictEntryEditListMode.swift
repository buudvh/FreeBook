import SwiftUI

/// Cấu hình **chế độ danh sách** của màn Sửa từ (`DictEntryEditSheet`, 1.3.1075 — anh Bửu: "làm cái gì có vế trái là chữ
/// Hán giống từ điển cũng làm kiểu edit của từ điển"): các danh sách `chữ Hán = …` ngoài từ điển VP / Name / Pronouns
/// (đuôi địa danh, tổ chức, thuật ngữ, "Không phải name", Danh sách họ, token tùy chọn `<@tên>`) mở **cùng** màn Sửa từ thay cho
/// form hai ô. `listMode == nil` ⇒ màn chạy y như trước cho VP / Name / Pronouns / name AI.
///
/// Khác với từ điển:
/// - Kiểm luật + trùng khoá qua store của từng danh sách (`keyError` / `meaningError`), lỗi hiện đỏ ở dòng thông báo
///   (ô còn trống thì không tô đỏ, như form cũ); từ điển thì ghi đè, danh sách thì **từ chối** khoá đã có.
/// - Lưu qua `save` — trả chuỗi lỗi thì sheet giữ nguyên để sửa tiếp, `nil` mới đóng.
/// - Khoá gốc rỗng = **thêm mục mới**: ô gõ chữ gốc mở sẵn và nhận focus, tiêu đề "Thêm từ", nút "Thêm".
/// - `replacing` của `keyError` / `save`: cập nhật ⇒ khoá đang sửa; đổi chữ gốc (chọn cả từ mới) ⇒ khoá đang sửa (store
///   xoá khoá cũ + thêm khoá mới); chọn một phần, hoặc đang thêm mới ⇒ `nil` (mục đang sửa giữ nguyên).
struct DictEntryEditListMode {
    /// `false` = chỉ hàng chữ gốc + hàng token ("Không phải name"): ẩn ô nghĩa, dải chip, aa…AA; nghĩa không bắt buộc.
    var showsMeaning = true
    var meaningPlaceholder = "Nhập nghĩa dịch..."
    /// Luật khoá + trùng khoá của danh sách. `nil` = hợp lệ.
    var keyError: (_ key: String, _ replacing: String?) -> String?
    /// Luật nghĩa của danh sách (bỏ qua khi `showsMeaning == false`). `nil` = hợp lệ.
    var meaningError: (_ meaning: String) -> String? = { _ in nil }
    /// Ghi vào store; `nil` = đã lưu (sheet đóng), chuỗi = lỗi (sheet hiện đỏ, giữ nguyên).
    var save: (_ key: String, _ meaning: String, _ replacing: String?) -> String?
    /// Phần riêng của danh sách (vd Loại / Nghĩa đứng / Về bản gốc của đuôi) đã đổi ⇒ tính là sửa dở và cho lưu.
    var isExtraDirty = false
    /// Hàng phụ đặt sau aa…AA, trước dòng thông báo + nút Cập nhật. Nhận (khoá sẽ lưu, nghĩa đang gõ).
    var extraRows: ((_ key: String, _ meaning: String) -> AnyView)? = nil
    /// **Thêm từ một cụm nguồn** (thêm đuôi từ màn Sửa từ của màn duyệt Lọc name local, 2026-11-27): khoá gốc là cụm nguồn
    /// (vd name 佐特兰街), không phải mục đang có — tiêu đề "Thêm từ", nút "Thêm", lưu luôn là thêm mới (`replacing == nil`)
    /// với phần đang chọn. Mặc định `false`.
    var addsFromSource = false
    /// Nghĩa gợi ý cho phần đang chọn, thay cho tra nghĩa của màn (vd phiên âm viết thường của đuôi). Có ⇒ mỗi lần đổi vùng
    /// chọn ô nghĩa theo gợi ý, cho tới khi người dùng tự gõ / chạm chip (từ đó giữ chữ người dùng). Mặc định `nil`.
    var suggestedMeaning: ((_ key: String) -> String)? = nil
}
