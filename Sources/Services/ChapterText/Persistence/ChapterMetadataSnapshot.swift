import Foundation

struct ChapterMetadataSnapshot: Sendable, Equatable {
    let title: String
    let url: String
    let index: Int
    let host: String?
    let titleTrans: String?
    /// Dòng tiêu đề nhóm tập (`type: "section"`) của truyện tranh/video.
    let isSection: Bool

    init(title: String, url: String, index: Int, host: String? = nil, titleTrans: String? = nil, isSection: Bool = false) {
        self.title = title
        self.url = url
        self.index = index
        self.host = host
        self.titleTrans = titleTrans
        self.isSection = isSection
    }
}
