import Foundation

/// Một session ORT của phép thử P1 "So EP cho Nano" — bọc `VieNeuONNXProbeBridge.h` (chỉ float32, chạy theo tên).
///
/// Chỉ `VieNeuNanoEPProbe` dùng; đường đọc truyện vẫn đi `VieNeuONNXRuntime`. Không an toàn đa luồng — mỗi lần chỉ
/// một luồng gọi `run`.
final class VieNeuONNXProbeSession {
    enum ProbeError: LocalizedError {
        case failure(String)
        case missingInput(String)

        var errorDescription: String? {
            switch self {
            case .failure(let message): return message
            case .missingInput(let name): return "thiếu input \(name)"
            }
        }
    }

    /// Một tensor float32: dữ liệu phẳng + shape.
    struct Tensor {
        let values: [Float]
        let shape: [Int64]
    }

    let inputNames: [String]
    let outputNames: [String]
    private let handle: OpaquePointer

    /// Một file trọng số external data nạp vào bộ nhớ trước khi tạo session (P1b): `name` = đúng `location` ghi trong
    /// graph (vd `ve_main.weights`), `path` = file trên máy.
    struct WeightFile: Sendable {
        let name: String
        let path: String
    }

    /// - `provider`: `"CPU"`, `"CoreML"` hoặc `"XNNPACK"`.
    /// - `logPath`: khác rỗng ⇒ bắt stderr lúc tạo session vào file này (bảng partition của EP; có thể rỗng).
    /// - `weights`: trọng số nạp từ bộ nhớ — né lỗi Core ML EP ORT 1.24.2 đọc external data sai đường dẫn.
    init(
        modelPath: String,
        provider: String,
        options: [String: String],
        threads: Int32,
        logPath: String,
        weights: [WeightFile] = []
    ) throws {
        let keys = options.keys.sorted()
        let cKeys = keys.map { strdup($0) }
        let cValues = keys.map { strdup(options[$0] ?? "") }
        let cWeightNames = weights.map { strdup($0.name) }
        let cWeightPaths = weights.map { strdup($0.path) }
        defer {
            cKeys.forEach { free($0) }
            cValues.forEach { free($0) }
            cWeightNames.forEach { free($0) }
            cWeightPaths.forEach { free($0) }
        }
        var keyPointers: [UnsafePointer<CChar>?] = cKeys.map { UnsafePointer($0) }
        var valuePointers: [UnsafePointer<CChar>?] = cValues.map { UnsafePointer($0) }
        var weightNamePointers: [UnsafePointer<CChar>?] = cWeightNames.map { UnsafePointer($0) }
        var weightPathPointers: [UnsafePointer<CChar>?] = cWeightPaths.map { UnsafePointer($0) }
        var message: UnsafeMutablePointer<CChar>?
        let created = VieNeuORTProbeCreate(
            modelPath, provider, &keyPointers, &valuePointers, Int32(keys.count), threads, logPath,
            &weightNamePointers, &weightPathPointers, Int32(weights.count), &message
        )
        guard let created else {
            throw ProbeError.failure(Self.consume(message, fallback: "không tạo được session"))
        }
        handle = created
        inputNames = (0..<VieNeuORTProbeInputCount(created)).map { String(cString: VieNeuORTProbeInputName(created, $0)) }
        outputNames = (0..<VieNeuORTProbeOutputCount(created)).map { String(cString: VieNeuORTProbeOutputName(created, $0)) }
    }

    deinit {
        VieNeuORTProbeDestroy(handle)
    }

    /// Chạy một lượt với input lấy theo tên từ `feeds`; trả mọi output (dữ liệu + shape) theo tên.
    func run(_ feeds: [String: Tensor]) throws -> [String: Tensor] {
        var shapes: [Int64] = []
        var ranks: [Int32] = []
        var buffers: [UnsafeMutableBufferPointer<Float>] = []
        defer { buffers.forEach { $0.deallocate() } }
        for name in inputNames {
            guard let tensor = feeds[name] else { throw ProbeError.missingInput(name) }
            let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: max(1, tensor.values.count))
            _ = buffer.initialize(from: tensor.values)
            buffers.append(buffer)
            shapes.append(contentsOf: tensor.shape)
            ranks.append(Int32(tensor.shape.count))
        }
        var inputPointers: [UnsafePointer<Float>?] = buffers.map { UnsafePointer($0.baseAddress) }
        var outputPointers = [UnsafeMutablePointer<Float>?](repeating: nil, count: outputNames.count)
        var outputCounts = [Int64](repeating: 0, count: outputNames.count)
        let maxRank = Int(VIENEU_PROBE_MAX_RANK)
        var outputShapes = [Int64](repeating: 0, count: max(1, outputNames.count * maxRank))
        var outputRanks = [Int32](repeating: 0, count: max(1, outputNames.count))
        var message: UnsafeMutablePointer<CChar>?
        let status = VieNeuORTProbeRun(
            handle, &inputPointers, shapes, ranks, &outputPointers, &outputCounts, &outputShapes, &outputRanks, &message
        )
        guard status == 0 else {
            throw ProbeError.failure(Self.consume(message, fallback: "Run thất bại"))
        }
        var result: [String: Tensor] = [:]
        for (index, name) in outputNames.enumerated() {
            guard let pointer = outputPointers[index] else { continue }
            let values = Array(UnsafeBufferPointer(start: pointer, count: Int(outputCounts[index])))
            free(pointer)
            let start = index * maxRank
            let shape = Array(outputShapes[start..<(start + Int(outputRanks[index]))])
            result[name] = Tensor(values: values, shape: shape)
        }
        return result
    }

    private static func consume(_ message: UnsafeMutablePointer<CChar>?, fallback: String) -> String {
        guard let message else { return fallback }
        let text = String(cString: message)
        VieNeuORTProbeFreeString(message)
        return text
    }
}
