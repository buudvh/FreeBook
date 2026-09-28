import Foundation
import onnxruntime

/// Bọc **C API** của ONNX Runtime cho engine VieNeu-TTS.
///
/// ## Vì sao không dùng lớp ObjC (`OnnxRuntimeBindings`) như `ONNXPiperEngine`
/// `ctx_mask` của `duration_predictor.onnx` và `vector_estimator.onnx` khai `elem_type = 9 = BOOL`
/// (đọc trực tiếp protobuf của model). Nhưng `ORTTensorElementDataType` của wrapper ObjC **không có
/// case `Bool`** ở **mọi** bản phát hành còn dùng được: đã kiểm `ort_enums.h` tại ORT v1.16.0, v1.20.0,
/// v1.24.2 (bản gói SPM `from: 1.16.0` resolve tới) và cả `main` của gói SPM — chỉ `main` của **ORT
/// core** mới có, và nó chưa phát hành. Hàm map `PublicToCAPITensorElementType` dùng bảng tra + throw
/// nên `ORTTensorElementDataType(rawValue: 9)` cũng không lọt, và `ORTValue` không có init nào nhận con
/// trỏ C `OrtValue*` ⇒ **không thể** tạo tensor bool qua lớp ObjC.
///
/// C API thì có `ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL` từ lâu, nên engine này đi thẳng C API và bỏ hẳn
/// `OnnxRuntimeBindings`.
///
/// ## Bẫy đã xác minh khi viết file này
/// - `ORT_API2_STATUS` **không** thêm tham số `const OrtApi*` vào đầu hàm ⇒ gọi qua
///   `api.pointee.TenHam(...)`, không truyền `api`.
/// - Các hàm `Release*` (sinh bằng `ORT_CLASS_RELEASE`) trả **`void`**, không phải `OrtStatus*` — không
///   được `try check(...)` chúng.
/// - `CreateTensorWithDataAsOrtValue` **không copy** dữ liệu: `NSMutableData` của mỗi input phải sống
///   tới hết lượt `Run`.
/// - Dữ liệu output do ORT cấp phát nên căn chỉnh đúng chuẩn ⇒ `assumingMemoryBound(to: Float.self)` an
///   toàn (khác hẳn trường hợp đọc `Data` trong `VieNeuConfig`, nơi phải đọc từng byte).
final class VieNeuONNXRuntime {
    /// Bốn graph của pipeline, theo đúng thứ tự thi hành.
    enum Graph: String, CaseIterable {
        case textEncoder = "text_encoder.onnx"
        case durationPredictor = "duration_predictor.onnx"
        case vectorEstimator = "vector_estimator.onnx"
        case codecDecoder = "codec_decoder.onnx"
    }

    enum RuntimeError: LocalizedError {
        case apiUnavailable
        case failure(String)
        case badOutput(String)

        var errorDescription: String? {
            switch self {
            case .apiUnavailable: return "Không lấy được C API của ONNX Runtime"
            case .failure(let message): return "ONNX Runtime: \(message)"
            case .badOutput(let name): return "Graph \(name) không trả về tensor mong đợi"
            }
        }
    }

    private let api: UnsafePointer<OrtApi>
    private let env: UnsafeMutablePointer<OrtEnv>
    private let memoryInfo: UnsafeMutablePointer<OrtMemoryInfo>
    private let sessions: [Graph: UnsafeMutablePointer<OrtSession>]

