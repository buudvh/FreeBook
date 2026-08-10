import Foundation
import JavaScriptCore

/// Owns one JavaScriptCore context for the active TTS extension. All calls are
/// serialized by the actor and by RemoteTTSSynthesisCoordinator. The runtime
/// is rebuilt when the script/config identity changes or execution fails.
internal actor ExtTTSRuntime {
    private struct Identity: Equatable, Sendable {
        let localPath: String
        let downloadUrl: String
        let scriptContent: String
        let configurationData: Data
    }

    private var identity: Identity?
    private var executor: JSExecutor?

    internal func generate(
        localPath: String,
        downloadUrl: String,
        scriptContent: String,
        configurationData: Data,
        text: String,
        voice: String,
        extensionName: String
    ) async throws -> String {
        let requestedIdentity = Identity(
            localPath: localPath,
            downloadUrl: downloadUrl,
            scriptContent: scriptContent,
            configurationData: configurationData
        )

        let activeExecutor: JSExecutor
        if identity == requestedIdentity, let executor {
            activeExecutor = executor
        } else {
            executor?.cancelCurrentExecution()

            let newExecutor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
            let configurationObject = try JSONSerialization.jsonObject(with: configurationData)
            if let globals = configurationObject as? [String: Any] {
                newExecutor.injectGlobals(globals)
            }
            try newExecutor.prepareScript(scriptContent)

            identity = requestedIdentity
            executor = newExecutor
            activeExecutor = newExecutor
        }

        do {
            let value = try await activeExecutor.callAsync(
                functionName: "execute",
                arguments: [text, voice]
            )
            try Task.checkCancellation()
            return try extractAudioBase64(from: value, extensionName: extensionName)
        } catch {
            if identity == requestedIdentity {
                activeExecutor.cancelCurrentExecution()
                identity = nil
                executor = nil
            }
            throw error
        }
    }

    internal func reset() {
        executor?.cancelCurrentExecution()
        executor = nil
        identity = nil
    }

    private func extractAudioBase64(from value: JSValue, extensionName: String) throws -> String {
        if value.isObject {
            if let successValue = value.objectForKeyedSubscript("success"),
               !successValue.isUndefined,
               !successValue.isNull {
                guard successValue.toBool() else {
                    let messageValue = value.objectForKeyedSubscript("message")
                    let message = (messageValue != nil && !messageValue!.isUndefined && !messageValue!.isNull)
                        ? messageValue!.toString() ?? "Lỗi từ nguồn truyện"
                        : "Lỗi từ nguồn truyện"
                    AppLogger.shared.log("❌ [\(extensionName) - tts] Response.error: \(message)")
                    throw ExtensionManagerError.sourceResponse(message: message)
                }

                if let dataValue = value.objectForKeyedSubscript("data"),
                   !dataValue.isUndefined,
                   !dataValue.isNull {
                    return dataValue.toString() ?? ""
                }
            }

            if let errorValue = value.objectForKeyedSubscript("error"),
               !errorValue.isUndefined,
               !errorValue.isNull,
               let message = errorValue.toString(),
               !message.isEmpty {
                AppLogger.shared.log("❌ [\(extensionName) - tts] Response.error (field): \(message)")
                throw ExtensionManagerError.sourceResponse(message: message)
            }
        }

        return value.toString() ?? ""
    }
}
