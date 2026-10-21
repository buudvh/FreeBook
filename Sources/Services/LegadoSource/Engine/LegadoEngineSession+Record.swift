import Foundation

/// Ghi vết request cho màn Gỡ lỗi từng bước (`LegadoEngineDiagnostics.requests`). Mọi lối gửi request của phiên
/// (`perform`, `loadInWebView`) đi qua đây, kể cả khi lỗi; huỷ thì không ghi.
extension LegadoEngineSession {
    func recordingRequest(_ request: LegadoHTTPRequest,
                          _ body: () throws -> LegadoHTTPResponse) throws -> LegadoHTTPResponse {
        let started = Date()
        do {
            let response = try body()
            diagnostics.recordRequest(Self.requestRecord(request, response: response, started: started, error: nil))
            return response
        } catch {
            if !(error is CancellationError), !cancellation.isCancelled {
                diagnostics.recordRequest(Self.requestRecord(request, response: nil, started: started, error: error))
            }
            throw error
        }
    }

    static func requestRecord(_ request: LegadoHTTPRequest, response: LegadoHTTPResponse?, started: Date,
                              error: Error?) -> LegadoEngineRequestRecord {
        let elapsed = Date().timeIntervalSince(started) * 1000
        let durationMs = elapsed.isFinite ? Int(max(0, min(elapsed, 86_400_000))) : 0
        let method = request.isDataURL ? "DATA" : request.method
        let charset: String?
        if let response {
            charset = LegadoResponseDecoder.charset(fromContentType: response.header("Content-Type")) ?? request.charset
        } else {
            charset = request.charset
        }
        return LegadoEngineRequestRecord(
            method: method,
            url: request.isDataURL ? String(request.url.prefix(200)) : request.url,
            finalUrl: response.map { $0.isDataResponse ? String($0.finalURL.prefix(200)) : $0.finalURL } ?? request.url,
            statusCode: response?.statusCode,
            charset: charset,
            byteCount: response?.data.count ?? 0,
            durationMs: durationMs,
            viaWebView: request.useWebView,
            bodySnippet: LegadoEngineRequestRecord.snippet(response?.body ?? ""),
            errorMessage: error.map { $0.localizedDescription }
        )
    }
}

extension LegadoHTTPResponse {
    /// Phản hồi giả của URL `data:` (không có request mạng thật).
    var isDataResponse: Bool {
        requestURL.lowercased().hasPrefix("data:")
    }
}
