import Foundation

/// Lỗi chuẩn bị model LAC (`LACModel.prepare`). `errorDescription` là chuỗi tiếng Việt cho người dùng.
///
/// Bộ lọc xử lý theo loại:
/// - `downloadFailed` / `invalidFiles` / `readFailed` ⇒ sự kiện `.failed(…)`, màn đang lọc có nút "Thử lại";
/// - `selfCheckFailed` ⇒ **không** báo người dùng: lùi về bộ luật cũ, log ❌.
/// Huỷ (người dùng đóng sheet) ném `CancellationError` như thường, không phải lỗi ở đây.
enum LACModelError: LocalizedError {
    /// Tải về hỏng: mạng, HTTP khác 2xx, sha256 không khớp manifest.
    case downloadFailed(String)
    /// File trên máy thiếu / hỏng (sha256 lệch, manifest / kích thước tensor / từ điển sai định dạng) — đã xoá để lần sau
    /// tải lại.
    case invalidFiles(String)
    /// Không **đọc** được file (lỗi I/O thoáng qua): file **giữ nguyên** — "Thử lại" đọc lại, không phải tải lại 19 MB.
    case readFailed(String)
    /// Nạp được nhưng chạy mẫu đối chiếu (`lac_golden.json`) lệch quá ngưỡng.
    case selfCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let why): return "Không tải được model nhận diện tên: \(why)"
        case .invalidFiles(let why): return "Model nhận diện tên bị hỏng, lần sau sẽ tải lại: \(why)"
        case .readFailed(let why): return "Không đọc được model nhận diện tên: \(why)"
        case .selfCheckFailed(let why): return "Model nhận diện tên chạy sai mẫu đối chiếu: \(why)"
        }
    }
}
