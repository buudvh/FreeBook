import Foundation

/// Luật chọn `VideoMinimizeStyle` khi vuốt xuống trình phát:
/// `Extension.videoMinimizeOverride ?? (phim 18+ ? cài đặt "Phim 18+" : cài đặt "Phim thường")`.
///
/// - "18+" = `RepositoryFilterPolicy.isNsfwBook` (phim tự đánh dấu hoặc nguồn NSFW), cùng luật với `VideoMutePolicy`.
/// - Hai khoá chung không có dấu chấm (`@AppStorage` theo dõi bằng KVO, khoá có dấu chấm không báo đổi). Khoá chưa ghi
///   hoặc giá trị lạ ⇒ `hub`, giữ hành vi cũ.
/// - Nguồn Legado loại video không có màn ghi đè ⇒ luôn theo cài đặt chung.
enum VideoMinimizePolicy {
    static let normalDefaultsKey = "videoSwipeMinimizeNormal"
    static let nsfwDefaultsKey = "videoSwipeMinimizeNsfw"
    static let defaultValue: VideoMinimizeStyle = .hub

    /// Cài đặt chung cho phim thường (`nsfw == false`) hoặc phim 18+.
    static func globalStyle(nsfw: Bool) -> VideoMinimizeStyle {
        let key = nsfw ? nsfwDefaultsKey : normalDefaultsKey
        guard let raw = UserDefaults.standard.string(forKey: key),
              let style = VideoMinimizeStyle(rawValue: raw) else { return defaultValue }
        return style
    }

    /// Ghi đè của tiện ích (`nil` hoặc giá trị lạ ⇒ không ghi đè).
    static func overrideStyle(packageId: String) -> VideoMinimizeStyle? {
        guard let raw = ExtensionLibraryRepository.snapshot(packageId: packageId)?.videoMinimizeOverride else { return nil }
        return VideoMinimizeStyle(rawValue: raw)
    }

    /// Kiểu thu nhỏ của phim `bookId` thuộc tiện ích `packageId`.
    static func style(bookId: String, packageId: String) -> VideoMinimizeStyle {
        if let style = overrideStyle(packageId: packageId) { return style }
        return globalStyle(nsfw: RepositoryFilterPolicy.isNsfwBook(bookId: bookId, packageId: packageId))
    }
}
