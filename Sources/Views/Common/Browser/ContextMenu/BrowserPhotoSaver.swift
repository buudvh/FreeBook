import UIKit

/// Lưu ảnh vào Thư viện ảnh bằng `UIImageWriteToSavedPhotosAlbum` (quyền "chỉ thêm ảnh" —
/// `NSPhotoLibraryAddUsageDescription` trong `project.yml`) và chờ kết quả qua `async`.
///
/// UIKit gọi lại bằng target/selector và không hứa giữ target ⇒ mỗi lần lưu là một đối tượng **tự giữ mình**
/// (`keepAlive`) tới khi nhận callback.
final class BrowserPhotoSaver: NSObject {
    private var continuation: CheckedContinuation<Error?, Never>?
    private var keepAlive: BrowserPhotoSaver?

    /// Trả `nil` khi lưu xong; lỗi (kể cả người dùng không cho quyền) ⇒ lỗi đó.
    @MainActor
    static func save(_ image: UIImage) async -> Error? {
        let saver = BrowserPhotoSaver()
        return await withCheckedContinuation { continuation in
            saver.continuation = continuation
            saver.keepAlive = saver
            UIImageWriteToSavedPhotosAlbum(
                image, saver, #selector(BrowserPhotoSaver.image(_:didFinishSavingWithError:contextInfo:)), nil
            )
        }
    }

    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeMutableRawPointer?) {
        continuation?.resume(returning: error)
        continuation = nil
        keepAlive = nil
    }
}
