import Foundation
import JavaScriptCore

extension JSExecutor {
    public func callAsync(functionName: String, arguments: [Any]) async throws -> JSValue {
        try Task.checkCancellation()
        beginExecution()

        let runner = context.objectForKeyedSubscript("__safe_run_extension")
        let result: JSValue = try await withTaskCancellationHandler {
            if let runner = runner, !runner.isUndefined {
                return runner.call(withArguments: [functionName, arguments]) ?? JSValue(nullIn: self.context)
            } else {
                guard let function = self.context.objectForKeyedSubscript(functionName), !function.isUndefined else {
                    throw NSError(domain: "JSExecutor", code: -404, userInfo: [NSLocalizedDescriptionKey: "JS Function '\(functionName)' not found"])
                }
                return function.call(withArguments: arguments) ?? JSValue(nullIn: self.context)
            }
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


