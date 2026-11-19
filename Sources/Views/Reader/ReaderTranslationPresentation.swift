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
    /// Nghe mốc dịch lại của TTS (`TTSRetranslationCoordinator.$anchor`) để nắn chương đã áp khi mốc tới muộn
    /// (`ReaderViewModel+TTSRetranslation`). Đăng ký lười ở lần dựng chương đầu tiên.
    var ttsAnchorSubscription: AnyCancellable?
}
