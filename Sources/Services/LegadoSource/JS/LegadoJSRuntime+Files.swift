import Foundation

/// Phía Swift của tệp (spec §14.2) và font chống thu thập (§14.1). Đường dẫn là tương đối với thư mục tệp của nguồn
/// (`LegadoSourceFiles`); RAR/7z ⇒ lỗi rõ "Chưa hỗ trợ định dạng …".
extension LegadoJSRuntime {
    func nativeFiles(_ command: String, _ arguments: LegadoJSArguments, _ session: LegadoEngineSession) throws -> String? {
        switch command {
        case "downloadFile":
            return try session.jsDownloadFile(text(of: arguments[0]))
        case "readTxtFile":
            return session.sourceFiles.readText(text(of: arguments[0]), charset: arguments.plainString(1))
        case "deleteFile":
            return session.sourceFiles.delete(text(of: arguments[0])) ? "1" : ""
        case "unzipFile":
            return try session.sourceFiles.unzip(text(of: arguments[0]))
        case "getTxtInFolder":
            return session.sourceFiles.textInFolder(text(of: arguments[0]))
        case "zipString":
            guard let data = try session.zipEntryData(url: text(of: arguments[0]), entry: text(of: arguments[1])) else {
                return ""
            }
            let encoding = LegadoCharset.encoding(named: arguments.plainString(2)) ?? .utf8
            return LegadoCharset.string(from: data, encoding: encoding)
        case "zipBytes":
            let data = try session.zipEntryData(url: text(of: arguments[0]), entry: text(of: arguments[1]))
            return Self.hex(data ?? Data())
        case "unsupportedArchive":
            let format = text(of: arguments[0])
            session.diagnostics.record(.unsupported, "định dạng nén \(format)")
            throw LegadoJSNativeError("\(LegadoJSNativeError.unsupportedPrefix)định dạng \(format) ở bản này (chỉ hỗ trợ zip)")

        case "queryTTF":
            if isByteArray(arguments[0]) { return registerFont(bytes(of: arguments[0]), session: session) }
            let value = text(of: arguments[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            if LegadoURLResolver.hasHTTPScheme(value) {
                let data = try session.fontData(url: value)
                return registerFont(data, session: session)
            }
            return registerFont(Self.base64Decode(value, flags: nil), session: session)
        case "queryB64TTF":
            return registerFont(Self.base64Decode(text(of: arguments[0]), flags: nil), session: session)
        case "replaceFont":
            let source = text(of: arguments[0])
            guard let first = font(handle: arguments.int(1)), let second = font(handle: arguments.int(2)) else {
                session.diagnostics.record(.info, "java.replaceFont: thiếu font — giữ nguyên văn bản")
                return source
            }
            return LegadoFont.replace(source, obfuscated: first, standard: second, filter: arguments.bool(3))
        default:
            return nil
        }
    }

    /// Nạp font và trả chỉ số (chuỗi JSON số) cho JS; hỏng ⇒ `"null"` + chẩn đoán.
    private func registerFont(_ data: Data?, session: LegadoEngineSession) -> String {
        guard let data, let font = LegadoFont.load(data) else {
            session.diagnostics.record(.info, "java.queryTTF: không đọc được font")
            return "null"
        }
        fontHandles.append(font)
        return String(fontHandles.count - 1)
    }

    private func font(handle: Int?) -> LegadoFont? {
        guard let handle, handle >= 0, handle < fontHandles.count else { return nil }
        return fontHandles[handle]
    }
}
