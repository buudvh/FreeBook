import Foundation

extension LACTagger {
    /// Nạp bộ gán nhãn từ thư mục đã cài (`LACModelStore.installedManifest()` khác `nil`).
    ///
    /// Kiểm sha256 mọi file trước (file hỏng mà đúng kích thước thì self-check sẽ lệch và người dùng bị lùi về bộ luật cũ
    /// mãi — kiểm ở đây biến nó thành `invalidFiles`, gọi viên xoá thư mục ⇒ lần sau tải lại). Trọng số mở bằng
    /// `.alwaysMapped`: embedding fp16 đọc thẳng từ trang ánh xạ, không chép ~15 MB vào RAM. Ném `invalidFiles` /
    /// `CancellationError`.
    static func load(from store: LACModelStore, manifest: LACManifest) throws -> LACTagger {
        try store.verifyChecksums(manifest)

        func read(_ name: String, mapped: Bool = false) throws -> Data {
            do {
                return try Data(contentsOf: store.url(for: name), options: mapped ? .alwaysMapped : [])
            } catch {
                throw LACModelError.invalidFiles("không đọc được \(name)")
            }
        }

        try Task.checkCancellation()
        let network = try LACNetwork(weights: read(LACModelMirror.weightsName, mapped: true), manifest: manifest)
        try Task.checkCancellation()
        let segmenter = try LACSegmenter(dictionary: read(LACModelMirror.segmentDictionaryName),
                                         segment: manifest.segment)
        try Task.checkCancellation()
        let vocabulary = try LACVocabulary(
            wordDictionary: read(LACModelMirror.wordDictionaryName),
            replaceDictionary: read(LACModelMirror.replaceDictionaryName),
            vocabSize: manifest.network.vocabSize
        )
        let labels = try LACLabelTable(tagDictionary: read(LACModelMirror.tagDictionaryName),
                                       numLabels: manifest.network.numLabels)
        return LACTagger(segmenter: segmenter, vocabulary: vocabulary, network: network, labels: labels)
    }
}
