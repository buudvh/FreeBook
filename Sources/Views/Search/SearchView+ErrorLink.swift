import SwiftUI

extension SearchView {
    /// Link "Mở link lỗi" gắn với **đúng** câu lỗi đang ở dải trạng thái (lỗi tìm một nguồn / lỗi đổi nguồn). Dải chỉ vẽ
    /// nút khi `message` còn trùng `searchStatusMessage`: câu trạng thái nào ghi đè (tìm lại, xoá ô tìm, tắt NSFW…) thì
    /// nút tự ẩn, không phải xoá tay ở mọi chỗ gán.
    struct StatusErrorLink {
        enum Retry {
            /// Tìm lại một nguồn với từ khoá đang ở ô tìm (`performSearch`).
            case search
            /// Chạy lại lượt đổi nguồn vừa lỗi (đã xác nhận ở alert, không hỏi lại).
            case sourceChange(result: ExtensionItemResult, ext: Extension)
        }

        let message: String
        let link: SourceErrorLink
        let retry: Retry
        /// Tiện ích/nguồn đã lỗi — nguồn Legado thì cookie của trình duyệt được gộp vào kho của nguồn.
        let packageId: String
    }

    /// Link của câu trạng thái đang hiện; `nil` khi câu đó không phải lỗi có link.
    var currentStatusErrorLink: SourceErrorLink? {
        guard let statusErrorLink, statusErrorLink.message == searchStatusMessage else { return nil }
        return statusErrorLink.link
    }

    /// Gọi ngay trong `catch`, **sau** khi đã gán câu lỗi vào `searchStatusMessage`.
    func attachStatusErrorLink(_ error: Error, fallbacks: [String?], host: String?, retry: StatusErrorLink.Retry,
                               packageId: String) {
        statusErrorLink = SourceErrorLink.resolve(from: error, fallbacks: fallbacks, host: host).map {
            StatusErrorLink(message: searchStatusMessage, link: $0, retry: retry, packageId: packageId)
        }
    }

    /// Thử lại sau khi đóng trình duyệt "Mở link lỗi" — đúng hành động đã lỗi.
    func retryStatusError() {
        guard let statusErrorLink else { return }
        switch statusErrorLink.retry {
        case .search:
            performSearch()
        case .sourceChange(let result, let ext):
            // Giống nút "Đồng ý" của alert đổi nguồn.
            isChangingSource = true
            Task {
                await executeSourceChange(to: result, ext: ext)
                await MainActor.run { isChangingSource = false }
            }
        }
    }
}
