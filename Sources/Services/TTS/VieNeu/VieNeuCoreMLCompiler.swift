import Foundation
import CoreML

/// Biên dịch các gói Core ML `.mlpackage` thành `.mlmodelc` để suy luận.
///
/// Chạy **sau khi tải xong** (có `ProgressView`), không lúc phát. `MLModel.compileModel(at:)` biên dịch
/// một `.mlpackage` thành `.mlmodelc` — với ~398 MB tổng, mất vài chục giây trên máy thật. Kết quả được
/// copy vào `CoreML/Compiled/<name>.mlmodelc`.
///
/// Idempotent: nếu `.mlmodelc` đã tồn tại thì bỏ qua (coi như đã biên dịch). Xoá đi rồi tải lại chỉ
/// biên dịch lại, **không** tải lại từ mạng.
enum VieNeuCoreMLCompiler {
    /// Biên dịch một gói. Trả `true` nếu thực sự biên dịch, `false` nếu đã có sẵn `.mlmodelc`.
    @discardableResult
    static func compile(packageName: String, store: VieNeuModelStore) throws -> Bool {
        let source = store.coreMLPackageURL(for: packageName)
        let destination = store.compiledURL(for: packageName)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else {
            throw CompileError.packageMissing(packageName)
        }
        guard !fileManager.fileExists(atPath: destination.path) else { return false }

        let compiled = try MLModel.compileModel(at: source)
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: compiled, to: destination)
        return true
    }

    /// Biên dịch tất cả 8 gói, báo tiến độ theo phần trăm (0…1).
    static func compileAll(store: VieNeuModelStore, progress: ((String, Double) -> Void)? = nil) throws {
        let names = VieNeuModelStore.coreMLPackageNames
        for (index, name) in names.enumerated() {
            progress?("Biên dịch \(name)…", Double(index) / Double(names.count))
            _ = try compile(packageName: name, store: store)
            progress?("Xong \(name)", Double(index + 1) / Double(names.count))
        }
        progress?("Biên dịch xong", 1.0)
    }

    enum CompileError: LocalizedError {
        case packageMissing(String)
        var errorDescription: String? {
            switch self {
            case .packageMissing(let name): return "Thiếu gói Core ML chưa biên dịch: \(name)"
            }
        }
    }
}
