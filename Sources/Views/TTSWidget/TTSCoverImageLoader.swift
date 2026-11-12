import Combine
import UIKit

/// Nạp ảnh bìa truyện đang đọc cho mặt đĩa TTS và sheet điều khiển nhanh: bìa đã lưu (`covers/`) trước, chưa có thì tải
/// về. Dời khỏi file widget "Đĩa nổi" khi kiểu đó bị bỏ (1.3.859).
@MainActor
final class TTSCoverImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    func load(bookId: String, coverURL: String) {
        guard !bookId.isEmpty else {
            image = nil
            return
        }

        if let cached = ImageCacheManager.shared.loadLocalCover(for: bookId) {
            image = cached
            return
        }

        guard !coverURL.isEmpty else {
            image = nil
            return
        }

        ImageCacheManager.shared.downloadAndSaveCover(urlStr: coverURL, bookId: bookId) { [weak self] downloaded in
            Task { @MainActor in
                self?.image = downloaded
            }
        }
    }
}
