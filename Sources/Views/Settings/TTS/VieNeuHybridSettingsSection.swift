import SwiftUI

/// Mục **"Đọc lai Nano · Turbo"** (1.3.934) của Cài đặt TTS — dưới hàng "Giọng đọc", chỉ khi trình đọc là VieNeu (1.3.943;
/// trước đó ở Cài đặt VieNeu TTS): hai công tắc (mặc định bật, `VieNeuHybridSettings`) +
/// một dòng trạng thái cặp giọng. Giải thích chỉ sau nút "?" (`SectionHelpHeader`).
///
/// Đổi công tắc ⇒ `TTSManager.vieNeuHybridSettingsDidChange()`: phát nốt đoạn đang đọc, nạp lại phần sau bằng engine
/// mới. Dòng trạng thái tra cặp giọng (đọc hai `voices_custom.json` + kiểm file) ở nền, không trong `body`.
///
/// Tự tạo bản cặp (1.3.938, `VieNeuHybridPairProvisioner`): đang tạo / đang chờ / thiếu file ("Tải và tạo" · "Bỏ qua
/// giọng này") / lỗi ("Thử lại") thay cho dòng trạng thái cặp.
struct VieNeuHybridSettingsSection: View {
    @AppStorage(VieNeuHybridSettings.languageKey) private var languageEnabled = true
    @AppStorage(VieNeuHybridSettings.thermalKey) private var thermalEnabled = true
    /// Đổi khi sheet chọn giọng đóng (giọng có thể đã đổi) ⇒ đọc lại trạng thái.
    let refreshToken: Int
    @State private var status: String?

    private var provisioner: VieNeuHybridPairProvisioner { .shared }

    var body: some View {
        Section {
            Toggle(isOn: $languageEnabled) {
                Label("Tiếng nước ngoài đọc bằng Turbo", systemImage: "globe")
            }
            Toggle(isOn: $thermalEnabled) {
                Label("Máy nóng thì đọc bằng Nano", systemImage: "thermometer.medium")
            }
            provisionRows
        } header: {
            SectionHelpHeader("Đọc lai Nano · Turbo", paragraphs: [
                "Chỉ chạy khi giọng đang chọn có **cặp** ở cả hai model: giọng có sẵn trùng tên (Adam, Mai Anh, Trúc Ly, Anh Khôi, Mạnh Dũng, Mỹ Duyên, Đức Trí) hoặc giọng nhân bản tạo cho **Cả hai**. Cần tải đủ Nano, Turbo và giọng Turbo của cặp.",
                "**Tiếng nước ngoài đọc bằng Turbo** — khi chọn giọng **Nano**: đoạn có tiếng Anh (từ hai từ, hoặc một từ dài) đọc bằng giọng Turbo của cặp, đoạn tiếng Việt vẫn đọc Nano. Chữ Hán không đổi model — không model nào đọc được.",
                "**Máy nóng thì đọc bằng Nano** — khi chọn giọng **Turbo**: máy ở mức Nóng quá một phút thì đọc bằng giọng Nano của cặp cho mát; về Turbo khi máy Mát liền ba phút (sau ít nhất mười phút). Lúc máy nóng, công tắc trên cũng tạm để tiếng Anh đọc Nano.",
                "Đổi model nghe hơi khác giọng. Phần đã đọc sẵn vẫn phát hết, model mới bắt đầu từ đoạn kế tiếp.",
                "Giọng đang chọn chưa có cặp: app tự tạo bản ở model kia (giọng Nano cần công tắc trên, giọng Turbo cần công tắc dưới), mỗi giọng một lần, chỉ khi app đang mở và không đọc truyện. Thiếu model kia thì chỉ hỏi tải khi gạt công tắc sang bật, không tự tải. Giọng không có mẫu gốc thì tạo từ tiếng máy đọc khoảng 15 giây, nên có thể kém giống hơn."
            ])
        }
        .onChange(of: languageEnabled) { _, isOn in settingsChanged(.language, isOn: isOn) }
        .onChange(of: thermalEnabled) { _, isOn in settingsChanged(.thermal, isOn: isOn) }
        .onChange(of: provisioner.state) { _, _ in Task { await reloadStatus() } }
        .task(id: refreshToken) { await reloadStatus() }
    }

    @ViewBuilder
    private var provisionRows: some View {
        switch provisioner.state {
        case .running(let source):
            VStack(alignment: .leading, spacing: 5) {
                Text("Đang tạo bản \(source.target.label) cho \(source.name) · \(runningStep)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .progressViewStyle(.linear)
                    .scaleEffect(x: 1, y: 0.6, anchor: .center)
            }
        case .waiting(let source):
            footnote("Chờ tạo bản \(source.target.label) cho \(source.name) — khi dừng đọc truyện hoặc mở lại app.")
        case .needsDownload(let source, let bytes):
            footnote("\(source.name) chưa có bản \(source.target.label) · cần tải \(VieNeuSizeFormatter.megabytes(bytes))")
            Button("Tải và tạo bản \(source.target.label)") { provisioner.downloadAndCreate() }
            Button("Bỏ qua giọng này") { provisioner.skip() }
                .foregroundStyle(.secondary)
        case .failed(_, let message):
            footnote(message)
            Button("Thử lại") { provisioner.retry() }
        case .idle:
            if let status { footnote(status) }
        }
    }

    private var runningStep: String {
        switch VieNeuVoiceCopyRunner.shared.phase {
        case .downloading: return "tải gói…"
        case .speaking: return "đọc mẫu…"
        case .creating: return "tạo giọng…"
        case nil: return "chuẩn bị…"
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func settingsChanged(_ which: VieNeuHybridPairProvisioner.Switch, isOn: Bool) {
        TTSManager.shared.vieNeuHybridSettingsDidChange()
        provisioner.switchChanged(which, isOn: isOn)
        Task { await reloadStatus() }
    }

    private func reloadStatus() async {
        let manager = TTSManager.shared
        let tool = manager.tool
        let voice = manager.selectedVoice
        let text = await Task.detached(priority: .userInitiated) {
            Self.statusText(tool: tool, voice: voice)
        }.value
        status = text
    }

    nonisolated private static func statusText(tool: String, voice: String) -> String {
        guard tool == "vieneu" else { return "Trình đọc đang không dùng VieNeu." }
        let model = VieNeuModelChoice.current
        guard let pair = VieNeuVoicePairing.shared.pair(model: model, voice: voice) else {
            return "Giọng đang chọn chưa có cặp Nano ↔ Turbo — đọc như thường."
        }
        let kind = pair.isCustom ? "nhân bản" : "có sẵn"
        let ready = VieNeuTurboTTSService.isReadyOnDisk
            && VieNeuTTSService.shared?.modelStore.isReady == true
            && VieNeuTurboTTSService.shared?.store.hasVoice(voiceId: pair.turboVoiceId) == true
        guard ready else {
            return "Cặp giọng \(pair.nanoVoice) (\(kind)) — cần tải đủ Nano, Turbo và giọng Turbo của cặp."
        }
        switch model {
        case .nano: return "Cặp giọng \(pair.nanoVoice) (\(kind)) · đang đọc Nano, tiếng nước ngoài sang Turbo."
        case .turbo: return "Cặp giọng \(pair.nanoVoice) (\(kind)) · đang đọc Turbo, máy nóng sang Nano."
        }
    }
}
