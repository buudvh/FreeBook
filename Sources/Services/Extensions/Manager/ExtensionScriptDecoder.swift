import CommonCrypto
import CryptoKit
import Foundation

/// Giải mã script extension bị mã hoá theo scheme của Vbook.
///
/// Scheme đã đối chứng với dữ liệu thật (xem `Docs/Plans/2026-10-15-plan-extension-script-decoder.md`):
/// 1. Ba token `x0P1Xx` / `x0P2Xx` / `x0P3Xx` lần lượt thay cho `+` `/` `=`, mỗi token ứng đúng **1 ký tự**
///    (kiểm chứng: `độ dài − 5×số_token ≡ 0 (mod 4)` trên cả 10/10 file).
/// 2. Phần còn lại là Base64 của ciphertext **AES-256-CBC**, IV 16 byte `0x00`, padding PKCS#7.
/// 3. Key = `SHA256(MD5("com.vbook.app" + source + author) dạng hex)`.
///
/// **Chỉ hỗ trợ đúng biến thể trên** (quyết định đã chốt): không thử ma trận biến thể key,
/// không giải nén payload — tool chính thức của Vbook mã hoá JS thô chứ không nén.
enum ExtensionScriptDecoder {

    // MARK: - Hằng số

    /// Salt cố định của Vbook khi sinh key.
    private static let salt = "com.vbook.app"

    /// Token trong chuỗi mã hoá, theo đúng thứ tự thay thế.
    private static let tokens: [(token: String, replacement: String)] = [
        ("x0P1Xx", "+"),
        ("x0P2Xx", "/"),
        ("x0P3Xx", "="),
    ]

    /// Dấu hiệu nhận biết JavaScript — dùng để phát hiện key sai (giải mã ra rác).
    private static let jsMarkers = ["function", "var ", "let ", "const ", "load(", "return", "Response"]

    /// Kích thước block AES. Bọc `Int(...)` vì macro của CommonCrypto có thể được import thành `Int32`.
    private static let aesBlockSize = Int(kCCBlockSizeAES128)

    // MARK: - API

    /// Giải mã tại chỗ mọi script bị mã hoá trong thư mục extension.
    ///
    /// - Ghi đè nội dung file script bằng bản plaintext, **giữ nguyên tên file** ⇒ bản đồ `script`
    ///   trong `plugin.json` không phải sửa, runtime và editor đọc như extension thường.
    /// - Đặt cờ `encrypt` về `false` để đánh dấu thư mục đã là bản rõ.
    /// - Ném lỗi khi gặp file **chắc chắn** bị mã hoá (có token) mà không giải được ⇒ luồng cài dừng
    ///   và báo lỗi, thay vì cài một extension chắc chắn hỏng lúc chạy.
    /// - Trả về số file đã giải mã; `0` nghĩa là extension không mã hoá (không làm gì).
    @discardableResult
    static func decodeScripts(in folder: URL) throws -> Int {
        let pluginUrl = folder.appendingPathComponent("plugin.json")
        guard let pluginData = try? Data(contentsOf: pluginUrl),
              let plugin = try? JSONSerialization.jsonObject(with: pluginData) as? [String: Any] else {
            return 0
        }

        // `plugin.json` của Vbook bọc metadata trong `metadata`; record của app có thể để phẳng ở root.
        let meta = (plugin["metadata"] as? [String: Any]) ?? plugin
        let source = (meta["source"] as? String) ?? ""
        let author = (meta["author"] as? String) ?? ""
        let encryptFlag = isEncryptFlagOn(meta: meta, plugin: plugin)

        var pending: [(url: URL, raw: String, hasTokens: Bool)] = []
        for fileUrl in scriptFiles(in: folder) {
            guard let raw = try? String(contentsOf: fileUrl, encoding: .utf8) else { continue }
            let hasTokens = tokens.contains { raw.contains($0.token) }
            // Không có token và nội dung đã là JS ⇒ file thường, bỏ qua.
            guard hasTokens || (encryptFlag && !looksLikeJS(raw)) else { continue }
            pending.append((url: fileUrl, raw: raw, hasTokens: hasTokens))
        }
        guard !pending.isEmpty else { return 0 }

        guard !source.isEmpty || !author.isEmpty else {
            throw failure("plugin.json thieu metadata.source/author nen khong sinh duoc key giai ma")
        }
        let key = deriveKey(source: source, author: author)

        var decodedCount = 0
        for item in pending {
            do {
                let plain = try decrypt(item.raw, key: key, fileName: item.url.lastPathComponent)
                try plain.write(to: item.url, atomically: true, encoding: .utf8)
                decodedCount += 1
            } catch {
                // Không có token ⇒ chỉ là phỏng đoán theo cờ `encrypt`, chưa đủ căn cứ để chặn cài.
                guard item.hasTokens else { continue }
                throw error
            }
        }

        if decodedCount > 0, encryptFlag {
            clearEncryptFlag(pluginUrl: pluginUrl, plugin: plugin)
        }
        return decodedCount
    }

