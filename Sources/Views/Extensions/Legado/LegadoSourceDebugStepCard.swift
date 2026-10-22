import SwiftUI

/// Thẻ một bước của màn "Gỡ lỗi từng bước": tiêu đề + trạng thái + thời gian; đầu vào; request (phương thức, URL cuối,
/// HTTP, bảng mã, kích thước, WebView); số kết quả; trường trích được của mục đầu; lỗi + lớp lỗi; hàm chưa hỗ trợ; log
/// JS; kết quả đầu dò bộ chọn (bước rỗng/lỗi); "Xem HTML trang (cắt 4 KB)". Bước lỗi có viền đỏ.
///
/// URL hiện nguyên văn (chỉ trên máy, không gửi đi); bản sao chép báo cáo mới che giá trị query.
struct LegadoSourceDebugStepCard: View {
    let step: LegadoDebugStep

    @State private var showsLogs = false
    @State private var showingBody = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(step.input)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)

            ForEach(Array(step.requests.enumerated()), id: \.offset) { _, request in
                Text(LegadoDebugReportFormatter.requestLine(request, redacting: false))
                    .font(.caption2.monospaced())
                    .foregroundColor(request.errorMessage == nil ? .primary : .red)
                    .textSelection(.enabled)
            }

            if let count = step.count {
                Text(countLabel(count))
                    .font(.caption.weight(.semibold))
            }

            ForEach(Array(step.fields.enumerated()), id: \.offset) { _, field in
                HStack(alignment: .top, spacing: 6) {
                    Text(field.name)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 92, alignment: .leading)
                    Text(field.value)
                        .font(.caption2)
                        .textSelection(.enabled)
                }
            }

            if let message = step.errorMessage {
                errorBlock(message)
            }

            if let rule = step.rule, step.status != .passed {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rule: \(rule.name)")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(LegadoDebugStep.clip(rule.value))
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let probe = step.probes.last, step.status != .passed {
                Text("Đầu dò bộ chọn: " + probe.summary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            if !step.unsupported.isEmpty {
                Text("Chưa hỗ trợ: " + step.unsupported.joined(separator: "; "))
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            footerButtons
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(step.isFailure ? Color.red : Color.clear, lineWidth: 1.5)
        )
        .sheet(isPresented: $showingBody) {
            bodySheet
        }
    }

    // MARK: - Phần

    private var header: some View {
        HStack(spacing: 8) {
            statusIcon
            Text("\(step.id + 1). \(step.kind.title)")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if step.status != .running {
                Text("\(step.durationMs) ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case .running:
            ProgressView()
                .scaleEffect(0.7)
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .empty:
            Image(systemName: "circle.dashed").foregroundColor(.orange)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
        case .cancelled:
            Image(systemName: "stop.circle").foregroundColor(.secondary)
        }
    }

    private func countLabel(_ count: Int) -> String {
        if let text = step.countText { return text }
        switch step.kind {
        case .search, .explore: return "Số kết quả: \(count)"
        case .detail: return "Có thông tin sách"
        case .toc: return "Số chương: \(count)"
        case .content: return "Độ dài nội dung: \(count) ký tự"
        }
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let category = step.errorCategory {
                Text("Lớp lỗi: \(category)")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundColor(.red)
            }
            Text(message)
                .font(.caption)
                .foregroundColor(step.isFailure ? .red : .orange)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        let hasBody = !step.lastBodySnippet.isEmpty
        if !step.logs.isEmpty || hasBody {
            HStack(spacing: 8) {
                if !step.logs.isEmpty {
                    Button(showsLogs ? "Ẩn log (\(step.logs.count))" : "Log JS (\(step.logs.count))") {
                        showsLogs.toggle()
                    }
                }
                if hasBody {
                    Button("Xem HTML trang (cắt 4 KB)") { showingBody = true }
                }
                Spacer()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        if showsLogs {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(step.logs.enumerated()), id: \.offset) { _, line in
                    Text("\(line.kind): \(line.message)")
                        .font(.caption2.monospaced())
                        .foregroundColor(line.kind == "info" ? .secondary : .orange)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var bodySheet: some View {
        NavigationStack {
            ScrollView {
                Text(step.lastBodySnippet)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("HTML trang (4 KB đầu)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { showingBody = false }
                }
            }
        }
    }
}