    init(modelStore: VieNeuModelStore, threadCount: Int32) throws {
        guard let apiBase = OrtGetApiBase(), let api = apiBase.pointee.GetApi(UInt32(ORT_API_VERSION)) else {
            throw RuntimeError.apiUnavailable
        }
        self.api = api

        var env: UnsafeMutablePointer<OrtEnv>?
        try Self.check(api.pointee.CreateEnv(Self.loggingWarning, "FreeBookVieNeu", &env), api: api)
        guard let env else { throw RuntimeError.failure("CreateEnv trả về con trỏ rỗng") }
        self.env = env

        var memoryInfo: UnsafeMutablePointer<OrtMemoryInfo>?
        try Self.check(
            api.pointee.CreateCpuMemoryInfo(Self.allocatorDevice, Self.memoryTypeDefault, &memoryInfo),
            api: api
        )
        guard let memoryInfo else { throw RuntimeError.failure("CreateCpuMemoryInfo trả về con trỏ rỗng") }
        self.memoryInfo = memoryInfo

        var options: UnsafeMutablePointer<OrtSessionOptions>?
        try Self.check(api.pointee.CreateSessionOptions(&options), api: api)
        guard let options else { throw RuntimeError.failure("CreateSessionOptions trả về con trỏ rỗng") }
        defer { api.pointee.ReleaseSessionOptions(options) }
        try Self.check(api.pointee.SetIntraOpNumThreads(options, threadCount), api: api)
        try Self.check(api.pointee.SetSessionGraphOptimizationLevel(options, Self.graphOptimizationAll), api: api)

        var built: [Graph: UnsafeMutablePointer<OrtSession>] = [:]
        for graph in Graph.allCases {
            var session: UnsafeMutablePointer<OrtSession>?
            let path = modelStore.url(for: graph.rawValue).path
            try Self.check(api.pointee.CreateSession(env, path, options, &session), api: api)
            guard let session else { throw RuntimeError.failure("CreateSession trả về con trỏ rỗng cho \(graph.rawValue)") }
            built[graph] = session
        }
        self.sessions = built
    }

    deinit {
        for session in sessions.values { api.pointee.ReleaseSession(session) }
        api.pointee.ReleaseMemoryInfo(memoryInfo)
        api.pointee.ReleaseEnv(env)
    }

    // MARK: - Bốn bước của pipeline

    /// `text_encoder(ids, style)` → `ctx` phẳng theo hàng, shape `[1, length, dim]`.
    func textEncoder(ids: [Int64], style: [Float], styleRows: Int, styleColumns: Int, dim: Int) throws -> [Float] {
        var keepAlive: [NSMutableData] = []
        let idsValue = try int64Value(ids, shape: [1, Int64(ids.count)], keepAlive: &keepAlive)
        let styleValue = try floatValue(style, shape: [1, Int64(styleRows), Int64(styleColumns)], keepAlive: &keepAlive)
        let outputs = try run(
            graph: .textEncoder,
            names: ["ids", "style"],
            values: [idsValue, styleValue]
        )
        let context = try floats(from: outputs[0], graph: .textEncoder)
        _ = dim
        _ = keepAlive
        return context
    }

    /// `duration_predictor(ctx, ctx_mask, spk)` → `log_s` (một số vô hướng).
    func durationPredictor(
        context: [Float],
        length: Int,
        mask: [UInt8],
        speaker: [Float],
        dim: Int
    ) throws -> Float {
        var keepAlive: [NSMutableData] = []
        let contextValue = try floatValue(context, shape: [1, Int64(length), Int64(dim)], keepAlive: &keepAlive)
        let maskValue = try boolValue(mask, shape: [1, Int64(mask.count)], keepAlive: &keepAlive)
        let speakerValue = try floatValue(speaker, shape: [1, Int64(speaker.count)], keepAlive: &keepAlive)
        let outputs = try run(
            graph: .durationPredictor,
            names: ["ctx", "ctx_mask", "spk"],
            values: [contextValue, maskValue, speakerValue]
        )
        let values = try floats(from: outputs[0], graph: .durationPredictor)
        guard let first = values.first else { throw RuntimeError.badOutput(Graph.durationPredictor.rawValue) }
        _ = keepAlive
        return first
    }

    /// `vector_estimator(x, t, ctx, ctx_mask, spk, style)` → velocity cùng shape với `x`.
    func vectorEstimator(
        latent: [Float],
        time: Float,
        context: [Float],
        length: Int,
        mask: [UInt8],
        speaker: [Float],
        style: [Float],
        styleRows: Int,
        styleColumns: Int,
        latentChannels: Int,
        frames: Int,
        dim: Int
    ) throws -> [Float] {
        var keepAlive: [NSMutableData] = []
        let latentValue = try floatValue(latent, shape: [1, Int64(latentChannels), Int64(frames)], keepAlive: &keepAlive)
        let timeValue = try floatValue([time], shape: [1], keepAlive: &keepAlive)
        let contextValue = try floatValue(context, shape: [1, Int64(length), Int64(dim)], keepAlive: &keepAlive)
        let maskValue = try boolValue(mask, shape: [1, Int64(mask.count)], keepAlive: &keepAlive)
        let speakerValue = try floatValue(speaker, shape: [1, Int64(speaker.count)], keepAlive: &keepAlive)
        let styleValue = try floatValue(style, shape: [1, Int64(styleRows), Int64(styleColumns)], keepAlive: &keepAlive)
        let outputs = try run(
            graph: .vectorEstimator,
            names: ["x", "t", "ctx", "ctx_mask", "spk", "style"],
            values: [latentValue, timeValue, contextValue, maskValue, speakerValue, styleValue]
        )
        let result = try floats(from: outputs[0], graph: .vectorEstimator)
        _ = keepAlive
        return result
    }

