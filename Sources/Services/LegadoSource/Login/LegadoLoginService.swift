import Foundation

/// API đăng nhập cho UI (spec §10). Mọi hàm chạm Keychain/kho cookie/engine đều `async` (gọi từ main bằng `await` sẽ chạy
/// ngoài main); `mode(for:)` đồng bộ vì chỉ đọc JSON. Hàm chạy engine dùng thread nền riêng và bật
/// `LegadoInteraction.isInteractive` để `java.startBrowser*`/`getVerificationCode` trong `login()` được trình bày.
///
/// Nhận `LegadoEngineSource` — lớp UI lấy từ `LegadoSourceRuntime.Target(packageId:source:).engineSource` hoặc
/// `LegadoSourceTargetResolver.shared.target(localPath:)?.engineSource`.
enum LegadoLoginService {
    struct Status: Sendable, Equatable {
        /// Có thông tin đăng nhập đã lưu (form) hoặc header đăng nhập.
        var hasLoginInfo: Bool
        var hasLoginHeader: Bool
        /// Lần đăng nhập/kiểm tra thành công gần nhất (dải "Đã đăng nhập · kiểm tra lúc …").
        var checkedAt: Date?
        /// `false` ⇒ Keychain từ chối, thông tin chỉ sống tới khi thoát app (UI nên báo).
        var isPersisted: Bool

        var isLoggedIn: Bool { hasLoginInfo || hasLoginHeader || checkedAt != nil }
    }

    struct SubmitResult: Sendable {
        var success: Bool
        /// Lỗi JS / "login() trả về false" khi thất bại.
        var message: String?
    }

    struct ActionResult: Sendable {
        /// Giá trị form sau khi JS gọi `java.upLoginData(map)`; `nil` ⇒ không đổi.
        var updatedValues: [String: String]?
        /// JS gọi `java.reLoginView()` ⇒ UI gọi lại `formFields`.
        var needsReload: Bool
        /// Lỗi JS (UI hiện "Lỗi: …").
        var errorMessage: String?
    }

    // MARK: - Đọc

    /// Cách đăng nhập (đồng bộ, không chạy JS).
    static func mode(for source: LegadoEngineSource) -> LegadoLoginMode {
        let object = LegadoEngineJSONParser.parse(source.rawJSON, lenient: true)
        let loginUi = object?["loginUi"].map { $0.isNull ? "" : $0.scalarString } ?? ""
        return LegadoLoginMode.resolve(loginUrl: source.loginUrl, loginUi: loginUi, baseURL: source.baseURL)
    }

    static func status(for source: LegadoEngineSource) async -> Status {
        let store = LegadoLoginStore.shared
        return Status(hasLoginInfo: store.loginInfo(sourceKey: source.key) != nil,
                      hasLoginHeader: store.loginHeader(sourceKey: source.key) != nil,
                      checkedAt: store.lastCheckedAt(sourceKey: source.key),
                      isPersisted: store.isPersisted(sourceKey: source.key))
    }

    /// Thông tin đăng nhập đã lưu (để điền sẵn form) — map `name → giá trị`.
    static func savedValues(for source: LegadoEngineSource) async -> [String: String] {
        guard let text = LegadoLoginStore.shared.loginInfo(sourceKey: source.key),
              let entries = LegadoEngineJSONParser.parse(text, lenient: true)?.objectEntries else { return [:] }
        return LegadoEngineSession.stringMap(entries)
    }

    // MARK: - Form (§10.3–§10.4)

    /// Dựng form từ `loginUi` (đánh giá lại mỗi lần mở; JS có thể đọc trạng thái đăng nhập).
    static func formFields(for source: LegadoEngineSource) async throws -> [LegadoLoginField] {
        let saved = await savedValues(for: source)
        return try await interactive(source) { session in
            try session.loginFormFields(savedValues: saved)
        }
    }

