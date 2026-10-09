import Foundation

enum ReaderLoadState: Equatable {
    case bootstrapping
    case loading(chapterIndex: Int)
    case ready(chapterIndex: Int)
    case failed(chapterIndex: Int?, message: String)
}
