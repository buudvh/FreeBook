import Foundation

/// `imageDecode` của nguồn tranh (spec §8.6): tải ảnh bằng client của nguồn (kho cookie, header nguồn/đăng nhập, option
/// của ảnh) rồi chạy JS giải mã **byte → byte**. Gọi từ `ComicImageScriptRunner` khi `ComicPageSource.script` là
/// `SourceRuntime.legadoImageDecodeScriptName`; kết quả được loader lưu cache ở dạng đã giải mã.
extension LegadoSourceRuntime {
    /// Trần cho một ảnh (tải + giải mã). Vòng JS thuần không ngắt được nên trần chỉ là "bỏ chờ".
    static let imageDecodeSeconds = 30

    /// `link` = chuỗi `src` đầy đủ (URL tuyệt đối + khối option, gồm `#…` nếu có) — cũng là biến JS `src` (U32: giữ
    /// nguyên). Một phiên engine mỗi ảnh (nạp `jsLib` trước). Giải mã lỗi/không ra ảnh ⇒ trả **byte gốc** (kèm chẩn đoán);
    /// chỉ lỗi tải mới ném.
    static func decodedImage(_ target: Target, link: String) async throws -> Data {
        let code = scriptBody(target.source.ruleContent.imageDecode)
        do {
            return try await LegadoCorpusDeadline.run(seconds: imageDecodeSeconds) { () async throws -> Data in
                try await Self.runSession(target, log: nil) { (session: LegadoEngineSession) throws -> Data in
                    let request = try session.buildRequest(link, baseUrl: LegadoURLResolver.splitOption(link).url)
                    let response = try session.perform(request)
                    let original = response.data
                    guard !code.isEmpty else { return original }
                    return try Self.runImageDecode(session: session, code: code, bytes: original, src: link) ?? original
                }
            }
        } catch is LegadoCorpusDeadline.Exceeded {
            throw LegadoEngineError.timeout(url: LegadoURLResolver.splitOption(link).url)
        }
    }

    /// Chạy `imageDecode` (hoặc `coverDecodeJs`, `field` chỉ đổi nhãn chẩn đoán) với `result` = mảng byte (`Uint8Array`
    /// kiêm luồng đọc `read()`/`read(buf)`/`available()`, spec §8.7) và `src` = `link`. Byte qua ranh giới dạng hex (cùng
    /// cách các hàm mã hoá của engine): giá trị JS → `.string` không mất byte, còn `Uint8Array` xuất thẳng sẽ bị đọc
    /// thành chuỗi UTF-8. Mã có `return` ở cấp ngoài cùng (không hợp lệ với `eval`) ⇒ chạy lại trong `new Function`.
    /// `nil` ⇒ dùng byte gốc (JS lỗi, trả `undefined`/chuỗi/rỗng, hay kết quả không phải ảnh).
    static func runImageDecode(session: LegadoEngineSession, code: String, bytes: Data, src: String,
                               field: String = "imageDecode") throws -> Data? {
        let quoted = LegadoEngineJSON.quoted(code)
        let harness = """
        (function (g) {
          g.result = g.__lg.hexToBytes(String(g.result || ''));
          if (typeof g.__lg.byteStream === 'function') { g.result = g.__lg.byteStream(g.result); }
          var out;
          try {
            out = (0, eval)(\(quoted));
          } catch (e) {
            if (!(e instanceof SyntaxError)) { throw e; }
            out = (new Function(\(quoted))).call(g);
          }
          if (out === undefined || out === null) { out = g.result; }
          if (out instanceof ArrayBuffer) { out = new Uint8Array(out); }
          if (typeof out !== 'object' || typeof out.length !== 'number' || out.length === 0) { return ''; }
          return g.__lg.bytesToHex(out);
        })(this)
        """
        let errorsBefore = session.diagnostics.count(of: .javaScript)
        let value = try session.evaluateScript(harness, result: .string(LegadoJSRuntime.hex(bytes)), baseUrl: src, src: src)
        guard case .string(let hex) = value, !hex.isEmpty else {
            let failed = session.diagnostics.count(of: .javaScript) > errorsBefore
            let lastError = session.diagnostics.entries.last(where: { $0.kind == .javaScript })?.message ?? ""
            if failed, lastError.contains("android") || lastError.contains("Bitmap") {
                session.diagnostics.record(.info, "\(field) cần shim đồ hoạ (android.graphics) — hiển thị ảnh gốc")
            } else {
                session.diagnostics.record(.info, "\(field) không trả mảng byte — dùng ảnh gốc")
            }
            return nil
        }
        let decoded = Data(LegadoJSRuntime.bytes(fromHex: hex))
        guard looksLikeImage(decoded) else {
            session.diagnostics.record(.info, "\(field) trả \(decoded.count) byte không phải ảnh — dùng ảnh gốc")
            return nil
        }
        return decoded
    }

    /// Chữ ký đầu tệp: JPEG, PNG, GIF, WebP, BMP, HEIF/AVIF (`ftyp`).
    static func looksLikeImage(_ data: Data) -> Bool {
        let head = [UInt8](data.prefix(12))
        guard head.count >= 4 else { return false }
        if head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return true }
        if head[0] == 0x89, head[1] == 0x50, head[2] == 0x4E, head[3] == 0x47 { return true }
        if head[0] == 0x47, head[1] == 0x49, head[2] == 0x46, head[3] == 0x38 { return true }
        if head[0] == 0x42, head[1] == 0x4D { return true }
        guard head.count >= 12 else { return false }
        if head[0] == 0x52, head[1] == 0x49, head[2] == 0x46, head[3] == 0x46,
           head[8] == 0x57, head[9] == 0x45, head[10] == 0x42, head[11] == 0x50 { return true }
        return head[4] == 0x66 && head[5] == 0x74 && head[6] == 0x79 && head[7] == 0x70
    }
}
