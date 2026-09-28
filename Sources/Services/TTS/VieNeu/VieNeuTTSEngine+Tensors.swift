import Foundation
import OnnxRuntimeBindings

/// Phần tensor và đo RTF của `VieNeuTTSEngine`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Các thành viên dùng chéo file buộc phải hạ
/// từ `private` xuống `internal` (Swift giới hạn `private` theo file) — đúng tiền lệ đã ghi ở
/// `Docs/CodeGraph/09_dependency_rules.md:120`.
extension VieNeuTTSEngine {
    /// Một lần chạy `vector_estimator`. Dùng cho **cả hai** nhánh của CFG: nhánh có điều kiện
    /// (`ctx`/`mask`/`spk`/`style` thật) và nhánh vô điều kiện (`null*`).
    func velocity(
        runtime: Runtime,
        x: ORTValue,
        t: ORTValue,
        ctx: ORTValue,
        mask: ORTValue,
        spk: ORTValue,
        style: ORTValue
    ) throws -> [Float] {
        let outputs = try runtime.vectorEstimator.session.run(
            withInputs: ["x": x, "t": t, "ctx": ctx, "ctx_mask": mask, "spk": spk, "style": style],
            outputNames: [runtime.vectorEstimator.outputName],
            runOptions: nil
        )
        guard let value = outputs[runtime.vectorEstimator.outputName] else {
            throw EngineError.badOutput("vector_estimator")
        }
        return try floats(from: value)
    }

    // MARK: - Thích nghi chất lượng

    /// Cập nhật bộ đếm RTF và đổi chế độ nếu đủ mẫu liên tiếp. Ngưỡng nằm ở `VieNeuSynthesisPolicy`.
    func updateMode(synthesisMs: Double, pcmDuration: Double) {
        guard pcmDuration > 0 else { return }
        let rtf = (synthesisMs / 1_000) / pcmDuration
        if rtf >= VieNeuSynthesisPolicy.downshiftRTF {
            consecutiveSlow += 1
            consecutiveFast = 0
        } else if rtf <= VieNeuSynthesisPolicy.upshiftRTF {
            consecutiveFast += 1
            consecutiveSlow = 0
        } else {
            consecutiveSlow = 0
            consecutiveFast = 0
        }
        if let next = VieNeuSynthesisPolicy.nextMode(
            current: mode,
            lastRTF: rtf,
            consecutiveSlow: consecutiveSlow,
            consecutiveFast: consecutiveFast
        ), next != mode {
            mode = next
            consecutiveSlow = 0
            consecutiveFast = 0
            AppLogger.shared.log("🎙️ [VieNeu] Đổi chế độ sang \(next.rawValue) (RTF=\(String(format: "%.2f", rtf)))")
        }
    }

    /// Phoneme lạ bị **bỏ qua** im lặng ở tầng mã hoá (đúng hành vi bản tham chiếu), nên đây là chỗ duy
    /// nhất nói ra rằng chuyện đó đã xảy ra. Chỉ log một lần cho cả vòng đời engine để không ngập log.
    func noteDroppedScalars(_ dropped: Int, total: Int) {
        guard dropped > 0, !droppedScalarWarningShown else { return }
        droppedScalarWarningShown = true
        AppLogger.shared.log("⚠️ [VieNeu] Bỏ qua \(dropped) phoneme không có trong vocab (tổng \(total) id)")
    }

    // MARK: - Tensor

    /// Đọc `ORTValue` float32 thành `[Float]`.
    ///
    /// Đọc **từng byte** chứ không `withMemoryRebound`: `Data` không bảo đảm căn chỉnh 4 byte, và rebind
    /// một con trỏ lệch căn chỉnh là hành vi không xác định — repo cũ đã crash thật ở đúng dạng lỗi này
    /// (`c838327 Fix memory alignment load crashes`). Chi phí chấp nhận được: mảng lớn nhất ở đây là
    /// latent 144 × T với T ≤ ~235 frame.
    func floats(from value: ORTValue) throws -> [Float] {
        let data = try value.tensorData() as Data
        let count = data.count / MemoryLayout<Float>.size
        var values = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let offset = index * 4
            let bits = UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
                | (UInt32(data[offset + 3]) << 24)
            values[index] = Float(bitPattern: bits)
        }
        return values
    }

    func int64Value(_ values: [Int64], shape: [NSNumber], keepAlive: inout [NSMutableData]) throws -> ORTValue {
        var bytes = [UInt8]()
        bytes.reserveCapacity(values.count * 8)
        for value in values {
            let bits = UInt64(bitPattern: value)
            for shift in stride(from: 0, through: 56, by: 8) {
                bytes.append(UInt8((bits >> UInt64(shift)) & 0xFF))
            }
        }
        return try makeValue(bytes, elementType: .int64, shape: shape, keepAlive: &keepAlive)
    }

    func floatValue(_ tensor: FloatTensor, keepAlive: inout [NSMutableData]) throws -> ORTValue {
        var bytes = [UInt8]()
        bytes.reserveCapacity(tensor.values.count * 4)
        for value in tensor.values {
            let bits = value.bitPattern
            for shift in stride(from: 0, through: 24, by: 8) {
                bytes.append(UInt8((bits >> UInt32(shift)) & 0xFF))
            }
        }
        return try makeValue(bytes, elementType: .float, shape: tensor.shape, keepAlive: &keepAlive)
    }

    /// `ctx_mask` là `tensor(bool)` — bản tham chiếu truyền thẳng `ids != pad` (numpy bool) vào
    /// `run(...)`, và ONNX Runtime kiểm dtype rất gắt nên model chỉ có thể khai `bool`.
    func boolValue(_ values: [UInt8], shape: [NSNumber], keepAlive: inout [NSMutableData]) throws -> ORTValue {
        try makeValue(values, elementType: .bool, shape: shape, keepAlive: &keepAlive)
    }

    func makeValue(
        _ bytes: [UInt8],
        elementType: ORTTensorElementDataType,
        shape: [NSNumber],
        keepAlive: inout [NSMutableData]
    ) throws -> ORTValue {
        let holder = NSMutableData(bytes: bytes, length: bytes.count)
        // `ORTValue` **không** giữ buffer: `NSMutableData` phải sống tới hết lượt `run`. Giữ nó trong
        // `keepAlive` của caller là cách duy nhất để không phải dựa vào hành vi chưa hứa của ORT —
        // `ONNXPiperEngine` cũng làm đúng vậy bằng các biến `_ = inputNSMutableData`.
        keepAlive.append(holder)
        return try ORTValue(tensorData: holder, elementType: elementType, shape: shape)
    }
}
