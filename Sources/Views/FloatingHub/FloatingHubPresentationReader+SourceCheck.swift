import Foundation

/// Dòng **Kiểm tra nguồn** của hub nổi (1.3.697): lượt kiểm tra nguồn Legado / tiện ích JS đang thu nhỏ
/// (`MinimizedSourceCheckCoordinator`). Đang chạy ⇒ tiến trình của nút (nháy); chỉ còn kết quả chưa xem ⇒ vẫn là mục của
/// nút nhưng không nháy (`quietKinds`). Tiến độ chỉ nằm ở chữ của dòng, không vào `ButtonState` ⇒ nút không vẽ lại mỗi
/// giây.
extension FloatingHubPresentationReader {
    /// Một lượt: tên bộ kiểm tra + tiến độ / kết quả. Hai lượt (một Legado, một tiện ích JS): đếm chung, chạm dòng sang
    /// trang "Kiểm tra nguồn".
    static func sourceCheckItem(entries: [MinimizedSourceCheck]) -> FloatingHubItem {
        guard let first = entries.first else {
            return FloatingHubItem(kind: .sourceCheck, detail: "Không có lượt kiểm tra thu nhỏ")
        }
        guard entries.count > 1 else {
            return FloatingHubItem(
                kind: .sourceCheck,
                isEnabled: true,
                headline: first.kind.title,
                detail: first.detailText,
                detailTone: first.detailTone,
                isActive: true
            )
        }
        let running = entries.filter(\.isRunning).count
        let done = entries.count - running
        let detail: String
        if done == 0 {
            detail = "\(running) lượt đang chạy"
        } else if running == 0 {
            detail = "\(done) lượt đã xong — bấm để xem"
        } else {
            detail = "\(running) đang chạy · \(done) đã xong"
        }
        return FloatingHubItem(kind: .sourceCheck, isEnabled: true, detail: detail, isActive: true)
    }
}
