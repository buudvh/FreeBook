import Foundation
import JavaScriptCore

extension JSExecutor {
    public func callAsync(functionName: String, arguments: [Any]) async throws -> JSValue {
        try Task.checkCancellation()
        beginExecution()

        guard let function = context.objectForKeyedSubscript(functionName) else {
            throw NSError(domain: "JSExecutor", code: -404, userInfo: [NSLocalizedDescriptionKey: "JS Function '\(functionName)' not found"])
        }

        let result: JSValue = try await withTaskCancellationHandler {
            guard let result = function.call(withArguments: arguments) else {
                if let exception = context.exception {
                    let desc = exception.toString() ?? "JS Execution Exception"
                    context.exception = nil
                    throw NSError(domain: "JSExecutor", code: -502, userInfo: [NSLocalizedDescriptionKey: "JS Call error: \(desc)"])
                }
                throw NSError(domain: "JSExecutor", code: -500, userInfo: [NSLocalizedDescriptionKey: "JS execution returned null"])
            }
            return result
        } onCancel: {
            self.cancelCurrentExecution()
        }

        if let exception = context.exception {
            let desc = exception.toString() ?? "JS Execution Exception"
            context.exception = nil
            throw NSError(domain: "JSExecutor", code: -502, userInfo: [NSLocalizedDescriptionKey: "JS Call error: \(desc)"])
        }

        guard let thenFunc = result.objectForKeyedSubscript("then"),
              !thenFunc.isUndefined,
              thenFunc.isObject else {
            try Task.checkCancellation()
            return result
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let onResolve: @convention(block) (JSValue) -> Void = { value in
                    continuation.resume(returning: value)
                }

                let onReject: @convention(block) (JSValue) -> Void = { error in
                    let desc = error.toString() ?? "JS Promise rejected"
                    continuation.resume(throwing: NSError(domain: "JSExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: desc]))
                }

                result.invokeMethod("then", withArguments: [
                    JSValue(object: onResolve, in: self.context) as Any,
                    JSValue(object: onReject, in: self.context) as Any
                ])
            }
        } onCancel: {
            self.cancelCurrentExecution()
        }
    }

    public func runAsync(scriptContent: String, functionName: String, arguments: [Any]) async throws -> JSValue {
        try prepareScript(scriptContent)
        return try await callAsync(functionName: functionName, arguments: arguments)
    }
}

internal func makeReadyResponse(
    ready: Bool,
    failed: Bool,
    reason: String,
    chars: Int = 0,
    encoded: Int = 0,
    timedOut: Bool = false,
    cancelled: Bool = false
) -> String {
    let dict: [String: Any] = [
        "ready": ready,
        "failed": failed,
        "reason": reason,
        "chars": chars,
        "encoded": encoded,
        "timedOut": timedOut,
        "cancelled": cancelled
    ]
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
       let str = String(data: data, encoding: .utf8) {
        return str
    }
    return "{\"ready\":false,\"failed\":true,\"reason\":\"JSON serialization error\",\"timedOut\":false,\"cancelled\":false}"
}
