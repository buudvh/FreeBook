import Foundation

/// `lac_manifest.json` của bản LAC trên kho `LACModelMirror`: hình dạng mạng, vị trí từng tensor trong
/// `lac_weights.bin`, hằng số tách từ và kích thước + sha256 của mọi file dữ liệu.
///
/// Manifest đã ghim sha256 trong code (`LACModelMirror.manifestSHA256`) nên giá trị ở đây đáng tin; `validated()` vẫn
/// kiểm hình dạng trước khi bất cứ phép tính con trỏ nào dựa vào nó — sai một offset là văng app, không phải lỗi.
struct LACManifest: Decodable, Sendable {
    struct Network: Decodable, Sendable {
        let vocabSize: Int
        let embeddingDim: Int
        let hiddenSize: Int
        let layers: Int
        let numLabels: Int
    }

    struct Tensor: Decodable, Sendable {
        let name: String
        let dtype: String
        let shape: [Int]
        let offset: Int
        let bytes: Int
    }

    struct Segment: Decodable, Sendable {
        let dictTotalCount: Int
        let maxWordLength: Int
        /// `log(tổng số lần)` của `small_seg.dic` — tính sẵn bằng Python để điểm tách từ trùng LAC tới từng bit.
        let logTotal: Double
        /// `logLength[k - 1] = log(k)`.
        let logLength: [Double]
    }

    struct Golden: Decodable, Sendable {
        let count: Int
    }

    struct FileEntry: Decodable, Sendable {
        let bytes: Int64
        let sha256: String
    }

    static let supportedFormat = 1

    let format: Int
    let network: Network
    let tensors: [Tensor]
    let segment: Segment
    let golden: Golden
    let files: [String: FileEntry]

    func tensor(_ name: String) -> Tensor? {
        tensors.first { $0.name == name }
    }

    /// Giải mã + kiểm các bất biến mà code nạp dựa vào. Ném `LACModelError.invalidFiles`.
    static func decode(_ data: Data) throws -> LACManifest {
        let manifest: LACManifest
        do {
            manifest = try JSONDecoder().decode(LACManifest.self, from: data)
        } catch {
            throw LACModelError.invalidFiles("manifest không đọc được (\(error.localizedDescription))")
        }
        try manifest.validate()
        return manifest
    }

    private func validate() throws {
        func fail(_ why: String) -> LACModelError { .invalidFiles("manifest: \(why)") }
        guard format == Self.supportedFormat else { throw fail("định dạng \(format) chưa hỗ trợ") }
        guard network.layers == 2, network.vocabSize > 0, network.embeddingDim > 0, network.hiddenSize > 0,
              network.numLabels > 0 else { throw fail("hình dạng mạng lạ") }
        guard segment.maxWordLength > 0, segment.logLength.count == segment.maxWordLength,
              segment.dictTotalCount > 0 else { throw fail("hằng số tách từ lạ") }
        guard golden.count > 0 else { throw fail("không có mẫu đối chiếu") }
        for name in LACModelMirror.dataFileNames {
            guard let entry = files[name], entry.bytes > 0, entry.sha256.count == 64 else {
                throw fail("thiếu mục \(name)")
            }
        }
        guard let weightsBytes = files[LACModelMirror.weightsName]?.bytes else { throw fail("thiếu trọng số") }
        for tensor in tensors {
            let elementSize: Int
            switch tensor.dtype {
            case "float32": elementSize = 4
            case "float16": elementSize = 2
            default: throw fail("\(tensor.name) kiểu \(tensor.dtype)")
            }
            let count = tensor.shape.reduce(1) { partial, dim in dim > 0 ? partial * dim : -1 }
            guard count > 0, tensor.bytes == count * elementSize, tensor.offset >= 0, tensor.offset % 4 == 0,
                  Int64(tensor.offset) + Int64(tensor.bytes) <= weightsBytes else {
                throw fail("\(tensor.name) sai kích thước / vị trí")
            }
        }
    }
}
