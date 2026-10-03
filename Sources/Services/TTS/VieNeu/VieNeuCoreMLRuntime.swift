import Foundation
import CoreML

/// Bộ máy suy luận **Core ML** cho VieNeu-TTS v3 Nano — nạp 8 gói `.mlmodelc` đã biên dịch và chạy
/// cùng đường ống 4 bước như `VieNeuONNXRuntime`, qua protocol `VieNeuInferenceBackend`.
///
/// ## Bẫy Core ML (ghi nhớ từ CI #6 và đo đạc pha 2)
/// - `ids` phải là **Int32** — Core ML khai INT32, ONNX khai int64. Truyền int64 là ném.
/// - `ctx_mask` phải là **Int32** — Core ML khai FLOAT32, ONNX khai bool; biến thể chạy được duy nhất
///   là `mask-int32` (đã đo trên máy). Truyền bool/uint8 là ném.
/// - `t` là tensor **[1]** (Core ML giữ nguyên shape ONNX, không collapse về scalar).
/// - **Tên tensor output Core ML KHÁC ONNX.** Khi nạp `.mlpackage` qua `coremltools`, tên output
///   được đặt lại theo node cuối: `log_s` → `log_seconds`, `velocity` → `v`, `pcm` → `wav`
///   (riêng `ctx` giữ nguyên). Đọc sai tên ⇒ `RuntimeError.missing` ⇒ tự test SNR −1 dB.
///   Xem `Docs/Plans/...phases-3-5.md` R1/G3. Luôn parse `model.mlmodel` để lấy tên chuẩn
///   thay vì đoán theo ONNX.
/// - Graph bị **đóng băng shape** ở bucket: `text_encoder`/`duration_predictor` ở `L = 200`, còn
///   `vector_estimator-T{n}`/`codec_decoder-T{n}` ở `T = n ∈ {64, 96, 234}`. Nên `effectiveFrames(_:)`
///   snap `frames` lên bucket gần nhất `≥ frames` (xem `VieNeuBucketSelector`), và mọi chunk truyền
///   vào hai graph phụ thuộc `T` luôn mang `frames` đã snap.
///
/// ## Padding lên L = 200
/// `text_encoder`/`duration_predictor`/`vector_estimator` Core ML đóng băng chiều `L = 200`
/// (`Scripts/coreml_bucket_package.py:LENGTH_FROZEN`), trong khi ONNX giữ `L` động. Một chunk thật
/// thường ngắn hơn 200 token, nên ở đây **đệm `ids`/`ctx_mask` lên 200**: token thật giữ nguyên, phần
/// đệm nhận `padID` (ids) và `0` (mask). `text_encoder` không có input mask nên đệm `padID` là cách
/// duy nhất để nó không đọc rác — chấp nhận rò rỉ chú ý nhẹ ở vị trí đệm (đo SNR 45–49 dB ở pha 2,
/// chất lượng thực tế đo trên máy, xem `Docs/Plans/...phases-3-5.md` R1/G2).
final class VieNeuCoreMLRuntime: VieNeuInferenceBackend {
    enum RuntimeError: LocalizedError {
        case missing(String)
        case notMultiArray(String)
        case load(String)
        case predict(String)

        var errorDescription: String? {
            switch self {
            case .missing(let name): return "Core ML: thiếu tensor '\(name)' trong output"
            case .notMultiArray(let name): return "Core ML: '\(name)' không phải MLMultiArray"
            case .load(let reason): return "Core ML: không nạp được model — \(reason)"
            case .predict(let reason): return "Core ML: dự đoán thất bại — \(reason)"
            }
        }
    }

    /// Định danh bộ máy (phần của `VieNeuInferenceBackend`).
    let backendID = "coreml"

    /// Chiều `L` đóng băng của `text_encoder`/`duration_predictor` — phải khớp
    /// `Scripts/coreml_bucket_package.py:LENGTH_FROZEN`.
    private static let frozenLength = 200

    private let store: VieNeuModelStore
    /// Giá trị `padID` (từ `config.json`) dùng để đệm `ids` lên `frozenLength`. `text_encoder` Core ML
    /// không nhận mask nên đệm đúng `padID` là bắt buộc (ORT không cần vì giữ `L` động).
    private let paddingID: Int64
    private let computeUnits: MLComputeUnits

    /// Cache các `MLModel` đã nạp, key theo tên gói. Giữ hết ≤ 383 MB (xem plan §6) — chưa quyết
    /// nạp/nhả theo bucket (U7), nên đơn giản là cache và tái dùng.
    private let lock = NSLock()
    private var models: [String: MLModel] = [:]

