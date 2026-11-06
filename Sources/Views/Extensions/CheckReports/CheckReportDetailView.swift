import SwiftUI

/// Màn chi tiết **chỉ xem** của một báo cáo kiểm tra đã lưu (đẩy từ `CheckReportListView`): dòng phạm vi + thông tin lượt,
/// rồi thân theo loại (`LegadoCheckReportContent` / `ScriptCheckReportContent`). Header: [Chia sẻ][Xoá]. Đọc file qua
/// `CheckReportRepository` (ngoài main), View không đụng đĩa.
struct CheckReportDetailView: View {
    let summary: CheckReportSummary

    @Environment(\.dismiss) private var dismiss
    @State private var document: CheckReportDocument?
    @State private var hasLoaded = false
    @State private var showingDeleteConfirm = false
    @State private var isPreparingShare = false
    @State private var shareURL: URL?
    @State private var message: String?

    private var repository: CheckReportRepository { .shared }

    var body: some View {
        VStack(spacing: 10) {
            header
            if let document {
                switch document {
                case .legado(let report):
                    LegadoCheckReportContent(report: report)
                case .script(let report):
                    ScriptCheckReportContent(report: report)
                }
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    if hasLoaded {
                        Text("Không đọc được báo cáo này (file đã bị xoá hoặc hỏng).")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        ProgressView()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
        .backPageTitle(CheckReportFormatter.dateText(summary.displayDate))
        .toolbar { toolbarContent }
        .confirmationDialog("Xoá báo cáo này?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Xoá báo cáo", role: .destructive, action: deleteReport)
            Button("Huỷ", role: .cancel) {}
        }
        .sheet(isPresented: isSharing) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL]) { _, _, _, _ in
                    self.shareURL = nil
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            document = await repository.document(for: summary)
            hasLoaded = true
        }
    }

    // MARK: - Phần trên

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(infoLine)
                .font(.caption)
                .foregroundColor(.secondary)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var infoLine: String {
        var parts = ["\(summary.kind.title) · \(summary.total) \(summary.kind.unitName)"]
        if let seconds = summary.durationSeconds {
            parts.append("chạy \(CheckReportFormatter.durationText(seconds))")
        }
        parts.append(CheckReportFormatter.statusBadge(summary.status)?.text.lowercased() ?? "đã xong")
        parts.append(CheckReportFormatter.sizeText(summary.byteCount))
        return parts.joined(separator: " · ")
    }

    // Cụm hai nút sát nhau ⇒ một `ToolbarItem` (chuẩn header 1.3.665).
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: HeaderButtonMetrics.pairSpacing) {
                Button(action: shareReport) {
                    Group {
                        if isPreparingShare {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .frame(width: HeaderButtonMetrics.pairIconWidth, height: 38)
                }
                .disabled(document == nil || isPreparingShare)
                .accessibilityLabel("Chia sẻ báo cáo")
                Button(action: { showingDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: HeaderButtonMetrics.pairIconWidth, height: 38)
                }
                .disabled(!summary.isDeletable)
                .accessibilityLabel("Xoá báo cáo")
            }
        }
    }

    // MARK: - Hành động

    /// Services ghi tệp tạm (ngoài main), View chỉ trình bày share sheet.
    private func shareReport() {
        guard let document, !isPreparingShare else { return }
        isPreparingShare = true
        Task { @MainActor in
            switch await document.writeShareFile() {
            case .success(let url):
                // Cờ còn kẹt từ lần trước (bảng chia sẻ tự đóng mà SwiftUI không biết) ⇒ hạ trước rồi mới trình bày lại.
                if shareURL != nil {
                    shareURL = nil
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                shareURL = url
            case .failure(let error):
                message = error.localizedDescription
            }
            isPreparingShare = false
        }
    }

    private func deleteReport() {
        Task { @MainActor in
            if await repository.delete(summary) {
                dismiss()
            } else {
                message = "Không xoá được báo cáo (lượt kiểm tra còn đang chạy?)."
            }
        }
    }

    private var isSharing: Binding<Bool> {
        Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })
    }
}
