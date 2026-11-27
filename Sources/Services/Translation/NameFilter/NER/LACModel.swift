import Foundation

/// Cửa vào duy nhất của model LAC cho bộ lọc name local.
///
/// **Bản giữ chỗ** của hợp đồng (chữ ký cố định); phần thật — tải từ kho Hugging Face ghim commit, kiểm sha256, nạp
/// trọng số, tự kiểm với `lac_golden.json` — thay thân hàm này. Nguồn: `datasets/raikiri1498/vietpharse`, thư mục `lac/`,
/// commit `73bb76d492d03f730b1aee1c6fade62d5eedf08c`; đặc tả thuật toán ở `lac/README.md` của kho đó.
enum LACModel {
    /// Đảm bảo model có trên máy (thiếu ⇒ tải, báo `progress(0…1)`), nạp + tự kiểm (báo `progress(nil)`), trả bộ gán nhãn.
    /// Gọi lại khi bộ gán nhãn cũ còn sống ⇒ trả lại nó ngay, không báo gì. Ném `LACModelError` / `CancellationError`.
    static func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws -> any LACTagging {
        throw LACModelError.invalidFiles("chưa có bộ nhận diện LAC")
    }
}
