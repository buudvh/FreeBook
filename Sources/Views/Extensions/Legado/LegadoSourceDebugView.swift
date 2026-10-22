import SwiftUI
import UIKit

/// Màn **Gỡ lỗi từng bước** của một nguồn Legado (spec §12.3): ô nhập + "Chạy"; chip chế độ Từ khoá / URL chi tiết /
/// `++` Mục lục / `--` Nội dung / `::` Khám phá; rồi một thẻ cho mỗi bước (Tìm kiếm → Chi tiết → Mục lục → Nội dung).
///
/// Bộ chạy `LegadoSourceDebugRunner` gọi thẳng luồng của nguồn (chạy được cả nguồn đang tắt), không ghi gì ra đĩa ngoài
/// trạng thái engine mà một lượt duyệt thường cũng ghi, không gửi gì ra ngoài. Nút sao chép (toolbar) chép báo cáo văn
/// bản đã che giá trị query của URL. Rời màn ⇒ dừng lượt đang chạy.
struct LegadoSourceDebugView: View {
    let packageId: String
    let sourceName: String
    /// `ruleSearch.checkKeyWord` của nguồn — dùng khi ô nhập trống ở chế độ từ khoá. Trống ⇒ màn tự đọc từ `source.json`.
    var checkKeyWord: String = ""

    @State private var input = ""
    @State private var mode: LegadoDebugInput.Mode = .keyword
    @State private var steps: [LegadoDebugStep] = []
    @State private var lastInput: LegadoDebugInput?
    @State private var runTask: Task<Void, Never>?
    @State private var message: String?
    @State private var loadedCheckKeyWord: String?
    @FocusState private var inputFocused: Bool

    private var isRunning: Bool { runTask != nil }

    private var effectiveCheckKeyWord: String { loadedCheckKeyWord ?? checkKeyWord }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                inputRow
                modeChips
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                if steps.isEmpty, !isRunning {
                    Text(hintText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                ForEach(steps) { step in
                    LegadoSourceDebugStepCard(step: step)
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Gỡ lỗi từng bước")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: copyReport) {
                    AppGlyph.copy.image(size: 17)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .disabled(steps.isEmpty)
                .accessibilityLabel("Sao chép báo cáo")
            }
        }
        .onDisappear {
            runTask?.cancel()
            runTask = nil
        }
        .task {
            guard checkKeyWord.isEmpty, loadedCheckKeyWord == nil else { return }
            if case .success(let source) = await LegadoSourceCoordinator.shared.loadSource(packageId: packageId) {
                loadedCheckKeyWord = source.ruleSearch.checkKeyWord
            }
        }
    }

    // MARK: - Ô nhập

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField(mode.placeholder, text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(mode == .keyword ? .default : .URL)
                .submitLabel(.go)
                .focused($inputFocused)
                .onSubmit(run)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .onChange(of: input) { _, newValue in
                    if let detected = LegadoDebugInput.prefixMode(newValue) { mode = detected }
                }
            Button(action: isRunning ? stop : run) {
                Text(isRunning ? "Dừng" : "Chạy")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(isRunning ? Color.red.opacity(0.85) : Color.blue, in: Capsule())
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var modeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LegadoDebugInput.Mode.allCases) { item in
                    let isSelected = item == mode
                    Button(action: { mode = item }) {
                        Text(item.label)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                            .foregroundColor(isSelected ? .accentColor : .primary)
                            .clipShape(Capsule())
                            // App đặt `.tint(.white)` toàn cục ⇒ màu nhấn là trắng: chip chọn theo kiểu `ExtensionKindFilterBar`.
                            .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var hintText: String {
        let keyword = effectiveCheckKeyWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = keyword.isEmpty ? LegadoDebugInput.fallbackKeyword : keyword
        return "Ô trống ở chế độ Từ khoá ⇒ dùng \"\(fallback)\". Gõ ++URL để bắt đầu ở mục lục, --URL ở nội dung, "
            + "tên::URL ở mục khám phá, URL thường ở trang thông tin sách. Lượt chạy đi tiếp tới chương đầu tiên và dừng "
            + "ở bước đầu tiên rỗng hoặc lỗi."
    }

    // MARK: - Chạy

    private func run() {
        guard runTask == nil else { return }
        let resolved: LegadoDebugInput
        switch LegadoDebugInput.resolve(raw: input, selected: mode, checkKeyWord: effectiveCheckKeyWord) {
        case .failure(let issue):
            message = issue.message
            return
        case .success(let value):
            resolved = value
        }
        message = nil
        mode = resolved.mode
        lastInput = resolved
        steps = []
        inputFocused = false
        let id = packageId
        runTask = Task { @MainActor in
            // Người dùng đang xem từng bước ⇒ nguồn được mở trình duyệt / hỏi mã xác minh như khi đọc thật.
            let failure = await SourceRuntime.userInitiated {
                await LegadoSourceDebugRunner.run(packageId: id, input: resolved, onStep: { step in
                    apply(step)
                })
            }
            if let failure { message = failure }
            runTask = nil
        }
    }

    private func stop() {
        runTask?.cancel()
    }

    private func apply(_ step: LegadoDebugStep) {
        if let index = steps.firstIndex(where: { $0.id == step.id }) {
            steps[index] = step
        } else {
            steps.append(step)
        }
    }

    private func copyReport() {
        guard let lastInput, !steps.isEmpty else { return }
        UIPasteboard.general.string = LegadoDebugReportFormatter.report(
            sourceName: sourceName, input: lastInput, steps: steps
        )
        ToastManager.shared.show(message: "Đã sao chép báo cáo (URL đã che giá trị query)", type: .success)
    }
}
