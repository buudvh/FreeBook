import Foundation

/// URL `data:` của nguồn Legado (spec §13.1): `data:[<mime>][;base64],<payload>[,{option}]`.
///
/// Không gửi mạng, không chạy `loginCheckJs`. Byte = base64 của `payload` (nhận bảng chữ URL-safe, thiếu `=`) hoặc
/// percent-decode khi không có `;base64`. **Thân phản hồi = chuỗi hex chữ thường** của byte (nguồn đọc bằng
/// `java.hexDecodeToString(result)`, U22 vẫn mở); URL cuối = nguyên chuỗi `data:` gồm khối option (nguồn kiểm
/// `baseUrl.startsWith("data:")` và tự tách option từ `baseUrl`).
enum LegadoDataURL {
    struct Decoded {
        /// Phần mime (có thể rỗng hoặc là nhãn tự đặt như `vipContent`).
        var mime: String
        var bytes: Data
    }

    static func isDataURL(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("data:")
    }

    /// `nil` khi không phải URL `data:` hoặc thiếu dấu `,` ngăn phần đầu và dữ liệu.
    static func decode(_ text: String) -> Decoded? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isDataURL(trimmed) else { return nil }
        let withoutOption = LegadoURLResolver.splitOption(trimmed).url
        let afterScheme = withoutOption.dropFirst("data:".count)
        guard let comma = afterScheme.firstIndex(of: ",") else { return nil }
        let header = String(afterScheme[..<comma])
        let payload = String(afterScheme[afterScheme.index(after: comma)...])
        let parameters = header.components(separatedBy: ";")
        let isBase64 = parameters.dropFirst().contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == "base64" }
        let mime = parameters.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let bytes: Data
        if isBase64 {
            bytes = LegadoJSRuntime.base64Decode(payload, flags: nil)
        } else {
            bytes = Data((payload.removingPercentEncoding ?? payload).utf8)
        }
        return Decoded(mime: mime, bytes: bytes)
    }

    /// Phản hồi giả của một request `data:`.
    static func response(for request: LegadoHTTPRequest) -> LegadoHTTPResponse? {
        guard let decoded = decode(request.url) else { return nil }
        let hex = LegadoJSRuntime.hex(decoded.bytes)
        return LegadoHTTPResponse(requestURL: request.url, finalURL: request.url, statusCode: 200, headers: [:],
                                  cookies: [:], body: hex, data: decoded.bytes)
    }
}
