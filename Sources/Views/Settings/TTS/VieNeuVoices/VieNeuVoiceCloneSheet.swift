import Combine
import SwiftUI

/// **Sheet "Nhân bản giọng"** (1.3.901, mockup anh Bửu duyệt) — mở từ hàng "Nhân bản giọng đọc" của sheet chọn giọng.
///
/// Segmented "Thu âm" | "Chọn file" → section "Mẫu giọng" (khối thu / chọn file, "Nghe lại mẫu", "Tên giọng") → section
/// "Dùng cho" (chip Nano | Turbo | Cả hai, "Khử nhiễu mẫu (Turbo)", số liệu "Cần tải") → tiến trình từng bước khi Lưu.
/// Giải thích chỉ nằm sau nút "?" của hai section. Nút chữ "Lưu" bên phải; vuốt xuống đóng — có mẫu (kể cả lúc đang lưu)
/// ⇒ hỏi "Bỏ thay đổi?"; bỏ lúc đang lưu ⇒ huỷ lượt lưu (chỉ các lượt tải nó khởi tạo), mẫu tạm xoá sau khi lượt dở dừng
/// hẳn (`VieNeuVoiceCloneFlow.cleanUp`). Logic ở `VieNeuVoiceCloneFlow`.
struct VieNeuVoiceCloneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloads = ModelDownloadCenter.shared
    @State private var flow: VieNeuVoiceCloneFlow
    @State private var isPickingFile = false

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(target: VieNeuVoiceCloneFlow.Target) {
        _flow = State(initialValue: VieNeuVoiceCloneFlow(target: target))
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        Picker("Nguồn mẫu", selection: Bindable(flow).source) {
                            ForEach(VieNeuVoiceCloneFlow.Source.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(flow.isRecording || flow.isSaving)
                    }
                    sampleSection
                    targetSection
                    if flow.isSaving || !flow.completedSteps.isEmpty || !flow.statusMessage.isEmpty || showsBlockReason {
                        progressSection
                    }
                }
                .glassSheetRows()
            }
            .pageTitle("Nhân bản giọng")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { flow.save() }
                        .headerTextButton()
                        .disabled(!flow.canSave)
                }
            }
            // Gắn ở gốc màn (cách đã chạy được trong LiveContainer); `.fileImporter` không trả kết quả ở đó.
            .background(
                DocumentPickerPresenter(
                    isPresented: $isPickingFile,
                    allowedContentTypes: [.audio],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        if let url = urls.first { flow.acceptPickedFile(url) }
                    },
                    onCancel: nil
                )
            )
        }
        // Một cơ chế chặn vuốt duy nhất: có mẫu (kể cả lúc đang lưu) ⇒ hỏi "Bỏ thay đổi?"; bỏ ⇒ huỷ lượt lưu + xoá mẫu tạm.
        .confirmDiscardOnSwipe(isDirty: flow.hasUnsavedWork) { flow.cleanUp() }
        .onAppear { flow.refreshMissingBytes() }
        .onReceive(ticker) { _ in flow.tick() }
        .onChange(of: flow.target) { _, _ in flow.refreshMissingBytes() }
        .onChange(of: flow.finishToken) { _, _ in dismiss() }
        .onDisappear { flow.cleanUp() }
    }

    // MARK: - Mẫu giọng

    private var sampleSection: some View {
        Section {
            if flow.source == .record {
                recordBlock
            } else {
                Button {
                    isPickingFile = true
                } label: {
                    Label(flow.sampleURL == nil ? "Chọn file âm thanh" : "Chọn file khác", systemImage: "folder")
                }
                .disabled(flow.isSaving || flow.isProbing)
                if flow.isProbing {
                    ProgressView()
                }
            }
            Button {
                flow.toggleSamplePlayback()
            } label: {
                HStack {
                    Label(flow.isPlayingSample ? "Dừng nghe" : "Nghe lại mẫu", systemImage: flow.isPlayingSample ? "stop.circle" : "play.circle")
                    Spacer()
                    if let seconds = flow.sampleSeconds {
                        Text(Self.seconds(seconds))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .disabled(flow.sampleURL == nil || flow.isRecording || flow.isSaving)
            if let original = flow.originalSampleSeconds, let kept = flow.sampleSeconds {
                LabeledContent("Đã cắt", value: "\(Self.number(kept)) / \(Self.seconds(original))")
                    .monospacedDigit()
            }
            TextField("Tên giọng", text: Bindable(flow).name)
                .textInputAutocapitalization(.words)
                .disabled(flow.isSaving)
        } header: {
            SectionHelpHeader("Mẫu giọng", paragraphs: [
                "Đọc tự nhiên ở chỗ yên tĩnh, 5–15 giây là đủ; bấm dừng khi xong. Mẫu dài bao nhiêu cũng được.",
                "Giọng Nano dùng tối đa 30 giây đầu: mẫu dài hơn thì app tự cắt ở chỗ ngắt hơi gần giây 29,5 (hàng \"Đã cắt\"). Giọng Turbo dùng khoảng 8 giây tiếng nói đầu (đã bỏ khoảng lặng), cũng cắt ở chỗ ngắt hơi."
            ])
        }
    }

    /// Nút tròn lớn (mic ↔ stop), đồng hồ "5,2 s" (không giới hạn — người dùng tự dừng), thanh mức âm.
    private var recordBlock: some View {
        VStack(spacing: 10) {
            Button {
                flow.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(flow.isRecording ? Color.red.opacity(0.85) : Color.accentColor.opacity(0.18))
                    Image(systemName: flow.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(flow.isRecording ? .white : .accentColor)
                }
                .frame(width: 72, height: 72)
                .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .disabled(flow.isSaving || flow.isProbing)
            .accessibilityLabel(flow.isRecording ? "Dừng thu" : "Bắt đầu thu")

            Text(Self.seconds(flow.isRecording ? flow.recordedSeconds : (flow.sampleSeconds ?? 0)))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.secondary)
            ProgressView(value: flow.isRecording ? flow.levelFraction : 0)
                .progressViewStyle(.linear)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Dùng cho

    private var targetSection: some View {
        Section {
            VieNeuChipBar(
                options: [
                    (value: VieNeuVoiceCloneFlow.Target.nano, title: "Nano"),
                    (value: .turbo, title: "Turbo"),
                    (value: .both, title: "Cả hai")
                ],
                selection: Bindable(flow).target
            )
            .disabled(flow.isSaving)
            if flow.target.includesTurbo {
                Toggle("Khử nhiễu mẫu (Turbo)", isOn: Bindable(flow).denoise)
                    .disabled(flow.isSaving)
            }
            if flow.missingBytes > 0 {
                LabeledContent("Cần tải", value: VieNeuSizeFormatter.megabytes(flow.missingBytes))
            }
        } header: {
            SectionHelpHeader("Dùng cho", paragraphs: [
                "Cả hai: app tạo một giọng Nano và một giọng Turbo từ cùng mẫu. Nano dùng gói nhân bản Nano; Turbo cần thêm bộ khử nhiễu. Thiếu gói nào thì Lưu sẽ tải gói đó trước."
            ])
        }
    }

    // MARK: - Tiến trình

    private var progressSection: some View {
        Section {
            if flow.isSaving || !flow.completedSteps.isEmpty {
                if flow.downloadTotal > 0 || flow.completedSteps.contains(.downloading) {
                    stepRow(.downloading, title: downloadTitle)
                }
                if flow.target.includesNano {
                    stepRow(.nano, title: flow.step == .nano ? (VieNeuCloneStageText.nano(flow.nanoStage) ?? "Đang tạo giọng Nano…") : "Giọng Nano")
                }
                if flow.target.includesTurbo {
                    stepRow(.turbo, title: flow.step == .turbo ? VieNeuCloneStageText.turbo(VieNeuTurboVoiceCloneCoordinator.shared.stage) : "Giọng Turbo")
                }
            }
            if flow.isSaving, flow.step == .downloading {
                Button(role: .destructive) {
                    flow.cancelSave()
                } label: {
                    Label("Huỷ tải", systemImage: "stop.fill")
                }
            }
            if !flow.statusMessage.isEmpty {
                Text(flow.statusMessage)
                    .font(.footnote)
                    .foregroundColor(flow.isError ? .red : .secondary)
            } else if showsBlockReason, let reason = flow.saveBlockReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Dòng "vì sao chưa Lưu được" chỉ hiện khi đã có mẫu (vd mẫu quá dài cho Nano, chưa đặt tên) — chưa có mẫu thì nút
    /// Lưu xám là đủ hiểu.
    private var showsBlockReason: Bool {
        !flow.isSaving && flow.sampleURL != nil && flow.saveBlockReason != nil
    }

    private var downloadTitle: String {
        guard flow.step == .downloading, flow.downloadTotal > 0 else { return "Tải gói còn thiếu" }
        let done = min(flow.downloadTotal, VieNeuClonePackages.completedBytes(targets: flow.downloadTargets, in: downloads.entries))
        let percent = Int(Double(done) / Double(flow.downloadTotal) * 100)
        return String(format: "Đang tải gói %d%% · %.0f / %.0f MB", percent, Double(done) / 1_000_000, Double(flow.downloadTotal) / 1_000_000)
    }

    private func stepRow(_ step: VieNeuVoiceCloneFlow.Step, title: String) -> some View {
        HStack(spacing: 10) {
            Group {
                if flow.completedSteps.contains(step) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                } else if flow.step == step {
                    ProgressView()
                } else {
                    Image(systemName: "circle").foregroundColor(.secondary)
                }
            }
            .frame(width: 22)
            Text(title)
                .font(.subheadline)
                .foregroundColor(flow.step == step ? .primary : .secondary)
                .monospacedDigit()
        }
    }

    /// "5,2 s" — dấu phẩy thập phân như mockup.
    static func seconds(_ value: Double) -> String {
        number(value) + " s"
    }

    /// "29,3" — số giây không đơn vị (hàng "Đã cắt": "29,3 / 45,2 s").
    static func number(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
