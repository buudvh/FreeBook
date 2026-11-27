import Foundation

/// Một từ LAC tách + gắn nhãn trong một dòng chữ Hán, đúng như `LAC.run` (Python) trả.
///
/// `tag` là nhãn của LAC sau khi gộp B/I (bỏ hậu tố `-B` / `-I`): thực thể `PER` (người) / `LOC` (nơi) / `ORG` (tổ chức) /
/// `TIME`; từ loại `nz` (danh từ riêng khác) / `nw` (tên tác phẩm) / `n` / `v` / `w` (dấu câu)… — bảng đủ ở `tag.dic`.
struct LACToken: Sendable, Equatable {
    let text: String
    let tag: String
}
