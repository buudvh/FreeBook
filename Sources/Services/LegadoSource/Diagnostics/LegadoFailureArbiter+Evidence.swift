import Foundation

/// Dựng `Evidence` cho bộ phân xử từ lỗi của bước + run log **của chính bước đó** — một bộ chuyển cho cả bộ chạy hàng
/// loạt lẫn màn Gỡ lỗi từng bước.
extension LegadoFailureArbiter {
    /// Bằng chứng của một bước hỏng. `log` là log riêng của bước (vết request, chẩn đoán, đầu dò bộ chọn).
    static func evidence(
        error: ErrorKind,
        isSearchStep: Bool,
        isFirstStep: Bool,
        log: LegadoRunLog?,
        hasLoginUrl: Bool
    ) -> Evidence {
        let requests = (log?.requests ?? []).map { record in
            Request(statusCode: record.statusCode, byteCount: record.byteCount, body: record.bodySnippet,
                    errorMessage: record.errorMessage)
        }
        return Evidence(
            error: error,
            isSearchStep: isSearchStep,
            isFirstStep: isFirstStep,
            requests: requests,
            probe: log?.probes.last,
            hasLoginUrl: hasLoginUrl,
            diagnostics: (log?.entries ?? []).map { $0.message }
        )
    }

    /// Quy lỗi bất kỳ của một bước (engine, luồng, bộ chạy) về `ErrorKind`. Không dùng `"\(error)"` (case HTTP của
    /// engine mang thân trang).
    static func errorKind(of error: Error) -> ErrorKind {
        if let exceeded = error as? LegadoCorpusDeadline.Exceeded {
            return .stepDeadline(exceeded.seconds)
        }
        if let failure = error as? LegadoCorpusErrorClassifier.StepFailure {
            if failure.isSourceDefect { return .sourceDefect(failure.message) }
            switch failure.failureClass {
            case .noMatch: return .noMatch(failure.message)
            case .invalidSource: return .invalidSource(failure.message)
            case .unsupportedSyntax: return .unsupported(failure.message)
            case .timeout: return .timeout
            case .network: return .network(failure.message)
            case .javaScript: return .javaScript(failure.message)
            case .http: return httpCode(in: failure.message).map { ErrorKind.http($0) } ?? .other(failure.message)
            default: return .other(failure.message)
            }
        }
        if let engine = error as? LegadoEngineError {
            return engineKind(engine)
        }
        if let runtime = error as? LegadoRuntimeError {
            switch runtime {
            case .unsupportedKind, .unsupportedScript:
                return .unsupported(runtime.localizedDescription)
            case .missingRule:
                return .sourceDefect(runtime.localizedDescription)
            case .comicWithoutImages:
                // Không kèm đoạn chữ của trang (có thể dài, là nội dung trang).
                return .noMatch("Chương truyện tranh không có ảnh nào")
            case .noPlayableSource:
                return .noMatch(runtime.localizedDescription)
            default:
                return .invalidSource(runtime.localizedDescription)
            }
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut ? .timeout : .network(urlError.localizedDescription)
        }
        if error is LegadoSourceError {
            return .invalidSource(error.localizedDescription)
        }
        let text = error.localizedDescription
        return text.hasPrefix(LegadoCorpusErrorClassifier.unsupportedPrefix) ? .unsupported(text) : .other(text)
    }

    /// Mã trong "… HTTP 403 …" (thông điệp do bộ chạy tự dựng).
    private static func httpCode(in message: String) -> Int? {
        guard let range = message.range(of: #"HTTP (\d{3})"#, options: .regularExpression) else { return nil }
        return Int(message[range].dropFirst(5))
    }

    private static func engineKind(_ error: LegadoEngineError) -> ErrorKind {
        switch error {
        case .unsupportedSyntax(let what):
            return .unsupported(what)
        case .httpStatus(let code, _, _):
            return .http(code)
        case .timeout:
            return .timeout
        case .network(_, let message):
            return .network(message)
        case .javaScript(let message):
            // Stub JS ném "Chưa hỗ trợ …" từ trong script — cùng cách bộ phân loại lỗi coi là cú pháp chưa hỗ trợ.
            return message.contains(LegadoCorpusErrorClassifier.unsupportedPrefix) ? .unsupported(message) : .javaScript(message)
        case .noMatch(let what):
            return .noMatch(what)
        case .missingBaseURL(let url):
            return .sourceDefect("Nguồn không có URL gốc để ghép " + url)
        default:
            return .invalidSource(error.localizedDescription)
        }
    }
}
