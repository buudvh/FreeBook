import SwiftUI

/// Màn **Đăng nhập** của một nguồn Legado (spec §10), đẩy từ màn Chi tiết nguồn.
///
/// - Dải trạng thái: "Đã đăng nhập · kiểm tra lúc …" / "Chưa đăng nhập"; cảnh báo khi thông tin chỉ nằm trong bộ nhớ.
/// - Chế độ **form** (`loginUi` + JS trong `loginUrl`): các ô do nguồn khai (bố cục flex §11.7), nút của nguồn chạy JS
///   (`LegadoLoginService.runAction`), nút "Đăng nhập" khi JS có hàm `login`, liên kết "Đăng nhập trên web".
/// - Chế độ **web** (`loginUrl` là URL): nút mở trình duyệt đăng nhập; "Xong" ⇒ cookie vào kho của nguồn.
/// - "Đăng xuất": xoá thông tin + header đăng nhập (Keychain) và mọi cookie của nguồn (hỏi trước).
///
/// Mọi lời gọi engine qua `LegadoLoginService` (async, chạy ngoài main, ngữ cảnh có người dùng ⇒ `getVerificationCode`
/// / `startBrowserAwait` trong `login()` được presenter ở root trình bày). View không ghi gì trực tiếp.
struct LegadoLoginView: View {
    let sourceName: String
    let source: LegadoEngineSource

    @State var mode: LegadoLoginMode = .none
    @State var status: LegadoLoginService.Status? = nil
    @State var fields: [LegadoLoginField] = []
    @State var values: [String: String] = [:]
    @State var hasLoaded = false
    @State var isLoadingForm = false
    @State var formError: String? = nil
    @State var busyFieldId: Int? = nil
    @State var isSubmitting = false
    @State var resultMessage: String? = nil
    @State var resultIsError = false
    @State var webLogin: LegadoBrowserRequest? = nil
    @State var webLoginImportsCookies = true
    @State var showingLogoutConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusStrip
                if let resultMessage {
                    resultBanner(resultMessage)
                }
                switch mode {
                case .form(let hasLoginFunction):
                    formSection(hasLoginFunction: hasLoginFunction)
                case .web(let url):
                    webSection(url: url)
                case .none:
                    noLoginSection
                }
                footerActions
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Đăng nhập")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadInitial() }
        .refreshable { await reloadForm() }
        .sheet(item: $webLogin) { request in
            LegadoLoginWebView(request: request, source: source, importsCookies: webLoginImportsCookies) { imported in
                if imported {
                    showResult("Đã lưu cookie đăng nhập của nguồn.", isError: false)
                }
                Task { await refreshStatus() }
            }
            .interactiveDismissDisabled()
        }
        .alert("Đăng xuất khỏi nguồn?", isPresented: $showingLogoutConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Đăng xuất", role: .destructive) { logout() }
        } message: {
            Text("Xoá thông tin đăng nhập đã lưu và mọi cookie của nguồn «\(sourceName)».")
        }
    }

    // MARK: - Trạng thái

    private var statusStrip: some View {
        let loggedIn = status?.isLoggedIn ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: loggedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(loggedIn ? .green : .secondary)
                Text(statusText)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 0)
                if status == nil {
                    ProgressView().controlSize(.small)
                }
            }
            if status?.isPersisted == false {
                Label("Chưa lưu bền được — thông tin đăng nhập sẽ mất khi thoát app.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusText: String {
        guard let status else { return "Đang đọc trạng thái…" }
        guard status.isLoggedIn else { return "Chưa đăng nhập" }
        guard let checkedAt = status.checkedAt else { return "Đã đăng nhập" }
        return "Đã đăng nhập · kiểm tra lúc \(Self.timeFormatter.string(from: checkedAt))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm dd/MM/yyyy"
        return formatter
    }()

    private func resultBanner(_ message: String) -> some View {
        Label(message, systemImage: resultIsError ? "xmark.octagon.fill" : "checkmark.circle.fill")
            .font(.footnote)
            .foregroundColor(resultIsError ? .red : .green)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((resultIsError ? Color.red : Color.green).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Form

    @ViewBuilder
    private func formSection(hasLoginFunction: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoadingForm && fields.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Đang dựng form của nguồn…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else if let formError {
                Text(formError)
                    .font(.footnote)
                    .foregroundColor(.red)
                Button("Thử lại") { Task { await reloadForm() } }
                    .font(.footnote.weight(.semibold))
            }
            if !fields.isEmpty {
                LegadoFlexLayout(spacing: 8, rowSpacing: 10).callAsFunction {
                    ForEach(fields) { field in
                        LegadoLoginFieldView(
                            field: field,
                            value: valueBinding(for: field),
                            isBusy: busyFieldId == field.id || isSubmitting,
                            onCommit: { commit(field) }
                        )
                        .legadoFlex(field.style, fullRow: Self.needsFullRow(field))
                    }
                }
            } else if !isLoadingForm && formError == nil && !hasLoginFunction {
                Text("Nguồn không khai ô nào trong form đăng nhập.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if hasLoginFunction {
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().tint(.white) }
                        Text("Đăng nhập")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundColor(.white)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 10)) // không dùng màu nhấn: app tint trắng
                }
                .disabled(isSubmitting || busyFieldId != nil || isLoadingForm)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Ô nhập / chọn / bật tắt không khai `flexBasisPercent` ⇒ trọn hàng (chiều rộng tự nhiên của ô nhập quá hẹp).
    static func needsFullRow(_ field: LegadoLoginField) -> Bool {
        guard field.style.flexBasisPercent == nil else { return false }
        return field.kind != .button
    }

    func valueBinding(for field: LegadoLoginField) -> Binding<String> {
        Binding(
            get: { values[field.name] ?? field.value },
            set: { values[field.name] = $0 }
        )
    }

    // MARK: - Web / không có đăng nhập

    private func webSection(url: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nguồn này đăng nhập trên trang web. Đăng nhập xong, bấm ✓ (Xong) để lưu cookie cho nguồn.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(url)
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(2)
                .textSelection(.enabled)
            Button(action: openWebLogin) {
                Label("Mở trang đăng nhập", systemImage: "safari")
            }
            .buttonStyle(.appFilled)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var noLoginSection: some View {
        Text("Nguồn không khai cách đăng nhập hợp lệ (loginUrl là chú thích hoặc rỗng). Vẫn có thể đăng nhập trên trang web của nguồn.")
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isWebMode {
                Button(action: openWebLogin) {
                    Label("Đăng nhập trên web", systemImage: "globe")
                        .font(.subheadline.weight(.medium))
                }
            }
            if status?.isLoggedIn == true {
                Button(role: .destructive, action: { showingLogoutConfirm = true }) {
                    Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.weight(.medium))
                }
            }
            Text("Thông tin đăng nhập lưu trong Keychain của máy, chỉ nguồn này dùng; không vào bản sao lưu hay tệp xuất nguồn.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var isWebMode: Bool {
        if case .web = mode { return true }
        return false
    }
}