    // MARK: - Giải mã

    /// Sinh key AES-256 theo công thức Vbook: `SHA256(MD5(salt + source + author) dạng hex)`.
    ///
    /// MD5 ở đây **không** phải để bảo mật mà là bước trộn chuỗi do định dạng Vbook quy định;
    /// bản thân AES-256 mới là phần mã hoá. Dùng `Insecure.MD5` của CryptoKit cho khớp
    /// `Sources/Common/Extensions/String+Crypto.swift:8`.
    private static func deriveKey(source: String, author: String) -> Data {
        let payload = Data((salt + source + author).utf8)
        let md5Hex = Insecure.MD5.hash(data: payload)
            .map { String(format: "%02hhx", $0) }
            .joined()
        return Data(SHA256.hash(data: Data(md5Hex.utf8)))
    }

    /// Bỏ token về ký tự gốc, Base64-decode rồi AES-256-CBC; kiểm tra kết quả phải là JavaScript.
    private static func decrypt(_ raw: String, key: Data, fileName: String) throws -> String {
        let base64 = unescape(raw).filter { !$0.isWhitespace }
        guard let cipher = Data(base64Encoded: base64) else {
            throw failure("\(fileName): noi dung sau khi bo token khong phai Base64 hop le")
        }
        guard !cipher.isEmpty, cipher.count % aesBlockSize == 0 else {
            throw failure("\(fileName): do dai ciphertext (\(cipher.count) byte) khong chia het cho 16")
        }

        let plain = try aesCBCDecrypt(cipher, key: key)
        guard let text = String(data: plain, encoding: .utf8), looksLikeJS(text) else {
            throw failure("\(fileName): giai ma ra du lieu khong phai JavaScript — nhieu kha nang metadata.source/author trong plugin.json da bi sua sau khi ma hoa")
        }
        return text
    }

    /// Thay `x0P1Xx` / `x0P2Xx` / `x0P3Xx` về `+` `/` `=`.
    private static func unescape(_ raw: String) -> String {
        var out = raw
        for entry in tokens {
            out = out.replacingOccurrences(of: entry.token, with: entry.replacement)
        }
        return out
    }

    /// AES-256-CBC với IV 16 byte `0x00`; PKCS#7 do CommonCrypto tự bỏ khi `CCCrypt`.
    ///
    /// CryptoKit không có AES-CBC (chỉ GCM/ChaChaPoly) nên phải dùng CommonCrypto.
    private static func aesCBCDecrypt(_ cipher: Data, key: Data) throws -> Data {
        let zeroIV = Data(repeating: 0, count: aesBlockSize)
        var out = Data(count: cipher.count + aesBlockSize)
        var moved = 0

        let status = out.withUnsafeMutableBytes { outBuffer -> CCCryptorStatus in
            cipher.withUnsafeBytes { cipherBuffer -> CCCryptorStatus in
                key.withUnsafeBytes { keyBuffer -> CCCryptorStatus in
                    zeroIV.withUnsafeBytes { ivBuffer -> CCCryptorStatus in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress,
                            key.count,
                            ivBuffer.baseAddress,
                            cipherBuffer.baseAddress,
                            cipher.count,
                            outBuffer.baseAddress,
                            outBuffer.count,
                            &moved
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw failure("AES-256-CBC giai ma that bai (CCCrypt status \(status))")
        }
        out.removeSubrange(moved..<out.count)
        return out
    }

    // MARK: - Nhận dạng

    /// Cờ `encrypt` nằm trong `metadata` (bản ZIP của Vbook) hoặc ở root (record của app).
    private static func isEncryptFlagOn(meta: [String: Any], plugin: [String: Any]) -> Bool {
        if let value = meta["encrypt"] as? Bool { return value }
        if let value = plugin["encrypt"] as? Bool { return value }
        return false
    }

    /// Nội dung đã là JavaScript (bản rõ) hay chưa.
    private static func looksLikeJS(_ text: String) -> Bool {
        if jsMarkers.contains(where: { text.contains($0) }) { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, let last = trimmed.last else { return false }
        return (first == "[" && last == "]") || (first == "{" && last == "}")
    }

    /// Mọi file `.js` trong thư mục extension, kể cả thư mục con (`src/`).
    private static func scriptFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "js" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    // MARK: - Ghi cờ

    /// Đặt `encrypt = false` trong `plugin.json` để đánh dấu thư mục đã là bản rõ.
    private static func clearEncryptFlag(pluginUrl: URL, plugin: [String: Any]) {
        var updated = plugin
        if var metaDict = updated["metadata"] as? [String: Any], metaDict["encrypt"] != nil {
            metaDict["encrypt"] = false
            updated["metadata"] = metaDict
        }
        if updated["encrypt"] != nil { updated["encrypt"] = false }

        guard let data = try? JSONSerialization.data(
            withJSONObject: updated,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: pluginUrl)
    }

    // MARK: - Lỗi

    /// Không khai báo type `Error` riêng để giữ luật 1 type top level mỗi file.
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ExtensionScriptDecoder", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
