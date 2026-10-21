import Foundation
import JavaScriptCore

/// Điểm vào duy nhất từ JS: `__lgNative(lệnh, đối-số-JSON)`. Lỗi của hàm native được ném lại vào JS thành `Error`
/// (script `try/catch` được); bị huỷ thì ném lỗi JS và phiên ném `CancellationError` khi đoạn JS trả về.
extension LegadoJSRuntime {
    func dispatchNative(_ command: String, _ argumentsJSON: String) -> String {
        let arguments = LegadoJSArguments(json: argumentsJSON)
        do {
            guard let session else { throw CancellationError() }
            try session.checkCancellation()
            if let output = try nativeRule(command, arguments, session) { return output }
            if let output = try nativeNetwork(command, arguments, session) { return output }
            if let output = try nativeStorage(command, arguments, session) { return output }
            if let output = try nativeCrypto(command, arguments) { return output }
            if let output = try nativeText(command, arguments, session) { return output }
            if let output = try nativeJsoup(command, arguments) { return output }
            if let output = try nativeLogin(command, arguments, session) { return output }
            if let output = try nativeExplore(command, arguments, session) { return output }
            if let output = try nativeTail(command, arguments, session) { return output }
            if let output = try nativeFiles(command, arguments, session) { return output }
            if let output = try nativeAsymmetric(command, arguments) { return output }
            throw LegadoJSNativeError("Lệnh bridge không tồn tại: \(command)")
        } catch is CancellationError {
            raise("Đã huỷ tác vụ")
        } catch let error as LegadoJSNativeError {
            raise(error.message)
        } catch let error as LegadoEngineError {
            raise(error.localizedDescription)
        } catch {
            raise("\(command): \(error.localizedDescription)")
        }
        return ""
    }

    /// Chuỗi JSON của một giá trị (để JS `JSON.parse`).
    static func json(_ value: LegadoEngineJSON) -> String {
        value.compactText
    }

    static func jsonArray(_ values: [String]) -> String {
        LegadoEngineJSON.strings(values).compactText
    }
}
