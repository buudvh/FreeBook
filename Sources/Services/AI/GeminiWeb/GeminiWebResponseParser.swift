import Foundation

/// Đọc envelope `["wrb.fr", <rpcid|null>, "<inner JSON>", …]` của hai endpoint. Thuần.
///
/// Vị trí field chép theo `gemini-webapi`: lỗi server `part[5][2][0][1][0]`; inner `[1][0]`=cid,
/// `[1][1]`=rid, `[4]`=ứng viên — mỗi ứng viên `[0]`=rcid, `[1][0]`=**text tích luỹ** (không phải
/// delta), `[8][0]==2`=đã xong. `GetUserStatus`: `[14]`=trạng thái tài khoản, `[15]`=model,
/// `[16]`/`[17]`=cờ tier/capability. App không giữ cid/rid vì mỗi lượt là temporary chat mới.
enum GeminiWebResponseParser {
    struct GenerateFrame: Sendable, Equatable {
        /// Toàn bộ text trả lời tính tới frame này.
        let text: String
        let completed: Bool
    }

    struct UserStatus: Sendable, Equatable {
        let statusCode: Int
        let models: [GeminiWebModel]
    }

    /// Link giữ chỗ Google chèn vào text ở vị trí đính kèm/ảnh — không có nghĩa với người đọc.
    private static let artifactPattern = try! NSRegularExpression(
        pattern: #"https?://googleusercontent\.com/(?:\w+/)+\d+\n*"#
    )
    private static let cardContentPattern = #"^https?://googleusercontent\.com/card_content/\d+"#

    // MARK: - StreamGenerate

    /// `nil` khi envelope không mang ứng viên (frame trạng thái, metadata). Ném lỗi khi có mã lỗi server.
    static func parseGenerateEnvelope(_ part: Any) throws -> GenerateFrame? {
        if let code = intValue(nested(part, [5, 2, 0, 1, 0])), code != 0 {
            throw GeminiWebError.fromServerCode(code)
        }
        guard let innerString = nested(part, [2]) as? String,
              let inner = parseJSON(innerString),
              let candidates = nested(inner, [4]) as? [Any] else {
            return nil
        }
        // Ứng viên đầu tiên có rcid — khớp cách thư viện tham chiếu bỏ qua ứng viên rỗng.
        guard let candidate = candidates.first(where: { !((nested($0, [0]) as? String) ?? "").isEmpty }) else {
            return nil
        }

        var text = (nested(candidate, [1, 0]) as? String) ?? ""
        if text.range(of: cardContentPattern, options: .regularExpression) != nil,
           let alternative = nested(candidate, [22, 0]) as? String {
            text = alternative
        }
        text = stripArtifacts(text)
        let completed = intValue(nested(candidate, [8, 0])) == 2
        return GenerateFrame(text: text, completed: completed)
    }

    // MARK: - GetUserStatus

    static func parseUserStatus(envelopes: [Any]) throws -> UserStatus {
        for part in envelopes {
            guard (nested(part, [1]) as? String) == GeminiWebRequestBuilder.userStatusRPC else { continue }
            // Mã 7 = permission denied: cookie không còn hiệu lực.
            if intValue(nested(part, [5, 0])) == 7 { throw GeminiWebError.notSignedIn }
            guard let bodyString = nested(part, [2]) as? String, let body = parseJSON(bodyString) else { continue }

            let status = intValue(nested(body, [14])) ?? 1000
            let tierFlags = intArray(nested(body, [16]))
            let capabilityFlags = intArray(nested(body, [17]))
            let capacity = GeminiWebModel.computeCapacity(tierFlags: tierFlags, capabilityFlags: capabilityFlags)
            let rawModels = (nested(body, [15]) as? [Any]) ?? []
            let models = rawModels.compactMap { raw -> GeminiWebModel? in
                guard let array = raw as? [Any] else { return nil }
                return GeminiWebModel.fromRPC(array, capacity: capacity.capacity, capacityField: capacity.field)
            }
            return UserStatus(statusCode: status, models: models)
        }
        throw GeminiWebError.protocolChanged("không thấy envelope \(GeminiWebRequestBuilder.userStatusRPC) trong phản hồi batchexecute")
    }

    // MARK: - Phụ trợ

    /// Đi theo đường dẫn chỉ số trong mảng lồng nhau; sai kiểu hay vượt biên ⇒ `nil`. Chỉ số âm đếm từ cuối.
    static func nested(_ root: Any?, _ path: [Int]) -> Any? {
        var current: Any? = root
        for index in path {
            guard let array = current as? [Any] else { return nil }
            let resolved = index < 0 ? array.count + index : index
            guard resolved >= 0, resolved < array.count else { return nil }
            current = array[resolved]
        }
        if current is NSNull { return nil }
        return current
    }

    static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    static func intArray(_ value: Any?) -> [Int] {
        ((value as? [Any]) ?? []).compactMap { intValue($0) }
    }

    static func parseJSON(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func stripArtifacts(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return artifactPattern.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