    /// Nút "Đăng nhập": `values` = giá trị hiện tại của mọi ô (UI tự bỏ nút/nhãn hoặc để nguyên — engine lọc theo ô).
    /// Thành công ⇒ lưu Keychain + ghi mốc kiểm tra.
    static func submit(source: LegadoEngineSource, values: [String: String]) async throws -> SubmitResult {
        let outcome = try await interactive(source) { session in
            try session.runLoginFormSubmit(values: values)
        }
        if outcome.success {
            LegadoLoginStore.shared.setValue(LegadoEngineSession.jsonText(outcome.info), item: .info, sourceKey: source.key)
            LegadoLoginStore.shared.markChecked(sourceKey: source.key)
        }
        return SubmitResult(success: outcome.success, message: outcome.error)
    }

    /// Nút của nguồn (`button` có `action` JS, hoặc `toggle`/`select` sau khi đổi giá trị). `action` là URL `http(s)` thì
    /// UI tự mở trình duyệt (`LegadoLoginField.actionURL`), không gọi hàm này.
    static func runAction(_ action: String, source: LegadoEngineSource, values: [String: String]) async throws -> ActionResult {
        let run: FormRun = try await interactive(source) { session in
            let error = try session.runLoginFormAction(action, values: values)
            var output = FormRun(error: error, values: values, changed: false, reload: false, commit: false)
            if let form = session.loginForm {
                output.values = form.values
                output.changed = form.valuesChanged
                output.reload = form.needsReload
                output.commit = form.requestsCommit
            }
            return output
        }
        if run.commit {
            LegadoLoginStore.shared.setValue(LegadoEngineSession.jsonText(run.values), item: .info, sourceKey: source.key)
        }
        return ActionResult(updatedValues: run.changed ? run.values : nil, needsReload: run.reload, errorMessage: run.error)
    }

    private struct FormRun: Sendable {
        var error: String?
        var values: [String: String]
        var changed: Bool
        var reload: Bool
        var commit: Bool
    }

    // MARK: - Đăng nhập trên web (§10.2)

    /// Yêu cầu trình duyệt đăng nhập (chế độ `.web`, hoặc link "Đăng nhập trên web" của form khi `loginUrl` là URL):
    /// URL + UA + cookie hiện có. `nil` khi nguồn không có URL đăng nhập.
    static func webLoginRequest(for source: LegadoEngineSource) async -> LegadoBrowserRequest? {
        let url: String
        switch mode(for: source) {
        case .web(let target):
            url = target
        default:
            guard !source.baseURL.isEmpty else { return nil }
            url = source.baseURL
        }
        let jar = LegadoCookieJar.shared(forSourceKey: source.key, store: LegadoFileStateStore.shared)
        return LegadoBrowserRequest(id: UUID(), sourceKey: source.key, sourceName: source.name, url: url, title: "Đăng nhập",
                                    html: nil, waitsForResult: true, userAgent: LegadoHTTPClient.webViewUserAgent,
                                    headers: [:], cookies: jar.storedCookies(forURL: url))
    }

    /// Người dùng bấm "Xong" ở trình duyệt đăng nhập: gộp cookie của các tên miền đã ghé vào kho cookie của nguồn.
    static func importWebCookies(_ cookies: [HTTPCookie], source: LegadoEngineSource) async {
        let jar = LegadoCookieJar.shared(forSourceKey: source.key, store: LegadoFileStateStore.shared)
        jar.absorbStored(cookies.map { LegadoStoredCookie(httpCookie: $0) })
        LegadoLoginStore.shared.markChecked(sourceKey: source.key)
    }

    /// Đăng xuất (§10.4 mục 6): xoá thông tin + header đăng nhập (Keychain) và **mọi** cookie của nguồn.
    static func logout(source: LegadoEngineSource) async {
        LegadoLoginStore.shared.removeAll(sourceKey: source.key)
        LegadoCookieJar.shared(forSourceKey: source.key, store: LegadoFileStateStore.shared).removeAll()
    }

    /// Xoá nguồn ⇒ xoá mục Keychain (lớp xoá nguồn gọi).
    static func forget(sourceKey: String) async {
        LegadoLoginStore.shared.removeAll(sourceKey: sourceKey)
    }

    // MARK: - Nội bộ

    private static func interactive<T>(_ source: LegadoEngineSource,
                                       _ body: @escaping @Sendable (LegadoEngineSession) throws -> T) async throws -> T {
        try await LegadoInteraction.$isInteractive.withValue(true) {
            try await LegadoEngineSession.run(source: source, body)
        }
    }
}
