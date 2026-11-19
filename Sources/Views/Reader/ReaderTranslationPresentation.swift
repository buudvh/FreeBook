import Combine
import Foundation

@MainActor
final class ReaderTranslationPresentation {
    struct Prepared {
        let index: Int
        let originalTitle: String
        let originalContent: String
        let result: ReaderParagraphBuildResult
        let revision: Int
        let token: Int
        let translationEnabled: Bool
        let convertTraditional: Bool
    }
    var deferred = false
    var pending: Prepared?
    /// Nghe mốc dịch lại của TTS (`TTSRetranslationCoordinator`: `$anchor` ⇒ nắn chương khi mốc tới muộn, `$ttsTextRevision`
    /// ⇒ trả chương đang ghim chữ về bản dựng gốc khi mốc hết hiệu lực; `ReaderViewModel+TTSRetranslation`). Đăng ký lười ở
    /// lần dựng chương đầu tiên.
    var ttsAnchorSubscriptions = Set<AnyCancellable>()
}
