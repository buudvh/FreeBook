import SwiftUI
import WebKit

/// Hộp nhập **mã xác minh** do JS của nguồn hỏi (`java.getVerificationCode(imageUrl)`, spec §10.8): ảnh mã (engine đã
/// tải bằng client của nguồn — cùng phiên cookie) + ô nhập + Xác nhận. Không có nút Huỷ (1.3.641): vuốt xuống đóng ⇒
/// `onDisappear` gọi `onFinish(nil)` (JS nhận `""`).
/// Ảnh SVG (`data:image/svg+xml`) không giải được bằng `UIImage` ⇒ vẽ bằng một `WKWebView` nhỏ.
struct LegadoVerificationCodeSheet: View {
    let request: LegadoVerificationRequest
    let onFinish: (String?) -> Void

    @State private var code = ""
    @State private var didFinish = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Nguồn «\(request.sourceName)» cần mã xác minh.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                imageView
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                TextField("Nhập mã", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit { finish(code) }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 0)
            }
            .padding()
            .pageTitle("Mã xác minh")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xác nhận") { finish(code) }
                        .headerTextButton()
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { isFocused = true }
        // Bị đóng từ ngoài (màn bên dưới đóng) mà chưa trả lời ⇒ coi như huỷ để engine không chờ tới hết giờ.
        .onDisappear { finish(nil) }
    }

    @ViewBuilder
    private var imageView: some View {
        if let data = request.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .padding(8)
        } else if let data = request.imageData, isSVG(data) {
            SVGHost(data: data)
                .padding(4)
        } else {
            Label("Không tải được ảnh mã", systemImage: "photo")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func isSVG(_ data: Data) -> Bool {
        if request.imageMimeType?.lowercased().contains("svg") == true { return true }
        let head = String(decoding: data.prefix(256), as: UTF8.self).lowercased()
        return head.contains("<svg")
    }

    private func finish(_ value: String?) {
        guard !didFinish else { return }
        didFinish = true
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        onFinish(trimmed)
    }

    /// `WKWebView` không tương tác chỉ để vẽ ảnh SVG của mã xác minh.
    private struct SVGHost: UIViewRepresentable {
        let data: Data

        func makeUIView(context: Context) -> WKWebView {
            let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.isScrollEnabled = false
            webView.isUserInteractionEnabled = false
            let html = "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>"
                + "<body style='margin:0;display:flex;align-items:center;justify-content:center;height:100vh'>"
                + "<img style='max-width:100%;max-height:100%' src='data:image/svg+xml;base64,"
                + data.base64EncodedString() + "'></body></html>"
            webView.loadHTMLString(html, baseURL: nil)
            return webView
        }

        func updateUIView(_ uiView: WKWebView, context: Context) {}
    }
}