    init(store: VieNeuModelStore, paddingID: Int64, computeUnits: MLComputeUnits = .all) {
        self.store = store
        self.paddingID = paddingID
        self.computeUnits = computeUnits
    }

    // MARK: - Nạp MLModel theo nhu cầu

    private func model(named name: String) throws -> MLModel {
        lock.lock(); defer { lock.unlock() }
        if let cached = models[name] { return cached }
        let url = store.compiledURL(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RuntimeError.load("thiếu gói đã biên dịch \(name).mlmodelc")
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        do {
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            models[name] = loaded
            return loaded
        } catch {
            throw RuntimeError.load("\(name): \(error.localizedDescription)")
        }
    }

    // MARK: - Đóng gói MLMultiArray

    /// Copy một mảng `Float` phẳng vào `MLMultiArray` shape đã cho (Core ML lưu C-contiguous, khớp
    /// thứ tự phẳng hàng-major của ta).
    private func floatMultiArray(shape: [Int], _ values: [Float]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        let count = values.count
        values.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: count)
            memcpy(pointer, base, count * MemoryLayout<Float>.stride)
        }
        return array
    }

    /// Copy một mảng `Int32` phẳng vào `MLMultiArray` shape đã cho (dùng cho `ids`/`ctx_mask`).
    private func intMultiArray(shape: [Int], _ values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .int32)
        let count = values.count
        values.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: count)
            memcpy(pointer, base, count * MemoryLayout<Int32>.stride)
        }
        return array
    }

    /// `ids` (int64, chiều động) → `MLMultiArray` [1, 200] int32, đệm `padID` lên `frozenLength`.
    private func idsMultiArray(_ ids: [Int64]) -> MLMultiArray {
        let length = Self.frozenLength
        var buffer = [Int32](repeating: Int32(paddingID), count: length)
        for index in 0..<min(ids.count, length) {
            buffer[index] = Int32(ids[index])
        }
        return try! intMultiArray(shape: [1, length], buffer)
    }

    /// `mask` (uint8, chiều động) → `MLMultiArray` [1, 200] int32, đệm `0` cho phần chưa tới `frozenLength`.
    /// Dùng được cả cho nhánh vô điều kiện (`nullMask` = [1,1] ⇒ chỉ 2 vị trí đầu là 1).
    private func maskMultiArray(_ mask: [UInt8]) -> MLMultiArray {
        let length = Self.frozenLength
        var buffer = [Int32](repeating: 0, count: length)
        for index in 0..<min(mask.count, length) {
            buffer[index] = Int32(mask[index])
        }
        return try! intMultiArray(shape: [1, length], buffer)
    }

    /// `ctx` (float32 phẳng, [1, 200, styleDim]) → `MLMultiArray` [1, 200, styleDim].
    private func ctxMultiArray(_ context: [Float]) throws -> MLMultiArray {
        let styleDim = max(1, context.count / Self.frozenLength)
        return try floatMultiArray(shape: [1, Self.frozenLength, styleDim], context)
    }

    // MARK: - Dự đoán

    private func predict(named name: String, _ inputs: [String: MLMultiArray]) throws -> MLFeatureProvider {
        var dictionary: [String: MLFeatureValue] = [:]
        for (key, array) in inputs {
            dictionary[key] = MLFeatureValue(multiArray: array)
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: dictionary)
        do {
            return try model(named: name).prediction(from: provider)
        } catch {
            throw RuntimeError.predict("\(name): \(error.localizedDescription)")
        }
    }

    private func floats(from provider: MLFeatureProvider, name: String) throws -> [Float] {
        guard let feature = provider.featureValue(for: name) else { throw RuntimeError.missing(name) }
        guard let array = feature.multiArrayValue else { throw RuntimeError.notMultiArray(name) }
        let count = array.count
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    private func firstFloat(from provider: MLFeatureProvider, name: String) throws -> Float {
        guard let feature = provider.featureValue(for: name) else { throw RuntimeError.missing(name) }
        if let array = feature.multiArrayValue {
            return array[0].floatValue
        }
        return Float(feature.doubleValue)
    }

    // MARK: - Bốn bước của pipeline (VieNeuInferenceBackend)

    func textEncoder(
        ids: [Int64],
        style: [Float],
        styleRows: Int,
        styleColumns: Int
    ) throws -> (values: [Float], shape: [Int64]) {
        let output = try predict(
            named: "text_encoder",
            [
                "ids": idsMultiArray(ids),
                "style": try floatMultiArray(shape: [1, styleRows, styleColumns], style)
            ]
        )
        let ctx = try floats(from: output, name: "ctx")
        return (ctx, [1, Int64(Self.frozenLength), Int64(styleColumns)])
    }

    func durationPredictor(
        context: [Float],
        contextShape: [Int64],
        mask: [UInt8],
        speaker: [Float]
    ) throws -> Float {
        let output = try predict(
            named: "duration_predictor",
            [
                "ctx": try ctxMultiArray(context),
                "ctx_mask": maskMultiArray(mask),
                "spk": try floatMultiArray(shape: [1, 192], speaker)
            ]
        )
        return try firstFloat(from: output, name: "log_seconds")
    }

    func vectorEstimator(
        latent: [Float],
        time: Float,
        context: [Float],
        contextShape: [Int64],
        mask: [UInt8],
        speaker: [Float],
        style: [Float],
        styleRows: Int,
        styleColumns: Int,
        latentChannels: Int,
        frames: Int
    ) throws -> [Float] {
        let output = try predict(
            named: "vector_estimator" + VieNeuBucketSelector.packageSuffix(for: frames),
            [
                "x": try floatMultiArray(shape: [1, latentChannels, frames], latent),
                "t": try floatMultiArray(shape: [1], [time]),
                "ctx": try ctxMultiArray(context),
                "ctx_mask": maskMultiArray(mask),
                "spk": try floatMultiArray(shape: [1, 192], speaker),
                "style": try floatMultiArray(shape: [1, styleRows, styleColumns], style)
            ]
        )
        return try floats(from: output, name: "v")
    }

    func vectorEstimatorUnconditioned(
        latent: [Float],
        time: Float,
        nullContext: [Float],
        nullContextShape: [Int64],
        nullMask: [UInt8],
        nullSpeaker: [Float],
        nullStyle: [Float],
        styleRows: Int,
        styleColumns: Int,
        latentChannels: Int,
        frames: Int
    ) throws -> [Float] {
        let output = try predict(
            named: "vector_estimator" + VieNeuBucketSelector.packageSuffix(for: frames),
            [
                "x": try floatMultiArray(shape: [1, latentChannels, frames], latent),
                "t": try floatMultiArray(shape: [1], [time]),
                "ctx": try ctxMultiArray(nullContext),
                "ctx_mask": maskMultiArray(nullMask),
                "spk": try floatMultiArray(shape: [1, 192], nullSpeaker),
                "style": try floatMultiArray(shape: [1, styleRows, styleColumns], nullStyle)
            ]
        )
        return try floats(from: output, name: "v")
    }

    func codecDecoder(latent: [Float], latentChannels: Int, frames: Int) throws -> [Float] {
        let output = try predict(
            named: "codec_decoder" + VieNeuBucketSelector.packageSuffix(for: frames),
            ["x": try floatMultiArray(shape: [1, latentChannels, frames], latent)]
        )
        return try floats(from: output, name: "wav")
    }

    // MARK: - Snap bucket & churn

    /// Core ML đóng băng mỗi graph ở một bucket `T` cố định ⇒ snap `frames` lên bucket nhỏ nhất `≥ frames`.
    func effectiveFrames(_ frames: Int) -> Int {
        let target = max(VieNeuConfig.minFrames, frames)
        return VieNeuBucketSelector.bucketFrames.first { $0 >= target }
            ?? VieNeuBucketSelector.bucketFrames.last
            ?? target
    }

    func resetChurnCounters() {
        // Core ML không đo churn tensor.
    }

    var churnSnapshot: (Int64, Int64, Int64) {
        (0, 0, 0)
    }

    /// Tổng hợp một chunk qua Core ML — ủy quyền cho hàm tự do chung (cùng `VieNeuONNXRuntime`).
    func runChunk(
        ids: [Int64],
        preset: VieNeuVoiceCatalog.Preset,
        tuning: VieNeuSynthesisPolicy.Tuning,
        speed: Double,
        config: VieNeuConfig,
        nullContext: [Float],
        nullContextShape: [Int64],
        nullMask: [UInt8],
        timing: inout VieNeuTTSEngine.Timing
    ) throws -> [Float] {
        try vieNeuOrchestrateChunk(
            backend: self, ids: ids, preset: preset, tuning: tuning, speed: speed, config: config,
            nullContext: nullContext, nullContextShape: nullContextShape, nullMask: nullMask, timing: &timing
        )
    }
}
