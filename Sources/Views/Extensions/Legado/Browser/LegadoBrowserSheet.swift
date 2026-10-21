import SwiftUI
import WebKit

/// Trình duyệt nhỏ của nguồn Legado: thanh trên **Huỷ · (tiêu đề + URL) · Xong (✓)**, vạch tải, trang web.
///
/// Dùng chung cho "Đăng nhập trên web" (`LegadoLoginWebView`) và trình duyệt do JS của nguồn mở (`java.startBrowser*`,
/// presenter ở root). Cả hai nút đều chụp trạng thái trang (outerHTML, URL, cookie các tên miền đã ghé) **trước** khi
/// báo `onFinish(snapshot, cancelled)`; người gọi tự đóng màn. Chỉ báo một lần.
struct LegadoBrowserSheet: View {
    let request: LegadoBrowserRequest
    let onFinish: (LegadoBrowserController.Snapshot, Bool) -> Void

    @StateObject private var controller: LegadoBrowserController
    @State private var isFinishing = false

    init(request: LegadoBrowserRequest, onFinish: @escaping (LegadoBrowserController.Snapshot, Bool) -> Void) {
        self.request = request
        self.onFinish = onFinish
        _controller = StateObject(wrappedValue: LegadoBrowserController(request: request))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .top) {
                WebViewHost(webView: controller.webView)
                if controller.isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }
                if let error = controller.loadError {
                    errorBanner(error)
                }
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { await controller.start() }
        .onDisappear {
            // Bị đóng từ ngoài (màn bên dưới đóng) khi chưa bấm gì ⇒ vẫn báo huỷ để engine không chờ tới hết giờ.
            if !isFinishing {
                isFinishing = true
                onFinish(LegadoBrowserController.Snapshot(html: "", finalURL: controller.currentURL, cookies: []), true)
            }
            controller.tearDown()
        }
    }

    // MARK: - Thanh trên

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: { finish(cancelled: true) }) {
                Text("Huỷ")
                    .font(.system(size: 17, weight: .regular))
                    .frame(minWidth: 44, minHeight: 38)
            }
            .accessibilityLabel("Huỷ")

            VStack(spacing: 1) {
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(urlText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)

            Button(action: { controller.reload() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 38)
            }
            .accessibilityLabel("Tải lại")

            Button(action: { finish(cancelled: false) }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.18), in: Circle())
            }
            .accessibilityLabel("Xong")
        }
        .disabled(isFinishing)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    private var titleText: String {
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return request.sourceName.isEmpty ? "Trình duyệt" : request.sourceName
    }

    private var urlText: String {
        controller.currentURL.isEmpty ? request.sourceName : controller.currentURL
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.footnote)
                .lineLimit(3)
            Spacer(minLength: 0)
            Button("Thử lại") { controller.reload() }
                .font(.footnote.weight(.semibold))
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(10)
    }

    private func finish(cancelled: Bool) {
        guard !isFinishing else { return }
        isFinishing = true
        Task { @MainActor in
            let snapshot = await controller.snapshot()
            onFinish(snapshot, cancelled)
        }
    }

    /// Vỏ `UIViewRepresentable` cho `WKWebView` do controller sở hữu.
    private struct WebViewHost: UIViewRepresentable {
        let webView: WKWebView

        func makeUIView(context: Context) -> WKWebView {
            webView
        }

        func updateUIView(_ uiView: WKWebView, context: Context) {}
    }
}
