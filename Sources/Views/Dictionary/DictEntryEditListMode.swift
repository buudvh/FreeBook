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
    /// Phần đặt **cuối hàng aa…AA** (như cụm R | C ở panel Dịch của Reader) — vd cụm R | C của hậu tố / tiền tố lọc name
    /// local mở từ một truyện (`DictEntryEditScopeToggle`, 2026-11-28). Mặc định `nil`.
    var caseRowTrailing: AnyView? = nil
    /// Nơi mở **nhận việc lưu** thay màn Sửa từ khi cần hỏi lại trước (vd chuyển hậu tố riêng lên Chung mà Chung đã có chữ
    /// đó — ghi đè cho mọi truyện): gọi sau khi đã qua mọi luật, nhận (khoá, nghĩa, `replacing`) như `save`. Trả `true` ⇒
    /// nơi mở đã hiện hộp hỏi và tự lưu + đóng sheet khi người dùng đồng ý; màn Sửa từ không lưu, không đóng. `false` /
    /// `nil` ⇒ lưu như thường.
    var interceptSave: ((_ key: String, _ meaning: String, _ replacing: String?) -> Bool)? = nil
    /// **Sửa một mục trong cụm nguồn** (2026-11-28, mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M5b — chạm
    /// chip có sẵn ở màn Quản lý tiền tố, hậu tố / hàng chip ✓): khoá gốc là cụm nguồn (name 古赫密斯语), vùng chọn ban đầu
    /// là chữ của mục này (语), nới / thu bằng ‹ › như khi thêm. Tiêu đề "Sửa từ", nút "Cập nhật"; lưu luôn thay mục này
    /// (`replacing` = khoá này): chọn đúng chữ cũ = cập nhật, chọn chữ khác = đổi chữ của mục (dòng "Đổi 语 thành 斯语").
    /// Đi cùng `suggestedMeaning` (chữ cũ ⇒ nghĩa đang lưu). Mặc định `nil`.
    var sourceEditingKey: String? = nil
}
