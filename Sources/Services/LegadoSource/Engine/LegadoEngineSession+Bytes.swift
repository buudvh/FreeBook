import Foundation
import JavaScriptCore

/// Chạy JS trên **mảng byte** (spec §8.6 `imageDecode`, §8.7 `coverDecodeJs`): `result` là `Uint8Array` kiêm luồng đọc
/// (`length`, `[i]`, `read()`, `read(buf)`), `src` = URL ảnh nguyên văn (gồm khối option / phần `#`).
extension LegadoEngineSession {
    /// Byte JS trả về (`Uint8Array`, mảng số, mảng byte của shim Java); `undefined`/`null`/chuỗi/lỗi ⇒ `nil` (lớp gọi dùng
    /// byte gốc và ghi log, §8.6 bước 5).
    func evaluateBytesScript(_ code: String, bytes: Data, src: String, baseUrl: String? = nil) throws -> Data? {
        var bindings = jsBindings(result: nil, baseUrl: baseUrl ?? sourceBase, src: src)
        bindings.bytesResult = bytes
        let outcome = try runtime.evaluateRaw(code, bindings: bindings)
        guard outcome.error == nil, let value = outcome.value, !value.isUndefined, !value.isNull, !value.isString,
              let text = runtime.exportedDescriptor(value),
              let descriptor = LegadoEngineJSONParser.parse(text) else { return nil }
        guard runtime.isByteArray(descriptor) else { return nil }
        return runtime.bytes(of: descriptor)
    }
}

extension LegadoJSRuntime {
    /// Descriptor JSON (`__lgExport`) của một giá trị JS.
    func exportedDescriptor(_ value: JSValue) -> String? {
        guard let exporter = context.objectForKeyedSubscript("__lgExport"), !exporter.isUndefined,
              let result = exporter.call(withArguments: [value]), result.isString else { return nil }
        return result.toString()
    }
}
