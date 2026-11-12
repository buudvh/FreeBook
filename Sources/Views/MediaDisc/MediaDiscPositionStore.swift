import Foundation

/// Chỗ người dùng kéo đĩa nghe tới (anh Bửu duyệt 2026-11-11): **mép** + **tỉ lệ dọc của tâm** (tâm Y / chiều cao màn),
/// một chỗ chung cho nhạc và TTS, khuôn khoá của nút hub (`FloatingHubViewModel.storedRatioKey`). Khoá không có dấu chấm
/// (`@AppStorage` / KVO đọc dấu chấm là key path lồng nhau).
///
/// Chưa kéo lần nào ⇒ `verticalRatio == nil`: đĩa nằm **thấp nhất** ở mép phải — trang có nút "+" thì đứng ngay trên nút
/// (chỗ của đĩa góc cũ), trang không có gì ở góc thì sát đáy.
enum MediaDiscPositionStore {
    struct Position: Equatable {
        let edge: EdgeDirection
        /// Tâm Y / chiều cao màn; `nil` ⇒ chỗ mặc định (thấp nhất).
        let verticalRatio: CGFloat?
    }

    static let edgeKey = "mediaDiscEdge"
    static let verticalRatioKey = "mediaDiscVerticalRatio"

    static func load() -> Position {
        let defaults = UserDefaults.standard
        let edge: EdgeDirection = defaults.string(forKey: edgeKey) == EdgeDirection.left.rawValue ? .left : .right
        // `object(forKey:)` để phân biệt "chưa có" với 0.
        let ratio = (defaults.object(forKey: verticalRatioKey) as? Double).map { CGFloat($0) }
        return Position(edge: edge, verticalRatio: ratio.flatMap { $0 > 0 && $0 < 1 ? $0 : nil })
    }

    static func save(edge: EdgeDirection, centerY: CGFloat, screenHeight: CGFloat) {
        guard screenHeight > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(edge.rawValue, forKey: edgeKey)
        defaults.set(Double(min(max(centerY / screenHeight, 0.01), 0.99)), forKey: verticalRatioKey)
    }
}
