import Foundation

/// Quét tĩnh `source.json` tìm hàm/tính năng mà bản này **chưa** hỗ trợ — chỉ để gợi ý trong báo cáo.
///
/// Vì sao cần: facade chỉ nâng lỗi "mềm" của engine (`session.diagnostics`) thành lỗi ném ra khi **bước đó ra rỗng**,
/// và chỉ một lý do. Stub chưa hỗ trợ gọi ở bước trước (vd biến `@put` không được ghi) vẫn chỉ hiện ra là "rule khớp 0" ở
/// bước sau. Gợi ý ở đây giúp đọc báo cáo: nguồn thất bại mà có gợi ý thì nhiều khả năng hỏng vì tính năng hoãn.
/// Danh sách lấy theo bảng hoãn của spec §6.11, §3.11 (`data:`) và §7.1. **Không** gồm các hàm cố ý không định
/// nghĩa ở §6.10 (`java.qread`, `java.deviceID`, `java.getUserAgent`): nguồn dò chúng trong `try` và đi nhánh khác,
/// nên chúng không phải dấu hiệu hỏng. Không đổi lớp lỗi chính.
enum LegadoCorpusFeatureScan {
    private static let tokens: [String] = [
        "java.startBrowser", "java.getVerificationCode", "java.reLoginView", "java.upLoginData",
        "java.getStrResponse", "java.initUrl", "java.refreshTocUrl", "java.reGetBook", "java.refreshBookUrl",
        "java.importScript", "java.cacheFile", "java.toURL", "java.queryTTF", "java.queryBase64TTF",
        "java.replaceFont", "java.downloadFile", "java.readTxtFile", "unzipFile", "unrarFile", "un7zFile",
        "unArchiveFile", "getTxtInFolder", "StringContent(", "ByteArrayContent(", "java.createAsymmetricCrypto",
        "java.createSign", "java.desEncodeToBase64String", "java.tripleDESEncodeBase64Str", "java.openUrl",
        "java.openVideoPlayer", "java.showBrowser", "java.showReadingBrowser", "java.copyText", "java.searchBook",
        "java.addBook", "putLoginHeader", "putLoginInfo", "source.login(", "Jsoup.connect", "setReverseToc"
    ]
    private static let maxHints = 12

    static func hints(in source: LegadoBookSource) -> [String] {
        let raw = source.rawJSONString
        var found = tokens.filter { raw.contains($0) }
        if raw.contains("\"data:") || raw.contains("'data:") {
            found.append("URL data:")
        }
        if isFilled(source.ruleToc.preUpdateJs) { found.append("preUpdateJs") }
        if isFilled(source.ruleToc.formatJs) { found.append("formatJs") }
        if isFilled(source.loginCheckJs) { found.append("loginCheckJs") }
        if source.needsLogin { found.append("loginUrl") }
        return Array(found.prefix(maxHints))
    }

    private static func isFilled(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