    /// `codec_decoder(x)` → PCM float32. Số mẫu **không** suy được từ công thức nên phải hỏi shape thật
    /// của tensor trả về.
    func codecDecoder(latent: [Float], latentChannels: Int, frames: Int) throws -> [Float] {
        var keepAlive: [NSMutableData] = []
        let latentValue = try floatValue(latent, shape: [1, Int64(latentChannels), Int64(frames)], keepAlive: &keepAlive)
        let outputs = try run(graph: .codecDecoder, names: ["x"], values: [latentValue])
        let elementCount = try elementCount(of: outputs[0])
        let samples = try floats(from: outputs[0], graph: .codecDecoder, elementCount: elementCount)
        _ = keepAlive
        return samples
    }

    // MARK: - Run

    private func run(
        graph: Graph,
        names: [String],
        values: [UnsafeMutablePointer<OrtValue>]
    ) throws -> [UnsafeMutablePointer<OrtValue>] {
        guard let session = sessions[graph] else { throw RuntimeError.badOutput(graph.rawValue) }
        defer { for value in values { api.pointee.ReleaseValue(value) } }

        let nameCStrings = names.map { strdup($0) }
        defer { nameCStrings.forEach { free($0) } }
        var inputNames: [UnsafePointer<CChar>?] = nameCStrings.map { UnsafePointer($0) }
        var inputValues: [UnsafePointer<OrtValue>?] = values.map { UnsafePointer($0) }
        var outputs: [UnsafeMutablePointer<OrtValue>?] = [nil]

        try inputNames.withUnsafeMutableBufferPointer { namesBuffer in
            try inputValues.withUnsafeMutableBufferPointer { valuesBuffer in
                try outputs.withUnsafeMutableBufferPointer { outputsBuffer in
                    let status = api.pointee.Run(
                        session,
                        nil,
                        namesBuffer.baseAddress,
                        valuesBuffer.baseAddress,
                        names.count,
                        namesBuffer.baseAddress,
                        1,
                        outputsBuffer.baseAddress
                    )
                    try Self.check(status, api: api)
                }
            }
        }
        guard let output = outputs[0] else { throw RuntimeError.badOutput(graph.rawValue) }
        return [output]
    }

    // MARK: - Tensor

    private func makeValue(
        _ bytes: [UInt8],
        elementType: ONNXTensorElementDataType,
        shape: [Int64],
        keepAlive: inout [NSMutableData]
    ) throws -> UnsafeMutablePointer<OrtValue> {
        let holder = NSMutableData(bytes: bytes, length: bytes.count)
        var value: UnsafeMutablePointer<OrtValue>?
        let status = shape.withUnsafeBufferPointer { shapeBuffer in
            api.pointee.CreateTensorWithDataAsOrtValue(
                memoryInfo,
                holder.mutableBytes,
                holder.length,
                shapeBuffer.baseAddress,
                shape.count,
                elementType,
                &value
            )
        }
        try Self.check(status, api: api)
        guard let value else { throw RuntimeError.failure("CreateTensorWithDataAsOrtValue trả về con trỏ rỗng") }
        keepAlive.append(holder)
        return value
    }

    private func int64Value(_ values: [Int64], shape: [Int64], keepAlive: inout [NSMutableData]) throws -> UnsafeMutablePointer<OrtValue> {
        var bytes = [UInt8]()
        bytes.reserveCapacity(values.count * 8)
        for value in values {
            let bits = UInt64(bitPattern: value)
            for shift in stride(from: 0, through: 56, by: 8) {
                bytes.append(UInt8((bits >> UInt64(shift)) & 0xFF))
            }
        }
        return try makeValue(bytes, elementType: Self.tensorInt64, shape: shape, keepAlive: &keepAlive)
    }

