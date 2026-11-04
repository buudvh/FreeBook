import Foundation

/// Trang lỗi HTTP của các bước chính (spec §4.6): tìm, khám phá, thông tin sách, mục lục, nội dung (kể cả trang sau).
/// Chỉ **HTTP 404** không ném ngay — thân vẫn đi qua rule (阅友: `chapterUrl` là id trần nên trả 404, nhưng rule nội dung
/// là JS tự gửi POST có chữ ký). Mã ≥ 400 khác (403/429/503 thử thách Cloudflare, captcha…) vẫn ném ngay như cũ: rule mở
/// đầu bằng JS trên `result` sẽ biến trang chặn thành "nội dung" rồi bị lưu vào bin, và nút "Mở link lỗi" / verdict cần
/// người dùng chỉ hiện khi có lỗi HTTP. Bước ra **rỗng** trên trang 404 (0 sách / không có `name` / 0 chương / nội dung
/// rỗng), hoặc rule ném lỗi trên thân trang đó ⇒ ném lại lỗi HTTP gốc, **trước** mọi lỗi "rỗng"/lỗi JS khác, để chẩn
/// đoán và bộ kiểm tra nguồn vẫn thấy "HTTP 404" như trước. Request từ JS (`java.ajax`/`connect`…) không đi đường này
/// (vốn đã nhận thân bất kể mã).
extension LegadoSourceRuntime {
    /// Tải trang của bước chính: `LegadoEngineSession.fetch` với `allowHTTPError` (`loginCheckJs` vẫn chạy như cũ).
    static func fetchPage(
        _ session: LegadoEngineSession,
        _ urlRule: String,
        key: String? = nil,
        page: Int? = nil,
        webJs: String? = nil,
        sourceRegex: String? = nil
    ) throws -> LegadoHTTPResponse {
        let response = try session.fetch(urlRule, key: key, page: page, webJs: webJs, sourceRegex: sourceRegex,
                                          allowHTTPError: true)
        if isErrorPage(response) {
            session.diagnostics.record(.info, "HTTP \(response.statusCode) \(response.finalURL) — vẫn chạy rule trên thân trang")
        } else if response.statusCode >= 400 {
            throw httpStatusError(session, response)
        }
        return response
    }

    /// Trang lỗi HTTP được đưa cho rule: chỉ 404 (mã ≥ 400 khác đã ném ở `fetchPage`).
    static func isErrorPage(_ response: LegadoHTTPResponse?) -> Bool {
        response?.statusCode == 404
    }

    /// Lỗi HTTP gốc của trang lỗi — đúng dạng `perform` của engine ném (thân giữ trong lỗi) — kèm dòng chẩn đoán `.http`
    /// như trước. Chỉ gọi ngay trước `throw`.
    static func httpStatusError(_ session: LegadoEngineSession, _ response: LegadoHTTPResponse) -> LegadoEngineError {
        session.diagnostics.record(.http, "HTTP \(response.statusCode) \(response.finalURL)")
        return .httpStatus(code: response.statusCode, url: response.finalURL, body: String(response.body.prefix(4000)))
    }

    /// Chạy phần rule của một bước trên `response`. Trang < 400 ⇒ chạy nguyên như cũ. Trang lỗi: rule ném (trừ huỷ) hoặc
    /// kết quả `isEmpty` ⇒ ném lỗi HTTP gốc.
    static func evaluatePage<T>(
        _ session: LegadoEngineSession,
        _ response: LegadoHTTPResponse,
        isEmpty: (T) -> Bool,
        _ body: () throws -> T
    ) throws -> T {
        guard isErrorPage(response) else { return try body() }
        let value: T
        do {
            value = try body()
        } catch {
            if error is CancellationError || session.cancellation.isCancelled { throw error }
            throw httpStatusError(session, response)
        }
        if isEmpty(value) { throw httpStatusError(session, response) }
        return value
    }
}
