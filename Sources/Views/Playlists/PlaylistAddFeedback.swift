import SwiftUI

/// Toast dùng chung của các lối "Thêm vào playlist" cho cả album / phim (sheet nhấn giữ trên Kệ, ⋮ của item danh sách,
/// icon của gợi ý nhạc, ⋮ của phim đề xuất) và "Thêm vào kệ" của ⋮ — một chỗ để chữ báo giống nhau ở mọi lối.
@MainActor
enum PlaylistAddFeedback {
    /// Lấy mục lục để thêm thất bại ⇒ log ❌ + toast; huỷ (rời màn) thì im lặng.
    static func reportLoadFailure(_ error: Error, album: PlaylistAlbumInfo, kind: PlaylistKind) {
        // Lỗi của tiện ích được bọc trong `ExtensionLoadError` ⇒ bóc ra trước khi so huỷ.
        guard !(ExtensionLoadError.unwrapped(error) is CancellationError), !(error is CancellationError) else { return }
        AppLogger.shared.log("❌ [Playlist] Không lấy được danh sách để thêm vào playlist (tiện ích=\(album.packageId), bookId=\(album.bookId)): \(error.localizedDescription)")
        ToastManager.shared.show(message: "Không lấy được danh sách \(kind.itemNoun): \(error.localizedDescription)", type: .error)
    }

    /// Kết quả "Thêm vào kệ" (`VideoWatchShelfAdder`) của ⋮ item danh sách.
    static func reportShelf(_ outcome: VideoWatchShelfAdder.Outcome, title: String?, kind: PlaylistKind) {
        let noun = kind == .audio ? "Album" : "Phim"
        switch outcome {
        case .added:
            let name = ExtensionHostResolver.nonEmpty(title) ?? noun.lowercased()
            ToastManager.shared.show(message: "Đã thêm \"\(name)\" vào kệ", type: .success)
        case .alreadyOnShelf:
            ToastManager.shared.show(message: "\(noun) đã có trên kệ", type: .info)
        case .failed(let message):
            ToastManager.shared.show(message: "Chưa thêm được vào kệ: \(message)", type: .error)
        }
    }
}
