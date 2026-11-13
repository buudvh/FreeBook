import CoreML
import Foundation

/// Nạp **Core ML gốc** (`MLModel(contentsOf:)`, `.cpuOnly`) bản `compiled_model.mlmodelc` mà ORT để trong cache, rồi chạy
/// **một lượt dự đoán với input toàn 0** ngay sau đó — cho phép đo P2a (`VieNeuCoreMLLoadWorker`).
///
/// Đo cả lượt dự đoán đầu vì Core ML có thể dời một phần việc chuẩn bị sang lần `prediction` đầu tiên: chỉ đo phần nạp
/// thì Core ML gốc có thể trông như 0,5 s so với 20 s của ORT trong khi tổng thời gian tới lúc chạy được vẫn vậy
/// (lượt đo tự động 1.3.911 cũng thấy đoạn đầu chậm 3,6 s so với trung vị 1,04 s). Giá trị input không quan trọng cho
/// thời gian; điền 0 cho khỏi rác.
enum VieNeuCoreMLNativeLoad {
    struct Result: Sendable {
        let load: VieNeuCoreMLLoadWorker.Measure
        /// `nil` = không chạy được lượt dự đoán (input không phải multiarray) — xem `note`.
        let firstPrediction: VieNeuCoreMLLoadWorker.Measure?
        let note: String

        var text: String {
            guard let firstPrediction else { return "nạp \(load.text)\(note)" }
            let total = (load.wallMs + firstPrediction.wallMs) / 1_000
            return "nạp \(load.text) · lượt đoán đầu \(firstPrediction.text) · cộng \(String(format: "%.2f", total)) s\(note)"
        }

        /// "0.4+1.2" cho dòng tóm tắt.
        var shortText: String {
            guard let firstPrediction else { return load.seconds }
            return "\(load.seconds)+\(firstPrediction.seconds)"
        }
    }

    /// Nạp mọi model (codec có 2 partition ⇒ 2 model) rồi dự đoán một lượt mỗi model. Model sống tới sau mốc đo.
    static func measure(_ urls: [URL]) throws -> Result {
        try autoreleasepool {
            let loadStart = VieNeuCoreMLLoadWorker.Mark.now()
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            let models = try urls.map { try MLModel(contentsOf: $0, configuration: configuration) }
            let load = loadStart.measure()

            let predictStart = VieNeuCoreMLLoadWorker.Mark.now()
            var skipped: [String] = []
            for model in models {
                guard let provider = try zeroInputs(for: model, skipped: &skipped) else { continue }
                _ = try model.prediction(from: provider)
            }
            let prediction = predictStart.measure()
            withExtendedLifetime(models) {}
            let note = skipped.isEmpty ? "" : " · không dự đoán được: input \(skipped.joined(separator: ", ")) không phải multiarray"
            return Result(load: load, firstPrediction: skipped.isEmpty ? prediction : nil, note: note)
        }
    }

    /// Input toàn 0 theo `multiArrayConstraint` của từng input; có input không phải multiarray ⇒ `nil` (ghi tên vào
    /// `skipped`).
    private static func zeroInputs(for model: MLModel, skipped: inout [String]) throws -> MLDictionaryFeatureProvider? {
        var features: [String: MLFeatureValue] = [:]
        for (name, description) in model.modelDescription.inputDescriptionsByName {
            guard let constraint = description.multiArrayConstraint else {
                skipped.append(name)
                return nil
            }
            let array = try MLMultiArray(shape: constraint.shape, dataType: constraint.dataType)
            array.withUnsafeMutableBytes { buffer, _ in
                if let base = buffer.baseAddress { memset(base, 0, buffer.count) }
            }
            features[name] = MLFeatureValue(multiArray: array)
        }
        return try MLDictionaryFeatureProvider(dictionary: features)
    }
}