    private func floatValue(_ values: [Float], shape: [Int64], keepAlive: inout [NSMutableData]) throws -> UnsafeMutablePointer<OrtValue> {
        var bytes = [UInt8]()
        bytes.reserveCapacity(values.count * 4)
        for value in values {
            let bits = value.bitPattern
            for shift in stride(from: 0, through: 24, by: 8) {
                bytes.append(UInt8((bits >> UInt32(shift)) & 0xFF))
            }
        }
        return try makeValue(bytes, elementType: Self.tensorFloat, shape: shape, keepAlive: &keepAlive)
    }

    /// Tensor **bool** — thứ mà lớp ObjC không tạo được, xem doc của type.
    private func boolValue(_ values: [UInt8], shape: [Int64], keepAlive: inout [NSMutableData]) throws -> UnsafeMutablePointer<OrtValue> {
        try makeValue(values, elementType: Self.tensorBool, shape: shape, keepAlive: &keepAlive)
    }

    // MARK: - Đọc output

    private func floats(
        from value: UnsafeMutablePointer<OrtValue>,
        graph: Graph,
        elementCount: Int? = nil
    ) throws -> [Float] {
        let count = try elementCount ?? self.elementCount(of: value)
        var raw: UnsafeMutableRawPointer?
        try Self.check(api.pointee.GetTensorMutableData(value, &raw), api: api)
        guard let raw, count > 0 else { return [] }
        // Output do ORT cấp phát nên căn chỉnh chuẩn — khác `Data` trong `VieNeuConfig` (đọc từng byte).
        let pointer = raw.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    private func elementCount(of value: UnsafeMutablePointer<OrtValue>) throws -> Int {
        var info: UnsafeMutablePointer<OrtTensorTypeAndShapeInfo>?
        try Self.check(api.pointee.GetTensorTypeAndShape(value, &info), api: api)
        guard let info else { throw RuntimeError.failure("GetTensorTypeAndShape trả về con trỏ rỗng") }
        defer { api.pointee.ReleaseTensorTypeAndShapeInfo(info) }

        var rank = 0
        try Self.check(api.pointee.GetDimensionsCount(info, &rank), api: api)
        guard rank > 0 else { return 0 }
        var dimensions = [Int64](repeating: 0, count: rank)
        try Self.check(api.pointee.GetDimensions(info, &dimensions, rank), api: api)
        return dimensions.reduce(1) { partial, dimension in partial * Int(max(1, dimension)) }
    }

    // MARK: - Hằng số enum của C API

    /// Lấy enum C theo **số** thay vì theo tên: cách Swift import một `typedef enum` của C khác nhau
    /// tuỳ hình dạng khai báo (enum có case, hay struct `RawRepresentable` có static member), nên tên
    /// case có thể là `OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING` hoặc `ORT_LOGGING_LEVEL_WARNING`.
    /// Số thì bất biến và luôn khớp header. Giá trị đều lấy từ `onnxruntime_c_api.h`.
    private static func ortEnum<T>(_ raw: Int32, as: T.Type) -> T {
        unsafeBitCast(raw, to: T.self)
    }

    /// `ORT_LOGGING_LEVEL_WARNING` = 2.
    private static let loggingWarning = ortEnum(2, as: OrtLoggingLevel.self)
    /// `OrtDeviceAllocator` = 0.
    private static let allocatorDevice = ortEnum(0, as: OrtAllocatorType.self)
    /// `OrtMemTypeDefault` = 0.
    private static let memoryTypeDefault = ortEnum(0, as: OrtMemType.self)
    /// `ORT_ENABLE_ALL` = 99.
    private static let graphOptimizationAll = ortEnum(99, as: GraphOptimizationLevel.self)
    /// `ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT` = 1.
    private static let tensorFloat = ortEnum(1, as: ONNXTensorElementDataType.self)
    /// `ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64` = 7.
    private static let tensorInt64 = ortEnum(7, as: ONNXTensorElementDataType.self)
    /// `ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL` = 9.
    private static let tensorBool = ortEnum(9, as: ONNXTensorElementDataType.self)

    private static func check(_ status: UnsafeMutablePointer<OrtStatus>?, api: UnsafePointer<OrtApi>) throws {
        guard let status else { return }
        let message = String(cString: api.pointee.GetErrorMessage(status))
        api.pointee.ReleaseStatus(status)
        throw RuntimeError.failure(message)
    }
}
