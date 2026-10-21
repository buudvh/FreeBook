import SwiftUI

/// Hành động của `LegadoLoginView`: nạp form/trạng thái, nút của nguồn, "Đăng nhập", đăng nhập trên web, đăng xuất.
/// Mọi lời gọi qua `LegadoLoginService` (async, ngoài main); kết quả gán lại state trên main.
extension LegadoLoginView {
    /// Lần mở màn: cách đăng nhập (đồng bộ, đọc JSON) → trạng thái → form (chạy JS `loginUi` khi là form).
    func loadInitial() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        mode = LegadoLoginService.mode(for: source)
        await refreshStatus()
        if case .form = mode {
            await reloadForm()
        }
    }

    func refreshStatus() async {
        status = await LegadoLoginService.status(for: source)
    }

    /// Đánh giá lại `loginUi` (JS có thể đọc trạng thái đăng nhập). Giá trị người dùng đang gõ dở được giữ theo `name`;
    /// ô mới lấy giá trị engine dựng (đã lưu → `default` → phần tử đầu của `chars`).
    func reloadForm() async {
        guard case .form = mode else {
            await refreshStatus()
            return
        }
        isLoadingForm = true
        formError = nil
        do {
            let loaded = try await LegadoLoginService.formFields(for: source)
            var merged: [String: String] = [:]
            for field in loaded where field.carriesValue {
                merged[field.name] = values[field.name] ?? field.value
            }
            fields = loaded
            values = merged
        } catch is CancellationError {
            // Màn bị đóng giữa chừng.
        } catch {
            formError = "Không dựng được form đăng nhập: \(error.localizedDescription)"
        }
        isLoadingForm = false
        await refreshStatus()
    }

    /// `select`/`toggle` vừa đổi giá trị hoặc bấm `button`: có `action` thì chạy (URL `http(s)` ⇒ mở trình duyệt).
    func commit(_ field: LegadoLoginField) {
        guard let action = field.action?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty else { return }
        if let url = field.actionURL {
            openBrowser(url: url, title: field.label, importsCookies: false)
            return
        }
        guard busyFieldId == nil, !isSubmitting else { return }
        busyFieldId = field.id
        resultMessage = nil
        let current = currentValues()
        Task { @MainActor in
            defer { busyFieldId = nil }
            do {
                let outcome = try await LegadoLoginService.runAction(action, source: source, values: current)
                if let updated = outcome.updatedValues {
                    for (name, value) in updated { values[name] = value }
                }
                if let error = outcome.errorMessage {
                    showResult("Lỗi: \(error)", isError: true)
                }
                if outcome.needsReload {
                    await reloadForm()
                } else {
                    await refreshStatus()
                }
            } catch is CancellationError {
                return
            } catch {
                showResult("Lỗi: \(error.localizedDescription)", isError: true)
            }
        }
    }

    /// Nút "Đăng nhập": gửi mọi giá trị đang có trên form; thành công ⇒ engine lưu Keychain + mốc kiểm tra.
    func submit() {
        guard !isSubmitting, busyFieldId == nil else { return }
        isSubmitting = true
        resultMessage = nil
        let current = currentValues()
        Task { @MainActor in
            defer { isSubmitting = false }
            do {
                let outcome = try await LegadoLoginService.submit(source: source, values: current)
                if outcome.success {
                    showResult("Đăng nhập thành công.", isError: false)
                    ToastManager.shared.show(message: "Đã đăng nhập nguồn «\(sourceName)»", type: .success)
                } else {
                    let reason = outcome.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    showResult(reason.isEmpty ? "Đăng nhập không thành công." : "Đăng nhập không thành công: \(reason)",
                               isError: true)
                }
                await refreshStatus()
            } catch is CancellationError {
                return
            } catch {
                showResult("Lỗi: \(error.localizedDescription)", isError: true)
            }
        }
    }

    /// "Đăng nhập trên web" / "Mở trang đăng nhập": URL đăng nhập của nguồn (hoặc trang gốc), UA + cookie hiện có.
    func openWebLogin() {
        Task { @MainActor in
            guard let request = await LegadoLoginService.webLoginRequest(for: source) else {
                showResult("Nguồn không có địa chỉ web để đăng nhập.", isError: true)
                return
            }
            webLoginImportsCookies = true
            webLogin = request
        }
    }

    func logout() {
        Task { @MainActor in
            await LegadoLoginService.logout(source: source)
            values = [:]
            showResult("Đã đăng xuất.", isError: false)
            await reloadForm()
        }
    }

    func showResult(_ message: String, isError: Bool) {
        resultMessage = message
        resultIsError = isError
    }

    // MARK: - Nội bộ

    /// Giá trị hiện có của mọi ô mang giá trị (đã gõ hoặc giá trị dựng sẵn).
    private func currentValues() -> [String: String] {
        var result: [String: String] = [:]
        for field in fields where field.carriesValue {
            result[field.name] = values[field.name] ?? field.value
        }
        return result
    }

    /// Trình duyệt nhỏ tại `url` (liên kết trong `action` của form): dùng UA + cookie của nguồn, không nhập cookie.
    private func openBrowser(url: String, title: String, importsCookies: Bool) {
        Task { @MainActor in
            guard let base = await LegadoLoginService.webLoginRequest(for: source) else { return }
            webLoginImportsCookies = importsCookies
            webLogin = LegadoBrowserRequest(id: UUID(), sourceKey: base.sourceKey, sourceName: base.sourceName, url: url,
                                            title: title, html: nil, waitsForResult: false, userAgent: base.userAgent,
                                            headers: [:], cookies: base.cookies)
        }
    }
}
